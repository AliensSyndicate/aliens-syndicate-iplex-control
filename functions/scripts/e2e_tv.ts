/**
 * Cross-project end-to-end driver (emulators only): plays the iPlex Control
 * (phone) against the real `manager` callable and Firestore rules, while the
 * iPlex Web runs as the TV (browser or Samsung shell) against the same emulators.
 *
 *   tsx scripts/e2e_tv.ts setup                 family, kids/regular profiles, parental PIN, M3U source
 *   tsx scripts/e2e_tv.ts link <6-digit code>   confirm the pairing code shown by the TV
 *   tsx scripts/e2e_tv.ts play <title> [tvId]   search the catalog and ask the TV to start it
 *   tsx scripts/e2e_tv.ts unlink [tvId]         unlink the TV (with the TV open)
 *   tsx scripts/e2e_tv.ts subscription <expired|trial>
 *   tsx scripts/e2e_tv.ts status
 *   tsx scripts/e2e_tv.ts invite                  admin invites the newest anonymous emulator account (Control on a simulator)
 *   tsx scripts/e2e_tv.ts single                  delete the non-admin profiles (TV opens the admin profile directly)
 *   tsx scripts/e2e_tv.ts tvcode [platform]     code shown by the newest unpaired TV (no camera/screen needed)
 *
 * Refuses to run unless every Firebase endpoint is an emulator on demo-iplex.
 */
