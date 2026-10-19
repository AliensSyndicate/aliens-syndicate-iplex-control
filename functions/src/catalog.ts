import {lookup} from 'node:dns/promises';
import http from 'node:http';
import https from 'node:https';
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
// Resolve once and pin the connection to a public address. SSRF-safe, follows redirects,
// supports IPTV player User-Agent, handles HTTP/HTTPS, large streams and credentials.
export async function fetchProvider(raw: string, hops = 0): Promise<string> {
  if (hops > 5) throw new DomainError('provider-unavailable');
  const url = new URL(raw);
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) throw new DomainError('unsafe-provider');
  const hostname = url.hostname.replace(/^\[|\]$/g, '');
  let addresses;
  try {
    addresses = await lookup(hostname, {all: true});
  } catch (err: any) {
    if (err && (err.code === 'ENOTFOUND' || err.code === 'EAI_AGAIN' || err.code === 'ENODATA')) {
      throw new DomainError('provider-unavailable', {reason: 'host-not-found', host: hostname});
    }
    throw new DomainError('provider-unavailable', {reason: 'dns-lookup-failed', host: hostname});
  }
  if (!addresses.length || addresses.some(x => !publicAddress(x.address))) throw new DomainError('unsafe-provider');
  const address = addresses[0]!;
  const transport = url.protocol === 'https:' ? https : http;
  return new Promise((resolve, reject) => {
    const req = transport.get(url, {
      // Node >= 20 asks for `{all: true}` (happy eyeballs) and expects an array;
      // answering in the single-address form fails every request with ERR_INVALID_IP_ADDRESS.
      lookup: pinnedLookup(address) as any,
      timeout: 30000,
      headers: {
        'user-agent': 'IPTVSmarters/1.0 (Linux; Android 12)',
        accept: 'application/json,application/x-mpegURL,text/plain,*/*',
        'accept-encoding': 'identity',
      },
    }, res => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode ?? 0) && res.headers.location) {
        res.resume();
        const nextUrl = new URL(res.headers.location, url.toString()).toString();
        fetchProvider(nextUrl, hops + 1).then(resolve, reject);
        return;
      }
      if (res.statusCode === 429) {
        res.resume();
        reject(new DomainError('provider-rate-limited'));
        return;
      }
      if (res.statusCode === 401 || res.statusCode === 403) {
        res.resume();
        reject(new DomainError('invalid-credentials'));
        return;
      }
      if (res.statusCode !== 200) {
        res.resume();
        reject(new DomainError('provider-unavailable', {statusCode: res.statusCode}));
        return;
      }
      const chunks: Buffer[] = [];
      let size = 0;
      res.on('data', (chunk: Buffer) => {
        size += chunk.length;
        if (size > 64 * 1024 * 1024) {
          req.destroy();
          reject(new DomainError('catalog-too-large'));
        } else {
          chunks.push(chunk);
        }
      });
      res.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
      res.on('error', (err: any) => reject(new DomainError('download-failed', {message: err?.message})));
    });
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      req.destroy();
    }, 60000);
    req.on('close', () => clearTimeout(timer));
    req.on('timeout', () => {
      timedOut = true;
      req.destroy();
    });
    req.on('error', (err: any) => {
      clearTimeout(timer);
      if (timedOut) {
        reject(new DomainError('provider-time-budget', {reason: 'request-timeout'}));
        return;
      }
      if (err?.code === 'ECONNRESET' || err?.code === 'EPIPE') {
        reject(new DomainError('download-failed', {code: err.code}));
        return;
      }
      reject(new DomainError('provider-unavailable', {code: err?.code, message: err?.message}));
    });
  });
}
export function parseM3u(body: string, sourceUrl = '', sourceName = ''): Catalog {
  const clean = body.replace(/^\uFEFF/, '').trimStart();
  if (!clean.startsWith('#EXTM3U') && !clean.startsWith('#EXTINF:')) throw new DomainError('invalid-catalog');
  // HLS media segments may have EXTINF titles. Classify the whole manifest
  // before parsing entries so segments never become independent IPTV channels.
  if (/#EXT-X-(?:STREAM-INF|TARGETDURATION|MEDIA-SEQUENCE|VERSION):/i.test(clean)) {
    if (!sourceUrl.startsWith('https://') && !sourceUrl.startsWith('http://')) throw new DomainError('hls-origin-required');
    const title = sourceName.trim().slice(0, 300) || 'Live Stream';
    const providerRef = hash(sourceUrl);
    return catalogSchema.parse({schemaVersion: 1, items: [{id: providerRef, title, titleKey: title.toLowerCase().normalize('NFKD'), kind: 'channel', category: '', providerRef}]});
  }
  const items: Catalog['items'] = [];
  let title = '', category = '', epgId = '', ageRating: string | undefined, kind: 'channel'|'movie'|'series' = 'channel';
  for (const rawLine of clean.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line.startsWith('#EXTINF:')) {
      title = line.slice((/^#EXTINF:(?:[^",]|"[^"]*")*,/.exec(line)?.[0].length ?? 0)).trim().slice(0, 300);
      epgId = /tvg-id="([^"]*)"/.exec(line)?.[1]?.slice(0, 300) ?? '';
      const declared = /(?:content-type|type)="([^"]*)"/.exec(line)?.[1];
      kind = declared === 'movie' || declared === 'series' ? declared : 'channel';
      category = /group-title="([^"]*)"/.exec(line)?.[1] ?? '';
      ageRating = normalizeAgeRating(/(?:tvg-rating|rating|age-rating|parental-rating)="([^"]*)"/.exec(line)?.[1]);
    } else if (line.trim() && !line.startsWith('#') && title) {
      try {
        const u = new URL(line.trim(), sourceUrl.startsWith('http') ? sourceUrl : undefined);
        if (!['http:', 'https:'].includes(u.protocol)) throw new DomainError('invalid-catalog');
        const providerRef = hash(u.toString());
        items.push({
          id: providerRef,
          title,
          titleKey: title.toLocaleLowerCase('en').normalize('NFKD'),
          kind,
          category: category.slice(0, 300),
          providerRef,
          ...(epgId ? {epgId} : {}),
          ...(ageRating ? {ageRating} : {}),
        });
      } catch {
        throw new DomainError('invalid-catalog');
      }
      title = '';
    }
  }
  return catalogSchema.parse({schemaVersion: 1, items});
}
export function parseXtream(rows:unknown,kind:'channel'|'movie'|'series',categories:Catalog['categories']=[]):Catalog['items'] {
 const data=z.array(z.object({name:z.string(),stream_id:z.union([z.string(),z.number()]).optional(),series_id:z.union([z.string(),z.number()]).optional(),category_id:z.union([z.string(),z.number()]).optional(),container_extension:z.string().optional(),plot:z.string().optional(),year:z.union([z.string(),z.number()]).optional(),rating:z.union([z.string(),z.number()]).optional(),age:z.union([z.string(),z.number()]).optional(),mpaa_rating:z.string().optional(),certification:z.string().optional()})).max(100000).parse(rows);
 return data.map(x=>{
   const providerRef=String(x.stream_id??x.series_id??'');
   if(!providerRef)throw new DomainError('invalid-catalog');
   const title=x.name, categoryId=String(x.category_id??''), ageRating=normalizeAgeRating(x.age??x.mpaa_rating??x.certification);
   return itemSchema.parse({id:hash(`${kind}:${providerRef}`),title,titleKey:title.toLocaleLowerCase('en').normalize('NFKD'),kind,
     category:categories?.find(c=>c.kind===kind&&c.id===categoryId)?.name??categoryId,categoryId,providerRef,
     ...(x.container_extension?{containerExtension:x.container_extension}:{}),...(x.plot?{plot:x.plot}:{}),
     ...(x.year!==undefined?{year:x.year}:{}),...(x.rating!==undefined?{rating:x.rating}:{}),...(ageRating?{ageRating}:{})});
 });
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
