import test from 'node:test';
import assert from 'node:assert/strict';
import { access, cp, mkdir, rm, stat } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { randomUUID } from 'node:crypto';
import { probeFile, validateSource } from '../src/probe.js';
import { transcode } from '../src/transcode.js';
import { ProcessingError } from '../src/errors.js';
import { withWorkspace } from '../src/workspace.js';
import { runCommand } from '../src/subprocess.js';
import type { ProcessingClaim, ProcessingProfile } from '../src/types.js';

const fixtures = resolve('test/fixtures/generated');
const profile: ProcessingProfile = {
  id: randomUUID(), code: 'AUDIO_STANDARD_V1', version: 1,
  container: 'mov,mp4,m4a,3gp,3g2,mj2', extension: 'm4a', mime_type: 'audio/mp4', codec: 'aac',
  bitrate_kbps: 96, sample_rate_hz: 44100, channels: 2,
  loudness_i_lufs: -16, loudness_tp_dbtp: -1.5, loudness_lra_lu: 11,
  max_duration_ms: 3_600_000, max_output_size_bytes: 52_428_800,
};

async function claimFor(path: string, extension: string, mime: string, formats: string[], codecs: string[]): Promise<ProcessingClaim> {
  const mediaId = randomUUID();
  const objectId = randomUUID();
  return {
    job_id: randomUUID(), attempt_id: randomUUID(), media_id: mediaId, claim_token: 1,
    original_bucket: 'tarteel-media-originals', original_path: `media/${mediaId}/original/${objectId}.${extension}`,
    original_object_version: 'test', original_filename: `fixture.${extension}`, declared_mime_type: mime,
    expected_size_bytes: (await stat(path)).size, source_extension: extension,
    allowed_formats: formats, allowed_codecs: codecs, profile,
  };
}

const cases = [
  ['valid.mp3','mp3','audio/mpeg',['mp3'],['mp3']],
  ['valid.m4a','m4a','audio/mp4',['mov','mp4','m4a','3gp','3g2','mj2'],['aac']],
  ['valid.aac','aac','audio/aac',['aac'],['aac']],
  ['valid.wav','wav','audio/wav',['wav'],['pcm_s16le']],
  ['valid.flac','flac','audio/flac',['flac'],['flac']],
] as const;

for (const [name, extension, mime, formats, codecs] of cases) {
  test(`ffprobe validates ${extension}`, async () => {
    const path = join(fixtures, name);
    const result = await probeFile('ffprobe', path, 30_000);
    await validateSource(path, await claimFor(path, extension, mime, [...formats], [...codecs]), result.probe);
    assert.equal(result.probe.audioStreamCount, 1);
    assert.ok(result.probe.durationMs > 1_900);
  });
}

test('odd-rate mono source is valid and normalizable', async () => {
  const path = join(fixtures, 'mono-odd-rate.wav');
  const result = await probeFile('ffprobe', path, 30_000);
  await validateSource(path, await claimFor(path, 'wav', 'audio/wav', ['wav'], ['pcm_s16le']), result.probe);
  assert.equal(result.probe.sampleRateHz, 32000);
  assert.equal(result.probe.channels, 1);
});

for (const name of ['fake.mp3','corrupt.mp3','zero.mp3','unsupported.txt']) {
  test(`rejects invalid input ${name}`, async () => {
    await assert.rejects(() => probeFile('ffprobe', join(fixtures, name), 30_000), ProcessingError);
  });
}

test('rejects audio plus video for MVP', async () => {
  await assert.rejects(
    () => probeFile('ffprobe', join(fixtures, 'audio-video.mp4'), 30_000),
    (error: unknown) => error instanceof ProcessingError && error.code === 'VIDEO_STREAM_REJECTED',
  );
});

test('rejects cross-media original object identity', async () => {
  const path = join(fixtures, 'valid.mp3');
  const claim = await claimFor(path, 'mp3', 'audio/mpeg', ['mp3'], ['mp3']);
  claim.original_path = `media/${randomUUID()}/original/${randomUUID()}.mp3`;
  const result = await probeFile('ffprobe', path, 30_000);
  await assert.rejects(() => validateSource(path, claim, result.probe),
    (error: unknown) => error instanceof ProcessingError && error.code === 'OBJECT_KEY_MISMATCH');
});

test('rejects real format that conflicts with declared extension policy', async () => {
  const path = join(fixtures, 'valid.mp3');
  const claim = await claimFor(path, 'wav', 'audio/wav', ['wav'], ['pcm_s16le']);
  const result = await probeFile('ffprobe', path, 30_000);
  await assert.rejects(() => validateSource(path, claim, result.probe),
    (error: unknown) => error instanceof ProcessingError && error.code === 'UNSUPPORTED_FORMAT');
});

test('real two-pass FFmpeg processing preserves duration and normalizes format', async () => {
  await withWorkspace(tmpdir(), 'tarteel-transcode-test', async (directory) => {
    const input = join(fixtures, 'valid.wav');
    const output = join(directory, 'output.m4a');
    const source = await probeFile('ffprobe', input, 30_000);
    const result = await transcode('ffmpeg', 'ffprobe', input, output, source.probe, profile, 60_000, 30_000);
    assert.equal(result.codec, 'aac');
    assert.equal(result.sampleRateHz, 44100);
    assert.equal(result.channels, 2);
    assert.match(result.sha256, /^[0-9a-f]{64}$/);
    assert.ok(Math.abs(result.durationMs - source.probe.durationMs) <= 250);
  });
});

test('argument arrays prevent filename shell injection', async () => {
  const base = join(tmpdir(), `tarteel-injection-${randomUUID()}`);
  await mkdir(base, { recursive: true });
  const marker = join(base, 'PWNED');
  const malicious = join(base, 'input;touch PWNED.wav');
  const output = join(base, 'output.m4a');
  try {
    await cp(join(fixtures, 'valid.wav'), malicious);
    const source = await probeFile('ffprobe', malicious, 30_000);
    await transcode('ffmpeg', 'ffprobe', malicious, output, source.probe, profile, 60_000, 30_000);
    await assert.rejects(() => access(marker));
  } finally { await rm(base, { recursive: true, force: true }); }
});

test('subprocess deadline kills runaway command', async () => {
  await assert.rejects(
    () => runCommand('ffmpeg', ['-nostdin','-f','lavfi','-i','anoisesrc','-t','60','-f','null','-'], 10, 'PROCESSING_TIMEOUT', 'FFMPEG_FAILED'),
    (error: unknown) => error instanceof ProcessingError && error.code === 'PROCESSING_TIMEOUT',
  );
});

test('isolated workspace is removed after success and failure', async () => {
  const root = join(tmpdir(), `tarteel-workspace-${randomUUID()}`);
  let successful = '';
  let failed = '';
  await withWorkspace(root, 'success', async (directory) => { successful = directory; });
  await assert.rejects(() => access(successful));
  await assert.rejects(() => withWorkspace(root, 'failure', async (directory) => {
    failed = directory; throw new Error('expected');
  }));
  await assert.rejects(() => access(failed));
  await rm(root, { recursive: true, force: true });
});
