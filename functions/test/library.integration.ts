/**
 * Personal library (Favoritos + Lista de desejos) over the emulators and a real
 * synced catalog: titles saved without IPTV availability, canonical identity,
 * de-duplication, later association with the catalog, TV compatibility,
 * cleanup and parental rules.
 */
process.env.IPLEX_TEST_PRIVATE_PROVIDERS = '1';
import {randomBytes} from 'node:crypto';
import {test, before, after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp, deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {execute, Identity} from '../src/service';
import {syncIptvCatalog} from '../src/iptv_sync';
import {firestoreQuota, runPlayer, consumePlayerRequest, type PlayerAuth} from '../src/player';
import {startFakeProvider, type FakeProvider} from './support/fake_iptv_server';
import {createFamily} from './support/membership';

let app: ReturnType<typeof initializeApp>, provider: FakeProvider, seq = 0;
const key = Buffer.alloc(32, 9).toString('base64');
before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) throw new Error('Emulators required');
  app = initializeApp({projectId: 'demo-iplex', storageBucket: 'demo-iplex.appspot.com'});
  provider = await startFakeProvider();
});
after(async () => { await provider.close(); await deleteApp(app); });
const db = () => getFirestore();
const deps = {execute, quota: firestoreQuota, consume: consumePlayerRequest, now: Date.now};
const tvCall = (action: string, payload: Record<string, unknown>, auth: PlayerAuth) =>
  runPlayer({action, payload: {...payload, requestId: randomBytes(16).toString('hex'), issuedAt: Date.now()}, auth, ip: '203.0.113.21'}, key, deps) as Promise<any>;

async function account(name: string): Promise<Identity> {
  const actor: Identity = {uid: `lib_${Date.now()}_${++seq}`, authTime: Math.floor(Date.now() / 1000)};
  await getAuth().createUser({uid: actor.uid, displayName: name});
  await execute('bootstrap', {}, actor);
  return actor;
}
async function setup() {
  const admin = await account('Ana');
  const fid = (await createFamily(admin, 'Casa') as {id: string}).id;
  const ctx = {contextFamilyId: fid};
  const save = async (name: string) => {
    const {id} = await execute('saveSource', {...ctx, name, format: 'xtream', url: provider.base, username: 'assinante', password: 'senha-1'}, admin, key) as {id: string};
    const ref = db().doc(`families/${fid}/sources/${id}`);
    await syncIptvCatalog(ref, key, (await ref.get()).data()!.currentJobId);
    assert.equal((await ref.get()).data()!.status, 'ready');
    return ref;
  };
  return {admin, fid, ctx, save};
}
const catalog = async (admin: Identity, ctx: object, id: string) => (await execute('readSourceCatalog', {...ctx, id}, admin) as any).items as any[];

