import assert from 'node:assert/strict';
import test from 'node:test';
import {diffRecords, derivedCategoryId, packRecords, recordHash, splitCatalog, stableStringify, unpack} from '../src/catalog_sets';
import {isAdultContent} from '../src/content_audience';
import {parseXtream} from '../src/catalog';
import type {Catalog} from '../src/catalog';

const item = (n: number, kind: 'channel' | 'movie' | 'series', categoryId?: string, extra: Record<string, unknown> = {}): Catalog['items'][number] => ({
  id: `id${n}`, title: `Título ${n}`, titleKey: `titulo ${n}`, kind, category: categoryId ? `Cat ${categoryId}` : 'Grupo M3U', providerRef: String(n),
  ...(categoryId ? {categoryId} : {}), ...extra,
});

test('splitCatalog separa os seis conjuntos e preserva os ids do provedor', () => {
  const catalog: Catalog = {
    schemaVersion: 1,
    categories: [{id: '1', name: 'Notícias', kind: 'channel'}, {id: '10', name: 'AÇAO', kind: 'movie'}, {id: '20', name: 'NETFLIX', kind: 'series'}],
    items: [item(1, 'channel', '1'), item(2, 'movie', '10'), item(3, 'series', '20'), item(4, 'movie', '10')],
  };
  const sets = splitCatalog(catalog);
  assert.deepEqual(sets.live.map(r => r.providerRef), ['1']);
  assert.deepEqual(sets.vod.map(r => r.providerRef), ['2', '4']);
  assert.deepEqual(sets.series.map(r => r.providerRef), ['3']);
  assert.deepEqual(sets.live_categories, [{id: '1', name: 'Notícias', kind: 'channel'}]);
  assert.deepEqual(sets.vod_categories, [{id: '10', name: 'AÇAO', kind: 'movie'}]);
  assert.equal(sets.series_categories[0]!.id, '20');
  // O vínculo item → categoria usa o id original, não o nome de exibição.
  assert.ok(sets.vod.every(r => r.categoryId === '10'));
});

test('fonte sem ids de categoria (M3U) recebe ids derivados estáveis, por tipo', () => {
  const catalog: Catalog = {schemaVersion: 1, items: [item(1, 'movie'), item(2, 'channel')]};
  const a = splitCatalog(catalog), b = splitCatalog(catalog);
  assert.equal(a.vod[0]!.categoryId, derivedCategoryId('movie', 'Grupo M3U'));
  assert.notEqual(derivedCategoryId('movie', 'Grupo M3U'), derivedCategoryId('channel', 'Grupo M3U'));
  assert.deepEqual(a.vod_categories, b.vod_categories);
  assert.equal((a.vod_categories[0] as {derived?: boolean}).derived, true);
});

test('categoria usada por itens mas ausente da lista do provedor continua vinculada', () => {
  const catalog: Catalog = {schemaVersion: 1, categories: [], items: [item(1, 'channel', '999')]};
  const sets = splitCatalog(catalog);
  assert.equal(sets.live_categories[0]!.id, '999');
  assert.equal(sets.live[0]!.categoryId, '999');
});

test('dois nomes iguais em categorias de origem diferentes continuam separados (ids distintos)', () => {
  const catalog: Catalog = {schemaVersion: 1, categories: [{id: '1', name: 'Ação', kind: 'movie'}, {id: '2', name: 'AÇAO', kind: 'movie'}], items: [item(1, 'movie', '1'), item(2, 'movie', '2')]};
  const sets = splitCatalog(catalog);
  assert.equal(sets.vod_categories.length, 2);
  assert.deepEqual(sets.vod.map(r => r.categoryId), ['1', '2']);
});

test('packRecords respeita o limite de documento e remonta os registros sem perda', () => {
  const rows = Array.from({length: 12000}, (_, i) => ({id: `id${String(i).padStart(6, '0')}`, title: `Filme ${i} ${'x'.repeat(i % 40)}`, plot: `${i}-${Math.random().toString(36)}`.repeat(6)}));
  const chunks = packRecords(rows, r => r.id);
  assert.ok(chunks.length >= 1);
  for (const chunk of chunks) assert.ok(chunk.payload.length <= 800_000, `bloco com ${chunk.payload.length} bytes`);
  const back = chunks.flatMap(c => unpack<typeof rows>(c.payload));
  assert.equal(back.length, rows.length);
  assert.deepEqual(back[0], rows[0]);
  assert.deepEqual(back.at(-1), rows.at(-1));
  assert.equal(chunks[0]!.firstId, rows[0]!.id);
});

