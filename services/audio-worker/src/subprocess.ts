import { spawn } from 'node:child_process';
import { ProcessingError } from './errors.js';
import type { ErrorCode } from './types.js';

export interface CommandResult { stdout: string; stderr: string; durationMs: number; }

export async function runCommand(
  executable: string,
  args: readonly string[],
  timeoutMs: number,
  timeoutCode: ErrorCode,
  failureCode: ErrorCode,
): Promise<CommandResult> {
  const started = performance.now();
  return await new Promise((resolve, reject) => {
    const child = spawn(executable, [...args], {
      shell: false,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { PATH: process.env.PATH ?? '/usr/bin:/bin', LANG: 'C.UTF-8', LC_ALL: 'C.UTF-8' },
    });
    let stdout = '';
    let stderr = '';
    const append = (current: string, data: Buffer): string => (current + data.toString('utf8')).slice(-32_768);
    child.stdout.on('data', (data: Buffer) => { stdout = append(stdout, data); });
    child.stderr.on('data', (data: Buffer) => { stderr = append(stderr, data); });
    let timedOut = false;
    const timer = setTimeout(() => { timedOut = true; child.kill('SIGKILL'); }, timeoutMs);
    child.once('error', (error) => { clearTimeout(timer); reject(new ProcessingError(failureCode, `Unable to start ${executable}`, error)); });
    child.once('close', (code) => {
      clearTimeout(timer);
      const durationMs = Math.round(performance.now() - started);
      if (timedOut) return reject(new ProcessingError(timeoutCode, `${executable} exceeded ${timeoutMs}ms`));
      if (code !== 0) return reject(new ProcessingError(failureCode, `${executable} exited ${code}: ${stderr.slice(-2000)}`));
      resolve({ stdout, stderr, durationMs });
    });
  });
}
