import {lookup} from 'node:dns/promises';
import http from 'node:http';
import https from 'node:https';
import zlib from 'node:zlib';
import ipaddr from 'ipaddr.js';
import {z} from 'zod';
import {DomainError,hash} from './domain';
import {normalizeAgeRating} from './content_audience';
export const itemSchema=z.object({id:z.string(),title:z.string().min(1).max(300),titleKey:z.string(),kind:z.enum(['channel','movie','series']),category:z.string().max(300),providerRef:z.string(),epgId:z.string().max(300).optional(),categoryId:z.string().optional(),imageRef:z.string().optional(),containerExtension:z.string().max(20).optional(),plot:z.string().max(10000).optional(),year:z.union([z.string(),z.number()]).optional(),rating:z.union([z.string(),z.number()]).optional(),ageRating:z.string().max(20).optional()});
export const catalogSchema=z.object({schemaVersion:z.literal(1),items:z.array(itemSchema).max(100000),categories:z.array(z.object({id:z.string(),name:z.string(),kind:z.enum(['channel','movie','series'])})).optional(),seriesDetails:z.record(z.unknown()).optional()});
export type Catalog=z.infer<typeof catalogSchema>;
export function publicAddress(value:string):boolean {
 try{return ipaddr.process(value).range()==='unicast';}catch{return false;}
}
/** DNS answer pinned to an address already checked by publicAddress. */
export function pinnedLookup(address: {address: string; family: number}) {
  return (_host: string, opts: unknown, cb?: (...args: unknown[]) => void) => {
    const callback = (typeof opts === 'function' ? opts : cb) as (...args: unknown[]) => void;
    if (typeof opts === 'object' && opts !== null && (opts as {all?: boolean}).all) callback(null, [address]);
    else callback(null, address.address, address.family);
  };
}
export const PROVIDER_LIMITS = {maxBytes: 64 * 1024 * 1024, idleMs: 30_000, totalMs: 180_000, maxRedirects: 5, maxItems: 100_000};
/**
 * User-Agents tried in order when a provider answers 401/403. Many IPTV panels
 * filter by client: the first is the common IPTV player, the second is the plain
 * OkHttp client used by Android IPTV shells (e.g. Dream+TV), the third VLC.
 */