test('library: editorial titles saved without IPTV, no duplicates across sources, linked when a catalog offers them', async () => {
  const {admin, fid, ctx, save} = await setup();
  const lib = (input: Record<string, unknown>) => execute('saveLibraryItem', {...ctx, profileId: 'admin', generation: 0, ...input}, admin) as Promise<any>;
  const home = (sourceId: string | null = null) => execute('readHome', {...ctx, sourceId}, admin) as Promise<any>;

  // 1) No source at all: a TMDB title (filmography) can be favorited and wished.
  await lib({list: 'favorites', kind: 'movie', tmdbId: 1001, title: 'Missão Fictícia', year: 2021, poster: 'https://image.tmdb.org/t/p/w342/abc.jpg'});
  await lib({list: 'wishlist', kind: 'series', tmdbId: 1001, title: 'Outra Série', year: 2020});
  let h = await home();
  assert.deepEqual(h.library.favorites.map((i: any) => [i.id, i.available, i.tmdbId, i.poster]), [['tmdb-movie-1001', false, 1001, 'https://image.tmdb.org/t/p/w342/abc.jpg']]);
  assert.deepEqual(h.library.wishlist.map((i: any) => [i.id, i.kind]), [['tmdb-tv-1001', 'series']], 'movie 1001 ≠ tv 1001');
  assert.ok(h.saved.favorites.includes('tmdb:movie:1001') && !h.saved.favorites.includes('tmdb:tv:1001'));
  assert.deepEqual([h.favorites, h.myList, h.favoriteIds], [[], [], []], 'legacy rows only carry catalog items');
  await assert.rejects(lib({list: 'wishlist', kind: 'channel', title: 'Canal'}), /wishlist-titles-only|title-reference/);
  await assert.rejects(lib({list: 'favorites', kind: 'movie', tmdbId: 5, title: 'X', poster: 'https://evil.example/p.jpg'}), /invalid|regex/i);
  await assert.rejects(lib({list: 'favorites', kind: 'movie', tmdbId: 5, title: 'X', generation: 7}), /stale-generation/);

  // 2) Saving the same TMDB title again is idempotent (one row).
  await lib({list: 'favorites', kind: 'movie', tmdbId: 1001, title: 'Missão Fictícia', year: 2021});
  const favorites = db().collection(`families/${fid}/profiles/admin/favorites`);
  assert.equal((await favorites.get()).size, 1);

  // 3) A source starts offering it (provider tmdb id): same library row, now available and linked.
  const a = await save('Fonte A');
  h = await home(a.id);
  const movieA = (await catalog(admin, ctx, a.id)).find(i => i.title === 'Missão Fictícia');
  assert.equal(movieA.tmdbId, 1001, 'provider tmdb id kept in the catalog');
  assert.deepEqual(h.library.favorites.map((i: any) => [i.id, i.available, i.library.id]), [[movieA.id, true, 'tmdb-movie-1001']]);
  assert.deepEqual(h.myList.map((i: any) => i.id), [movieA.id]);
  const row = (await favorites.doc('tmdb-movie-1001').get()).data()!;
  assert.deepEqual([row.catalogContentId, row.contentId, row.sourceId], [movieA.id, movieA.id, a.id], 'association persisted');
  assert.equal((await favorites.get()).size, 1, 'never saved twice');

  // 4) A second source with the same title: still one row; saving from it merges.
  const b = await save('Fonte B');
  const movieB = (await catalog(admin, ctx, b.id)).find(i => i.title === 'Missão Fictícia');
  await lib({list: 'favorites', kind: 'movie', contentId: movieB.id, sourceId: b.id, title: movieB.title});
  assert.equal((await favorites.get()).size, 1);
  h = await home(b.id);
  assert.equal(h.library.favorites.length, 1);
  assert.ok(h.saved.favorites.includes(movieA.id) || h.saved.favorites.includes(movieB.id));

  // 5) TV compatibility: the TV sees it through readPlayerLibrary and its own removal removes the row.
  const s = await execute('beginDevicePair', {name: 'Sala', platform: 'tizen'}, undefined) as {token: string};
  const d = await execute('linkDevice', {...ctx, token: s.token}, admin) as {id: string};
  const credentialVersion = (await db().doc(`families/${fid}/devices/${d.id}`).get()).data()?.credentialVersion;
  const tv = {uid: `tv_${d.id}`, token: {deviceId: d.id, familyId: fid, credentialVersion, firebase: {sign_in_provider: 'custom'}}};
  await tvCall('acquireSession', {profileId: 'admin'}, tv);
  const linked = (await favorites.doc('tmdb-movie-1001').get()).data()!.contentId;
  const tvLib = await tvCall('readPlayerLibrary', {profileId: 'admin'}, tv);
  assert.deepEqual(tvLib.favorites.map((f: any) => f.contentId), [linked]);
  await tvCall('favorite', {profileId: 'admin', contentId: linked, title: 'Missão Fictícia', generation: 0}, tv);
  assert.equal((await favorites.get()).size, 1, 'TV add reuses the same row');
  await tvCall('favorite', {profileId: 'admin', contentId: linked, remove: true}, tv);
  assert.equal((await favorites.get()).size, 0, 'TV removal removes the canonical row');

  // Wishlist on the TV persists in the same profile collection used by Control.
  const wish = {profileId:'admin',contentId:linked,sourceId:linked===movieA.id?a.id:b.id,kind:'movie',title:'Missão Fictícia',generation:0};
  await tvCall('wishlist', wish, tv);
  await tvCall('wishlist', wish, tv);
  assert.equal((await db().collection(`families/${fid}/profiles/admin/wishlist`).where('contentId','==',linked).get()).size,1);
  assert.ok((await tvCall('readPlayerLibrary',{profileId:'admin'},tv)).wishlist.some((i:any)=>i.contentId===linked));
  assert.ok((await home()).library.wishlist.some((i:any)=>i.id===linked));
  await assert.rejects(tvCall('wishlist',{...wish,generation:99},tv),/stale-generation/);
  await assert.rejects(tvCall('wishlist',{...wish,profileId:'guest'},tv),/session-expired|profile/);
  await assert.rejects(tvCall('wishlist',{...wish,kind:'channel'},tv),/invalid/);
  await assert.rejects(tvCall('wishlist',{...wish,contentId:'not-authorized'},tv),/not-found/);
  await tvCall('wishlist',{...wish,remove:true},tv);
  assert.ok(!(await tvCall('readPlayerLibrary',{profileId:'admin'},tv)).wishlist.some((i:any)=>i.contentId===linked));

  // 6) Source removed: an editorial row stays (unavailable), it is not deleted.
  await lib({list: 'wishlist', kind: 'movie', contentId: movieA.id, sourceId: a.id, tmdbId: 1001, title: 'Missão Fictícia', year: 2021});
  await a.update({enabled: false}); await b.update({enabled: false});
  h = await home();
  assert.deepEqual(h.library.wishlist.map((i: any) => [i.id, i.available]).sort(), [['tmdb-movie-1001', false], ['tmdb-tv-1001', false]]);

  // 7) Remove and add again.
  await lib({list: 'wishlist', kind: 'series', tmdbId: 1001, remove: true});
  await lib({list: 'wishlist', kind: 'series', tmdbId: 1001, title: 'Outra Série', year: 2020});
  assert.equal((await home()).library.wishlist.length, 2);

  // 8) Title-only correspondence is accepted only with exact title + year and no conflicting id.
  await a.update({enabled: true});
  assert.equal((await execute('resolveTitle', {...ctx, kind: 'movie', tmdbId: 1001}, admin) as any).match, 'tmdb');
  const series = (await execute('resolveTitle', {...ctx, kind: 'series', tmdbId: 77, title: 'Série Exemplo'}, admin) as any);
  assert.equal(series.item, null, 'no year → ambiguous, never linked');
  assert.equal((await execute('resolveTitle', {...ctx, kind: 'movie', tmdbId: 999, title: 'Missão Fictícia', year: 2021}, admin) as any).item, null, 'another provider tmdb id wins over the title');
  assert.equal((await execute('resolveTitle', {...ctx, kind: 'movie', tmdbId: 1001, title: 'X'}, admin) as any).item.title, 'Missão Fictícia');

  // 9) "Limpar favoritos" in the Gestor clears both lists (one personal library).
  await execute('clearProfileData', {...ctx, profileId: 'admin', category: 'favorites', requestId: 'clear-lib-1'}, admin);
  h = await home();
  assert.deepEqual([h.library.favorites, h.library.wishlist], [[], []]);
  assert.equal((await db().collection(`families/${fid}/profiles/admin/wishlist`).get()).size, 0);
  await assert.rejects(lib({list: 'wishlist', kind: 'movie', tmdbId: 1, title: 'Velho'}), /stale-generation/);

  // "Ver tudo": the Home shows 10 per section; the section request returns all.
  for (let id = 2001; id <= 2012; id++) await lib({list: 'favorites', kind: 'movie', tmdbId: id, title: `Título ${id}`, generation: 1});
  assert.equal((await home()).library.favorites.length, 10);
  const whole = await execute('readHome', {...ctx, sourceId: null, section: 'favorites'}, admin) as any;
  assert.equal(whole.library.favorites.length, 12);
  assert.equal(whole.library.wishlist.length <= 10, true, 'other sections keep the Home size');
  await assert.rejects(execute('readHome', {...ctx, section: 'everything'}, admin), /invalid|enum/i);

  // Catalog tabs: one kind only.
  const onlyMovies = await execute('readSourceCatalog', {...ctx, id: a.id, kind: 'movie'}, admin) as any;
  assert.ok(onlyMovies.items.length > 0 && onlyMovies.items.every((i: any) => i.kind === 'movie'));
  await assert.rejects(execute('readSourceCatalog', {...ctx, id: a.id, kind: 'radio'}, admin), /invalid|enum/i);

  // "Remover de Continuar assistindo": the title and all its episodes, own profile only.
  const progressCol = db().collection(`families/${fid}/profiles/admin/watch_progress`);
  await progressCol.doc('serieX').set({contentId: 'serieX', position: 5, duration: 100, generation: 0, updatedAt: Date.now()});
  await progressCol.doc('serieX_e1').set({contentId: 'serieX_e1', position: 5, duration: 100, generation: 0, updatedAt: Date.now()});
  await progressCol.doc('serieX_e2').set({contentId: 'serieX_e2', position: 5, duration: 100, generation: 0, updatedAt: Date.now()});
  await progressCol.doc('outro').set({contentId: 'outro', position: 5, duration: 100, generation: 0, updatedAt: Date.now()});
  assert.deepEqual(await execute('removeProgress', {...ctx, profileId: 'admin', contentId: 'serieX'}, admin), {ok: true, removed: 2});
  assert.deepEqual((await progressCol.get()).docs.map(d => d.id), ['outro']);
  const stranger = await account('Outro');
  await assert.rejects(execute('removeProgress', {contextFamilyId: fid, profileId: 'admin', contentId: 'outro'}, stranger), /permission|denied|family/i);

  // Presence: only the caller's own member record gets lastActiveAt.
  assert.equal((await execute('touchPresence', {}, admin) as {ok: boolean}).ok, true);
  const presence = (await db().doc(`families/${fid}/members/${admin.uid}`).get()).data();
  assert.equal(typeof presence?.lastActiveAt, 'number');

  // 10) Discovery grant: person account yes; TVs never.
  assert.deepEqual(await execute('authorizeDiscovery', ctx, admin), {ok: true});
  await assert.rejects(tvCall('authorizeDiscovery', {}, tv), /permission|unknown|not-allowed|invalid/i);
});

