import {inviteAndAccept,createFamily} from './support/membership';
import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore} from 'firebase-admin/firestore';
import {execute,Identity} from '../src/service';
import {unseal} from '../src/domain';

let app:ReturnType<typeof initializeApp>,sequence=0;
const key=Buffer.alloc(32,9).toString('base64');
before(()=>{
  if(!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST)throw new Error('Emulators required');
  app=initializeApp({projectId:'demo-iplex'});
});
after(async()=>{await deleteApp(app);});
async function account(){
  const actor:Identity={uid:`iptv_person_${++sequence}`,authTime:Math.floor(Date.now()/1000)};
  await getAuth().createUser({uid:actor.uid});await execute('bootstrap',{},actor);
  return {actor,ref:getFirestore().doc(`users/${actor.uid}`)};
}
const source={name:'Personal M3U',format:'m3u',url:'https://example.com/playlist'};

for (const format of ['m3u', 'url', 'other_m3u8']) {
  test(`${format} URL can be saved, edited and deleted in the individual family without subscription`, async () => {
    const {actor,ref}=await account();
    const url='https://example.com/playlist.m3u8?username=fixture&password=private-token';
    const {id}=await execute('saveSource',{...source,format,url,isProtected:false},actor,key) as {id:string};
    const accountData=(await ref.get()).data()!;
    assert.ok(accountData.familyId);assert.equal(accountData.iptvWorkspaceId,undefined);
    const metadata=getFirestore().doc(`families/${accountData.familyId}/sources/${id}`);
    assert.equal((await metadata.get()).data()?.format,format);
    assert.equal(JSON.stringify((await metadata.get()).data()).includes('private-token'),false);
    const encrypted=(await getFirestore().doc(`source_secrets/${accountData.familyId}_${id}`).get()).data()!.encrypted;
    assert.equal(unseal<{url:string}>(encrypted,key).url,url);
    await execute('saveSource',{...source,id,format,url,name:'Updated M3U8'},actor,key);
    assert.equal((await metadata.get()).data()?.name,'Updated M3U8');
    await execute('deleteSource',{id},actor,key);
    assert.equal((await metadata.get()).exists,false);
  });
}

test('first IPTV save uses the individual family created at bootstrap: no trial, only the administrator profile',async()=>{
  const {actor,ref}=await account();
  const data=(await ref.get()).data()!;
  assert.ok(data.familyId);assert.equal(data.iptvWorkspaceId,undefined);
  const result=await execute('saveSource',source,actor,key) as {id:string};
  assert.equal((await ref.get()).data()?.familyId,data.familyId);
  const family=getFirestore().doc(`families/${data.familyId}`);
  assert.equal((await family.get()).data()?.kind,undefined);assert.equal((await family.get()).data()?.individual,true);
  assert.equal((await family.get()).data()?.ownerId,actor.uid);
  assert.equal((await family.collection('sources').doc(result.id).get()).data()?.status,'queued');
  assert.deepEqual((await family.collection('private').doc('subscription').get()).data(),{status:'notStarted'});
  assert.deepEqual((await family.collection('profiles').get()).docs.map(d=>d.id),['admin']);
  await execute('saveProfile',{name:'Personal profile'},actor);
});

test('protected URL sources persist failed PIN attempts and lock after five guesses',async()=>{
  const {actor,ref}=await account();
  const {id}=await execute('saveSource',{...source,format:'url',isProtected:true,pin:'1234',confirmPin:'1234'},actor,key) as {id:string};
  const scope=(await ref.get()).data()?.familyId;
  const secret=getFirestore().doc(`source_secrets/${scope}_${id}`);
  for(let attempt=1;attempt<=5;attempt++){
    await assert.rejects(execute('verifySourcePin',{id,pin:'9999'},actor,key),/invalid-pin/);
    assert.equal((await secret.get()).data()?.failedAttempts,attempt);
  }
  await assert.rejects(execute('verifySourcePin',{id,pin:'1234'},actor,key),/pin-locked/);
  await secret.update({lockedUntil:0});
  assert.deepEqual(await execute('verifySourcePin',{id,pin:'1234'},actor,key),{ok:true,verified:true});
  assert.equal((await secret.get()).data()?.failedAttempts,0);
});

test('invalid form, encryption key or edit leaves no source and no extra family',async()=>{
  const {actor,ref}=await account();
  await assert.rejects(execute('saveSource',{...source,url:'ftp://example.com'},actor,key));
  await assert.rejects(execute('saveSource',source,actor,'invalid-key'));
  await assert.rejects(execute('saveSource',{...source,id:'nonexistent'},actor,key),/not-found/);
  const familyId=(await ref.get()).data()?.familyId;
  assert.equal((await getFirestore().collection(`families/${familyId}/sources`).get()).size,0);
  assert.equal((await getFirestore().collection('families').where('ownerId','==',actor.uid).get()).size,1);
});