export const PROVIDER_USER_AGENTS = ['IPTVSmarters/1.0 (Linux; Android 12)', 'okhttp/4.12.0', 'VLC/3.0.20 LibVLC/3.0.20'];
export type ProviderFetchOptions = {
  /** Tests only (controlled local provider). Production never allows private addresses. */
  allowPrivateAddress?: boolean;
  userAgents?: string[];
  limits?: Partial<typeof PROVIDER_LIMITS>;
};
/** Diagnostic record without credentials: host only, never path/query/userinfo. */
export function providerLog(event: string, url: URL, extra: Record<string, unknown>) {
  console.info(JSON.stringify({component: 'iptv-fetch', event, host: url.hostname, port: url.port || null, scheme: url.protocol.replace(':', ''), ...extra}));
}
/** Charset from Content-Type; otherwise strict UTF-8 with Windows-1252 fallback (common in older IPTV lists). */
export function decodeProviderBody(body: Buffer, contentType = ''): string {
  const declared = /charset=([^;\s]+)/i.exec(contentType)?.[1]?.toLowerCase().replace(/["']/g, '');
  if (declared && !['utf-8', 'utf8'].includes(declared)) {
    try { return new TextDecoder(declared === 'latin1' ? 'windows-1252' : declared).decode(body); } catch { /* unknown label */ }
  }
  try { return new TextDecoder('utf-8', {fatal: true}).decode(body); }
  catch { return new TextDecoder('windows-1252').decode(body); }
}
function decompress(res: http.IncomingMessage): NodeJS.ReadableStream {
  const encoding = String(res.headers['content-encoding'] ?? '').toLowerCase();
  if (encoding === 'gzip' || encoding === 'x-gzip') return res.pipe(zlib.createGunzip());
  if (encoding === 'deflate') return res.pipe(zlib.createInflate());
  if (encoding === 'br') return res.pipe(zlib.createBrotliDecompress());
  return res;
}
// Resolve once and pin the connection to a checked address (SSRF-safe), follow
// redirects, decompress, cap size/time and classify every failure with a stable code.
export function createProviderFetch(options: ProviderFetchOptions = {}): (raw: string) => Promise<string> {
  const limits = {...PROVIDER_LIMITS, ...options.limits};
  const agents = options.userAgents ?? PROVIDER_USER_AGENTS;
  const allowed = (address: string) => options.allowPrivateAddress === true || publicAddress(address);
  const request = async (raw: string, agent: number, hops: number, started: number): Promise<string> => {
    if (hops > limits.maxRedirects) throw new DomainError('provider-unavailable', {reason: 'too-many-redirects'});
    let url: URL;
    try { url = new URL(raw); } catch { throw new DomainError('invalid-source-url', {reason: 'invalid-url'}); }
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) throw new DomainError('unsafe-provider');
    const hostname = url.hostname.replace(/^\[|\]$/g, '');
    let address: {address: string; family: number};
    if (ipaddr.isValid(hostname)) address = {address: hostname, family: hostname.includes(':') ? 6 : 4};
    else {
      let addresses;
      try { addresses = await lookup(hostname, {all: true}); }
      catch (err: any) {
        throw new DomainError('provider-unavailable', {reason: ['ENOTFOUND', 'EAI_AGAIN', 'ENODATA'].includes(err?.code) ? 'host-not-found' : 'dns-lookup-failed'});
      }
      if (!addresses.length) throw new DomainError('provider-unavailable', {reason: 'host-not-found'});
      if (addresses.some(x => !allowed(x.address))) throw new DomainError('unsafe-provider');
      address = addresses[0]!;
    }
    if (!allowed(address.address)) throw new DomainError('unsafe-provider');
    const transport = url.protocol === 'https:' ? https : http;
    const remaining = limits.totalMs - (Date.now() - started);
    if (remaining <= 0) throw new DomainError('provider-time-budget', {reason: 'total-timeout'});
    return new Promise<string>((resolve, reject) => {
      let settled = false;
      const done = (fn: () => void) => { if (!settled) { settled = true; clearTimeout(total); fn(); } };
      const fail = (error: DomainError) => done(() => { req.destroy(); providerLog('fetch-failed', url, {code: error.code, ...error.details, ms: Date.now() - started, agent}); reject(error); });
      const total = setTimeout(() => fail(new DomainError('provider-time-budget', {reason: 'total-timeout'})), remaining);
      const req = transport.get(url, {
        // Node >= 20 asks for `{all: true}` (happy eyeballs) and expects an array.
        lookup: pinnedLookup(address) as any,
        headers: {'user-agent': agents[agent]!, accept: 'application/json,application/x-mpegURL,audio/x-mpegurl,text/plain,*/*', 'accept-encoding': 'gzip, deflate, identity', connection: 'close'},
      }, res => {
        const status = res.statusCode ?? 0;
        if ([301, 302, 303, 307, 308].includes(status) && res.headers.location) {
          res.resume();
          done(() => request(new URL(res.headers.location!, url).toString(), agent, hops + 1, started).then(resolve, reject));
          return;
        }
        if ((status === 401 || status === 403) && agent + 1 < agents.length) {
          res.resume();
          // Some panels only answer known player clients: same URL, next User-Agent.
          done(() => request(raw, agent + 1, hops, started).then(resolve, reject));
          return;
        }
        if (status === 429) { res.resume(); fail(new DomainError('provider-rate-limited', {statusCode: status})); return; }
        if (status === 401 || status === 403) { res.resume(); fail(new DomainError('invalid-credentials', {statusCode: status})); return; }
        if (status < 200 || status >= 300) { res.resume(); fail(new DomainError('provider-unavailable', {reason: 'http-status', statusCode: status})); return; }
        const declared = Number(res.headers['content-length'] ?? 0);
        if (declared > limits.maxBytes) { res.resume(); fail(new DomainError('catalog-too-large', {bytes: declared})); return; }
        const chunks: Buffer[] = [];
        let size = 0;
        const stream = decompress(res);
        stream.on('data', (chunk: Buffer) => {
          size += chunk.length;
          if (size > limits.maxBytes) fail(new DomainError('catalog-too-large', {bytes: size}));
          else chunks.push(chunk);
        });
        stream.on('end', () => done(() => {
          const body = decodeProviderBody(Buffer.concat(chunks), String(res.headers['content-type'] ?? ''));
          providerLog('fetch-ok', url, {status, bytes: size, ms: Date.now() - started, agent});
          resolve(body);
        }));
        stream.on('error', (err: any) => fail(new DomainError('download-failed', {reason: 'body-error', code: err?.code})));
        res.on('aborted', () => fail(new DomainError('download-failed', {reason: 'connection-aborted'})));
      });
      req.setTimeout(limits.idleMs, () => fail(new DomainError('provider-time-budget', {reason: 'idle-timeout'})));
      req.on('error', (err: any) => {
        if (['ECONNRESET', 'EPIPE'].includes(err?.code)) fail(new DomainError('download-failed', {reason: 'connection-reset', code: err.code}));
        else if (['CERT_HAS_EXPIRED', 'DEPTH_ZERO_SELF_SIGNED_CERT', 'SELF_SIGNED_CERT_IN_CHAIN', 'UNABLE_TO_VERIFY_LEAF_SIGNATURE', 'ERR_TLS_CERT_ALTNAME_INVALID'].includes(err?.code))
          fail(new DomainError('provider-unavailable', {reason: 'tls-certificate', code: err.code}));
        else fail(new DomainError('provider-unavailable', {reason: 'connection-failed', code: err?.code}));
      });
    });
  };
  return raw => request(raw, 0, 0, Date.now());
}
/**
 * Integration tests against a controlled local IPTV server need private
 * addresses. Only honored with emulators on a demo-* project and an explicit
 * flag; production (iplex-2c8fc, no emulator) always keeps SSRF protection.
 */
export function privateProvidersAllowedForTests(env: NodeJS.ProcessEnv = process.env): boolean {
  return env.IPLEX_TEST_PRIVATE_PROVIDERS === '1' && !!env.FIRESTORE_EMULATOR_HOST && /^demo-/.test(env.GCLOUD_PROJECT ?? env.GOOGLE_CLOUD_PROJECT ?? '');
}
const productionFetch = createProviderFetch(), testFetch = createProviderFetch({allowPrivateAddress: true});
export const fetchProvider = (raw: string): Promise<string> => (privateProvidersAllowedForTests() ? testFetch : productionFetch)(raw);

export type M3uStats = {entries: number; skipped: number; duplicates: number; episodes: number};
const SERIES_EPISODE = /^(.*?)[\s._\-–|:]*\bS(\d{1,3})[\s._-]*E(\d{1,4})\b\s*[-–|:]?\s*(.*)$/i;
const VOD_EXTENSION = /\.(mp4|mkv|avi|mov|wmv|m4v)$/i;
function attribute(line: string, name: string): string {
  return new RegExp(`${name}="([^"]*)"`, 'i').exec(line)?.[1]?.trim() ?? '';
}
function titleOf(value: string): string {
  return value.replace(/\s+/g, ' ').trim().slice(0, 300);
}
/**
 * Tolerant M3U / M3U Plus parser. One bad, unsupported or repeated entry never
 * invalidates the list: it is skipped and counted. Xtream "M3U Plus" exports are
 * classified by path (/movie/, /series/); series episodes (SxxEyy) are grouped
 * into one series item with seasons and episodes (episode id = stream reference).
 */
export function parseM3uDetailed(body: string, sourceUrl = '', sourceName = ''): {catalog: Catalog; stats: M3uStats} {
  const clean = body.replace(/^﻿/, '').trimStart();
  if (!clean.startsWith('#EXTM3U') && !clean.startsWith('#EXTINF:')) throw new DomainError('invalid-catalog', {reason: 'not-m3u'});
  // HLS media segments may have EXTINF titles. Classify the whole manifest
  // before parsing entries so segments never become independent IPTV channels.
  if (/#EXT-X-(?:STREAM-INF|TARGETDURATION|MEDIA-SEQUENCE|VERSION):/i.test(clean)) {
    if (!sourceUrl.startsWith('https://') && !sourceUrl.startsWith('http://')) throw new DomainError('hls-origin-required');
    const title = titleOf(sourceName) || 'Live Stream';
    const providerRef = hash(sourceUrl);
    return {catalog: catalogSchema.parse({schemaVersion: 1, items: [{id: providerRef, title, titleKey: title.toLowerCase().normalize('NFKD'), kind: 'channel', category: '', providerRef}]}),
      stats: {entries: 1, skipped: 0, duplicates: 0, episodes: 0}};
  }
  const stats: M3uStats = {entries: 0, skipped: 0, duplicates: 0, episodes: 0};
  const items: Catalog['items'] = [], seen = new Set<string>();
  const series = new Map<string, {item: Catalog['items'][number]; episodes: Map<number, {id: string; title: string; season: number; episodeNum: number}[]>}>();
  let info: string | null = null;
  for (const rawLine of clean.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) continue;
    if (line.startsWith('#EXTINF:')) { info = line; continue; }
    if (line.startsWith('#')) continue;
    if (info === null) continue;
    const extinf = info;
    info = null;
    stats.entries++;
    let url: URL;
    try { url = new URL(line, sourceUrl.startsWith('http') ? sourceUrl : undefined); }
    catch { stats.skipped++; continue; }
    if (!['http:', 'https:'].includes(url.protocol)) { stats.skipped++; continue; }
    const providerRef = hash(url.toString());
    if (seen.has(providerRef)) { stats.duplicates++; continue; }
    seen.add(providerRef);
    const named = titleOf(extinf.slice((/^#EXTINF:(?:[^",]|"[^"]*")*,/.exec(extinf)?.[0].length ?? extinf.length)));
    const basename = decodeURIComponent(url.pathname.split('/').pop() ?? '').replace(/\.[a-z0-9]{2,4}$/i, '');
    const title = named || titleOf(attribute(extinf, 'tvg-name')) || titleOf(basename) || 'Sem título';
    const category = titleOf(attribute(extinf, 'group-title'));
    const epgId = attribute(extinf, 'tvg-id').slice(0, 300);
    const ageRating = normalizeAgeRating(/(?:tvg-rating|rating|age-rating|parental-rating)="([^"]*)"/i.exec(extinf)?.[1]);
    const declared = attribute(extinf, '(?:content-type|type)').toLowerCase();
    const path = url.pathname.toLowerCase();
    const isSeries = declared === 'series' || /\/series\//.test(path);
    const isMovie = !isSeries && (declared === 'movie' || /\/movie\//.test(path) || (VOD_EXTENSION.test(path) && !/\/live\//.test(path)));
    const episode = isSeries ? SERIES_EPISODE.exec(title) : null;
    if (isSeries && episode && episode[1]!.trim()) {
      const seriesName = titleOf(episode[1]!.replace(/[\s._\-–|:]+$/, '')) || title;
      const key = `${category.toLowerCase()}|${seriesName.toLowerCase()}`;
      let entry = series.get(key);
      if (!entry) {
        const ref = hash(`m3u-series:${key}`);
        entry = {item: {id: ref, title: seriesName, titleKey: seriesName.toLocaleLowerCase('en').normalize('NFKD'), kind: 'series', category, providerRef: ref, ...(ageRating ? {ageRating} : {})}, episodes: new Map()};
        series.set(key, entry);
        items.push(entry.item);
      }
      const season = Number(episode[2]), number = Number(episode[3]);
      const list = entry.episodes.get(season) ?? [];
      list.push({id: providerRef, title: titleOf(episode[4] ?? '') || `Episódio ${number}`, season, episodeNum: number});
      entry.episodes.set(season, list);
      stats.episodes++;
      continue;
    }
    items.push({id: providerRef, title, titleKey: title.toLocaleLowerCase('en').normalize('NFKD'), kind: isMovie ? 'movie' : 'channel', category, providerRef,
      ...(epgId && !isMovie ? {epgId} : {}), ...(ageRating ? {ageRating} : {})});
  }
  if (items.length > PROVIDER_LIMITS.maxItems) throw new DomainError('catalog-too-large', {items: items.length});
  const seriesDetails: Record<string, unknown> = {};
  for (const {item, episodes} of series.values()) {
    const seasons = [...episodes.keys()].sort((a, b) => a - b);
    seriesDetails[item.providerRef] = {
      seasons: seasons.map(n => ({id: null, name: `Temporada ${n}`, seasonNumber: n, episodeCount: episodes.get(n)!.length})),
      episodes: Object.fromEntries(seasons.map(n => [String(n), episodes.get(n)!.sort((a, b) => a.episodeNum - b.episodeNum)])),
    };
  }
  return {catalog: catalogSchema.parse({schemaVersion: 1, items, ...(series.size ? {seriesDetails} : {})}), stats};
}
export function parseM3u(body: string, sourceUrl = '', sourceName = ''): Catalog {
  return parseM3uDetailed(body, sourceUrl, sourceName).catalog;
}
const scalar = (v: unknown) => typeof v === 'string' || typeof v === 'number' ? v : undefined;
/** Tolerant Xtream rows: a malformed row is skipped, never the whole catalog. */
export function parseXtream(rows:unknown,kind:'channel'|'movie'|'series',categories:Catalog['categories']=[],stats?:{skipped:number}):Catalog['items'] {
 if(!Array.isArray(rows))return [];
 if(rows.length>PROVIDER_LIMITS.maxItems)throw new DomainError('catalog-too-large',{items:rows.length});
 const names=new Map((categories??[]).filter(c=>c.kind===kind).map(c=>[c.id,c.name]));
 const items:Catalog['items']=[],seen=new Set<string>();
 for(const row of rows){
   const x=(row&&typeof row==='object'?row:{}) as Record<string,unknown>;
   const providerRef=String(scalar(kind==='series'?x.series_id??x.stream_id:x.stream_id??x.series_id)??'').trim();
   if(!/^[A-Za-z0-9_-]{1,64}$/.test(providerRef)||seen.has(providerRef)){if(stats)stats.skipped++;continue;}
   seen.add(providerRef);
   const title=titleOf(String(scalar(x.name)??scalar(x.title)??''))||`#${providerRef}`;
   const categoryId=String(scalar(x.category_id)??''),ageRating=normalizeAgeRating(scalar(x.age)??scalar(x.mpaa_rating)??scalar(x.certification));
   const extension=String(scalar(x.container_extension)??'');
   const year=scalar(x.year)??scalar(x.releaseDate);
   items.push(itemSchema.parse({id:hash(`${kind}:${providerRef}`),title,titleKey:title.toLocaleLowerCase('en').normalize('NFKD'),kind,
     category:titleOf(names.get(categoryId)??categoryId),categoryId,providerRef,
     ...(typeof x.epg_channel_id==='string'&&x.epg_channel_id?{epgId:x.epg_channel_id.slice(0,300)}:{}),
     ...(/^\w{1,20}$/.test(extension)?{containerExtension:extension}:{}),...(typeof x.plot==='string'&&x.plot?{plot:x.plot.slice(0,10000)}:{}),
     ...(year!==undefined&&year!==''?{year}:{}),...(scalar(x.rating)!==undefined&&x.rating!==''?{rating:scalar(x.rating)}:{}),...(ageRating?{ageRating}:{})}));
 }
 return items;
}
export function validateUpdate(previousCount:number,next:Catalog):void {
 if(!next.items.length||(previousCount>20&&next.items.length<previousCount*0.5))throw new DomainError('suspicious-catalog');
 if(new Set(next.items.map(x=>x.id)).size!==next.items.length)throw new DomainError('duplicate-content');
}
export function fingerprint(catalog:Catalog):string {
 // Full canonical identity, never host alone. IDs encode credential-sensitive M3U
 // references, deliberately preferring missed deduplication to permission leakage.
 return hash(JSON.stringify({...catalog,items:[...catalog.items].sort((a,b)=>a.id.localeCompare(b.id))}));
}
