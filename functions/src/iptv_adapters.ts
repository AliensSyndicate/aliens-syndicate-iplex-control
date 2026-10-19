import {getStorage} from 'firebase-admin/storage';
import {z} from 'zod';
import {Catalog, catalogSchema, fetchProvider, parseM3u, parseXtream} from './catalog';
import {DomainError, hash, sourceSchema} from './domain';
import {normalizeServerEndpoint, xtreamBase} from './iptv_server';

export type Source = z.infer<typeof sourceSchema>;
export type ProviderFetch = typeof fetchProvider;
export type ProviderSnapshot = {proof: string; build: () => Promise<Catalog>; singleStream: boolean};

export interface SourceLimitations {
  readonly supportsEpg: boolean;
  readonly supportsSeries: boolean;
  readonly supportsVod: boolean;
  readonly supportsCatchup: boolean;
  readonly isSingleStream: boolean;
}

export interface IptvSourceAdapter {
  readonly name: string;
  readonly format: string;

  supports(source: Source, sample?: {contentType?: string; body?: string}): Promise<boolean> | boolean;
  validateAccess(source: Source, fetch: ProviderFetch): Promise<void>;
  identifyServer(source: Source): {canonicalEndpoint: string; identityHash: string} | null;
  extractCatalog(source: Source, fid: string, sourceId: string, fetch: ProviderFetch): Promise<ProviderSnapshot>;
  getLimitations(source: Source): SourceLimitations;
}

export function xtreamUrl(source: Source, action?: string, params: Record<string, string> = {}): string {
  const url = new URL('player_api.php', xtreamBase(source.url!));
  url.searchParams.set('username', source.username!);
  url.searchParams.set('password', source.password!);
  if (action) url.searchParams.set('action', action);
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  return url.toString();
}

export async function validateXtream(source: Source, fetch: ProviderFetch): Promise<void> {
  const auth = JSON.parse(await fetch(xtreamUrl(source)));
  const userInfo = auth?.user_info;
  const isAuthValid = [1, '1', true].includes(userInfo?.auth);
  const status = String(userInfo?.status ?? '').toLowerCase().trim();
  const isStatusAllowed = !status || ['active', 'trial', 'enabled', '1', 'true', 'active / valid'].includes(status);
  const isExpired = userInfo?.exp_date && Number(userInfo.exp_date) > 0 && Number(userInfo.exp_date) * 1000 <= Date.now();
  if (!isAuthValid || !isStatusAllowed || isExpired) throw new DomainError('invalid-credentials');
}

export async function playlistBody(source: Source, fid: string, sourceId: string, fetch: ProviderFetch): Promise<string> {
  if (source.format !== 'file') return fetch(source.url!);
  const file = getStorage().bucket().file(source.filePath ?? `source_files/${fid}_${sourceId}.m3u`);
  const [meta] = await file.getMetadata();
  if (Number(meta.size) > 64 * 1024 * 1024) throw new DomainError('catalog-too-large');
  const [body] = await file.download();
  if (body.length > 64 * 1024 * 1024) throw new DomainError('catalog-too-large');
  return body.toString('utf8');
}

export function normalizeSeriesDetail(detail: any): unknown {
  const episodes: Record<string, unknown[]> = {};
  let count = 0;
  for (const [season, rows] of Object.entries(detail.episodes ?? {})) {
    if (!Array.isArray(rows)) throw new DomainError('invalid-catalog');
    episodes[season] = rows.map((row: any) => {
      if (++count > 100000 || !row.id) throw new DomainError('invalid-catalog');
      return {
        id: String(row.id),
        title: String(row.title ?? ''),
        season: row.season ?? season,
        episodeNum: row.episode_num ?? null,
        containerExtension: row.container_extension ?? null,
        ...(row.info?.duration ? {duration: row.info.duration} : {}),
        ...(row.info?.plot ? {plot: row.info.plot} : {}),
      };
    });
  }
  const seasons = Array.isArray(detail.seasons)
    ? detail.seasons.map((s: any) => ({
        id: s.id ?? null,
        name: s.name ?? '',
        seasonNumber: s.season_number ?? null,
        episodeCount: s.episode_count ?? null,
      }))
    : [];
  return {seasons, episodes};
}

