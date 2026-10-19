import {test, before, after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp, deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getStorage} from 'firebase-admin/storage';
import {execute, Identity} from '../src/service';
import {syncIptvCatalog} from '../src/iptv_sync';
import {cleanupIptvResources} from '../src/iptv_cleanup';
import {unseal} from '../src/domain';

let app: ReturnType<typeof initializeApp>, seq = 0;
const key = Buffer.alloc(32, 7).toString('base64');
const playlist = '#EXTM3U\n#EXTINF:-1 tvg-id="one",Own synthetic channel\nhttps://example.invalid/own-synthetic-stream\n';
before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) throw new Error('Firestore and Storage emulators required');
  app = initializeApp({projectId:'demo-iplex', storageBucket:'demo-iplex.appspot.com'});
});
after(async () => deleteApp(app));
async function account() {
  const actor: Identity = {uid:`pipeline_${++seq}`};
  await getFirestore().doc(`users/${actor.uid}`).set({uid:actor.uid});
  return actor;
}
async function sourceRef(actor: Identity, id: string) {
  const account = (await getFirestore().doc(`users/${actor.uid}`).get()).data()!;
  return getFirestore().doc(`families/${account.iptvWorkspaceId}/sources/${id}`);
}

test('real Storage upload → worker → versioned catalog → restart/read → edit → cleanup', async () => {
  const actor = await account();
  const result = await execute('saveSource', {name:'Synthetic file',format:'file',fileName:'test.m3u',fileContent:playlist,requestId:'file-create'}, actor, key) as {id:string};
  const ref = await sourceRef(actor,result.id);
  assert.equal((await ref.get()).data()?.status,'queued');
  await syncIptvCatalog(ref,key);
  const ready = (await ref.get()).data()!;
  assert.equal(ready.status,'ready'); assert.equal(ready.count,1);
  const [json] = await getStorage().bucket().file(`catalogs/${ready.version}.json`).download();
  assert.equal(JSON.parse(json.toString()).items.length,1);
  assert.equal(json.toString().includes('synthetic-stream'),false);
  const oldFile = ready.filePath;
  await execute('saveSource',{id:ref.id,name:'Renamed',format:'file',expectedRevision:ready.revision},actor,key);
  assert.equal((await ref.get()).data()?.filePath,oldFile);
  await syncIptvCatalog(ref,key);
  assert.equal((await ref.get()).data()?.status,'ready');
  await execute('deleteSource',{id:ref.id},actor,key);
  assert.equal((await ref.get()).exists,false);
  assert.equal((await getFirestore().doc(`source_secrets/${ref.parent.parent!.id}_${ref.id}`).get()).exists,false);
  const cleanup = await getFirestore().collection('iptv_cleanup').where('sourcePath','==',ref.path).get();
  for(const row of cleanup.docs) await row.ref.update({notBefore:0});
  await cleanupIptvResources();
  assert.equal((await getStorage().bucket().file(oldFile).exists())[0],false);
  assert.equal((await ref.parent.parent!.collection('catalog').where('sourceId','==',ref.id).get()).size,0);
  assert.equal((await getStorage().bucket().file(`catalogs/${ready.version}.json`).exists())[0],true);
});

test('invalid update retains last usable catalog; duplicate worker delivery is harmless', async () => {
  const actor=await account();
  const {id}=await execute('saveSource',{name:'File',format:'file',fileContent:playlist},actor,key) as {id:string};
  const ref=await sourceRef(actor,id);
  await Promise.all([syncIptvCatalog(ref,key),syncIptvCatalog(ref,key)]);
  const ready=(await ref.get()).data()!;
  assert.equal(ready.status,'ready');
  await execute('saveSource',{id,name:'Empty update',format:'file',fileContent:'#EXTM3U\n'},actor,key);
  await syncIptvCatalog(ref,key);
  const failed=(await ref.get()).data()!;
  assert.equal(failed.status,'error');assert.equal(failed.errorCode,'suspicious-catalog');assert.equal(failed.version,ready.version);
  await execute('saveSource',{id,name:'Recovered',format:'file',fileContent:playlist},actor,key);
  await syncIptvCatalog(ref,key);
  assert.equal((await ref.get()).data()?.status,'ready');
});

test('retry receipt prevents duplicate creation and credentials/EPG remain private on rename', async () => {
  const actor=await account();
  const payload={name:'URL',format:'url',url:'https://example.com/list?secret=private',epgUrl:'https://example.com/epg?token=private',requestId:'retry'};
  const [a,b]=await Promise.all([execute('saveSource',payload,actor,key),execute('saveSource',payload,actor,key)]) as {id:string}[];
  assert.equal(a!.id,b!.id);
  const ref=await sourceRef(actor,a!.id);
  assert.equal((await ref.parent.get()).size,1);
  assert.equal(JSON.stringify((await ref.get()).data()).includes('private'),false);
  await execute('saveSource',{id:ref.id,name:'Renamed',format:'url'},actor,key);
  const secret=(await getFirestore().doc(`source_secrets/${ref.parent.parent!.id}_${ref.id}`).get()).data()!;
  const saved=unseal<{url:string;epgUrl:string}>(secret.encrypted,key);
  assert.equal(saved.url,payload.url);assert.equal(saved.epgUrl,payload.epgUrl);
  await assert.rejects(execute('saveSource',{id:ref.id,name:'Stale',format:'url',expectedRevision:1},actor,key),/source-conflict/);
  await assert.rejects(execute('saveSource',{id:'missing',name:'No resurrection',format:'url',url:payload.url},actor,key),/not-found/);
});

test('PIN gates edit/delete/sync at server and grant expires or is invalidated by revision', async () => {
  const actor=await account();
  const {id}=await execute('saveSource',{name:'PIN',format:'url',url:'https://example.com',isProtected:true,pin:'1234',confirmPin:'1234'},actor,key) as {id:string};
  const ref=await sourceRef(actor,id),grant=ref.parent.parent!.collection('source_access').doc(`${id}_${actor.uid}`);
  await grant.update({expiresAt:0});
  for(const action of ['deleteSource','syncSource'])await assert.rejects(execute(action,{id},actor,key),/pin-required/);
  await assert.rejects(execute('saveSource',{id,name:'Bypass',format:'url',isProtected:false},actor,key),/pin-required/);
  await execute('verifySourcePin',{id,pin:'1234'},actor,key);
  await execute('saveSource',{id,name:'Authorized',format:'url'},actor,key);
  await grant.update({revision:1});
  await assert.rejects(execute('deleteSource',{id},actor,key),/pin-required/);
});

test('expired lease recovers and disabled/deleted sources are never resurrected', async () => {
  const actor=await account();
  const {id}=await execute('saveSource',{name:'File',format:'file',fileContent:playlist},actor,key) as {id:string};
  const ref=await sourceRef(actor,id);
  await ref.update({status:'syncing',lockedUntil:1});
  await syncIptvCatalog(ref,key);assert.equal((await ref.get()).data()?.status,'ready');
  await execute('deleteSource',{id},actor,key);
  await syncIptvCatalog(ref,key);assert.equal((await ref.get()).exists,false);
});