test('library: kids profile only saves catalog items it can see; no editorial discovery or entries', async () => {
  const {admin, fid, ctx, save} = await setup();
  const src = await save('Fonte');
  const pid = (await execute('saveProfile', {name: 'Lia', type: 'kids', ...ctx}, admin) as {id: string}).id;
  const {code} = await execute('createProfileLinkCode', {profileId: pid, ...ctx}, admin) as {code: string};
  const lia = await account('Lia');
  await execute('redeemProfileLink', {code}, lia);
  const liaCtx = {contextFamilyId: fid};
  await assert.rejects(execute('authorizeDiscovery', liaCtx, lia), /content-unavailable/);
  const lib = (input: Record<string, unknown>) => execute('saveLibraryItem', {...liaCtx, profileId: pid, generation: 0, ...input}, lia);
  await assert.rejects(lib({list: 'favorites', kind: 'movie', tmdbId: 1001, title: 'Missão Fictícia'}), /content-unavailable/);
  const items = await catalog(lia, liaCtx, src.id);
  const kidsMovie = items.find(i => i.title === 'Aventura no Parque');
  assert.ok(kidsMovie && !items.some(i => i.title === 'Missão Fictícia'), 'kids catalog only');
  await lib({list: 'wishlist', kind: 'movie', contentId: kidsMovie.id, sourceId: src.id, title: kidsMovie.title});
  // An adult item of the source is refused even with its real id.
  const adult = (await catalog(admin, ctx, src.id)).find(i => i.title === 'Missão Fictícia');
  await assert.rejects(lib({list: 'favorites', kind: 'movie', contentId: adult.id, sourceId: src.id, title: adult.title}), /not-found/);
  // Another profile's library cannot be written.
  await assert.rejects(execute('saveLibraryItem', {...liaCtx, profileId: 'admin', generation: 0, list: 'favorites', kind: 'movie', contentId: kidsMovie.id, sourceId: src.id, title: 'x'}, lia), /permission-denied/);
  // A wished editorial row planted for the kids profile is never shown to it.
  await db().doc(`families/${fid}/profiles/${pid}/wishlist/tmdb-movie-1001`).set({contentId: 'tmdb-movie-1001', kind: 'movie', tmdbId: 1001, title: 'Missão Fictícia', generation: 0, updatedAt: Date.now()});
  const h = await execute('readHome', {...liaCtx, sourceId: src.id}, lia) as any;
  assert.deepEqual(h.library.wishlist.map((i: any) => i.title), ['Aventura no Parque']);
});

