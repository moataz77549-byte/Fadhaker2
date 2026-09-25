import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';

export async function withWorkspace<T>(root: string, jobId: string, work: (directory: string) => Promise<T>): Promise<T> {
  await mkdir(root, { recursive: true, mode: 0o700 });
  const safePrefix = jobId.replace(/[^A-Za-z0-9-]/g, '').slice(0, 64);
  const directory = await mkdtemp(join(root, `${safePrefix}-`));
  try { return await work(directory); }
  finally { await rm(directory, { recursive: true, force: true }); }
}
