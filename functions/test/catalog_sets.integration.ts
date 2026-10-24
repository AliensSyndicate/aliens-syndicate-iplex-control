import {ensureFamily} from '../src/family_individual';
import {test, before, after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp, deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {execute, Identity} from '../src/service';
import {syncIptvCatalog} from '../src/iptv_sync';
import {readManifest, readChunk, SET_NAMES} from '../src/catalog_sets';

let app: ReturnType<typeof initializeApp>, seq = 0;
const key = Buffer.alloc(32, 7).toString('base64');
const line = (group: string, title: string, path: string, extra = '') => `#EXTINF:-1 group-title="${group}" ${extra},${title}\nhttps://example.invalid/${path}`;
const list = (...rows: string[]) => `#EXTM3U\n${rows.join('\n')}\n`;
const v1 = list(
  line('Notícias', 'Canal A', 'live/u/p/1.ts'), line('Notícias', 'Canal B', 'live/u/p/2.ts'),
  line('Ação', 'Filme Um (2020)', 'movie/u/p/10.mp4'), line('Ação', 'Filme Dois (2021)', 'movie/u/p/11.mp4'), line('Drama', 'Filme Três (2019)', 'movie/u/p/12.mp4'),
  line('Séries', 'Serie X S01E01 Piloto', 'series/u/p/20.mkv', 'type="series"'),
);
// Inclui um canal, remove um filme, move um filme de categoria e muda um título.
const v2 = list(
  line('Notícias', 'Canal A', 'live/u/p/1.ts'), line('Notícias', 'Canal B', 'live/u/p/2.ts'), line('Notícias', 'Canal C', 'live/u/p/3.ts'),
  line('Drama', 'Filme Um (2020)', 'movie/u/p/10.mp4'), line('Drama', 'Filme Três (2019) Restaurado', 'movie/u/p/12.mp4'),
  line('Séries', 'Serie X S01E01 Piloto', 'series/u/p/20.mkv', 'type="series"'),
);
before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) throw new Error('Firestore and Storage emulators required');
  app = initializeApp({projectId: 'demo-iplex', storageBucket: 'demo-iplex.appspot.com'});
});
after(async () => deleteApp(app));
async function account() {
  const actor: Identity = {uid: `sets_${++seq}`};
  await getFirestore().doc(`users/${actor.uid}`).set({uid: actor.uid, name: 'Sets'});
  await ensureFamily(actor.uid);
  return actor;
}
async function sourceRef(actor: Identity, id: string) {
  const data = (await getFirestore().doc(`users/${actor.uid}`).get()).data()!;
  return getFirestore().doc(`families/${data.familyId}/sources/${id}`);
}
type Rec = {id: string; title?: string; categoryId?: string; name?: string; catalogItemId?: string};
async function readSet(actor: Identity, id: string, set: string): Promise<Rec[]> {
  const manifest = await execute('readCatalogManifest', {id}, actor, key) as {sets: Record<string, {chunks: number}>};
  const rows: Rec[] = [];
  for (let n = 0; n < manifest.sets[set]!.chunks; n += 1) rows.push(...((await execute('readCatalogChunk', {id, set, n}, actor, key) as {records: Rec[]}).records));
  return rows;
}

