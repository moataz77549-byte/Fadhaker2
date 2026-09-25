import test from 'node:test';
import assert from 'node:assert/strict';
import { Logger } from '../src/logger.js';
import { ProcessingError, safeErrorMessage } from '../src/errors.js';
import { loadConfig } from '../src/config.js';

test('error redaction removes service secrets and bearer tokens', () => {
  const message = safeErrorMessage(new Error('sb_secret_ABC-def Bearer abc.def token=signed-value'));
  assert.doesNotMatch(message, /ABC-def|abc\.def|signed-value/);
  assert.match(message, /REDACTED/);
});

test('structured logger redacts sensitive field names', () => {
  const writes: string[] = [];
  const original = process.stdout.write.bind(process.stdout);
  process.stdout.write = ((chunk: any) => { writes.push(String(chunk)); return true; }) as any;
  try { new Logger().info('TEST', { authorization: 'Bearer secret', signed_url: 'https://secret' }); }
  finally { process.stdout.write = original; }
  assert.doesNotMatch(writes.join(''), /Bearer secret|https:\/\/secret/);
});

test('unsafe heartbeat/lease configuration is rejected', () => {
  const previousLease = process.env.TARTEEL_AUDIO_WORKER_LEASE_SECONDS;
  const previousHeartbeat = process.env.TARTEEL_AUDIO_WORKER_HEARTBEAT_SECONDS;
  process.env.TARTEEL_AUDIO_WORKER_LEASE_SECONDS = '60';
  process.env.TARTEEL_AUDIO_WORKER_HEARTBEAT_SECONDS = '30';
  try { assert.throws(() => loadConfig(false), ProcessingError); }
  finally {
    if (previousLease === undefined) delete process.env.TARTEEL_AUDIO_WORKER_LEASE_SECONDS; else process.env.TARTEEL_AUDIO_WORKER_LEASE_SECONDS = previousLease;
    if (previousHeartbeat === undefined) delete process.env.TARTEEL_AUDIO_WORKER_HEARTBEAT_SECONDS; else process.env.TARTEEL_AUDIO_WORKER_HEARTBEAT_SECONDS = previousHeartbeat;
  }
});
