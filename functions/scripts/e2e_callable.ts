/**
 * End-to-end scenarios over the deployed callable contract, against the full
 * emulator suite (`firebase emulators:start --only auth,firestore,functions,storage
 * --project demo-iplex`). Uses the Firebase client SDK exactly like the Gestor:
 * HTTPS callable `manager`, Auth ID tokens, Firestore reads under Security Rules.
 */
import assert from 'node:assert/strict';
import {initializeApp} from 'firebase/app';
import {connectAuthEmulator, createUserWithEmailAndPassword, getAuth, signInWithCustomToken, updateProfile} from 'firebase/auth';
import {connectFunctionsEmulator, getFunctions, httpsCallable} from 'firebase/functions';
import {collection, connectFirestoreEmulator, doc, getDoc, getDocs, getFirestore, query, where} from 'firebase/firestore';
import {randomUUID} from 'node:crypto';

const host = process.env.EMULATOR_HOST ?? '127.0.0.1';
type Client = {call: (action: string, payload?: Record<string, unknown>) => Promise<any>; uid: string; db: ReturnType<typeof getFirestore>};
async function client(label: string, customToken?: string): Promise<Client> {
  const app = initializeApp({projectId: 'demo-iplex', apiKey: 'demo-key', appId: 'demo'}, `${label}-${randomUUID()}`);
  const auth = getAuth(app); connectAuthEmulator(auth, `http://${host}:9099`, {disableWarnings: true});
  const functions = getFunctions(app, 'us-central1'); connectFunctionsEmulator(functions, host, 5001);
  const db = getFirestore(app); connectFirestoreEmulator(db, host, 8080);
  if (customToken) await signInWithCustomToken(auth, customToken);
  else {
    const cred = await createUserWithEmailAndPassword(auth, `${label}-${randomUUID()}@example.test`, randomUUID());
    await updateProfile(cred.user, {displayName: label});
  }
  const manager = httpsCallable(functions, 'manager', {timeout: 60000});
  return {uid: auth.currentUser!.uid, db, call: async (action, payload = {}) => (await manager({action, payload})).data};
}
const code = async (c: Client) => (await getDoc(doc(c.db, `users/${c.uid}`))).data()!.publicCode as string;
const rejects = async (p: Promise<unknown>, pattern: RegExp) => assert.rejects(p, (e: any) => pattern.test(`${e.code} ${e.message}`));
const step = (s: string) => console.log(`  ✔ ${s}`);
const tv = (c: Client, label: string) => c.call('beginDevicePair', {name: label, platform: 'android_tv', model: 'Simulated TV', nativeDeviceId: `e2e-${randomUUID()}`, identitySource: 'simulated'});