import assert from 'node:assert/strict';
import {randomBytes, randomUUID} from 'node:crypto';
import {existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {initializeApp} from 'firebase/app';
import {connectAuthEmulator, createUserWithEmailAndPassword, getAuth, signInWithEmailAndPassword, updateProfile} from 'firebase/auth';
import {connectFunctionsEmulator, getFunctions, httpsCallable} from 'firebase/functions';
import {collection, connectFirestoreEmulator, doc, getDoc, getDocs, getFirestore, onSnapshot} from 'firebase/firestore';

const host = process.env.EMULATOR_HOST ?? '127.0.0.1';
const STATE = process.env.E2E_TV_STATE ?? 'build/e2e-tv/state.json';
type State = {email: string; password: string; fid?: string; sourceId?: string; tvId?: string};
const load = (): State | null => existsSync(STATE) ? JSON.parse(readFileSync(STATE, 'utf8')) : null;
const save = (s: State) => { mkdirSync(STATE.replace(/\/[^/]+$/, ''), {recursive: true}); writeFileSync(STATE, JSON.stringify(s, null, 1)); };
const log = (s: string) => console.log(`  ✔ ${s}`);

async function phone(state: State, create = false) {
  const app = initializeApp({projectId: 'demo-iplex', apiKey: 'demo-key', appId: 'demo'}, randomUUID());
  const auth = getAuth(app); connectAuthEmulator(auth, `http://${host}:9099`, {disableWarnings: true});
  const functions = getFunctions(app, 'us-central1'); connectFunctionsEmulator(functions, host, 5001);
  const db = getFirestore(app); connectFirestoreEmulator(db, host, 8080);
  if (create) {
    const cred = await createUserWithEmailAndPassword(auth, state.email, state.password);
    await updateProfile(cred.user, {displayName: 'Ana Admin'});
  } else await signInWithEmailAndPassword(auth, state.email, state.password);
  const manager = httpsCallable(functions, 'manager', {timeout: 60000});
  const call = async (action: string, payload: Record<string, unknown> = {}) =>
    (await manager({action, payload: {contextFamilyId: state.fid ?? null, ...payload}})).data as any;
  return {db, call, uid: auth.currentUser!.uid};
}

// Public test streams (HLS); classification comes from the playlist itself.
const PLAYLIST = `#EXTM3U
#EXTINF:-1 tvg-id="teste.noticias" group-title="Notícias",Canal Teste Notícias
https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8
#EXTINF:-1 tvg-id="teste.infantil" tvg-rating="L" group-title="Infantil",Canal Teste Infantil
https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8
#EXTINF:-1 type="movie" tvg-rating="L" group-title="Infantil",Big Buck Bunny (2008)
https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8
#EXTINF:-1 type="movie" tvg-rating="12" group-title="Filmes",Sintel (2010)
https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8
#EXTINF:-1 type="movie" tvg-rating="16" group-title="Filmes",Tears of Steel (2012)
https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8
#EXTINF:-1 tvg-id="teste.offline" group-title="Notícias",Canal Fora do Ar
https://test-streams.mux.dev/iplex-e2e-offline/stream.m3u8
`;

async function setup() {
  const state: State = {email: `ana-${Date.now()}@example.test`, password: randomUUID()};
  const p = await phone(state, true);
  await p.call('bootstrap');
  state.fid = (await p.call('createFamily', {name: 'Família E2E'})).id; save(state);
  log(`account + family ${state.fid}`);
  await p.call('saveProfile', {name: 'Lia', type: 'kids', requestId: 'e2e-kids'});
  await p.call('saveProfile', {name: 'Rui', requestId: 'e2e-regular'});
  log('profiles: Ana (admin), Lia (kids), Rui (regular)');
  await p.call('setParentalPin', {pin: '2468', confirmPin: '2468'});
  log('parental PIN set (2468)');
  const source = await p.call('saveSource', {name: 'Lista E2E', format: 'file', fileName: 'e2e.m3u', fileContent: PLAYLIST, requestId: 'e2e-source'});
  state.sourceId = source.id; save(state);
  const started = Date.now();
  for (;;) {
    const s = (await getDoc(doc(p.db, `families/${state.fid}/sources/${source.id}`))).data();
    if (s?.status === 'ready') { log(`source synced by the real pipeline: ${s.count} items`); break; }
    if (s?.status === 'error') throw new Error(`sync failed: ${s.errorCode}`);
    if (Date.now() - started > 120_000) throw new Error('sync timeout');
    await new Promise(r => setTimeout(r, 1500));
  }
}

async function link(code: string) {
  const state = load()!; const p = await phone(state);
  const info = await p.call('inspectPairingSession', {code});
  log(`TV found: ${info.displayName} (${info.platform} ${info.model})`);
  const device = await p.call('linkDevice', {code});
  state.tvId = device.id; save(state);
  log(`TV linked: ${device.id}`);
}

const FINAL = new Set(['started', 'declined', 'failed', 'expired', 'superseded']);
async function play(title: string, tvId?: string) {
  const state = load()!; const p = await phone(state); const target = tvId ?? state.tvId!;
  const page = await p.call('readSourceCatalog', {id: state.sourceId, search: title});
  const item = page.items[0]; assert.ok(item, `no catalog item for "${title}"`);
  log(`search "${title}" → ${item.title} (${item.kind})`);
  const t0 = Date.now();
  const sent = await p.call('requestPlayback', {deviceId: target, sourceId: state.sourceId, itemId: item.id, requestId: randomBytes(16).toString('hex')});
  log(`request ${sent.id} sent (expires in ${Math.round((sent.expiresAt - Date.now()) / 1000)} s)`);
  await new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => { stop(); reject(new Error('no final status in 90 s')); }, 90_000);
    const stop = onSnapshot(doc(p.db, `families/${state.fid}/devices/${target}/play_requests/${sent.id}`), snap => {
      const d = snap.data(); if (!d) return;
      console.log(`    · ${((Date.now() - t0) / 1000).toFixed(1)} s ${d.status}${d.errorCode ? ` (${d.errorCode})` : ''}`);
      if (FINAL.has(d.status)) { clearTimeout(timer); stop(); resolve(); }
    }, reject);
  });
}

async function unlink(tvId?: string) {
  const state = load()!; const p = await phone(state);
  await p.call('deleteDevice', {id: tvId ?? state.tvId});
  log(`TV ${tvId ?? state.tvId} unlinked`);
}

