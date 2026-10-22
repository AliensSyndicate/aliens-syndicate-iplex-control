import {test} from 'node:test';
import assert from 'node:assert/strict';
import {editorialDocId, foldTitle, libraryInputSchema, TitleResolver, tmdbKey, yearOf, type CatalogCandidate} from '../src/library';
import {parseXtream, providerTmdbId} from '../src/catalog';

const item = (id: string, sourceId: string, title: string, extra: Partial<CatalogCandidate> = {}): CatalogCandidate => ({id, sourceId, kind: 'movie', title, ...extra});
const resolver = (items: CatalogCandidate[], known: string[] = [], preferred: string | null = null) =>
  new TitleResolver(new Map(items.map(i => [i.id, i])), new Set([...items.map(i => i.id), ...known]), preferred);

test('canonical identity separates movies and series with the same TMDB number', () => {
  assert.equal(tmdbKey('movie', 603), 'movie:603');
  assert.equal(tmdbKey('series', 603), 'tv:603');
  assert.notEqual(editorialDocId('movie', 603), editorialDocId('series', 603));
});

test('provider tmdb id is parsed strictly and never for channels', () => {
  assert.equal(providerTmdbId('603'), 603);
  for (const bad of ['', '0', '-1', 'abc', '12.5', '1234567890', null]) assert.equal(providerTmdbId(bad), undefined);
  const [movie] = parseXtream([{stream_id: 1, name: 'Matrix', tmdb: '603'}], 'movie');
  const [channel] = parseXtream([{stream_id: 2, name: 'Canal', tmdb: '603'}], 'channel');
  assert.equal(movie!.tmdbId, 603);
  assert.equal(channel!.tmdbId, undefined);
});

test('resolver: stored link, then provider id, preferring the selected source (no duplicates)', () => {
  const r = resolver([item('a1', 'A', 'Matrix', {tmdbId: 603}), item('b1', 'B', 'Matrix', {tmdbId: 603})], [], 'B');
  assert.deepEqual(r.resolve({contentId: 'a1'}), {id: 'a1', via: 'link', hidden: false});
  assert.deepEqual(r.resolve({contentId: 'tmdb-movie-603', kind: 'movie', tmdbId: 603}), {id: 'b1', via: 'tmdb', hidden: false});
  assert.equal(r.resolve({contentId: 'x', kind: 'series', tmdbId: 603}).id, null, 'tv:603 is another title');
});

test('resolver: a link to an item the profile cannot see hides the entry', () => {
  assert.deepEqual(resolver([], ['secret']).resolve({contentId: 'secret', kind: 'movie', tmdbId: 1}), {id: null, via: null, hidden: true});
});

test('resolver: title correspondence needs exact title and year and no conflicting id', () => {
  const items = [item('m1', 'A', 'Matrix (1999)', {year: '1999'}), item('m2', 'A', 'Matrix Reloaded', {year: 2003})];
  assert.equal(resolver(items).resolve({kind: 'movie', tmdbId: 603, title: 'Matrix', year: 1999}).id, 'm1');
  assert.equal(resolver(items).resolve({kind: 'movie', tmdbId: 603, title: 'Matrix'}).id, null, 'no year: ambiguous');
  assert.equal(resolver(items).resolve({kind: 'movie', tmdbId: 603, title: 'Matrix', year: 2000}).id, null);
  const conflicting = [...items, item('m3', 'B', 'Matrix', {year: 1999, tmdbId: 999})];
  assert.equal(resolver(conflicting).resolve({kind: 'movie', tmdbId: 603, title: 'Matrix', year: 1999}).id, null, 'another declared id: never the wrong title');
  assert.equal(resolver(items).resolve({kind: 'movie', tmdbId: 1, originalTitle: 'Matrix', title: 'Matriz', year: 1999}).id, 'm1', 'original title also counts');
});

test('title folding and year parsing', () => {
  assert.equal(foldTitle('Ação & Reação [4K] (2020)'), 'acao e reacao');
  assert.equal(yearOf({title: 'Filme (2019)'}), 2019);
  assert.equal(yearOf({year: '2021-05-01'}), 2021);
  assert.equal(yearOf({year: 'n/a'}), undefined);
});

test('library input: lists, references and poster origin', () => {
  const ok = (v: object) => libraryInputSchema.safeParse(v).success;
  assert.ok(ok({list: 'wishlist', kind: 'movie', tmdbId: 1, title: 'X'}));
  assert.ok(ok({list: 'favorites', kind: 'channel', contentId: 'c', sourceId: 's', title: 'Canal'}));
  assert.ok(ok({list: 'favorites', kind: 'movie', tmdbId: 1, remove: true}));
  assert.ok(!ok({list: 'wishlist', kind: 'channel', contentId: 'c', sourceId: 's', title: 'Canal'}));
  assert.ok(!ok({list: 'favorites', kind: 'movie', title: 'Sem referência'}));
  assert.ok(!ok({list: 'favorites', kind: 'movie', contentId: 'c', title: 'Sem fonte'}));
  assert.ok(!ok({list: 'favorites', kind: 'movie', tmdbId: 1, title: 'X', poster: 'https://evil.example/a.jpg'}));
});