export function findM3uStream(body: string, base: string, providerRef: string): string | undefined {
  if (hash(base) === providerRef && /#EXT-X-/.test(body)) return base;
  for (const line of body.split(/\r?\n/).map(x => x.trim())) {
    if (!line || line.startsWith('#')) continue;
    try {
      const url = new URL(line, base || undefined);
      if (['http:', 'https:'].includes(url.protocol) && hash(url.toString()) === providerRef) {
        return url.toString();
      }
    } catch {
      /* not a URL */
    }
  }
  return undefined;
}

/**
 * 1. Xtream Codes / API Adapter
 */
export class XtreamAdapter implements IptvSourceAdapter {
  readonly name = 'Xtream Codes API';
  readonly format = 'xtream';

  supports(source: Source, sample?: {contentType?: string; body?: string}): boolean {
    if (source.format === 'xtream') return true;
    if (!source.url) return false;
    try {
      const u = new URL(source.url);
      if (u.pathname.toLowerCase().includes('player_api.php')) return true;
      if (source.username && source.password && !u.pathname.toLowerCase().includes('get.php')) return true;
      if (sample?.body && sample.body.includes('"user_info"') && sample.body.includes('"auth"')) return true;
    } catch {
      return false;
    }
    return false;
  }

  async validateAccess(source: Source, fetch: ProviderFetch): Promise<void> {
    await validateXtream(source, fetch);
  }

  identifyServer(source: Source): {canonicalEndpoint: string; identityHash: string} | null {
    if (!source.url) return null;
    return normalizeServerEndpoint(source.url, 'xtream');
  }

  async extractCatalog(source: Source, fid: string, sourceId: string, fetch: ProviderFetch): Promise<ProviderSnapshot> {
    const started = Date.now();
    const groups = [
      ['get_live_streams', 'get_live_categories', 'channel'],
      ['get_vod_streams', 'get_vod_categories', 'movie'],
      ['get_series', 'get_series_categories', 'series'],
    ] as const;

    const data: {kind: 'channel' | 'movie' | 'series'; rows: any[]; categories: any[]}[] = [];
    const details: Record<string, unknown> = {};

    for (const [streams, categories, kind] of groups) {
      let rawStreams: any = [];
      let rawCats: any = [];
      try {
        rawStreams = JSON.parse(await fetch(xtreamUrl(source, streams)));
      } catch {
        rawStreams = [];
      }
      try {
        rawCats = JSON.parse(await fetch(xtreamUrl(source, categories)));
      } catch {
        rawCats = [];
      }
      const rows = Array.isArray(rawStreams) ? z.array(z.record(z.unknown())).max(100000).parse(rawStreams) : [];
      const cats = Array.isArray(rawCats)
        ? rawCats
            .filter((c: any) => c && typeof c === 'object' && c.category_id !== undefined)
            .map((c: any) => ({
              category_id: String(c.category_id),
              category_name: String(c.category_name ?? c.name ?? 'General').slice(0, 300),
            }))
        : [];
      data.push({kind, rows, categories: cats});

      if (kind === 'series') {
        for (const row of rows) {
          if (Date.now() - started > 240000) break;
          const id = String(row.series_id ?? '');
          if (!/^\d+$/.test(id)) continue;
          try {
            const detail = JSON.parse(await fetch(xtreamUrl(source, 'get_series_info', {series_id: id})));
            if (detail && typeof detail === 'object' && detail.episodes && typeof detail.episodes === 'object') {
              details[id] = normalizeSeriesDetail(detail);
            }
          } catch {
            // Tolerate single series detail failure
          }
        }
      }
    }

    const proof = hash(`parser-2:${xtreamBase(source.url!).toString()}:${JSON.stringify(data)}:${JSON.stringify(details)}`);
    return {
      proof,
      singleStream: false,
      build: async () => {
        const categories: NonNullable<Catalog['categories']> = data.flatMap(d =>
          d.categories.map(c => ({id: String(c.category_id), name: c.category_name, kind: d.kind}))
        );
        const items = data.flatMap(d => parseXtream(d.rows, d.kind, categories));
        const itemIndex = new Map(items.map(i => [`${i.kind}:${i.providerRef}`, i]));
        for (const group of data) {
          for (let i = 0; i < group.rows.length; i++) {
            const row = group.rows[i]!;
            const item = itemIndex.get(`${group.kind}:${String(row.stream_id ?? row.series_id)}`);
            const image = row.stream_icon ?? row.cover;
            if (item && typeof image === 'string' && image) item.imageRef = hash(image);
          }
        }
        return catalogSchema.parse({schemaVersion: 1, items, categories, seriesDetails: details});
      },
    };
  }

  getLimitations(source: Source): SourceLimitations {
    return {
      supportsEpg: true,
      supportsSeries: true,
      supportsVod: true,
      supportsCatchup: false,
      isSingleStream: false,
    };
  }
}

/**
 * 2. M3U / M3U Plus Playlist Adapter
 */
export class M3uPlaylistAdapter implements IptvSourceAdapter {
  readonly name = 'M3U / M3U Plus Playlist';
  readonly format = 'm3u';

  supports(source: Source, sample?: {contentType?: string; body?: string}): boolean {
    if (source.format === 'file') return true;
    if (source.format === 'm3u') return true;
    if (source.url) {
      const lower = source.url.toLowerCase();
      if (lower.includes('type=m3u') || lower.includes('type=m3u_plus') || lower.endsWith('.m3u') || lower.includes('output=ts')) {
        return true;
      }
    }
    if (sample?.body) {
      const clean = sample.body.replace(/^\uFEFF/, '').trimStart();
      if ((clean.startsWith('#EXTM3U') || clean.startsWith('#EXTINF:')) && !/#EXT-X-(?:STREAM-INF|TARGETDURATION|MEDIA-SEQUENCE):/i.test(clean)) {
        return true;
      }
    }
    return false;
  }

  async validateAccess(source: Source, fetch: ProviderFetch): Promise<void> {
    if (source.format !== 'file' && source.url) {
      // Just test fetch reachability
      const body = await fetch(source.url);
      const clean = body.replace(/^\uFEFF/, '').trimStart();
      if (!clean.startsWith('#EXTM3U') && !clean.startsWith('#EXTINF:')) {
        throw new DomainError('invalid-catalog');
      }
    }
  }

  identifyServer(source: Source): {canonicalEndpoint: string; identityHash: string} | null {
    if (source.format === 'file' || !source.url) return null;
    return normalizeServerEndpoint(source.url, 'playlist');
  }

  async extractCatalog(source: Source, fid: string, sourceId: string, fetch: ProviderFetch): Promise<ProviderSnapshot> {
    const body = await playlistBody(source, fid, sourceId, fetch);
    const singleStream = /#EXT-X-(?:STREAM-INF|TARGETDURATION|MEDIA-SEQUENCE|VERSION):/i.test(body);
    const origin = source.format === 'file' ? 'file' : source.url!;
    return {
      proof: hash(`parser-2:${origin}:${singleStream ? source.name : ''}:${body}`),
      singleStream,
      build: async () => parseM3u(body, source.url ?? '', source.name),
    };
  }

  getLimitations(source: Source): SourceLimitations {
    return {
      supportsEpg: !!source.epgUrl,
      supportsSeries: false,
      supportsVod: true,
      supportsCatchup: false,
      isSingleStream: false,
    };
  }
}

/**
 * 3. HLS Playback Manifest Adapter (Live Stream / Master Manifest / Segment Playlist)
 */
export class HlsManifestAdapter implements IptvSourceAdapter {
  readonly name = 'HLS Playback Manifest';
  readonly format = 'other_m3u8';

  supports(source: Source, sample?: {contentType?: string; body?: string}): boolean {
    if (source.format === 'other_m3u8') return true;
    if (sample?.body) {
      const clean = sample.body.replace(/^\uFEFF/, '').trimStart();
      if (/#EXT-X-(?:STREAM-INF|TARGETDURATION|MEDIA-SEQUENCE|VERSION):/i.test(clean)) {
        return true;
      }
    }
    if (source.url) {
      const lower = source.url.toLowerCase();
      if (lower.endsWith('.m3u8') || lower.includes('.m3u8?')) return true;
    }
    return false;
  }

  async validateAccess(source: Source, fetch: ProviderFetch): Promise<void> {
    if (source.url) {
      const body = await fetch(source.url);
      const clean = body.replace(/^\uFEFF/, '').trimStart();
      if (!clean.startsWith('#EXTM3U') && !/#EXT-X-/.test(clean)) {
        throw new DomainError('invalid-catalog');
      }
    }
  }

  identifyServer(source: Source): {canonicalEndpoint: string; identityHash: string} | null {
    if (!source.url) return null;
    return normalizeServerEndpoint(source.url, 'playlist');
  }

  async extractCatalog(source: Source, fid: string, sourceId: string, fetch: ProviderFetch): Promise<ProviderSnapshot> {
    const body = await playlistBody(source, fid, sourceId, fetch);
    const origin = source.url ?? '';
    const title = source.name.trim().slice(0, 300) || 'Live Stream';
    const providerRef = hash(origin);

    return {
      proof: hash(`parser-2:hls:${origin}:${title}:${body}`),
      singleStream: true,
      build: async () => {
        return catalogSchema.parse({
          schemaVersion: 1,
          items: [
            {
              id: providerRef,
              title,
              titleKey: title.toLowerCase().normalize('NFKD'),
              kind: 'channel',
              category: 'Live Stream',
              providerRef,
            },
          ],
        });
      },
    };
  }

  getLimitations(source: Source): SourceLimitations {
    return {
      supportsEpg: false,
      supportsSeries: false,
      supportsVod: false,
      supportsCatchup: false,
      isSingleStream: true,
    };
  }
}

/**
 * 4. Direct Playback Stream Adapter (.mp4, .mkv, .ts, direct stream)
 */
export class DirectStreamAdapter implements IptvSourceAdapter {
  readonly name = 'Direct Playback Stream';
  readonly format = 'direct_stream';

  supports(source: Source, sample?: {contentType?: string; body?: string}): boolean {
    if (source.format === 'direct_stream') return true;
    if (source.url) {
      const lower = source.url.toLowerCase();
      const directExtensions = ['.mp4', '.mkv', '.ts', '.mpd', '.avi', '.mov', '.flv'];
      if (directExtensions.some(ext => lower.endsWith(ext) || lower.includes(`${ext}?`))) {
        return true;
      }
    }
    if (sample?.contentType) {
      const ct = sample.contentType.toLowerCase();
      if (ct.startsWith('video/') || ct.startsWith('audio/') || ct.includes('dash+xml')) {
        return true;
      }
    }
    return false;
  }

  async validateAccess(source: Source, fetch: ProviderFetch): Promise<void> {
    if (source.url) {
      // Direct stream reachability check
      await fetch(source.url);
    }
  }

  identifyServer(source: Source): {canonicalEndpoint: string; identityHash: string} | null {
    if (!source.url) return null;
    return normalizeServerEndpoint(source.url, 'playlist');
  }

  async extractCatalog(source: Source, fid: string, sourceId: string, fetch: ProviderFetch): Promise<ProviderSnapshot> {
    const origin = source.url ?? '';
    const title = source.name.trim().slice(0, 300) || 'Direct Stream';
    const providerRef = hash(origin);
    const lower = origin.toLowerCase();
    const isMovie = lower.includes('.mp4') || lower.includes('.mkv') || lower.includes('.avi');
    const kind = isMovie ? 'movie' : 'channel';

    return {
      proof: hash(`parser-2:direct:${origin}:${title}`),
      singleStream: true,
      build: async () => {
        return catalogSchema.parse({
          schemaVersion: 1,
          items: [
            {
              id: providerRef,
              title,
              titleKey: title.toLowerCase().normalize('NFKD'),
              kind,
              category: isMovie ? 'Movies' : 'Streams',
              providerRef,
            },
          ],
        });
      },
    };
  }

  getLimitations(source: Source): SourceLimitations {
    return {
      supportsEpg: false,
      supportsSeries: false,
      supportsVod: true,
      supportsCatchup: false,
      isSingleStream: true,
    };
  }
}

/**
 * Extensible Adapter Registry
 */
export class IptvAdapterRegistry {
  private readonly adapters: IptvSourceAdapter[] = [];

  constructor() {
    // Register default adapters in order of specificity
    this.register(new XtreamAdapter());
    this.register(new HlsManifestAdapter());
    this.register(new DirectStreamAdapter());
    this.register(new M3uPlaylistAdapter());
  }

  register(adapter: IptvSourceAdapter): void {
    // Newer / custom adapters take precedence if registered first
    this.adapters.unshift(adapter);
  }

  get(format: string): IptvSourceAdapter | undefined {
    return this.adapters.find(a => a.format === format);
  }

  getAll(): readonly IptvSourceAdapter[] {
    return this.adapters;
  }

  async selectAdapter(source: Source, sample?: {contentType?: string; body?: string}): Promise<IptvSourceAdapter> {
    for (const adapter of this.adapters) {
      if (await adapter.supports(source, sample)) {
        return adapter;
      }
    }
    // Default fallback to M3U only if source is local file
    if (source.format === 'file') {
      const m3u = this.get('m3u');
      if (m3u) return m3u;
    }
    throw new DomainError('unrecognized-source-format', {name: source.name, format: source.format});
  }
}

export const defaultAdapterRegistry = new IptvAdapterRegistry();