test('concurrent saves converge on the one individual family',async()=>{
  const {actor,ref}=await account();
  await Promise.all([execute('saveSource',source,actor,key),execute('saveSource',{...source,name:'Second'},actor,key)]);
  const id=(await ref.get()).data()?.familyId;
  assert.equal((await getFirestore().collection(`families/${id}/sources`).get()).size,2);
  assert.equal((await getFirestore().collection('families').where('ownerId','==',actor.uid).get()).size,1);
});

test('Xtream can edit, sync and delete in the individual family while secrets remain encrypted',async()=>{
  const {actor,ref}=await account();
  const {id}=await execute('saveSource',{...source,format:'xtream',username:'private-user',password:'private-password'},actor,key) as {id:string};
  const scope=(await ref.get()).data()?.familyId;
  await execute('saveSource',{...source,id,name:'Updated',format:'xtream',username:'private-user'},actor,key);
  await execute('syncSource',{id},actor);
  const metadata=(await getFirestore().doc(`families/${scope}/sources/${id}`).get()).data()!;
  assert.equal(metadata.name,'Updated');assert.equal(metadata.status,'queued');
  assert.equal(JSON.stringify(metadata).includes('private-password'),false);
  const secret=getFirestore().doc(`source_secrets/${scope}_${id}`);
  assert.equal(unseal<{password:string}>((await secret.get()).data()!.encrypted,key).password,'private-password');
  await execute('deleteSource',{id},actor);
  assert.equal((await secret.get()).exists,false);
  assert.equal((await getFirestore().doc(`families/${scope}/sources/${id}`).get()).exists,false);
});

test('joining a family never strands IPTV: blocked while the individual family has sources, parked and restored otherwise',async()=>{
  const person=await account(),owner=await account();
  const {id}=await execute('saveSource',source,person.actor,key) as {id:string};
  const original=(await person.ref.get()).data()?.familyId as string;
  const family=await createFamily(owner.actor,'Real family') as {id:string};
  await assert.rejects(inviteAndAccept(owner.actor,person.actor),/individual-family-has-resources/);
  // Nothing was moved or removed.
  assert.equal((await person.ref.get()).data()?.familyId,original);
  assert.equal((await getFirestore().doc(`families/${original}/sources/${id}`).get()).exists,true);
  await execute('deleteSource',{id},person.actor,key);
  await inviteAndAccept(owner.actor,person.actor);
  const joined=(await person.ref.get()).data()!;
  assert.equal(joined.familyId,family.id);assert.equal(joined.homeFamilyId,original);
  const parked=(await getFirestore().doc(`families/${original}`).get()).data()!;
  assert.equal(parked.parked,true);assert.deepEqual(parked.members,{});
  await assert.rejects(execute('saveProfile',{name:'Not admin'},person.actor),/permission-denied/);
  await execute('leaveFamily',{},person.actor);
  const back=(await person.ref.get()).data()!;
  assert.equal(back.familyId,original);
  assert.deepEqual((await getFirestore().doc(`families/${original}`).get()).data()!.members,{[person.actor.uid]:'admin'});
  assert.equal((await getFirestore().doc(`families/${original}`).get()).data()!.parked,undefined);
});

test('client-selected account/workspace fields cannot redirect writes to another account',async()=>{
  const first=await account(),second=await account();
  const {id}=await execute('saveSource',source,first.actor,key) as {id:string};
  const foreign=(await first.ref.get()).data()?.familyId;
  await execute('saveSource',{...source,workspaceId:foreign,familyId:foreign,iptvWorkspaceId:foreign,uid:first.actor.uid},second.actor,key);
  assert.notEqual((await second.ref.get()).data()?.familyId,foreign);
  await assert.rejects(execute('syncSource',{id},second.actor),/not-found/);
  assert.equal((await getFirestore().collection(`families/${foreign}/sources`).get()).size,1);
  await assert.rejects(execute('saveSource',source,{uid:'tv_fake',deviceId:'fake',familyId:foreign},key),/permission-denied/);
  await assert.rejects(execute('saveSource',source,undefined,key),/unauthenticated/);
});

test('account deletion immediately revokes the individual family and queues cleanup',async()=>{
  const {actor,ref}=await account();await execute('saveSource',source,actor,key);
  const scope=(await ref.get()).data()?.familyId;
  await execute('prepareDeletion',{},actor);
  const workspace=(await getFirestore().doc(`families/${scope}`).get()).data()!;
  assert.equal(workspace.deleting,true);assert.deepEqual(workspace.members,{});
  const job=(await getFirestore().doc(`deletion_jobs/${actor.uid}`).get()).data()!;
  assert.deepEqual(job.familyIds,[scope]);assert.equal(job.iptvWorkspaceId,null);
  await assert.rejects(execute('prepareDeletion',{},actor),/not-found/);
});
