export class ProviderHttpError extends Error {
  readonly status: number;
  readonly code: string;
  constructor(status: number, code: string) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

export async function fetchProviderJson(
  url: string,
  options: {
    fetcher?: typeof fetch;
    maxAttempts?: number;
    timeoutMs?: number;
    onRequest?: (rateLimited: boolean) => void;
    sleep?: (ms: number) => Promise<void>;
  } = {},
): Promise<unknown> {
  const parsed = new URL(url);
  if (parsed.protocol !== 'https:' ||
      !['quranenc.com', 'hadeethenc.com', 'www.mp3quran.net'].includes(parsed.hostname)) {
    throw new ProviderHttpError(400, 'unapproved_provider_host');
  }
  const fetcher = options.fetcher ?? fetch;
  const sleep = options.sleep ?? ((ms: number) => new Promise<void>(resolve => setTimeout(resolve, ms)));
  const attempts = Math.min(3, Math.max(1, options.maxAttempts ?? 3));
  for (let attempt = 0; attempt < attempts; attempt++) {
    let response: Response;
    try {
      options.onRequest?.(false);
      response = await fetcher(url, {
        headers: { accept: 'application/json' },
        signal: AbortSignal.timeout(options.timeoutMs ?? 8000),
      });
    } catch (_) {
      if (attempt + 1 >= attempts) throw new ProviderHttpError(504, 'provider_timeout');
      await sleep(400 * (2 ** attempt));
      continue;
    }
    if (response.status === 429 || response.status >= 500) {
      if (response.status === 429) options.onRequest?.(true);
      if (attempt + 1 >= attempts) {
        throw new ProviderHttpError(response.status, response.status === 429 ? 'provider_rate_limited' : 'provider_unavailable');
      }
      const retryAfter = Number(response.headers.get('retry-after'));
      await sleep(Number.isFinite(retryAfter) && retryAfter > 0
        ? Math.min(10000, retryAfter * 1000) : 400 * (2 ** attempt));
      continue;
    }
    if (!response.ok) throw new ProviderHttpError(response.status, 'provider_http_error');
    try {
      return await response.json();
    } catch (_) {
      throw new ProviderHttpError(502, 'provider_malformed_json');
    }
  }
  throw new ProviderHttpError(503, 'provider_unavailable');
}
