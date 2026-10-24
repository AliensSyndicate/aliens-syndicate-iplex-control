/**
 * Oito conjuntos de dados por catálogo, persistidos no Firestore em blocos.
 *
 *   catalogs/{version}/meta/manifest                         versão, anterior, contagens, hashes
 *   catalogs/{version}/sets/{set}                            contagem/hash do conjunto
 *   catalogs/{version}/sets/{set}/chunks/{0000}              registros (JSON gzip em Bytes, < 1 MiB)
 *   catalogs/{version}/deltas/{from}_{set}_{0000}            diferença {from → version} (gzip)
 *
 * Conjuntos: live_categories, live, vod_categories, vod, series_categories, series e, à parte,
 * adult_categories e adult (7º e 8º): todo conteúdo adulto de canais, filmes e séries, REMOVIDO dos seis
 * conjuntos comuns. adult_categories é fixa: Ao Vivo, Filmes e Séries (só as que têm itens).
 * (get_live_categories, get_live_streams, get_vod_categories, get_vod_streams,
 * get_series_categories, get_series). Cada registro mantém o identificador do
 * provedor (`providerRef` = stream_id/series_id; `categoryId` = category_id).
 * M3U não tem ids de categoria: o id é derivado de (tipo, nome) de forma estável.
 *
 * Por que blocos e não um documento por item: ~33 mil itens são ~20 documentos
 * (leituras/escritas quase nulas), cada documento respeita o limite de 1 MiB e o
 * acesso continua passando pelo backend, que filtra por perfil (adulto,
 * classificação, permissões). `catalogs/**` não é legível por clientes.
 *
 * O Xtream não entrega delta: a diferença é calculada aqui, comparando o hash de
 * cada registro com o catálogo anterior. Se a diferença for grande ou não houver
 * catálogo anterior, o cliente reconstrói o cache inteiro (sempre seguro).
 */