test('sincroniza → seis conjuntos no Firestore → leitura por callable → delta confiável após alterar a lista', async () => {
  const actor = await account();
  const {id} = await execute('saveSource', {name: 'Lista', format: 'file', fileName: 'a.m3u', fileContent: v1}, actor, key) as {id: string};
  const ref = await sourceRef(actor, id);
  await syncIptvCatalog(ref, key);
  const first = (await ref.get()).data()!;
  assert.equal(first.status, 'ready');
  const m1 = (await readManifest(first.version))!;
  assert.ok(m1.ready); assert.equal(m1.previousVersion, null); assert.equal(m1.delta, null);
  for (const name of SET_NAMES) assert.ok(m1.sets[name].chunks >= 1, name);
  assert.equal(m1.sets.live.count, 2); assert.equal(m1.sets.vod.count, 3); assert.equal(m1.sets.series.count, 1);
  // Categorias de M3U: ids derivados, vínculo item → categoria preservado.
  const vodRows = await readChunk(first.version, 'vod', 0), cats = await readChunk(first.version, 'vod_categories', 0);
  assert.ok(vodRows.every(r => cats.some(c => c.id === r.categoryId)));
  // O cliente recebe pelo callable (ids públicos, sem blocos crus).
  const live = await readSet(actor, id, 'live');
  assert.deepEqual(live.map(r => r.title).sort(), ['Canal A', 'Canal B']);
  assert.ok(live.every(r => r.catalogItemId && r.id !== r.catalogItemId));
  const manifest = await execute('readCatalogManifest', {id}, actor, key) as Record<string, unknown>;
  assert.equal(JSON.stringify(manifest).includes('"count"'), false, 'contagens de itens não vazam no manifesto');
  assert.match(String(manifest.viewerKey), /^[a-f0-9]{64}$/);
  // Segunda versão da lista.
  await execute('saveSource', {id, name: 'Lista', format: 'file', fileName: 'a.m3u', fileContent: v2, expectedRevision: first.revision}, actor, key);
  await syncIptvCatalog(ref, key);
  const second = (await ref.get()).data()!;
  assert.equal(second.status, 'ready'); assert.notEqual(second.version, first.version);
  const m2 = (await readManifest(second.version))!;
  assert.equal(m2.previousVersion, first.version);
  assert.equal(m2.delta?.from, first.version);
  assert.equal(m2.delta!.sets.live.upserts, 1); assert.equal(m2.delta!.sets.live.deletes, 0);
  assert.equal(m2.delta!.sets.vod.deletes, 1);
  const delta = await execute('readCatalogDelta', {id, from: first.version}, actor, key) as {full: boolean; steps: Array<{sets: Record<string, {upserts: Rec[]; deletes: string[]}>}>};
  assert.equal(delta.full, false);
  // O resultado final (leitura completa) e o delta contam a mesma história.
  const finalVod = await readSet(actor, id, 'vod');
  assert.deepEqual(finalVod.map(r => r.title).sort(), ['Filme Três (2019) Restaurado', 'Filme Um (2020)']);
  const upsertTitles = (delta.steps[0]!.sets.vod?.upserts ?? []).map(r => r.title).sort();
  assert.deepEqual(upsertTitles, ['Filme Três (2019) Restaurado', 'Filme Um (2020)']);
  assert.equal(delta.steps[0]!.sets.vod!.deletes.length, 1);
  // Versão desconhecida pela cadeia → reconstrução completa (nunca um delta parcial).
  const unknown = await execute('readCatalogDelta', {id, from: 'a'.repeat(64)}, actor, key) as {full: boolean};
  assert.equal(unknown.full, true);
  // Sem alteração: nenhum passo.
  const same = await execute('readCatalogDelta', {id, from: second.version}, actor, key) as {full: boolean; steps: unknown[]};
  assert.equal(same.full, false); assert.equal(same.steps.length, 0);
});

test('fonte sincronizada antes deste formato ganha os conjuntos sob demanda, sem nova sincronização', async () => {
  const actor = await account();
  const {id} = await execute('saveSource', {name: 'Antiga', format: 'file', fileName: 'b.m3u', fileContent: v1}, actor, key) as {id: string};
  const ref = await sourceRef(actor, id);
  await syncIptvCatalog(ref, key);
  const version = (await ref.get()).data()!.version as string;
  // Simula catálogo legado: remove os conjuntos persistidos.
  const db = getFirestore();
  await db.recursiveDelete(db.collection(`catalogs/${version}/sets`));
  await db.recursiveDelete(db.collection(`catalogs/${version}/meta`));
  assert.equal(await readManifest(version), null);
  const live = await readSet(actor, id, 'live');
  assert.equal(live.length, 2);
  assert.ok(await readManifest(version));
});