async function scenarioA() {
  console.log('A — individual account (its own individual family)');
  const a = await client('Alice'); await a.call('bootstrap');
  const user = (await getDoc(doc(a.db, `users/${a.uid}`))).data()!;
  assert.match(user.publicCode, /^[A-Z0-9]{12}$/); assert.ok(user.familyId); assert.equal(user.homeFamilyId, user.familyId);
  assert.equal((await getDoc(doc(a.db, `families/${user.familyId}`))).data()!.individual, true);
  await rejects(a.call('createFamily', {name: 'Second'}), /already-in-family/);
  step(`signup → bootstrap: public code ${user.publicCode}, one individual family, no second family`);
  const session = await tv(a, 'Sala');
  await a.call('inspectPairingSession', {code: session.code, contextFamilyId: null});
  const device = await a.call('linkDevice', {code: session.code, contextFamilyId: null});
  await a.call('renameDevice', {id: device.id, name: 'Sala renomeada', contextFamilyId: null});
  step('TV linked by manual code and renamed without family or subscription');
  const source = await a.call('saveSource', {name: 'Lista pessoal', format: 'm3u', url: 'https://iptv-org.github.io/iptv/languages/por.m3u', contextFamilyId: null});
  const ws = (await getDoc(doc(a.db, `users/${a.uid}`))).data()!.familyId;
  let status = 'queued', errorCode = null, started = Date.now();
  while (Date.now() - started < 120000) {
    const s = (await getDoc(doc(a.db, `families/${ws}/sources/${source.id}`))).data()!;
    status = s.status; errorCode = s.errorCode;
    if (['ready', 'error'].includes(status)) break;
    await new Promise(r => setTimeout(r, 2000));
  }
  const synced = (await getDoc(doc(a.db, `families/${ws}/sources/${source.id}`))).data()!;
  assert.equal(status, 'ready', `sync ended as ${status} (${errorCode})`);
  assert.ok(synced.lastSuccessfulSyncAt > 0 && synced.count > 0);
  step(`IPTV source saved and synced by the job trigger: ${synced.count} items, catalog ${String(synced.catalogId).slice(0, 12)}…`);
  const catalog = await a.call('readSourceCatalog', {id: source.id, contextFamilyId: null});
  const selectedItem = catalog.items[0];
  const recent = await a.call('readHome', {sourceId: source.id, recentSearchIds: [selectedItem.id, selectedItem.id], contextFamilyId: null});
  assert.deepEqual(recent.recentSearches.map((item: any) => item.id), [selectedItem.id]);
  step('search recent items resolve through the real callable without duplicates');
  await a.call('deleteDevice', {id: device.id, contextFamilyId: null});
  await a.call('deleteSource', {id: source.id, contextFamilyId: null});
  step('TV unlinked and source deleted by the owner');
  return a;
}

async function scenarioBC(a: Client) {
  console.log('B/C — one family per account: membership, limit, exclusivity');
  const f1 = (await getDoc(doc(a.db, `users/${a.uid}`))).data()!.familyId as string;
  const members: Client[] = [];
  for (let i = 0; i < 5; i++) { const m = await client(`Membro${i}`); await m.call('bootstrap'); members.push(m); }
  const found = await a.call('lookupPublicUser', {code: (await code(members[0]!)).toLowerCase(), familyId: f1});
  assert.deepEqual(Object.keys(found).sort(), ['code', 'name']);
  step('lookup by code returns only public name + code');
  for (const m of members.slice(0, 4)) {
    const r = await a.call('requestMembership', {code: await code(m), familyId: f1});
    const mine = (await getDoc(doc(m.db, `family_requests/${r.id}`))).data()!;
    assert.equal(mine.status, 'pending');
    assert.equal((await getDoc(doc(a.db, `family_requests/${r.id}`))).data()!.status, 'pending'); // the administrator follows it
    await m.call('respondMembership', {id: r.id, accept: true});
    assert.equal((await getDoc(doc(m.db, `users/${m.uid}`))).data()!.familyId, f1);
  }
  step('4 members accepted addressed requests (5/5 seats with the administrator); each moved out of its individual family');
  await rejects(a.call('requestMembership', {code: await code(members[4]!), familyId: f1}), /family-limit/);
  step('6th member rejected with family-limit');
  await a.call('removeMember', {id: members[3]!.uid, familyId: f1});
  const back = (await getDoc(doc(members[3]!.db, `users/${members[3]!.uid}`))).data()!;
  assert.notEqual(back.familyId, f1); assert.equal(back.familyId, back.homeFamilyId);
  // The removed account's profile and data stay; deleting the profile frees the seat.
  await rejects(a.call('requestMembership', {code: await code(members[4]!), familyId: f1}), /family-limit/);
  const kept = (await getDocs(query(collection(a.db, `families/${f1}/profiles`), where('linkedUid', '==', null)))).docs.find(d => d.data().type === 'regular')!;
  await a.call('deleteProfile', {id: kept.id, contextFamilyId: f1});
  const r = await a.call('requestMembership', {code: await code(members[4]!), familyId: f1});
  await members[4]!.call('respondMembership', {id: r.id, accept: true});
  step('removing a member returns it to its individual family; deleting its kept profile frees the seat');
  const b = members[0]!;
  await rejects(b.call('requestMembership', {code: await code(a)}), /permission-denied/);
  await rejects(members[1]!.call('createFamily', {name: 'Outra'}), /already-in-family/);
  await rejects(a.call('createFamily', {name: 'Outra'}), /already-in-family/);
  await rejects(a.call('saveProfile', {name: 'Denied', contextFamilyId: back.familyId}), /permission-denied/);
  await rejects(b.call('saveProfile', {name: 'Denied', contextFamilyId: back.familyId}), /permission-denied/);
  await rejects(getDoc(doc(members[3]!.db, `families/${f1}`)), /permission/i);
  step('no second family, no foreign context, no cross-family reads; members hold no administrator rights');
}