test('readHome: Meu iPlex rules — Lançamentos merged by date, Assistidos, one Continuar entry per title', async () => {
  const {admin, fid, ctx, save} = await setup();
  const src = await save('Fonte');
  const items = await catalog(admin, ctx, src.id);
  const byTitle = (t: string) => items.find(i => i.title === t);
  const [missao, aventura, serie, canal] = ['Missão Fictícia', 'Aventura no Parque', 'Série Exemplo', 'Canal Notícias'].map(byTitle);
  const profile = db().doc(`families/${fid}/profiles/admin`);
  const now = Date.now();
  // Series: the newest episode is completed, an older one unfinished → the series is not offered.
  await profile.collection('watch_progress').doc(`${serie.id}_e2`).set({contentId: `${serie.id}_e2`, position: 99, duration: 100, generation: 0, updatedAt: now});
  await profile.collection('watch_progress').doc(`${serie.id}_e1`).set({contentId: `${serie.id}_e1`, position: 10, duration: 100, generation: 0, updatedAt: now - 1000});
  await profile.collection('watch_progress').doc(missao.id).set({contentId: missao.id, position: 10, duration: 100, generation: 0, updatedAt: now - 2000});
  await profile.collection('watch_progress').doc(canal.id).set({contentId: canal.id, position: 10, duration: 100, generation: 0, updatedAt: now - 3000});
  for (const [id, at] of [[`${serie.id}_e1`, now], [`${serie.id}_e2`, now - 10], [aventura.id, now - 20], [canal.id, now - 30]] as const) {
    await profile.collection('watched').doc(id).set({contentId: id, completedAt: at, generation: 0});
  }
  const h = await execute('readHome', {...ctx, sourceId: src.id}, admin) as any;
  assert.deepEqual(h.continueWatching.map((i: any) => i.id), [missao.id], 'one per title, no channels, completed newest wins');
  assert.deepEqual(h.watched.map((i: any) => i.id), [serie.id, aventura.id], 'one per title, movies and series only');
  const dates = h.releases.map((i: any) => i.addedAt);
  assert.ok(h.releases.length > 0 && h.releases.every((i: any) => i.kind === 'movie' || i.kind === 'series'));
  assert.deepEqual(dates, [...dates].sort((a: number, b: number) => b - a), 'newest first, movies and series merged');
  assert.ok(h.releases.some((i: any) => i.id === aventura.id) && h.releases.some((i: any) => i.id === missao.id));
  const whole = await execute('readHome', {...ctx, sourceId: src.id, section: 'watched'}, admin) as any;
  assert.deepEqual(whole.watched.map((i: any) => i.id), [serie.id, aventura.id]);

});
