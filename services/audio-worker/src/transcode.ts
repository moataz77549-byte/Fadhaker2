import { stat } from 'node:fs/promises';
import { ProcessingError } from './errors.js';
import { probeFile, verifyOutput } from './probe.js';
import { runCommand } from './subprocess.js';
import { sha256File } from './checksum.js';
import type { LoudnessMeasurement, ProcessedOutput, ProcessingProfile, ProbeResult } from './types.js';

function extractLoudness(stderr: string): LoudnessMeasurement {
  const match = stderr.match(/\{[\s\S]*?"input_i"[\s\S]*?"target_offset"\s*:\s*"[^"]+"[\s\S]*?\}/g)?.at(-1);
  if (!match) throw new ProcessingError('FFMPEG_FAILED', 'Two-pass loudness analysis did not return measurements');
  try {
    const value = JSON.parse(match) as LoudnessMeasurement;
    for (const key of ['input_i','input_tp','input_lra','input_thresh','target_offset'] as const) {
      if (!Number.isFinite(Number(value[key]))) throw new Error(`invalid ${key}`);
    }
    return value;
  } catch (error) { throw new ProcessingError('FFMPEG_FAILED', 'Invalid loudness analysis output', error); }
}

export async function transcode(
  ffmpegPath: string, ffprobePath: string, inputPath: string, outputPath: string,
  source: ProbeResult, profile: ProcessingProfile, timeoutMs: number, probeTimeoutMs: number,
): Promise<ProcessedOutput> {
  const target = `I=${profile.loudness_i_lufs}:TP=${profile.loudness_tp_dbtp}:LRA=${profile.loudness_lra_lu}`;
  const analysis = await runCommand(ffmpegPath, [
    '-nostdin','-hide_banner','-v','info','-i',inputPath,'-map','0:a:0','-vn','-sn','-dn',
    '-af',`loudnorm=${target}:print_format=json`,'-f','null','-',
  ], timeoutMs, 'PROCESSING_TIMEOUT', 'FFMPEG_FAILED');
  const loudness = extractLoudness(analysis.stderr);
  const filter = `loudnorm=${target}:measured_I=${loudness.input_i}:measured_TP=${loudness.input_tp}`
    + `:measured_LRA=${loudness.input_lra}:measured_thresh=${loudness.input_thresh}`
    + `:offset=${loudness.target_offset}:linear=true:print_format=summary`;
  const encoded = await runCommand(ffmpegPath, [
    '-nostdin','-hide_banner','-v','warning','-y','-i',inputPath,'-map','0:a:0','-vn','-sn','-dn',
    '-map_metadata','-1','-map_chapters','-1','-af',filter,'-c:a','aac','-profile:a','aac_low',
    '-b:a',`${profile.bitrate_kbps}k`,'-ar',String(profile.sample_rate_hz),'-ac',String(profile.channels),
    '-movflags','+faststart',outputPath,
  ], timeoutMs, 'PROCESSING_TIMEOUT', 'FFMPEG_FAILED');
  const file = await stat(outputPath);
  const verified = await probeFile(ffprobePath, outputPath, probeTimeoutMs);
  verifyOutput(verified.probe, source, profile, file.size);
  return {
    ...verified.probe,
    path: outputPath,
    sizeBytes: file.size,
    sha256: await sha256File(outputPath),
    ffmpegDurationMs: analysis.durationMs + encoded.durationMs,
    loudness,
  };
}
