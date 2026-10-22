import {getStorage} from 'firebase-admin/storage';
import {z} from 'zod';
import {Catalog, catalogSchema, fetchProvider, parseM3uDetailed, parseXtream} from './catalog';
import {DomainError, hash, sourceSchema} from './domain';
import {normalizeServerEndpoint, xtreamBase} from './iptv_server';

export type Source = z.infer<typeof sourceSchema>;
export type ProviderFetch = typeof fetchProvider;
export type ProviderSnapshot = {
  proof: string;
  build: () => Promise<Catalog>;
  singleStream: boolean;
  /** Filled by build(): diagnostic counters (entries, skipped, duplicates, episodes...). */
  stats?: Record<string, number>;
  /** M3U only: providerRef/episode id → stream URL, sealed by the worker so playback never re-downloads the list. */
  streamIndex?: () => Record<string, string>;
};

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

/** The same account exported as one M3U Plus playlist (what IPTV players load
 * from Xtream panels). Carries credentials: never logged or stored in clear. */
export function xtreamM3uPlusUrl(source: Source): string {
  const url = new URL('get.php', xtreamBase(source.url!));
  url.searchParams.set('username', source.username!);
  url.searchParams.set('password', source.password!);
  url.searchParams.set('type', 'm3u_plus');
  url.searchParams.set('output', 'ts');
  return url.toString();
}

/** Only failures of the API itself fall back to the M3U Plus export. Wrong
 * credentials, rate limiting, unsafe or unreachable hosts and size limits never do:
 * the export lives on the same server and would fail the same way. */
export function xtreamFallbackAllowed(error: unknown): boolean {
  if (error instanceof SyntaxError) return true;
  if (!(error instanceof DomainError)) return false;
  const reason = String(error.details?.reason ?? '');
  if (error.code === 'provider-unavailable') return reason === 'http-status' || reason.endsWith('-unexpected-response');
  if (error.code === 'provider-time-budget') return reason !== 'sync-budget';
  return ['parsing-failed', 'download-failed'].includes(error.code);
}

const XTREAM_STREAM_PATH = /\/(live|movie)\/[^/]+\/[^/]+\/(\d{1,20})\.(\w{1,10})$/;

/** Catalog from the M3U Plus export. Live channels and movies keep the API
 * identifiers (id and providerRef of get_live_streams/get_vod_streams), so
 * favourites survive switching paths; series are grouped from episode titles.
 * `streams` maps each playback reference to its URL for the sealed index. */
export function xtreamCatalogFromM3uPlus(body: string, base: string): {catalog: Catalog; stats: Record<string, number>; streams: Record<string, string>} {
  const {catalog, stats} = parseM3uDetailed(body, base);
  const urls = m3uStreamIndex(body, base), streams: Record<string, string> = {}, seen = new Set<string>();
  const items: Catalog['items'] = [];
  let duplicates = stats.duplicates;
  for (const item of catalog.items) {
    const url = urls[item.providerRef];
    const match = url && item.kind !== 'series' ? XTREAM_STREAM_PATH.exec(new URL(url).pathname) : null;
    const next = match && (match[1] === 'live') === (item.kind === 'channel')
      ? {...item, id: hash(`${item.kind}:${match[2]}`), providerRef: match[2]!, ...(item.kind === 'movie' ? {containerExtension: match[3]!} : {})}
      : item;
    if (seen.has(next.id)) { duplicates++; continue; }
    seen.add(next.id);
    items.push(next);
    if (url) streams[next.providerRef] = url;
  }
  for (const detail of Object.values(catalog.seriesDetails ?? {}) as {episodes: Record<string, {id: string}[]>}[]) {
    for (const episode of Object.values(detail.episodes).flat()) if (urls[episode.id]) streams[episode.id] = urls[episode.id]!;
  }
  return {catalog: catalogSchema.parse({...catalog, items}), stats: {...stats, duplicates, xtreamM3uPlus: 1}, streams};
}

/** Xtream answers wrong credentials in several ways: 401/403, an empty body, `[]`,
 * `{"user_info":{"auth":0}}`. An HTML page or other text means the panel/URL is wrong. */
