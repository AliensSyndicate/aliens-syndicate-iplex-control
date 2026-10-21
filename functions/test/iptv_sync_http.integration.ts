/**
 * IPTV sync end to end over real HTTP (controlled local provider) and the
 * emulators: Control saves the source → worker downloads/parses/publishes →
 * the TV (player callable) reads the catalog, series episodes and stream URL.
 */
process.env.IPLEX_TEST_PRIVATE_PROVIDERS = '1';
import {randomBytes} from 'node:crypto';
import {test, before, after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp, deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {getStorage} from 'firebase-admin/storage';
import {execute, Identity} from '../src/service';
import {syncIptvCatalog, streamIndexPath} from '../src/iptv_sync';
import {firestoreQuota, runPlayer, consumePlayerRequest, type PlayerAuth} from '../src/player';
import {startFakeProvider, type FakeProvider} from './support/fake_iptv_server';
import {hash} from '../src/domain';

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
  runPlayer({action, payload: {...payload, requestId: randomBytes(16).toString('hex'), issuedAt: Date.now()}, auth, ip: '203.0.113.20'}, key, deps) as Promise<any>;

async function family() {
  const admin: Identity = {uid: `sync_${Date.now()}_${++seq}`, authTime: Math.floor(Date.now() / 1000)};
  await getAuth().createUser({uid: admin.uid, displayName: 'Ana'});
  await execute('bootstrap', {}, admin);
  const fid = (await execute('createFamily', {name: 'Casa'}, admin) as {id: string}).id;
  return {admin, fid, ctx: {contextFamilyId: fid}};
}
async function tv(admin: Identity, fid: string): Promise<PlayerAuth> {
  const s = await execute('beginDevicePair', {name: 'Sala', platform: 'tizen'}, undefined) as {token: string};
  const d = await execute('linkDevice', {token: s.token, contextFamilyId: fid}, admin) as {id: string};
  const credentialVersion = (await db().doc(`families/${fid}/devices/${d.id}`).get()).data()?.credentialVersion;
  const auth = {uid: `tv_${d.id}`, token: {deviceId: d.id, familyId: fid, credentialVersion, firebase: {sign_in_provider: 'custom'}}};
  await tvCall('acquireSession', {profileId: 'admin'}, auth);
  return auth;
}
async function save(admin: Identity, fid: string, input: Record<string, unknown>) {
  const {id} = await execute('saveSource', {contextFamilyId: fid, ...input}, admin, key) as {id: string};
  return db().doc(`families/${fid}/sources/${id}`);
}
async function sync(ref: FirebaseFirestore.DocumentReference) {
  const data = (await ref.get()).data()!;
  await syncIptvCatalog(ref, key, data.currentJobId);
  const source = (await ref.get()).data()!;
  const job = source.currentJobId ? (await db().doc(`iptv_sync_jobs/${source.currentJobId}`).get()).data() : (await db().collection('iptv_sync_jobs').where('sourceId', '==', ref.id).get()).docs.map(d => d.data()).sort((a, b) => b.createdAt - a.createdAt)[0];
  return {source, job: job!};
}
/** The scheduler (recoverIptvJobs) picks retries later; tests advance time by clearing nextSyncAt. */
const due = (ref: FirebaseFirestore.DocumentReference) => ref.update({nextSyncAt: 0});

test('Xtream Codes: channels, movies and series synced; TV reads catalog, episodes on demand and stream URL', async () => {
  const {admin, fid} = await family();
  const ref = await save(admin, fid, {name: 'Xtream de teste', format: 'xtream', url: provider.base, username: 'assinante', password: 'senha-1'});
  const {source, job} = await sync(ref);
  assert.equal(source.status, 'ready', JSON.stringify({code: source.errorCode, reason: source.errorReason}));
  assert.equal(job.status, 'completed'); assert.equal(job.progress, 100);
  assert.deepEqual([source.channelCount, source.movieCount, source.seriesCount], [3, 2, 1]);
  assert.equal(provider.hits['/player_api.php?get_series_info'] ?? 0, 0, 'no per-series request during sync');
  assert.equal(JSON.stringify(source).includes('senha-1'), false);
  const player = await tv(admin, fid);
  const spaces = await tvCall('listProfileSpaces', {}, player);
  assert.deepEqual(spaces.spaces[0].kinds, ['channel', 'movie', 'series']);
  const page = await tvCall('readSourceCatalog', {id: ref.id}, player);
  assert.deepEqual(page.categories.map((c: any) => c.name).sort(), ['Filmes', 'Infantil', 'Notícias', 'Séries']);
  const series = page.items.find((i: any) => i.kind === 'series');
  const details = await tvCall('readSourceSeries', {id: ref.id, seriesId: series.providerRef}, player);
  assert.deepEqual(details.details.episodes['1'].map((e: any) => e.title), ['Começo', 'Meio']);
  assert.equal(provider.hits['/player_api.php?get_series_info'], 1);
  await tvCall('readSourceSeries', {id: ref.id, seriesId: series.providerRef}, player);
  assert.equal(provider.hits['/player_api.php?get_series_info'], 1, 'episodes cached');
  const movie = page.items.find((i: any) => i.title === 'Missão Fictícia');
  const grant = await tvCall('resolveSourceStream', {id: ref.id, itemId: movie.id}, player);
  assert.equal(grant.url, `${provider.base}/movie/assinante/senha-1/201.mkv`);
});

test('Xtream wrong credentials: invalid-credentials (not retried, authorization invalid), in each provider shape', async () => {
  const {admin, fid} = await family();
  const getPhpBefore = provider.hits['/get.php'] ?? 0;
  for (const mode of ['zero', 'empty'] as const) {
    provider.mode.auth = mode;
    const ref = await save(admin, fid, {name: `Errada ${mode}`, format: 'xtream', url: provider.base, username: 'assinante', password: 'senha-1'});
    const {source, job} = await sync(ref);
    assert.equal(source.status, 'error'); assert.equal(source.errorCode, 'invalid-credentials'); assert.equal(source.authorizationStatus, 'invalid');
    assert.equal(job.status, 'failed'); assert.equal(job.errorRetryable, false);
  }
  // Wrong credentials never try the M3U Plus export.
  assert.equal(provider.hits['/get.php'] ?? 0, getPhpBefore);
  // API answering HTML and no M3U Plus export either: the API error is reported.
  provider.mode.auth = 'html'; provider.mode.m3uPlus = false;
  const ref = await save(admin, fid, {name: 'Painel errado', format: 'xtream', url: provider.base, username: 'assinante', password: 'senha-1'});
  const {source} = await sync(ref);
  assert.equal(source.errorCode, 'provider-unavailable'); assert.equal(source.errorReason, 'xtream-auth-unexpected-response');
  Object.assign(provider.mode, {auth: 'ok', m3uPlus: true});
});

test('Xtream API down: catalog from the M3U Plus export, playback from the sealed index; API back keeps channel/movie ids', async () => {
  const {admin, fid} = await family();
  provider.mode.apiStatus = 503;
  try {
    const ref = await save(admin, fid, {name: 'Xtream sem API', format: 'xtream', url: provider.base, username: 'assinante', password: 'senha-1'});
    const {source, job} = await sync(ref);
    assert.equal(source.status, 'ready', JSON.stringify({code: source.errorCode, reason: source.errorReason}));
    assert.equal(job.status, 'completed');
    assert.deepEqual([source.channelCount, source.movieCount, source.seriesCount], [2, 2, 1]);
    assert.equal(JSON.stringify(source).includes('senha-1'), false);
    const [sealed] = await getStorage().bucket().file(streamIndexPath(fid, ref.id)).download();
    assert.equal(sealed.toString().includes('senha-1'), false, 'stream index is encrypted');
    const player = await tv(admin, fid);
    const page = await tvCall('readSourceCatalog', {id: ref.id}, player);
    const apiHits = provider.hits['/player_api.php'] ?? 0;
    const channel = page.items.find((i: any) => i.title === 'Canal Notícias');
    assert.equal(channel.catalogItemId, hash('channel:101'), 'same id as get_live_streams');
    assert.equal((await tvCall('resolveSourceStream', {id: ref.id, itemId: channel.id}, player)).url, `${provider.base}/live/assinante/senha-1/101.ts`);
    const movie = page.items.find((i: any) => i.kind === 'movie' && i.title.startsWith('Missão'));
    assert.equal((await tvCall('resolveSourceStream', {id: ref.id, itemId: movie.id}, player)).url, `${provider.base}/movie/assinante/senha-1/201.mkv`);
    const series = page.items.find((i: any) => i.kind === 'series');
    const details = await tvCall('readSourceSeries', {id: ref.id, seriesId: series.providerRef}, player);
    assert.deepEqual(details.details.episodes['1'].map((e: any) => e.title), ['Começo', 'Meio']);
    const episode = details.details.episodes['2'][0];
    assert.equal((await tvCall('resolveSourceStream', {id: ref.id, itemId: series.id, episodeId: episode.id}, player)).url, `${provider.base}/series/assinante/senha-1/303.mkv`);
    await assert.rejects(tvCall('resolveSourceStream', {id: ref.id, itemId: series.id, episodeId: 'f'.repeat(64)}, player), /not-found/);
    assert.equal(provider.hits['/player_api.php'] ?? 0, apiHits, 'playback did not depend on the unavailable API');

    // API back: next sync uses it again; channels and movies keep their ids, the stale index is removed.
    provider.mode.apiStatus = 0;
    await ref.update({lastAttemptAt: 0});
    await execute('syncSource', {id: ref.id, contextFamilyId: fid}, admin, key);
    const back = await sync(ref);
    assert.equal(back.source.status, 'ready');
    assert.deepEqual([back.source.channelCount, back.source.movieCount, back.source.seriesCount], [3, 2, 1]);
    const ids = new Set((await tvCall('readSourceCatalog', {id: ref.id}, player)).items.map((i: any) => i.catalogItemId));
    for (const id of [hash('channel:101'), hash('channel:102'), hash('movie:201'), hash('movie:202')]) assert.ok(ids.has(id), id);
    assert.equal((await getStorage().bucket().file(streamIndexPath(fid, ref.id)).exists())[0], false);
    const again = (await tvCall('readSourceCatalog', {id: ref.id, search: 'Missão'}, player)).items[0];
    assert.equal((await tvCall('resolveSourceStream', {id: ref.id, itemId: again.id}, player)).url, `${provider.base}/movie/assinante/senha-1/201.mkv`);
  } finally {
    provider.mode.apiStatus = 0;
  }
});

test('M3U file uploaded from the Control: synced, published and playable', async () => {
  const {admin, fid} = await family();
  const fileContent = '#EXTM3U\n#EXTINF:-1 group-title="Notícias",Canal Arquivo A\nhttps://example.com/a.m3u8\n#EXTINF:-1 group-title="Filmes",Filme Arquivo (2020)\nhttps://example.com/f.mp4\n';
  const ref = await save(admin, fid, {name: 'Lista em arquivo', format: 'file', fileName: 'lista.m3u', fileContent});
  const {source, job} = await sync(ref);
  assert.equal(source.status, 'ready', JSON.stringify({code: source.errorCode, reason: source.errorReason}));
  assert.equal(job.status, 'completed');
  assert.deepEqual([source.channelCount, source.movieCount], [1, 1]);
  const player = await tv(admin, fid);
  const channel = (await tvCall('readSourceCatalog', {id: ref.id, search: 'Canal Arquivo'}, player)).items[0];
  assert.equal((await tvCall('resolveSourceStream', {id: ref.id, itemId: channel.id}, player)).url, 'https://example.com/a.m3u8');
});

test('M3U Plus (get.php): single download, tolerant parsing, series with episodes, playback from the sealed index', async () => {
  const {admin, fid} = await family();
  const before = provider.hits['/get.php'] ?? 0;
  const ref = await save(admin, fid, {name: 'Lista M3U', format: 'm3u', url: `${provider.base}/get.php?username=assinante&password=senha-1&type=m3u_plus&output=ts`});
  const {source} = await sync(ref);
  assert.equal(source.status, 'ready', JSON.stringify({code: source.errorCode, reason: source.errorReason}));
  assert.equal((provider.hits['/get.php'] ?? 0) - before, 1, 'the list is downloaded once');
  assert.deepEqual([source.channelCount, source.movieCount, source.seriesCount], [2, 2, 1]);
  const [exists] = await getStorage().bucket().file(streamIndexPath(fid, ref.id)).exists();
  assert.ok(exists);
  const [sealed] = await getStorage().bucket().file(streamIndexPath(fid, ref.id)).download();
  assert.equal(sealed.toString().includes('senha-1'), false, 'stream index is encrypted');
  const player = await tv(admin, fid);
  const page = await tvCall('readSourceCatalog', {id: ref.id}, player);
  const series = page.items.find((i: any) => i.kind === 'series');
  const details = await tvCall('readSourceSeries', {id: ref.id, seriesId: series.providerRef}, player);
  const firstEpisode = details.details.episodes['1'][0];
  const hits = provider.hits['/get.php'];
  const grant = await tvCall('resolveSourceStream', {id: ref.id, itemId: series.id, episodeId: firstEpisode.id}, player);
  assert.equal(grant.url, `${provider.base}/series/assinante/senha-1/301.mkv`);
  const channel = page.items.find((i: any) => i.title === 'Canal Notícias');
  assert.equal((await tvCall('resolveSourceStream', {id: ref.id, itemId: channel.id}, player)).url, `${provider.base}/live/assinante/senha-1/101.ts`);
  assert.equal(provider.hits['/get.php'], hits, 'playback does not download the list again');
  await assert.rejects(tvCall('resolveSourceStream', {id: ref.id, itemId: series.id, episodeId: 'f'.repeat(64)}, player), /not-found/);
});

test('server unavailable and interrupted download: retried, then succeed; failure reason recorded', async () => {
  const {admin, fid} = await family();
  const down = await save(admin, fid, {name: 'Fora do ar', format: 'm3u', url: 'http://127.0.0.1:9/lista.m3u'});
  let r = await sync(down);
  assert.equal(r.source.status, 'queued'); assert.equal(r.source.errorCode, 'provider-unavailable'); assert.equal(r.source.errorReason, 'connection-failed');
  assert.equal(r.job.status, 'queued'); assert.equal(r.job.errorRetryable, true);
  for (let i = 0; i < 2; i++) { await due(down); r = await sync(down); }
  // Wrong URL (404): definitive at once, no pointless retries.
  const missing = await save(admin, fid, {name: 'URL errada', format: 'm3u', url: `${provider.base}/nao-existe.m3u`});
  r = await sync(missing);
  assert.equal(r.source.status, 'error'); assert.equal(r.source.errorReason, 'http-404'); assert.equal(r.job.errorRetryable, false);
  assert.equal(r.source.status, 'error', 'gives up after 3 attempts'); assert.equal(r.job.status, 'failed');

  // One interrupted connection is absorbed inside the same sync (a new connection, not a cached failure).
  provider.mode.flaky = 1;
  const once = await save(admin, fid, {name: 'Instável uma vez', format: 'm3u', url: `${provider.base}/flaky.m3u`});
  assert.equal((await sync(once)).source.status, 'ready');
  // Interrupted again on retry: the job is queued and the next run completes it.
  provider.mode.flaky = 2;
  const flaky = await save(admin, fid, {name: 'Instável', format: 'm3u', url: `${provider.base}/flaky.m3u?b`});
  r = await sync(flaky);
  assert.equal(r.source.status, 'queued'); assert.equal(r.source.errorCode, 'download-failed');
  await due(flaky);
  r = await sync(flaky);
  assert.equal(r.source.status, 'ready'); assert.equal(r.job.status, 'completed'); assert.equal(r.job.attempts, 2);
});

test('empty and large catalogs; same source again keeps identifiers; credential change and removal', async () => {
  const {admin, fid} = await family();
  const empty = await save(admin, fid, {name: 'Vazia', format: 'm3u', url: `${provider.base}/empty.m3u`});
  assert.equal((await sync(empty)).source.errorCode, 'suspicious-catalog');

  const started = Date.now();
  const big = await save(admin, fid, {name: 'Grande', format: 'm3u', url: `${provider.base}/big.m3u?n=60000`});
  const bigResult = await sync(big);
  assert.equal(bigResult.source.status, 'ready'); assert.equal(bigResult.source.channelCount, 60000);
  const elapsed = Date.now() - started;
  assert.ok(elapsed < 60000, `large catalog synced in ${elapsed} ms`);

  const ref = await save(admin, fid, {name: 'Xtream', format: 'xtream', url: provider.base, username: 'assinante', password: 'senha-1'});
  const first = await sync(ref);
  const player = await tv(admin, fid);
  const ids = (await tvCall('readSourceCatalog', {id: ref.id}, player)).items.map((i: any) => i.id).sort();
  // Same source again (manual sync from the Control; 10 s anti-repeat window elapsed).
  await ref.update({lastAttemptAt: 0});
  await execute('syncSource', {id: ref.id, contextFamilyId: fid}, admin, key);
  const again = await sync(ref);
  assert.equal(again.source.version, first.source.version); assert.equal(again.job.reusedCatalog, true);
  assert.deepEqual((await tvCall('readSourceCatalog', {id: ref.id}, player)).items.map((i: any) => i.id).sort(), ids);
  // Provider changed the password: the old one fails, the new one syncs with the same identifiers.
  provider.credentials.password = 'senha-2';
  await due(ref); // daily scheduled sync
  assert.equal((await sync(ref)).source.errorCode, 'invalid-credentials');
  await execute('saveSource', {id: ref.id, contextFamilyId: fid, name: 'Xtream', format: 'xtream', username: 'assinante', password: 'senha-2'}, admin, key);
  const renewed = await sync(ref);
  assert.equal(renewed.source.status, 'ready'); assert.equal(renewed.source.authorizationStatus, 'valid');
  assert.deepEqual((await tvCall('readSourceCatalog', {id: ref.id}, player)).items.map((i: any) => i.id).sort(), ids);
  const movie = (await tvCall('readSourceCatalog', {id: ref.id, search: 'Missão'}, player)).items[0];
  assert.match((await tvCall('resolveSourceStream', {id: ref.id, itemId: movie.id}, player)).url, /\/senha-2\//);
  provider.credentials.password = 'senha-1';
  // Removal: the source, its secret and its sealed stream index disappear.
  await execute('deleteSource', {id: big.id, contextFamilyId: fid}, admin, key);
  assert.equal((await big.get()).exists, false);
  assert.equal((await db().doc(`source_secrets/${fid}_${big.id}`).get()).exists, false);
  assert.equal((await getStorage().bucket().file(streamIndexPath(fid, big.id)).exists())[0], false);
  await assert.rejects(tvCall('readSourceCatalog', {id: big.id}, player), /not-found/);
});

test('personal IPTV space (account without family): the first TV gets the owner profile and reads the synced catalog', async () => {
  const owner: Identity = {uid: `personal_${Date.now()}_${++seq}`, authTime: Math.floor(Date.now() / 1000)};
  await getAuth().createUser({uid: owner.uid, displayName: 'Dono'});
  await execute('bootstrap', {}, owner);
  const {id} = await execute('saveSource', {name: 'Lista pessoal', format: 'm3u', url: `${provider.base}/big.m3u?n=5`}, owner, key) as {id: string};
  const ws = (await db().doc(`users/${owner.uid}`).get()).data()!.iptvWorkspaceId as string;
  assert.equal((await db().doc(`families/${ws}`).get()).data()?.kind, 'personalIptv');
  const ref = db().doc(`families/${ws}/sources/${id}`);
  assert.equal((await sync(ref)).source.status, 'ready');
  const pair = async () => {
    const s = await execute('beginDevicePair', {name: 'Sala', platform: 'tizen'}, undefined) as {token: string};
    const d = await execute('linkDevice', {token: s.token}, owner) as {id: string};
    const credentialVersion = (await db().doc(`families/${ws}/devices/${d.id}`).get()).data()?.credentialVersion;
    return {uid: `tv_${d.id}`, token: {deviceId: d.id, familyId: ws, credentialVersion, firebase: {sign_in_provider: 'custom'}}};
  };
  const auth = await pair();
  const profiles = await tvCall('listPlayerProfiles', {}, auth);
  assert.deepEqual(profiles.profiles.map((p: any) => [p.id, p.type]), [['admin', 'admin']]);
  await tvCall('acquireSession', {profileId: 'admin'}, auth);
  assert.deepEqual((await tvCall('listProfileSpaces', {}, auth)).spaces.map((s: any) => s.sourceId), [id]);
  assert.equal((await tvCall('readSourceCatalog', {id}, auth)).items.length, 5);
  // A second TV does not duplicate or reset the owner profile.
  await pair();
  assert.equal((await db().collection(`families/${ws}/profiles`).get()).size, 1);
});

test('Control Home: favorites, my list, continue watching and recently added, resolved from the real catalog', async () => {
  const {admin, fid, ctx} = await family();
  const ref = await save(admin, fid, {name: 'Xtream Home', format: 'xtream', url: provider.base, username: 'assinante', password: 'senha-1'});
  assert.equal((await sync(ref)).source.status, 'ready');
  const home = (input: Record<string, unknown> = {}) => execute('readHome', {...ctx, sourceId: ref.id, ...input}, admin) as Promise<any>;
  let h = await home();
  assert.deepEqual([h.profile.id, h.favorites, h.myList, h.continueWatching], ['admin', [], [], []]);
  // Recently added: newest first, only titles whose provider published a date.
  assert.deepEqual(h.recentMovies.map((i: any) => i.title), ['Aventura no Parque', 'Missão Fictícia']);
  assert.deepEqual(h.recentSeries.map((i: any) => i.title), ['Série Exemplo']);
  assert.equal(h.recentMovies[1].imageRef, 'https://img.example.com/p/missao.jpg');
  assert.equal(h.recentMovies[0].imageRef, undefined, 'artwork URL with a token is dropped');
  assert.equal(h.recentSeries[0].imageRef, undefined, 'http artwork is dropped');
  assert.equal((await home({sourceId: null})).recentMovies.length, 0, 'recent rows depend on the selected source');

  const page = await execute('readSourceCatalog', {...ctx, id: ref.id}, admin) as any;
  const byTitle = (t: string) => page.items.find((i: any) => i.title === t);
  const movie = byTitle('Missão Fictícia'), other = byTitle('Aventura no Parque'), channel = byTitle('Canal Notícias'), series = byTitle('Série Exemplo');
  for (const item of [movie, channel]) await execute('favorite', {...ctx, profileId: 'admin', contentId: item.id, title: item.title, generation: 0}, admin);
  await execute('watchProgress', {...ctx, profileId: 'admin', contentId: other.id, position: 30, duration: 100, generation: 0}, admin);
  await execute('watchProgress', {...ctx, profileId: 'admin', contentId: `${series.id}_e3011`, position: 10, duration: 100, generation: 0}, admin);
  await execute('watchProgress', {...ctx, profileId: 'admin', contentId: movie.id, position: 99, duration: 100, generation: 0}, admin);
  h = await home();
  assert.deepEqual(h.favorites.map((i: any) => i.title), ['Canal Notícias']);
  assert.deepEqual(h.myList.map((i: any) => i.title), ['Missão Fictícia']);
  assert.deepEqual(h.favoriteIds.sort(), [movie.id, channel.id].sort());
  assert.deepEqual(h.continueWatching.map((i: any) => [i.title, i.episodeId ?? null, i.progress.position]).sort(), [['Aventura no Parque', null, 30], ['Série Exemplo', '3011', 10]], 'finished titles (≥95%) are not offered');
  assert.equal(h.myList[0].id, movie.id, 'same public id as readSourceCatalog');
  assert.equal(JSON.stringify(h).includes('senha-1'), false);

  // A list cleared in the Gestor (new generation) disappears from the Home too.
  await db().doc(`families/${fid}/profiles/admin`).update({'generations.favorites': 1});
  h = await home();
  assert.deepEqual([h.favorites, h.myList, h.favoriteIds], [[], [], []]);

  // TMDB grant for the Control: movies/series only, same catalog rules.
  assert.deepEqual(await execute('authorizeMetadata', {...ctx, sourceId: ref.id, itemId: movie.id}, admin), {kind: 'movie', title: 'Missão Fictícia', year: '2021'});
  await assert.rejects(execute('authorizeMetadata', {...ctx, sourceId: ref.id, itemId: channel.id}, admin), /not-found/);

  // "Continuar assistindo" on the TV: the play request carries resume.
  const tvAuth = await tv(admin, fid);
  const request = await execute('requestPlayback', {...ctx, deviceId: tvAuth.token.deviceId, sourceId: ref.id, itemId: other.id, requestId: randomBytes(16).toString('hex'), resume: true}, admin) as any;
  const stored = (await db().doc(`families/${fid}/devices/${tvAuth.token.deviceId}/play_requests/${request.id}`).get()).data()!;
  assert.equal(stored.resume, true);
});
