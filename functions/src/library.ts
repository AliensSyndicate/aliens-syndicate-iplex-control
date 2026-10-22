/**
 * Personal library (Favoritos + Lista de desejos) of a media profile.
 *
 * Identity: a title is identified editorially by TMDB id + media type
 * (`tmdbKey`, "movie:603" ≠ "tv:603"). The link to an IPTV catalog item
 * (`catalogContentId`, the public id returned by readSourceCatalog) is optional:
 * a title can be saved without being available, keeps its place when a source
 * is removed or re-synced, and is recognised again when a catalog publishes it.
 *
 * Contract (families/{fid}/profiles/{pid}/{favorites|wishlist}/{docId}):
 *   docId            catalog public id (legacy / channel) or `tmdb-<movie|tv>-<id>`
 *   contentId        catalog public id when linked (TV compatibility), else docId
 *   catalogContentId catalog public id of the last confident link (optional)
 *   sourceId         source of that link (optional)
 *   kind             channel | movie | series
 *   tmdbId, tmdbKey  editorial identity (optional for channels/legacy entries)
 *   title, originalTitle, year, poster (https://image.tmdb.org only)
 *   generation       profile `generations.favorites` (shared by both lists)
 */
import {z} from 'zod';
import type {Transaction, DocumentReference, DocumentSnapshot} from 'firebase-admin/firestore';
import {DomainError, idSchema} from './domain';
import {requireWritableGeneration, type ProfileView} from './family_profiles';

export type LibraryList = 'favorites' | 'wishlist';
export const LIBRARY_LISTS: LibraryList[] = ['favorites', 'wishlist'];
export type TitleKind = 'movie' | 'series';
type Kind = 'channel' | TitleKind;

export const mediaTypeOf = (kind: TitleKind) => kind === 'movie' ? 'movie' : 'tv';
export const tmdbKey = (kind: TitleKind, tmdbId: number) => `${mediaTypeOf(kind)}:${tmdbId}`;
export const editorialDocId = (kind: TitleKind, tmdbId: number) => `tmdb-${mediaTypeOf(kind)}-${tmdbId}`;

const tmdbIdSchema = z.number().int().positive().max(999_999_999);
const posterSchema = z.string().max(500).regex(/^https:\/\/image\.tmdb\.org\/t\/p\/[a-z0-9]+\/[A-Za-z0-9_.-]+$/);
export const libraryInputSchema = z.object({
  list: z.enum(['favorites', 'wishlist']),
  kind: z.enum(['channel', 'movie', 'series']),
  contentId: idSchema.optional(),
  sourceId: idSchema.optional(),
  tmdbId: tmdbIdSchema.optional(),
  title: z.string().trim().min(1).max(300).optional(),
  originalTitle: z.string().trim().max(300).optional(),
  year: z.number().int().min(1870).max(2100).optional(),
  poster: posterSchema.optional(),
  remove: z.boolean().optional(),
}).refine(v => v.contentId || (v.tmdbId && v.kind !== 'channel'), {message: 'title-reference-required'})
  .refine(v => v.list === 'favorites' || v.kind !== 'channel', {message: 'wishlist-titles-only'})
  .refine(v => v.kind !== 'channel' || !v.tmdbId, {message: 'channel-has-no-tmdb'})
  .refine(v => v.remove === true || !!v.title, {message: 'title-required'})
  .refine(v => !v.contentId || !!v.sourceId || v.remove === true, {message: 'source-required'});
export type LibraryInput = z.infer<typeof libraryInputSchema>;

/** Catalog item the profile may see, as checked by the catalog backend. */
export interface VerifiedItem {kind: Kind; title: string; year?: unknown; tmdbId?: number}

/** Every stored row that represents the same title: same doc, same catalog link or same tmdbKey. */
export async function sameTitleDocs(tx: Transaction, list: FirebaseFirestore.CollectionReference, contentId?: string, key?: string | null) {
  const reads: Promise<DocumentSnapshot[]>[] = [];
  if (contentId) {
    reads.push(tx.get(list.doc(contentId)).then(d => d.exists ? [d] : []));
    reads.push(tx.get(list.where('contentId', '==', contentId).limit(10)).then(q => q.docs));
    reads.push(tx.get(list.where('catalogContentId', '==', contentId).limit(10)).then(q => q.docs));
  }
  if (key) reads.push(tx.get(list.where('tmdbKey', '==', key).limit(10)).then(q => q.docs));
  const byId = new Map<string, DocumentSnapshot>();
  for (const docs of await Promise.all(reads)) for (const d of docs) byId.set(d.id, d);
  return [...byId.values()];
}

/**
 * Adds/removes one title in one list. Never duplicates: rows of the same title
 * (another source, a TV-created row, an editorial row) are merged into one.
 * Kids profiles only save catalog items they can see (no editorial-only titles).
 */
