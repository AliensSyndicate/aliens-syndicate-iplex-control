import {DomainError} from './domain';

export const KNOWN_IPTV_ERROR_CODES = [
  'invalid-source-url',
  'unrecognized-source-format',
  'invalid-credentials',
  'provider-unavailable',
  'provider-rate-limited',
  'provider-time-budget',
  'download-failed',
  'catalog-too-large',
  'invalid-catalog',
  'suspicious-catalog',
  'duplicate-content',
  'hls-origin-required',
  'parsing-failed',
  'normalization-failed',
  'storage-upload-failed',
  'catalog-publication-failed',
  'catalog-sync-failed',
  'unsafe-provider',
  'invalid-epg',
  'catalog-integrity',
  'worker-retries-exhausted',
  'source-secret-unavailable',
  'job-superseded',
  'timeout',
] as const;

export type IptvErrorCode = typeof KNOWN_IPTV_ERROR_CODES[number];

/**
 * Categorizes an error code as retryable (temporary) or non-retryable (definitive until user fixes).
 */
export function isRetryableIptvError(code: string): boolean {
  return [
    'provider-unavailable',
    'provider-rate-limited',
    'provider-time-budget',
    'timeout',
    'download-failed',
    'storage-upload-failed',
    'catalog-publication-failed',
  ].includes(code);
}

/**
 * Normalizes an unknown error into a stable IptvErrorCode.
 */
export function classifyIptvError(error: unknown, fallbackStage?: string): {code: IptvErrorCode; details: Record<string, unknown>} {
  if (error instanceof DomainError) {
    const isKnown = (KNOWN_IPTV_ERROR_CODES as readonly string[]).includes(error.code);
    return {
      code: isKnown ? (error.code as IptvErrorCode) : 'catalog-sync-failed',
      details: error.details ?? {},
    };
  }

  if (error instanceof SyntaxError) {
    return {code: 'parsing-failed', details: {reason: 'syntax-error'}};
  }

  if (error && typeof error === 'object' && (error as any).name === 'ZodError') {
    return {code: 'normalization-failed', details: {reason: 'validation-failed'}};
  }

  const message = error instanceof Error ? error.message : String(error);
  if (/timeout|ETIMEDOUT|ESOCKETTIMEDOUT/i.test(message)) {
    return {code: 'provider-time-budget', details: {reason: 'timeout'}};
  }
  if (/ECONNRESET|EPIPE|premature close/i.test(message)) {
    return {code: 'download-failed', details: {reason: 'connection-reset'}};
  }
  if (/ECONNREFUSED|ENOTFOUND|EAI_AGAIN|ENODATA/i.test(message)) {
    return {code: 'provider-unavailable', details: {reason: 'dns-or-connection-refused'}};
  }

  if (fallbackStage === 'uploading_catalog') {
    return {code: 'storage-upload-failed', details: {reason: 'storage-error'}};
  }
  if (fallbackStage === 'publishing_catalog') {
    return {code: 'catalog-publication-failed', details: {reason: 'transaction-error'}};
  }
  if (fallbackStage === 'parsing') {
    return {code: 'parsing-failed', details: {reason: 'parser-crash'}};
  }
  if (fallbackStage === 'downloading') {
    return {code: 'download-failed', details: {reason: 'download-crash'}};
  }

  return {code: 'catalog-sync-failed', details: {}};
}

export interface StructuredSyncLog {
  level: 'info' | 'warn' | 'error';
  jobId: string;
  sourceId: string;
  catalogId?: string | null;
  stage: string;
  errorCode?: string | null;
  errorRetryable?: boolean;
  traceId: string;
  elapsedMs: number;
  adapter: string;
  attempts: number;
  message?: string;
}

/**
 * Emits a structured log guaranteed to contain no passwords, tokens, or raw credentials.
 */
export function logSyncFailure(log: StructuredSyncLog): void {
  // Ensure message has no credentials or URL secrets
  const sanitizedMessage = (log.message ?? '')
    .replace(/(password|pass|secret|token)=[^& \n]*/gi, '$1=***')
    .replace(/(:\/\/[^:]+:)[^@]+(@)/g, '$1***$2');

  console.error(
    JSON.stringify({
      ...log,
      message: sanitizedMessage || undefined,
    })
  );
}
