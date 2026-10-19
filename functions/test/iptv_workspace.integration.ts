import {inviteAndAccept} from './support/membership';
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
  test(`${format} URL can be saved, edited and deleted without family or subscription`, async () => {
    const {actor,ref}=await account();
    const url='https://example.com/playlist.m3u8?username=fixture&password=private-token';
    const {id}=await execute('saveSource',{...source,format,url,isProtected:false},actor,key) as {id:string};
    const accountData=(await ref.get()).data()!;
    assert.equal(accountData.familyId,undefined);
    const metadata=getFirestore().doc(`families/${accountData.iptvWorkspaceId}/sources/${id}`);
    assert.equal((await metadata.get()).data()?.format,format);
    assert.equal(JSON.stringify((await metadata.get()).data()).includes('private-token'),false);
    const encrypted=(await getFirestore().doc(`source_secrets/${accountData.iptvWorkspaceId}_${id}`).get()).data()!.encrypted;
    assert.equal(unseal<{url:string}>(encrypted,key).url,url);
    await execute('saveSource',{...source,id,format,url,name:'Updated M3U8'},actor,key);
    assert.equal((await metadata.get()).data()?.name,'Updated M3U8');
    await execute('deleteSource',{id},actor,key);
    assert.equal((await metadata.get()).exists,false);
  });
}

test('first IPTV save provisions only a private workspace, without family, trial or profiles',async()=>{
  const {actor,ref}=await account();
  assert.equal((await ref.get()).data()?.iptvWorkspaceId,undefined);
  const result=await execute('saveSource',source,actor,key) as {id:string};
  const data=(await ref.get()).data()!;
  assert.equal(data.familyId,undefined);assert.ok(data.iptvWorkspaceId);
  const workspace=getFirestore().doc(`families/${data.iptvWorkspaceId}`);
  assert.equal((await workspace.get()).data()?.kind,'personalIptv');
  assert.equal((await workspace.get()).data()?.ownerId,actor.uid);
  assert.equal((await workspace.collection('sources').doc(result.id).get()).data()?.status,'queued');
  assert.equal((await workspace.collection('private').doc('subscription').get()).exists,false);
  assert.equal((await workspace.collection('profiles').get()).size,0);
  await execute('saveProfile',{name:'Personal profile'},actor);
});

test('protected URL sources persist failed PIN attempts and lock after five guesses',async()=>{
  const {actor,ref}=await account();
  const {id}=await execute('saveSource',{...source,format:'url',isProtected:true,pin:'1234',confirmPin:'1234'},actor,key) as {id:string};
  const scope=(await ref.get()).data()?.iptvWorkspaceId;
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

test('invalid form, encryption key or edit does not leave an empty workspace',async()=>{
  const {actor,ref}=await account();
  await assert.rejects(execute('saveSource',{...source,url:'ftp://example.com'},actor,key));
  await assert.rejects(execute('saveSource',source,actor,'invalid-key'));
  await assert.rejects(execute('saveSource',{...source,id:'nonexistent'},actor,key),/not-found/);
  assert.equal((await ref.get()).data()?.iptvWorkspaceId,undefined);
  assert.equal((await getFirestore().collection('families').where('ownerId','==',actor.uid).get()).size,0);
});

test('concurrent first saves converge on one private workspace',async()=>{
  const {actor,ref}=await account();
  await Promise.all([execute('saveSource',source,actor,key),execute('saveSource',{...source,name:'Second'},actor,key)]);
  const id=(await ref.get()).data()?.iptvWorkspaceId;
  assert.equal((await getFirestore().collection(`families/${id}/sources`).get()).size,2);
  assert.equal((await getFirestore().collection('families').where('ownerId','==',actor.uid).get()).size,1);
});

test('personal Xtream can edit, sync and delete without family while secrets remain encrypted',async()=>{
  const {actor,ref}=await account();
  const {id}=await execute('saveSource',{...source,format:'xtream',username:'private-user',password:'private-password'},actor,key) as {id:string};
  const scope=(await ref.get()).data()?.iptvWorkspaceId;
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

test('joining a family preserves personal IPTV and does not grant its member shared administrator rights',async()=>{
  const person=await account(),owner=await account();
  const {id}=await execute('saveSource',source,person.actor,key) as {id:string};
  const original=(await person.ref.get()).data()?.iptvWorkspaceId;
  const family=await execute('createFamily',{name:'Real family'},owner.actor) as {id:string};
  await inviteAndAccept(owner.actor,person.actor);
  await execute('syncSource',{id},person.actor);
  const updated=(await person.ref.get()).data()!;
  assert.equal(updated.familyId,family.id);assert.equal(updated.iptvWorkspaceId,original);
  assert.equal((await getFirestore().doc(`families/${original}/sources/${id}`).get()).data()?.status,'queued');
  await assert.rejects(execute('saveProfile',{name:'Not admin'},person.actor),/permission-denied/);
});

test('client-selected account/workspace fields cannot redirect writes to another account',async()=>{
  const first=await account(),second=await account();
  const {id}=await execute('saveSource',source,first.actor,key) as {id:string};
  const foreign=(await first.ref.get()).data()?.iptvWorkspaceId;
  await execute('saveSource',{...source,workspaceId:foreign,familyId:foreign,iptvWorkspaceId:foreign,uid:first.actor.uid},second.actor,key);
  assert.notEqual((await second.ref.get()).data()?.iptvWorkspaceId,foreign);
  await assert.rejects(execute('syncSource',{id},second.actor),/not-found/);
  assert.equal((await getFirestore().collection(`families/${foreign}/sources`).get()).size,1);
  await assert.rejects(execute('saveSource',source,{uid:'tv_fake',deviceId:'fake',familyId:foreign},key),/permission-denied/);
  await assert.rejects(execute('saveSource',source,undefined,key),/unauthenticated/);
});

test('account deletion immediately revokes the personal workspace and queues cleanup',async()=>{
  const {actor,ref}=await account();await execute('saveSource',source,actor,key);
  const scope=(await ref.get()).data()?.iptvWorkspaceId;
  await execute('prepareDeletion',{},actor);
  const workspace=(await getFirestore().doc(`families/${scope}`).get()).data()!;
  assert.equal(workspace.deleting,true);assert.deepEqual(workspace.members,{});
  const job=(await getFirestore().doc(`deletion_jobs/${actor.uid}`).get()).data()!;
  assert.equal(job.iptvWorkspaceId,scope);assert.equal(job.familyId,null);
  await assert.rejects(execute('prepareDeletion',{},actor),/not-found/);
  assert.equal((await getFirestore().doc(`deletion_jobs/${actor.uid}`).get()).data()?.iptvWorkspaceId,scope);
});