async function subscription(kind: string) {
  const state = load()!;
  const now = Date.now();
  await (await adminDb()).doc(`families/${state.fid}/private/subscription`).set(kind === 'expired' ? {status: 'expired', trialStartedAt: now - 9e8, trialEndsAt: now - 1000} : {status: 'trial', trialStartedAt: now, trialEndsAt: now + 7 * 864e5});
  log(`subscription → ${kind}`);
}

async function adminDb() {
  const {initializeApp: adminApp, getApps} = await import('firebase-admin/app');
  const {getFirestore: db} = await import('firebase-admin/firestore');
  process.env.FIRESTORE_EMULATOR_HOST ??= `${host}:8080`;
  if (!getApps().length) adminApp({projectId: 'demo-iplex'});
  return db();
}

async function tvcode(platform = 'tizen') {
  const rows = (await (await adminDb()).collection('device_pairing_sessions').where('platform', '==', platform).get()).docs
    .map(d => d.data()).filter(d => !d.used && d.expiresAt > Date.now()).sort((a, b) => b.createdAt - a.createdAt);
  assert.ok(rows[0], `no pending ${platform} pairing`);
  console.log(`${rows[0].code} · ${rows[0].name} · ${rows[0].model}`);
}

async function invite() {
  const state = load()!; const p = await phone(state);
  const {getAuth: adminAuth} = await import('firebase-admin/auth');
  process.env.FIREBASE_AUTH_EMULATOR_HOST ??= `${host}:9099`;
  const db = await adminDb();
  const users = (await adminAuth().listUsers(1000)).users.filter(u => !u.providerData.length).sort((a, b) => Date.parse(b.metadata.creationTime) - Date.parse(a.metadata.creationTime));
  assert.ok(users[0], 'no anonymous account');
  const code = (await db.doc(`users/${users[0].uid}`).get()).data()?.publicCode as string;
  assert.ok(code, 'account not bootstrapped yet');
  await p.call('lookupPublicUser', {code, familyId: state.fid});
  const r = await p.call('requestMembership', {code, familyId: state.fid});
  log(`membership request ${r.id} sent to ${users[0].uid} (${code})`);
}

async function single() {
  const state = load()!; const p = await phone(state);
  for (const requestId of ['e2e-kids', 'e2e-regular']) {
    const {createHash} = await import('node:crypto');
    const id = `p_${createHash('sha256').update(`${state.fid}:${requestId}`).digest('hex').slice(0, 32)}`;
    await p.call('deleteProfile', {id}).then(() => log(`profile ${id} deleted`), (e: any) => console.log(`    · ${id}: ${e.message}`));
  }
}

async function status() {
  const state = load()!; const p = await phone(state);
  const family = (await getDoc(doc(p.db, `families/${state.fid}`))).data()!;
  const devices = await getDocs(collection(p.db, `families/${state.fid}/devices`));
  console.log(JSON.stringify({fid: state.fid, parental: family.parental, leases: family.leases, devices: devices.docs.map(d => ({id: d.id, name: d.data().name, onlineUntil: d.data().onlineUntil}))}, null, 1));
}

const [command, ...args] = process.argv.slice(2);
if (!/^(127\.0\.0\.1|localhost|192\.168\.\d+\.\d+)$/.test(host)) throw new Error('emulator host required');
const run = {setup, link: () => link(args[0]!), play: () => play(args[0]!, args[1]), unlink: () => unlink(args[0]), subscription: () => subscription(args[0]!), status, single, invite, tvcode: () => tvcode(args[0])}[command ?? ''];
if (!run) { console.error('usage: setup | link <code> | play <title> [tvId] | unlink [tvId] | subscription <expired|trial> | status | tvcode [platform]'); process.exit(2); }
run().then(() => process.exit(0), e => { console.error(`✖ ${e.code ?? ''} ${e.message}`); process.exit(1); });
