import { stat } from 'node:fs/promises';
import { ProcessingError } from './errors.js';
import { runCommand } from './subprocess.js';
import type { ProbeResult, ProcessingClaim, ProcessingProfile } from './types.js';

interface ProbeJson {
  format?: { format_name?: string; duration?: string; bit_rate?: string; format_long_name?: string };
  streams?: Array<{ codec_type?: string; codec_name?: string; sample_rate?: string; channels?: number; bit_rate?: string; disposition?: { attached_pic?: number }; tags?: Record<string,string> }>;
}

export async function probeFile(ffprobePath: string, path: string, timeoutMs: number): Promise<{probe: ProbeResult; durationMs: number}> {
  const result = await runCommand(ffprobePath, [
    '-v','error','-show_error','-show_format','-show_streams','-of','json',path,
  ], timeoutMs, 'FFPROBE_TIMEOUT', 'FFPROBE_FAILED');
  let parsed: ProbeJson;
  try { parsed = JSON.parse(result.stdout) as ProbeJson; }
  catch (error) { throw new ProcessingError('CORRUPT_INPUT', 'ffprobe returned invalid JSON', error); }
  const streams = parsed.streams ?? [];
  const audio = streams.filter((stream) => stream.codec_type === 'audio');
  const video = streams.filter((stream) => stream.codec_type === 'video' && stream.disposition?.attached_pic !== 1);
  if (audio.length === 0) throw new ProcessingError('NO_AUDIO_STREAM', 'No audio stream detected');
  if (audio.length !== 1) throw new ProcessingError('INVALID_MEDIA', 'Exactly one audio stream is required for MVP');
  if (video.length > 0) throw new ProcessingError('VIDEO_STREAM_REJECTED', 'Audio+video and video-only containers are rejected for MVP');
  if (streams.length > 8) throw new ProcessingError('INVALID_MEDIA', 'Excessive stream count');
  const stream = audio[0]!;
  const duration = Number(parsed.format?.duration);
  const sampleRate = Number(stream.sample_rate);
  const channels = Number(stream.channels);
  const bitrate = Number(stream.bit_rate ?? parsed.format?.bit_rate ?? 0);
  if (!Number.isFinite(duration) || duration <= 0) throw new ProcessingError('CORRUPT_INPUT', 'Invalid or zero media duration');
  if (!Number.isInteger(sampleRate) || sampleRate < 8000 || sampleRate > 192000) throw new ProcessingError('INVALID_MEDIA', 'Invalid sample rate');
  if (!Number.isInteger(channels) || channels < 1 || channels > 8) throw new ProcessingError('INVALID_MEDIA', 'Invalid channel count');
  return {
    durationMs: result.durationMs,
    probe: {
      detectedFormat: parsed.format?.format_name ?? '',
      codec: stream.codec_name ?? '',
      durationMs: Math.round(duration * 1000),
      sampleRateHz: sampleRate,
      channels,
      bitrateKbps: Math.max(1, Math.round(bitrate / 1000)),
      audioStreamCount: audio.length,
      videoStreamCount: video.length,
      encrypted: Object.values(stream.tags ?? {}).some((value) => /encrypt|protected|drm/i.test(value)),
      diagnostics: { format_long_name: parsed.format?.format_long_name, stream_count: streams.length },
    },
  };
}

export async function validateSource(path: string, claim: ProcessingClaim, probe: ProbeResult): Promise<void> {
  const file = await stat(path);
  if (file.size !== claim.expected_size_bytes) throw new ProcessingError('INPUT_SIZE_MISMATCH', 'Downloaded size differs from database');
  const keyPattern = new RegExp(`^media/${claim.media_id}/original/[0-9a-f-]{36}\\.${claim.source_extension}$`);
  if (claim.original_bucket !== 'tarteel-media-originals' || !keyPattern.test(claim.original_path)) {
    throw new ProcessingError('OBJECT_KEY_MISMATCH', 'Original object identity does not match media');
  }
  const detected = new Set(probe.detectedFormat.split(','));
  if (!claim.allowed_formats.some((format) => detected.has(format))) {
    throw new ProcessingError('UNSUPPORTED_FORMAT', `Detected container ${probe.detectedFormat} is not allowed for ${claim.source_extension}`);
  }
  if (!claim.allowed_codecs.includes(probe.codec)) {
    throw new ProcessingError('UNSUPPORTED_FORMAT', `Detected codec ${probe.codec} is not allowed for ${claim.source_extension}`);
  }
  if (probe.encrypted) throw new ProcessingError('UNSUPPORTED_FORMAT', 'Encrypted or protected media is unsupported');
  if (probe.durationMs > claim.profile.max_duration_ms) throw new ProcessingError('DURATION_LIMIT_EXCEEDED', 'Input duration exceeds processing profile limit');
}

export function verifyOutput(probe: ProbeResult, source: ProbeResult, profile: ProcessingProfile, sizeBytes: number): void {
  const detected = new Set(probe.detectedFormat.split(','));
  if (!detected.has('m4a') && !detected.has('mov') && !detected.has('mp4')) throw new ProcessingError('OUTPUT_INVALID', `Unexpected output container ${probe.detectedFormat}`);
  if (probe.codec !== profile.codec || probe.sampleRateHz !== profile.sample_rate_hz || probe.channels !== profile.channels) {
    throw new ProcessingError('OUTPUT_INVALID', 'Output codec, sample rate or channels differ from profile');
  }
  const toleranceMs = Math.max(250, Math.round(source.durationMs * 0.001));
  if (Math.abs(probe.durationMs - source.durationMs) > toleranceMs) throw new ProcessingError('OUTPUT_INVALID', 'Output duration drift exceeds tolerance');
  if (sizeBytes <= 0 || sizeBytes > profile.max_output_size_bytes) throw new ProcessingError('OUTPUT_INVALID', 'Output size is outside profile limits');
  const bitrateTolerance = 12;
  if (Math.abs(probe.bitrateKbps - profile.bitrate_kbps) > bitrateTolerance) throw new ProcessingError('OUTPUT_INVALID', 'Output bitrate differs materially from profile');
}
