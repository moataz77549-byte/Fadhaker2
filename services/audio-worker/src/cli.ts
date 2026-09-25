import { runCommand } from './subprocess.js';
import { loadConfig } from './config.js';
import { AudioWorker } from './worker.js';
import { Logger } from './logger.js';

const logger = new Logger();
const command = process.argv[2];

async function checkDependencies(): Promise<void> {
  const config = loadConfig(false);
  const ffmpeg = await runCommand(config.ffmpegPath, ['-version'], 10_000, 'PROCESSING_TIMEOUT', 'WORKER_INTERNAL_ERROR');
  const ffprobe = await runCommand(config.ffprobePath, ['-version'], 10_000, 'FFPROBE_TIMEOUT', 'WORKER_INTERNAL_ERROR');
  logger.info('DEPENDENCIES_OK', { ffmpeg: ffmpeg.stdout.split('\n')[0], ffprobe: ffprobe.stdout.split('\n')[0], node: process.version });
}

async function main(): Promise<void> {
  if (command === 'check-dependencies') return await checkDependencies();
  const config = loadConfig(true);
  const worker = new AudioWorker(config);
  const shutdown = () => worker.stop();
  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);
  if (command === 'run-once') { await worker.runOnce(); return; }
  if (command === 'run') { await worker.run(); return; }
  throw new Error('Usage: cli.js check-dependencies|run-once|run');
}

main().catch((error) => { logger.error('WORKER_FATAL', error); process.exitCode = 1; });
