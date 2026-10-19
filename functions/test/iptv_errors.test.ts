import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DomainError} from '../src/domain';
import {
  classifyIptvError,
  isRetryableIptvError,
  logSyncFailure,
  KNOWN_IPTV_ERROR_CODES,
  StructuredSyncLog,
} from '../src/iptv_errors';

test('1. classifyIptvError preserves all known DomainError codes', () => {
  for (const code of KNOWN_IPTV_ERROR_CODES) {
    const err = new DomainError(code, {custom: 123});
    const classified = classifyIptvError(err);
    assert.equal(classified.code, code);
    assert.equal(classified.details.custom, 123);
  }
});

test('2. classifyIptvError maps unexpected DomainError to catalog-sync-failed', () => {
  const err = new DomainError('some-unmapped-internal-error');
  const classified = classifyIptvError(err);
  assert.equal(classified.code, 'catalog-sync-failed');
});

test('3. classifyIptvError correctly classifies non-DomainErrors', () => {
  // SyntaxError -> parsing-failed
  assert.equal(classifyIptvError(new SyntaxError('Unexpected token < in JSON')).code, 'parsing-failed');

  // Network timeouts -> provider-time-budget
  assert.equal(classifyIptvError(new Error('ETIMEDOUT while connecting')).code, 'provider-time-budget');

  // Network reset -> download-failed
  assert.equal(classifyIptvError(new Error('ECONNRESET connection reset by peer')).code, 'download-failed');

  // DNS failure -> provider-unavailable
  assert.equal(classifyIptvError(new Error('getaddrinfo ENOTFOUND server.iptv.com')).code, 'provider-unavailable');

  // Stage-based fallback
  assert.equal(classifyIptvError(new Error('Google Cloud Storage connection drop'), 'uploading_catalog').code, 'storage-upload-failed');
  assert.equal(classifyIptvError(new Error('Transaction contention abort'), 'publishing_catalog').code, 'catalog-publication-failed');
  assert.equal(classifyIptvError(new Error('Corrupt line in playlist'), 'parsing').code, 'parsing-failed');
  assert.equal(classifyIptvError(new Error('Generic network abort'), 'downloading').code, 'download-failed');
});

test('4. isRetryableIptvError identifies temporary vs permanent failures', () => {
  // Temporary / Retryable
  assert.equal(isRetryableIptvError('provider-unavailable'), true);
  assert.equal(isRetryableIptvError('provider-rate-limited'), true);
  assert.equal(isRetryableIptvError('provider-time-budget'), true);
  assert.equal(isRetryableIptvError('download-failed'), true);
  assert.equal(isRetryableIptvError('storage-upload-failed'), true);
  assert.equal(isRetryableIptvError('catalog-publication-failed'), true);
  assert.equal(isRetryableIptvError('timeout'), true);

  // Permanent / Non-retryable
  assert.equal(isRetryableIptvError('invalid-credentials'), false);
  assert.equal(isRetryableIptvError('invalid-source-url'), false);
  assert.equal(isRetryableIptvError('unrecognized-source-format'), false);
  assert.equal(isRetryableIptvError('catalog-too-large'), false);
  assert.equal(isRetryableIptvError('invalid-catalog'), false);
  assert.equal(isRetryableIptvError('suspicious-catalog'), false);
  assert.equal(isRetryableIptvError('duplicate-content'), false);
  assert.equal(isRetryableIptvError('hls-origin-required'), false);
  assert.equal(isRetryableIptvError('unsafe-provider'), false);
  assert.equal(isRetryableIptvError('parsing-failed'), false);
  assert.equal(isRetryableIptvError('normalization-failed'), false);
});

test('5. logSyncFailure sanitizes sensitive tokens and passwords', () => {
  let output = '';
  const originalError = console.error;
  console.error = (msg: string) => {
    output = msg;
  };

  try {
    const log: StructuredSyncLog = {
      level: 'error',
      jobId: 'job-123',
      sourceId: 'src-456',
      catalogId: 'cat-789',
      stage: 'downloading',
      errorCode: 'provider-unavailable',
      errorRetryable: true,
      traceId: 'trace-uuid-1',
      elapsedMs: 250,
      adapter: 'xtream',
      attempts: 1,
      message: 'Failed to fetch https://stream.tv/get.php?username=admin&password=mySecretPassword123&token=tok_98765',
    };

    logSyncFailure(log);

    const parsed = JSON.parse(output);
    assert.equal(parsed.jobId, 'job-123');
    assert.equal(parsed.traceId, 'trace-uuid-1');
    assert.ok(!output.includes('mySecretPassword123'), 'Raw password must be stripped');
    assert.ok(!output.includes('tok_98765'), 'Raw token must be stripped');
    assert.ok(output.includes('password=***'));
    assert.ok(output.includes('token=***'));
  } finally {
    console.error = originalError;
  }
});