export function parseXtreamJson(body: string, reason: string): any {
  const clean = body.replace(/^\uFEFF/, '').trim();
  if (!clean || clean === '[]' || clean === 'null') throw new DomainError('invalid-credentials', {reason: `${reason}-empty`});
  try { return JSON.parse(clean); }
  catch { throw new DomainError('provider-unavailable', {reason: `${reason}-unexpected-response`}); }
}

export async function validateXtream(source: Source, fetch: ProviderFetch): Promise<void> {
  const auth = parseXtreamJson(await fetch(xtreamUrl(source)), 'xtream-auth');
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

/** Every playable URL of a playlist keyed by its stream reference (hash of the URL). */
export function m3uStreamIndex(body: string, base: string): Record<string, string> {
  const index: Record<string, string> = {};
  if (/#EXT-X-(?:STREAM-INF|TARGETDURATION|MEDIA-SEQUENCE|VERSION):/i.test(body)) {
    if (base) index[hash(base)] = base;
    return index;
  }
  for (const line of body.split(/\r?\n/)) {
    const value = line.trim();
    if (!value || value.startsWith('#')) continue;
    try {
      const url = new URL(value, base.startsWith('http') ? base : undefined);
      if (['http:', 'https:'].includes(url.protocol)) index[hash(url.toString())] ??= url.toString();
    } catch { /* not a URL */ }
  }
  return index;
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

  /** Sources whose API failed (not on credentials) and whose M3U Plus export answered. */
  private readonly m3uPlusSources = new WeakSet<Source>();

  async validateAccess(source: Source, fetch: ProviderFetch): Promise<void> {
    try {
      await validateXtream(source, fetch);
    } catch (error) {
      if (!xtreamFallbackAllowed(error)) throw error;
      await this.m3uPlusFallback(source, fetch, error);
      this.m3uPlusSources.add(source);
    }
  }

  identifyServer(source: Source): {canonicalEndpoint: string; identityHash: string} | null {
    if (!source.url) return null;
    return normalizeServerEndpoint(source.url, 'xtream');
  }

  /** M3U Plus export of the account, or the original API error when the export
   * fails too (its own wrong-credentials answer wins: it is conclusive). */
  private async m3uPlusFallback(source: Source, fetch: ProviderFetch, apiError: unknown, announce = true): Promise<ProviderSnapshot> {
    const base = xtreamBase(source.url!).toString();
    let body: string;
    try {
      body = await fetch(xtreamM3uPlusUrl(source));
    } catch (error) {
      if (error instanceof DomainError && error.code === 'invalid-credentials') throw error;
      throw apiError;
    }
    const clean = body.replace(/^﻿/, '').trimStart();
    if (!clean.startsWith('#EXTM3U') && !clean.startsWith('#EXTINF:')) throw apiError;
    // Codes and reasons only: never the URL, host credentials or response body.
    if (announce) console.warn(JSON.stringify({component: 'iptv-xtream', event: 'm3u-plus-fallback',
      apiCode: apiError instanceof DomainError ? apiError.code : (apiError as Error)?.name,
      apiReason: apiError instanceof DomainError ? apiError.details?.reason ?? apiError.details?.statusCode ?? null : null}));
    let parsed: ReturnType<typeof xtreamCatalogFromM3uPlus> | undefined;
    const result = () => (parsed ??= xtreamCatalogFromM3uPlus(body, base));
    const snapshot: ProviderSnapshot = {
      proof: hash(`parser-6:xtream-m3u-plus:${base}:${body}`),
      singleStream: false,
      build: async () => {
        const {catalog, stats} = result();
        snapshot.stats = stats;
        return catalog;
      },
      streamIndex: () => result().streams,
    };
    return snapshot;
  }

  async extractCatalog(source: Source, fid: string, sourceId: string, fetch: ProviderFetch): Promise<ProviderSnapshot> {
    // Already announced by validateAccess; the export body is shared by the sync's fetch.
    if (this.m3uPlusSources.has(source)) return this.m3uPlusFallback(source, fetch, new DomainError('provider-unavailable'), false);
    let data: {kind: 'channel' | 'movie' | 'series'; rows: unknown[]; categories: {category_id: string; category_name: string}[]}[];
    try {
      data = await this.apiLists(source, fetch);
    } catch (error) {
      if (!xtreamFallbackAllowed(error)) throw error;
      return this.m3uPlusFallback(source, fetch, error);
    }
    // Every type answered "not implemented"/empty: the export may still list the account.
    if (data.every(d => !d.rows.length)) {
      try { return await this.m3uPlusFallback(source, fetch, new DomainError('provider-unavailable', {reason: 'empty-api-lists'})); }
      catch { /* an empty account stays empty (rejected later as suspicious-catalog) */ }
    }
    // Episodes are fetched on demand (readSourceSeries), like IPTV players do:
    // one get_series_info per series during sync does not scale to large panels.
    const snapshot: ProviderSnapshot = {
      proof: hash(`parser-6:${xtreamBase(source.url!).toString()}:${JSON.stringify(data)}`),
      singleStream: false,
      build: async () => {
        const categories: NonNullable<Catalog['categories']> = data.flatMap(d =>
          d.categories.map(c => ({id: String(c.category_id), name: c.category_name, kind: d.kind}))
        );
        const counters = {skipped: 0};
        const items = data.flatMap(d => parseXtream(d.rows, d.kind, categories, counters));
        snapshot.stats = {entries: data.reduce((n, d) => n + d.rows.length, 0), skipped: counters.skipped};
        return catalogSchema.parse({schemaVersion: 1, items, categories});
      },
    };
    return snapshot;
  }

  private async apiLists(source: Source, fetch: ProviderFetch) {
    const groups = [
      ['get_live_streams', 'get_live_categories', 'channel'],
      ['get_vod_streams', 'get_vod_categories', 'movie'],
      ['get_series', 'get_series_categories', 'series'],
    ] as const;
    // Main lists: one retry on transient failures, then fail closed (a partial
    // catalog would silently remove a whole content type). A 200 that is not a
    // list (panel without VOD/series) is an empty type. Categories are optional.
    const list = async (action: string, required: boolean): Promise<unknown[]> => {
      for (let attempt = 0; ; attempt++) {
        try {
          const body = (await fetch(xtreamUrl(source, action))).replace(/^\uFEFF/, '').trim();
          if (!body) return [];
          const parsed = JSON.parse(body);
          return Array.isArray(parsed) ? parsed : [];
        } catch (error) {
          if (!required) return [];
          // Panels without VOD/series answer "not implemented": that type is empty, not a failure.
          if (error instanceof DomainError && [400, 404, 405, 501].includes(Number(error.details?.statusCode))) return [];
          const transient = error instanceof DomainError && ['provider-unavailable', 'download-failed', 'provider-time-budget'].includes(error.code);
          if (error instanceof SyntaxError) throw new DomainError('parsing-failed', {reason: `${action}-invalid-json`});
          if (!transient || attempt >= 1) throw error;
        }
      }
    };
    const data: {kind: 'channel' | 'movie' | 'series'; rows: unknown[]; categories: {category_id: string; category_name: string}[]}[] = [];
    for (const [streams, categories, kind] of groups) {
      const rows = await list(streams, true);
      const cats = (await list(categories, false))
        .filter((c: any) => c && typeof c === 'object' && c.category_id !== undefined)
        .map((c: any) => ({category_id: String(c.category_id), category_name: String(c.category_name ?? c.name ?? 'General').slice(0, 300)}));
      data.push({kind, rows, categories: cats});
    }
    return data;
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
    const snapshot: ProviderSnapshot = {
      proof: hash(`parser-6:${origin}:${singleStream ? source.name : ''}:${body}`),
      singleStream,
      build: async () => {
        const {catalog, stats} = parseM3uDetailed(body, source.url ?? '', source.name);
        snapshot.stats = stats;
        return catalog;
      },
      streamIndex: () => m3uStreamIndex(body, source.url ?? ''),
    };
    return snapshot;
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