export async function writeLibraryItem(tx: Transaction, profile: DocumentReference, view: ProfileView, input: LibraryInput, verified: VerifiedItem | null, generation: unknown, now: number) {
  if (view.type === 'guest') throw new DomainError('guest-not-persisted');
  const remove = input.remove === true;
  if (!remove && input.contentId && !verified) throw new DomainError('not-found');
  if (!remove && view.type === 'kids' && !verified) throw new DomainError('content-unavailable');
  if (verified && verified.kind !== input.kind) throw new DomainError('invalid-argument');
  // The provider's own TMDB id wins over a client-side match; kids never use a client id.
  const tmdbId = verified?.tmdbId ?? (view.type === 'kids' ? undefined : input.tmdbId);
  const key = tmdbId && input.kind !== 'channel' ? tmdbKey(input.kind, tmdbId) : null;
  const list = profile.collection(input.list);
  const existing = await sameTitleDocs(tx, list, input.contentId, key);
  if (remove) {
    for (const d of existing) tx.delete(d.ref);
    return {ok: true, saved: false};
  }
  const current = requireWritableGeneration(view, 'favorites', generation);
  const primary = existing.find(d => d.data()?.tmdbKey === key && key) ?? existing[0];
  const docId = primary?.id ?? (key ? editorialDocId(input.kind as TitleKind, tmdbId!) : input.contentId!);
  const previous = primary?.data() ?? {};
  const linked = input.contentId ?? previous.catalogContentId;
  tx.set(list.doc(docId), {
    contentId: linked ?? docId,
    ...(linked ? {catalogContentId: linked} : {}),
    ...(input.sourceId ?? previous.sourceId ? {sourceId: input.sourceId ?? previous.sourceId} : {}),
    kind: input.kind,
    ...(key ? {tmdbId, tmdbKey: key} : {}),
    title: input.title ?? verified?.title,
    ...(input.originalTitle ? {originalTitle: input.originalTitle} : {}),
    ...(input.year ?? yearOf(verified) ? {year: input.year ?? yearOf(verified)} : {}),
    ...(input.poster ? {poster: input.poster} : {}),
    generation: current, updatedAt: now,
  }, {merge: true});
  for (const d of existing) if (d.id !== docId) tx.delete(d.ref);
  return {ok: true, saved: true, id: docId};
}

/** Accent/case/punctuation-insensitive title; a bracketed year or tag never matters. */
export function foldTitle(value: string) {
  return value.normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase()
    .replace(/\[[^\]]*\]|\((?:19|20)\d{2}\)/g, ' ').replace(/&/g, ' e ').replace(/[^a-z0-9]+/g, ' ').trim();
}
/** Year published by the source (field or "(2021)" in the title); unknown → undefined. */
export function yearOf(item: {year?: unknown; title?: string} | null | undefined): number | undefined {
  if (!item) return undefined;
  const raw = typeof item.year === 'number' ? item.year : Number(String(item.year ?? '').trim().slice(0, 4));
  if (Number.isInteger(raw) && raw >= 1870 && raw <= 2100) return raw;
  const m = /\(((?:19|20)\d{2})\)/.exec(item.title ?? '');
  return m ? Number(m[1]) : undefined;
}

export interface CatalogCandidate {id: string; sourceId: string; kind: Kind; title: string; year?: unknown; tmdbId?: number}
export interface ResolvedLink {id: string | null; via: 'link' | 'tmdb' | 'title' | null; hidden: boolean}

/**
 * Finds the catalog item of a saved title among the items the profile can see.
 * Order: stored link → provider TMDB id → exact title + exact year (only when
 * no item with the same title/year declares another TMDB id). Anything else is
 * ambiguous and stays unlinked: never the wrong title.
 * `known` = every public id of the profile's sources (visible or not), so a link
 * to an item the profile may no longer see hides the entry instead of exposing it.
 */
export class TitleResolver {
  private byTmdb?: Map<string, CatalogCandidate[]>;
  private byTitle?: Map<string, CatalogCandidate[]>;
  constructor(private visible: Map<string, CatalogCandidate>, private known: Set<string>, private preferredSource: string | null = null) {}

  private index() {
    if (this.byTmdb) return;
    this.byTmdb = new Map(); this.byTitle = new Map();
    for (const item of this.visible.values()) {
      if (item.kind === 'channel') continue;
      if (item.tmdbId) push(this.byTmdb, tmdbKey(item.kind, item.tmdbId), item);
      push(this.byTitle, `${item.kind}:${foldTitle(item.title)}`, item);
    }
  }
  private pick(items: CatalogCandidate[]) {
    return [...items].sort((a, b) => Number(b.sourceId === this.preferredSource) - Number(a.sourceId === this.preferredSource) || a.id.localeCompare(b.id))[0]!;
  }

  resolve(doc: {contentId?: unknown; catalogContentId?: unknown; kind?: unknown; tmdbId?: unknown; title?: unknown; originalTitle?: unknown; year?: unknown}): ResolvedLink {
    for (const link of [doc.catalogContentId, doc.contentId]) {
      if (typeof link !== 'string') continue;
      if (this.visible.has(link)) return {id: link, via: 'link', hidden: false};
      if (this.known.has(link)) return {id: null, via: null, hidden: true};
    }
    const kind = doc.kind, tmdbId = doc.tmdbId;
    if ((kind !== 'movie' && kind !== 'series') || typeof tmdbId !== 'number') return {id: null, via: null, hidden: false};
    this.index();
    const strong = this.byTmdb!.get(tmdbKey(kind, tmdbId));
    if (strong?.length) return {id: this.pick(strong).id, via: 'tmdb', hidden: false};
    const year = typeof doc.year === 'number' ? doc.year : undefined;
    if (!year) return {id: null, via: null, hidden: false};
    const titles = new Set([doc.title, doc.originalTitle].filter((t): t is string => typeof t === 'string').map(foldTitle).filter(Boolean));
    const candidates = [...titles].flatMap(t => this.byTitle!.get(`${kind}:${t}`) ?? []).filter(i => yearOf(i) === year);
    if (!candidates.length || candidates.some(i => i.tmdbId && i.tmdbId !== tmdbId)) return {id: null, via: null, hidden: false};
    return {id: this.pick(candidates).id, via: 'title', hidden: false};
  }
}
function push<T>(map: Map<string, T[]>, key: string, value: T) {
  const list = map.get(key);
  if (list) list.push(value); else map.set(key, [value]);
}