test('hash do registro não depende da ordem das chaves', () => {
  assert.equal(recordHash({id: '1', a: 1, b: {x: 1, y: 2}}), recordHash({b: {y: 2, x: 1}, a: 1, id: '1'}));
  assert.equal(stableStringify({b: undefined, a: 1}), '{"a":1}');
});

test('diffRecords: inclusão, alteração (nome e categoria) e exclusão', () => {
  const before = [{id: 'a', title: 'A', categoryId: '1'}, {id: 'b', title: 'B', categoryId: '1'}, {id: 'c', title: 'C', categoryId: '2'}, {id: 'd', title: 'D', categoryId: '2'}];
  const after = [{id: 'a', title: 'A', categoryId: '1'}, {id: 'b', title: 'B renomeado', categoryId: '1'}, {id: 'c', title: 'C', categoryId: '3'}, {id: 'e', title: 'E', categoryId: '2'}];
  const diff = diffRecords(before, after);
  assert.deepEqual(diff.upserts.map(r => r.id).sort(), ['b', 'c', 'e']);
  assert.deepEqual(diff.deletes, ['d']);
  assert.deepEqual(diffRecords(after, after), {upserts: [], deletes: []});
});

test('Xtream: is_adult do provedor é preservado e protege como conteúdo adulto', () => {
  const rows = [{stream_id: 1, name: 'Filme comum', category_id: '5', is_adult: '0'}, {stream_id: 2, name: 'Título neutro', category_id: '5', is_adult: '1'}];
  const items = parseXtream(rows, 'movie', [{id: '5', name: 'FILMES', kind: 'movie'}]);
  assert.equal(items[0]!.isAdult, undefined);
  assert.equal(items[1]!.isAdult, true);
  assert.equal(isAdultContent(items[1]!), true);
  assert.equal(isAdultContent(items[0]!), false);
});

test('conteúdo adulto de canais, filmes e séries vai para o 7º e 8º conjuntos e sai dos comuns', () => {
  const catalog: Catalog = {
    schemaVersion: 1,
    categories: [{id: '1', name: 'Notícias', kind: 'channel'}, {id: '2', name: 'Adultos +18', kind: 'channel'}, {id: '10', name: 'Ação', kind: 'movie'}, {id: '11', name: 'XXX Filmes', kind: 'movie'}, {id: '20', name: 'Drama', kind: 'series'}],
    items: [
      item(1, 'channel', '1'), item(2, 'channel', '2'),
      item(3, 'movie', '10'), item(4, 'movie', '11'), item(5, 'movie', '10', {title: 'Algo XXX', titleKey: 'algo xxx'}), item(6, 'movie', '10', {ageRating: '18'}),
      item(7, 'series', '20'), item(8, 'series', '20', {isAdult: true}),
    ],
  };
  const sets = splitCatalog(catalog);
  assert.deepEqual(sets.live.map(r => r.providerRef), ['1']);
  assert.deepEqual(sets.vod.map(r => r.providerRef), ['3']);
  assert.deepEqual(sets.series.map(r => r.providerRef), ['7']);
  assert.deepEqual(sets.adult.map(r => r.providerRef).sort(), ['2', '4', '5', '6', '8']);
  // Categorias adultas do provedor saem das comuns; as três categorias fixas só existem para tipos com itens.
  assert.deepEqual(sets.live_categories.map(c => c.name), ['Notícias']);
  assert.deepEqual(sets.vod_categories.map(c => c.name), ['Ação']);
  assert.deepEqual(sets.adult_categories, [
    {id: 'adult_live', name: 'Ao Vivo', kind: 'channel'}, {id: 'adult_series', name: 'Séries', kind: 'series'}, {id: 'adult_vod', name: 'Filmes', kind: 'movie'},
  ]); // ordenadas por id (estável); a ordem de exibição é do cliente
  // Cada item adulto mantém o tipo e fica na categoria fixa do tipo.
  assert.deepEqual(sets.adult.map(r => [r.kind, r.categoryId]).sort(), [['channel', 'adult_live'], ['movie', 'adult_vod'], ['movie', 'adult_vod'], ['movie', 'adult_vod'], ['series', 'adult_series']]);
});

test('sem conteúdo adulto os conjuntos adultos ficam vazios', () => {
  const sets = splitCatalog({schemaVersion: 1, items: [item(1, 'movie', '10')]});
  assert.deepEqual(sets.adult, []);
  assert.deepEqual(sets.adult_categories, []);
});