async function scenarioD(a: Client) {
  console.log('D — TV pairing via QR token and revocation');
  const session = await tv(a, 'Quarto'), token = new URL(`iplex://pair?token=${session.token}`).searchParams.get('token')!;
  const info = await a.call('inspectPairingSession', {token, contextFamilyId: null});
  assert.equal(info.model, 'Simulated TV');
  const linked = await a.call('linkDevice', {token, contextFamilyId: null});
  const player = await client('Player', (await a.call('finishDevicePair', {token})).customToken);
  await rejects(player.call('finishDevicePair', {token}), /invalid-token/);
  await rejects(a.call('linkDevice', {token, contextFamilyId: null}), /pairing-expired/);
  step('QR token linked once; replay and second credential exchange denied');
  const ws = (await getDoc(doc(a.db, `users/${a.uid}`))).data()!.familyId;
  assert.equal((await getDoc(doc(player.db, `devices/${linked.id}`))).exists(), true);
  await a.call('deleteDevice', {id: linked.id, contextFamilyId: null});
  await rejects(player.call('heartbeat', {sessionId: 'x', profileId: 'p'}), /device-revoked/);
  await rejects(getDoc(doc(player.db, `families/${ws}/devices/${linked.id}`)), /permission/i);
  step('after unlink the Player credential is rejected by Functions and Rules');
}

async function scenarioF() {
  console.log('F — family profiles, guest, linking and clears');
  const admin = await client('Admin'); await admin.call('bootstrap');
  const fid = (await getDoc(doc(admin.db, `users/${admin.uid}`))).data()!.familyId as string;
  const kid = (await admin.call('saveProfile', {name: 'Lia', type: 'kids', requestId: 'e2e-kid', contextFamilyId: fid})).id;
  assert.equal((await admin.call('saveProfile', {name: 'Lia', type: 'kids', requestId: 'e2e-kid', contextFamilyId: fid})).id, kid);
  await admin.call('setGuestEnabled', {enabled: true, name: 'Visitante', contextFamilyId: fid});
  step('kids profile without account (idempotent) and guest enabled');
  const {code} = await admin.call('createProfileLinkCode', {profileId: kid, contextFamilyId: fid});
  const lia = await client('Lia'); await lia.call('bootstrap');
  assert.deepEqual(await lia.call('redeemProfileLink', {code}), {familyId: fid, profileId: kid});
  assert.deepEqual(await lia.call('redeemProfileLink', {code}), {familyId: fid, profileId: kid}); // retry is idempotent
  const other = await client('Outro'); await other.call('bootstrap');
  await rejects(other.call('redeemProfileLink', {code}), /link-code-expired/);
  step('account linked to the existing profile by single-use code');
  const result = await admin.call('clearProfileData', {profileId: kid, category: 'favorites', requestId: 'e2e-clear', contextFamilyId: fid});
  assert.equal(result.generation, 1);
  await rejects(lia.call('clearProfileData', {profileId: kid, category: 'favorites', requestId: 'x', contextFamilyId: fid}), /permission-denied/);
  step('admin clear bumps the generation; associates cannot clear');
}

(async () => {
  const a = await scenarioA();
  await scenarioBC(a);
  await scenarioD(a);
  await scenarioF();
  console.log('All callable E2E scenarios passed.');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