import {getFirestore} from 'firebase-admin/firestore';
import {gunzipSync, gzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import type {Catalog} from './catalog';
import {isAdultContent} from './content_audience';

export const SET_NAMES = ['live_categories', 'live', 'vod_categories', 'vod', 'series_categories', 'series', 'adult_categories', 'adult'] as const;
export type SetName = typeof SET_NAMES[number];
export const ITEM_SETS = ['live', 'vod', 'series', 'adult'] as const;
/** 2: conjuntos adult_categories/adult (manifestos 1 são refeitos na próxima leitura). */
export const SETS_SCHEMA_VERSION = 2;
/** Quantas versões anteriores uma TV desligada ainda consegue recuperar por deltas. */
export const MAX_DELTA_CHAIN = 30;

type Kind = 'channel' | 'movie' | 'series';
export type SetRecord = {id: string; [key: string]: unknown};
export type CatalogSets = Record<SetName, SetRecord[]>;

const ITEM_SET: Record<Kind, 'live' | 'vod' | 'series'> = {channel: 'live', movie: 'vod', series: 'series'};
const CATEGORY_SET: Record<Kind, SetName> = {channel: 'live_categories', movie: 'vod_categories', series: 'series_categories'};
export const setNameOf = (kind: Kind): SetName => ITEM_SET[kind];

const sha = (value: string | Buffer) => createHash('sha256').update(value).digest('hex');
/** JSON com chaves ordenadas: o hash de um registro não depende da ordem de montagem. */
export function stableStringify(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;
  if (value && typeof value === 'object') {
    const entries = Object.entries(value as Record<string, unknown>).filter(([, v]) => v !== undefined).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
    return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${stableStringify(v)}`).join(',')}}`;
  }
  return JSON.stringify(value);
}
export const recordHash = (record: SetRecord) => sha(stableStringify(record));

/** Id de categoria para fontes sem ids (M3U): estável por (tipo, nome). */
export const derivedCategoryId = (kind: Kind, name: string) => `m3u_${sha(`${kind}:${name}`).slice(0, 16)}`;

/** Divide um catálogo normalizado nos seis conjuntos, mantendo os ids do provedor. */
export const ADULT_CATEGORY_ID: Record<Kind, string> = {channel: 'adult_live', movie: 'adult_vod', series: 'adult_series'};
const ADULT_CATEGORY_NAME: Record<Kind, string> = {channel: 'Ao Vivo', movie: 'Filmes', series: 'Séries'};
/** Item adulto: marca do provedor, título, categoria ou classificação 18 (mesma regra de visibilidade por perfil). */
const isAdultItem = (item: Catalog['items'][number]) => isAdultContent(item);

export function splitCatalog(catalog: Catalog): CatalogSets {
  const out: CatalogSets = {live_categories: [], live: [], vod_categories: [], vod: [], series_categories: [], series: [], adult_categories: [], adult: []};
  const categories = new Map<string, SetRecord>();
  for (const c of catalog.categories ?? []) categories.set(`${c.kind}:${c.id}`, {id: c.id, name: c.name, kind: c.kind});
  const adultKinds = new Set<Kind>();
  // Categorias adultas pelo nome no cadastro do provedor: todo item delas é adulto, mesmo que o item não repita o nome.
  const adultCategoryKeys = new Set((catalog.categories ?? []).filter(c => isAdultContent({category: c.name})).map(c => `${c.kind}:${c.id}`));
  for (const item of catalog.items) {
    if (isAdultItem(item) || (item.categoryId && adultCategoryKeys.has(`${item.kind}:${item.categoryId}`))) {
      // Fora das listas comuns: vai para o 8º conjunto, na categoria fixa do tipo.
      adultKinds.add(item.kind);
      out.adult.push({...item, categoryId: ADULT_CATEGORY_ID[item.kind]});
      continue;
    }
    const categoryId = item.categoryId || derivedCategoryId(item.kind, item.category);
    // Categoria usada por itens mas ausente da lista do provedor (ou fonte sem ids): vínculo preservado.
    if (!categories.has(`${item.kind}:${categoryId}`)) categories.set(`${item.kind}:${categoryId}`, {id: categoryId, name: item.category || categoryId, kind: item.kind, derived: true});
    out[ITEM_SET[item.kind]].push({...item, categoryId});
  }
  for (const [key, record] of categories) {
    // Categoria adulta do provedor: seus itens já foram para o 8º conjunto.
    if (isAdultContent({category: String(record.name ?? '')})) continue;
    out[CATEGORY_SET[key.split(':')[0] as Kind]].push(record);
  }
  for (const kind of ['channel', 'movie', 'series'] as const) {
    if (adultKinds.has(kind)) out.adult_categories.push({id: ADULT_CATEGORY_ID[kind], name: ADULT_CATEGORY_NAME[kind], kind});
  }
  for (const name of SET_NAMES) out[name].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return out;
}

const RAW_LIMIT = 1_500_000, GZ_LIMIT = 800_000;
export type PackedChunk = {n: number; count: number; firstId: string; lastId: string; payload: Buffer; hash: string};
export const pad = (n: number) => String(n).padStart(4, '0');

/** Agrupa registros em blocos cujo gzip cabe com folga em um documento (< 1 MiB). */
export function packRecords<T>(rows: T[], idOf: (row: T) => string, wrap: (rows: T[]) => unknown = rows => rows): PackedChunk[] {
  const chunks: PackedChunk[] = [];
  const emit = (part: T[]): void => {
    const payload = gzipSync(Buffer.from(JSON.stringify(wrap(part))), {level: 9});
    if (payload.length > GZ_LIMIT && part.length > 1) {
      const half = Math.ceil(part.length / 2);
      emit(part.slice(0, half));
      emit(part.slice(half));
      return;
    }
    chunks.push({n: chunks.length, count: part.length, firstId: idOf(part[0]!), lastId: idOf(part[part.length - 1]!), payload, hash: sha(payload)});
  };
  let batch: T[] = [], size = 0;
  for (const row of rows) {
    const bytes = JSON.stringify(row).length + 1;
    if (batch.length && size + bytes > RAW_LIMIT) { emit(batch); batch = []; size = 0; }
    batch.push(row); size += bytes;
  }
  if (batch.length) emit(batch);
  return chunks;
}
export const unpack = <T>(payload: Buffer | Uint8Array): T => JSON.parse(gunzipSync(Buffer.from(payload)).toString('utf8')) as T;

export type SetDiff = {upserts: SetRecord[]; deletes: string[]};
/** Diferença entre dois conjuntos: novos/alterados (hash do registro) e removidos (tombstones). */
export function diffRecords(previous: SetRecord[], next: SetRecord[]): SetDiff {
  const before = new Map(previous.map(r => [r.id, recordHash(r)]));
  const upserts: SetRecord[] = [];
  const seen = new Set<string>();
  for (const record of next) {
    seen.add(record.id);
    if (before.get(record.id) !== recordHash(record)) upserts.push(record);
  }
  const deletes = previous.filter(r => !seen.has(r.id)).map(r => r.id);
  return {upserts, deletes};
}

export type SetSummary = {count: number; chunks: number; hash: string};
export type DeltaSummary = {upserts: number; deletes: number; chunks: number};
export interface CatalogManifest {
  schemaVersion: number;
  version: string;
  previousVersion: string | null;
  ready: boolean;
  createdAt: number;
  sets: Record<SetName, SetSummary>;
  /** Presente só quando existe diferença confiável {previousVersion → version}. */
  delta: {from: string; sets: Record<SetName, DeltaSummary>} | null;
}

const db = () => getFirestore();
const manifestRef = (version: string) => db().doc(`catalogs/${version}/meta/manifest`);
const inFlight = new Map<string, Promise<CatalogManifest>>();

export async function readManifest(version: string): Promise<CatalogManifest | null> {
  const data = (await manifestRef(version).get()).data() as CatalogManifest | undefined;
  // Manifesto de outro formato (sem os conjuntos adultos) conta como inexistente: é refeito sem nova sincronização.
  return data?.ready && data.schemaVersion === SETS_SCHEMA_VERSION ? data : null;
}

/** Se o delta passar desta fração do conjunto, reconstruir é mais barato e mais seguro. */
const DELTA_MAX_FRACTION = 0.5;

/**
 * Persiste os oito conjuntos de `version` (e a diferença para `previous`). Idempotente:
 * ids de documentos determinísticos e o manifesto, escrito por último, marca o fim.
 * Um processo interrompido deixa blocos órfãos inofensivos, nunca um manifesto pronto incompleto.
 */
export function persistCatalogSets(version: string, catalog: Catalog, previous: {version: string; catalog: Catalog} | null): Promise<CatalogManifest> {
  const running = inFlight.get(version);
  if (running) return running;
  const job = (async () => {
    const existing = await readManifest(version);
    if (existing) return existing;
    const sets = splitCatalog(catalog);
    const writer = db().bulkWriter();
    const summaries = {} as Record<SetName, SetSummary>;
    for (const name of SET_NAMES) {
      const chunks = packRecords(sets[name], r => r.id);
      summaries[name] = {count: sets[name].length, chunks: chunks.length, hash: sha(chunks.map(c => c.hash).join(''))};
      for (const chunk of chunks) {
        void writer.set(db().doc(`catalogs/${version}/sets/${name}/chunks/${pad(chunk.n)}`), {set: name, n: chunk.n, count: chunk.count, firstId: chunk.firstId, lastId: chunk.lastId, hash: chunk.hash, payload: chunk.payload});
      }
      void writer.set(db().doc(`catalogs/${version}/sets/${name}`), {set: name, schemaVersion: SETS_SCHEMA_VERSION, ...summaries[name]});
    }
    let delta: CatalogManifest['delta'] = null;
    if (previous && previous.version !== version) {
      const before = splitCatalog(previous.catalog);
      const counts = {} as Record<SetName, DeltaSummary>;
      let usable = true;
      const pending: Array<() => void> = [];
      for (const name of SET_NAMES) {
        const diff = diffRecords(before[name], sets[name]);
        const total = diff.upserts.length + diff.deletes.length;
        if (total > Math.max(200, sets[name].length * DELTA_MAX_FRACTION)) { usable = false; break; }
        const rows: Array<{u?: SetRecord; d?: string}> = [...diff.upserts.map(u => ({u})), ...diff.deletes.map(d => ({d}))];
        const chunks = rows.length ? packRecords(rows, r => r.u?.id ?? r.d!, part => ({upserts: part.filter(r => r.u).map(r => r.u), deletes: part.filter(r => r.d).map(r => r.d)})) : [];
        counts[name] = {upserts: diff.upserts.length, deletes: diff.deletes.length, chunks: chunks.length};
        for (const chunk of chunks) {
          pending.push(() => void writer.set(db().doc(`catalogs/${version}/deltas/${previous.version}_${name}_${pad(chunk.n)}`), {from: previous.version, set: name, n: chunk.n, count: chunk.count, hash: chunk.hash, payload: chunk.payload}));
        }
      }
      if (usable) { pending.forEach(run => run()); delta = {from: previous.version, sets: counts}; }
    }
    await writer.flush();
    const manifest: CatalogManifest = {schemaVersion: SETS_SCHEMA_VERSION, version, previousVersion: previous && previous.version !== version ? previous.version : null, ready: true, createdAt: Date.now(), sets: summaries, delta};
    await manifestRef(version).set(manifest);
    await writer.close();
    return manifest;
  })().finally(() => inFlight.delete(version));
  inFlight.set(version, job);
  return job;
}

export async function readChunk(version: string, set: SetName, n: number): Promise<SetRecord[]> {
  const snap = await db().doc(`catalogs/${version}/sets/${set}/chunks/${pad(n)}`).get();
  if (!snap.exists) throw new Error('chunk-missing');
  const data = snap.data()!;
  const payload = Buffer.from(data.payload as Uint8Array);
  if (sha(payload) !== data.hash) throw new Error('chunk-integrity');
  return unpack<SetRecord[]>(payload);
}

export async function readDeltaChunk(version: string, from: string, set: SetName, n: number): Promise<{upserts: SetRecord[]; deletes: string[]}> {
  const snap = await db().doc(`catalogs/${version}/deltas/${from}_${set}_${pad(n)}`).get();
  if (!snap.exists) throw new Error('delta-missing');
  const data = snap.data()!;
  const payload = Buffer.from(data.payload as Uint8Array);
  if (sha(payload) !== data.hash) throw new Error('delta-integrity');
  return unpack<{upserts: SetRecord[]; deletes: string[]}>(payload);
}
