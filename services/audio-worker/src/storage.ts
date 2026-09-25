import { createReadStream } from 'node:fs';
import { open, stat } from 'node:fs/promises';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { ProcessingError, safeErrorMessage } from './errors.js';

export class TrustedStorage {
  private readonly client: SupabaseClient<any, any, any>;
  constructor(private readonly url: string, private readonly secretKey: string) {
    this.client = createClient<any>(url, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
  }

  async download(bucket: string, objectKey: string, destination: string, timeoutMs: number): Promise<void> {
    if (bucket !== 'tarteel-media-originals') throw new ProcessingError('OBJECT_KEY_MISMATCH', 'Unexpected original bucket');
    this.validateKey(objectKey, /^media\/[0-9a-f-]{36}\/original\/[0-9a-f-]{36}\.[a-z0-9]+$/);
    const encodedKey = objectKey.split('/').map(encodeURIComponent).join('/');
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(`${this.url}/storage/v1/object/authenticated/${bucket}/${encodedKey}`, {
        headers: { apikey: this.secretKey, authorization: `Bearer ${this.secretKey}` },
        signal: controller.signal,
      });
      if (!response.ok || !response.body) throw new ProcessingError('DOWNLOAD_FAILED', `Storage download returned HTTP ${response.status}`);
      const handle = await open(destination, 'wx', 0o600);
      try { await pipeline(Readable.fromWeb(response.body as any), handle.createWriteStream()); }
      finally { await handle.close().catch(() => undefined); }
    } catch (error) {
      if (error instanceof ProcessingError) throw error;
      throw new ProcessingError('DOWNLOAD_FAILED', safeErrorMessage(error), error);
    } finally { clearTimeout(timer); }
  }

  async uploadProcessed(objectKey: string, path: string, mimeType: string, sha256: string): Promise<void> {
    this.validateKey(objectKey, /^media\/[0-9a-f-]{36}\/processed\/audio-standard-v1\/v[0-9]+\/[0-9a-f-]{36}\.m4a$/);
    const file = await stat(path);
    if (file.size <= 0 || file.size > 52_428_800) throw new ProcessingError('OUTPUT_INVALID', 'Processed file size is outside bucket limits');
    const stream = createReadStream(path);
    const chunks: Buffer[] = [];
    for await (const chunk of stream) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    const bytes = Buffer.concat(chunks);
    const { error } = await this.client.storage.from('tarteel-media-processed').upload(objectKey, bytes, {
      contentType: mimeType, upsert: false, cacheControl: '3600', metadata: { sha256 },
    });
    if (error) throw new ProcessingError('STORAGE_FAILED', safeErrorMessage(error), error);
  }

  async removeProcessed(objectKey: string): Promise<void> {
    this.validateKey(objectKey, /^media\/[0-9a-f-]{36}\/processed\//);
    await this.client.storage.from('tarteel-media-processed').remove([objectKey]);
  }

  private validateKey(key: string, pattern: RegExp): void {
    if (!pattern.test(key) || key.includes('..') || key.includes('\\') || /[\0-\x1f\x7f]/.test(key)) {
      throw new ProcessingError('OBJECT_KEY_MISMATCH', 'Invalid or unsafe object key');
    }
  }
}
