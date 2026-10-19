import {DomainError, sourceSchema} from './domain';
import {
  defaultAdapterRegistry,
  IptvAdapterRegistry,
  IptvSourceAdapter,
  ProviderFetch,
  Source,
} from './iptv_adapters';

export interface DetectionResult {
  readonly detectedFormat: string;
  readonly adapter: IptvSourceAdapter;
  readonly confidence: number;
  readonly isSingleStream: boolean;
  readonly sample?: {contentType?: string; bodyPreview?: string};
}

/**
 * Sanitizes URLs for logging without exposing credentials or tokens.
 */
export function sanitizeLogUrl(rawUrl?: string): string {
  if (!rawUrl) return '<empty>';
  try {
    const u = new URL(rawUrl);
    const sanitizedParams = new URLSearchParams();
    for (const [k, v] of u.searchParams.entries()) {
      if (/username|user|password|pass|token|key|secret/i.test(k)) {
        sanitizedParams.set(k, '***');
      } else {
        sanitizedParams.set(k, v);
      }
    }
    u.search = sanitizedParams.toString();
    return u.toString();
  } catch {
    return '<invalid-url>';
  }
}

/**
 * IPTV Source Automatic Detection Service.
 * Implements the CODEX Detection Pipeline:
 *
 * Source Registered
 *        |
 *        v
 * Input Validation
 *        |
 *        v
 * Format Identification (URL, params, content signature, headers)
 *        |
 *        v
 * Adapter Selection
 *        |
 *        v
 * Access Validation
 *        |
 *        v
 * Content Extraction & Normalization -> JSON Catalog
 */
export async function detectSourceFormat(
  source: Source,
  fetch: ProviderFetch,
  registry: IptvAdapterRegistry = defaultAdapterRegistry
): Promise<DetectionResult> {
  // 1. Input Validation
  sourceSchema.parse(source);

  // 2. File sources directly map to M3U
  if (source.format === 'file') {
    const adapter = registry.get('m3u')!;
    return {
      detectedFormat: 'file',
      adapter,
      confidence: 1.0,
      isSingleStream: false,
    };
  }

  if (!source.url) {
    throw new DomainError('unrecognized-source-format', {reason: 'missing-url'});
  }

  const rawUrl = source.url;
  let parsedUrl: URL;
  try {
    parsedUrl = new URL(rawUrl);
  } catch {
    throw new DomainError('unrecognized-source-format', {reason: 'invalid-url-structure'});
  }

  const pathnameLower = parsedUrl.pathname.toLowerCase();
  const searchLower = parsedUrl.search.toLowerCase();

  // 3. Heuristic inspection of URL structure
  // Xtream Codes endpoint inspection
  const hasXtreamPath = pathnameLower.includes('player_api.php');
  const hasGetPhp = pathnameLower.includes('get.php');
  const hasM3uParam = searchLower.includes('type=m3u') || searchLower.includes('type=m3u_plus') || searchLower.includes('output=ts');
  const hasHlsExt = pathnameLower.endsWith('.m3u8') || searchLower.includes('.m3u8');
  const hasM3uExt = pathnameLower.endsWith('.m3u') || searchLower.includes('.m3u');
  const hasDirectMediaExt = ['.mp4', '.mkv', '.ts', '.mpd', '.avi', '.mov', '.flv'].some(
    ext => pathnameLower.endsWith(ext) || searchLower.includes(`${ext}`)
  );

  // Specific check: get.php with m3u parameters is NOT Xtream JSON API; it's an M3U playlist!
  if (hasGetPhp && hasM3uParam) {
    const adapter = registry.get('m3u')!;
    return {
      detectedFormat: 'm3u',
      adapter,
      confidence: 0.95,
      isSingleStream: false,
    };
  }

  if (hasXtreamPath || (source.format === 'xtream' && source.username && source.password)) {
    const adapter = registry.get('xtream')!;
    return {
      detectedFormat: 'xtream',
      adapter,
      confidence: 0.95,
      isSingleStream: false,
    };
  }

  if (hasDirectMediaExt) {
    const adapter = registry.get('direct_stream')!;
    return {
      detectedFormat: 'direct_stream',
      adapter,
      confidence: 0.9,
      isSingleStream: true,
    };
  }

  // 4. Sample Probe: Dynamic Content Signature Detection
  let sampleBody = '';
  try {
    sampleBody = await fetch(rawUrl);
  } catch (err: any) {
    // If explicit format was provided, allow fallback to matching adapter
    if (source.format === 'other_m3u8') {
      return {
        detectedFormat: 'other_m3u8',
        adapter: registry.get('other_m3u8')!,
        confidence: 0.7,
        isSingleStream: true,
      };
    }
    if (source.format === 'm3u' || source.format === 'url') {
      return {
        detectedFormat: 'm3u',
        adapter: registry.get('m3u')!,
        confidence: 0.6,
        isSingleStream: false,
      };
    }
    throw err;
  }

  const cleanSample = sampleBody.replace(/^\uFEFF/, '').trimStart();
  const sampleSnippet = cleanSample.slice(0, 500);

  // Check for HLS manifest tags vs M3U playlist tags
  const isHlsPlayback = /#EXT-X-(?:STREAM-INF|TARGETDURATION|MEDIA-SEQUENCE|VERSION):/i.test(cleanSample);
  if (isHlsPlayback || source.format === 'other_m3u8' || (hasHlsExt && !cleanSample.includes('#EXTINF:'))) {
    const adapter = registry.get('other_m3u8')!;
    return {
      detectedFormat: 'other_m3u8',
      adapter,
      confidence: 0.98,
      isSingleStream: true,
      sample: {bodyPreview: sampleSnippet},
    };
  }

  if (cleanSample.startsWith('#EXTM3U') || cleanSample.startsWith('#EXTINF:')) {
    const adapter = registry.get('m3u')!;
    return {
      detectedFormat: 'm3u',
      adapter,
      confidence: 0.98,
      isSingleStream: false,
      sample: {bodyPreview: sampleSnippet},
    };
  }

  // Check for JSON response (Xtream or JSON metadata)
  if (cleanSample.startsWith('{') && cleanSample.includes('"user_info"')) {
    const adapter = registry.get('xtream')!;
    return {
      detectedFormat: 'xtream',
      adapter,
      confidence: 0.95,
      isSingleStream: false,
      sample: {bodyPreview: sampleSnippet},
    };
  }

  // Check if adapter can recognize via adapter registry
  const adapter = await registry.selectAdapter(source, {body: cleanSample});
  return {
    detectedFormat: adapter.format,
    adapter,
    confidence: 0.85,
    isSingleStream: adapter.getLimitations(source).isSingleStream,
    sample: {bodyPreview: sampleSnippet},
  };
}
