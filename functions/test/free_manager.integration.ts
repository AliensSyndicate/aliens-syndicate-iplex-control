import {inviteAndAccept,createFamily} from './support/membership';
import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {execute,Identity} from '../src/service';
import {Subscription,TRIAL_MS} from '../src/domain';

let app:ReturnType<typeof initializeApp>;
let sequence=0;
const key=Buffer.alloc(32,7).toString('base64');
before(()=>{
  if(!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST)throw new Error('Emulators required');
  app=initializeApp({projectId:'demo-iplex'});
});
after(async()=>{await deleteApp(app);});

async function fixture(){
  const actor:Identity={uid:`free_owner_${++sequence}`,authTime:Math.floor(Date.now()/1000)};
  await getAuth().createUser({uid:actor.uid});
  await execute('bootstrap',{},actor);
  const {id:fid}=await createFamily(actor,'Free family') as {id:string};
  const family=getFirestore().doc(`families/${fid}`);
  return {actor,fid,family,subscription:family.collection('private').doc('subscription')};
}
async function link(actor:Identity,fid:string){
  const {token}=await execute('beginDevicePair',{name:'Free TV'},undefined) as {token:string};
  const {id}=await execute('linkDevice',{token},actor) as {id:string};
  return {uid:`tv_${id}`,familyId:fid,deviceId:id,credentialVersion:(await getFirestore().doc(`families/${fid}/devices/${id}`).get()).data()?.credentialVersion} satisfies Identity;
}
const expired:Subscription={status:'expired',trialStartedAt:1,trialEndsAt:2,paidUntil:2};

test('creating a free family does not start a trial or require a subscription',async()=>{
  const f=await fixture();
  assert.deepEqual((await f.subscription.get()).data(),{status:'notStarted'});
  await execute('saveProfile',{id:'profile',name:'Free profile'},f.actor);
  await assert.rejects(execute('createMemberLink',{},f.actor),/invalid-action/);
  await execute('savePreferences',{locale:'pt_BR'},f.actor);
  await execute('favorite',{profileId:'profile',contentId:'film',title:'Film',generation:0},f.actor);
  assert.deepEqual((await f.subscription.get()).data(),{status:'notStarted'});
});

for(const state of ['notStarted','expired','pending'] as const){
  test(`Manager IPTV CRUD and sync remain free with ${state} subscription`,async()=>{
    const f=await fixture();
    await f.subscription.set({status:state,trialStartedAt:1,trialEndsAt:2});
    for(const format of ['m3u','xtream'] as const){
      const input={name:'Free source',format,url:'https://example.com/list',...(format==='xtream'?{username:'user',password:'protected-secret'}:{})};
      const {id}=await execute('saveSource',input,f.actor,key) as {id:string};
      await execute('saveSource',{...input,id,name:'Updated',...(format==='xtream'?{password:''}:{})},f.actor,key);
      await execute('syncSource',{id},f.actor);
      const metadata=(await f.family.collection('sources').doc(id).get()).data()!;
      assert.equal(metadata.name,'Updated');assert.equal(metadata.status,'queued');
      assert.equal(JSON.stringify(metadata).includes('protected-secret'),false);
      const secret=getFirestore().doc(`source_secrets/${f.fid}_${id}`);
      assert.equal(JSON.stringify((await secret.get()).data()).includes('protected-secret'),false);
      await execute('deleteSource',{id},f.actor);
      assert.equal((await secret.get()).exists,false);
      assert.equal((await f.family.collection('sources').doc(id).get()).exists,false);
    }
    assert.equal((await f.subscription.get()).data()?.status,state);
  });
}

test('expired playback rights do not limit device registration or restart the trial',async()=>{
  const f=await fixture();await f.subscription.set(expired);
  await execute('saveProfile',{id:'p',name:'Profile'},f.actor);
  for(let i=0;i<5;i++){
    const device=await link(f.actor,f.fid);
    await execute('renameDevice',{id:device.deviceId,name:`TV ${i}`},f.actor);
    await assert.rejects(execute('acquireSession',{profileId:'p',isActive:true,subscription:{status:'active',paidUntil:Date.now()+TRIAL_MS}},device),/subscription-required/);
  }
  assert.equal((await f.family.collection('devices').get()).size,5);
  assert.deepEqual((await f.subscription.get()).data(),expired);
  await execute('bootstrap',{},f.actor);
  await execute('deleteProfile',{id:'p'},f.actor);
  await execute('saveProfile',{id:'new',name:'New profile'},f.actor);
  assert.deepEqual((await f.subscription.get()).data(),expired);
  const first=(await f.family.collection('devices').limit(1).get()).docs[0]!;
  await execute('deleteDevice',{id:first.id},f.actor);
  assert.equal((await f.family.collection('devices').get()).size,4);
});

test('first TV starts exactly seven days once; linking another TV preserves paid access',async()=>{
  const f=await fixture();const paidUntil=Date.now()+30*86400000;
  await f.subscription.set({status:'active',paidUntil});
  await link(f.actor,f.fid);
  const first=(await f.subscription.get()).data()!;
  assert.equal(first.status,'active');assert.equal(first.paidUntil,paidUntil);
  assert.equal(first.trialEndsAt-first.trialStartedAt,TRIAL_MS);
  await link(f.actor,f.fid);
  assert.deepEqual((await f.subscription.get()).data(),first);
});

test('server denies missing or invalid playback rights and ignores client entitlement flags',async()=>{
  const f=await fixture();const device=await link(f.actor,f.fid);
  await execute('saveProfile',{id:'p',name:'Profile'},f.actor);
  for(const subscription of [undefined,{status:'notStarted'},expired,{status:'pending',paidUntil:Date.now()+TRIAL_MS},{status:'active',paidUntil:1}]){
    if(subscription)await f.subscription.set(subscription);else await f.subscription.delete();
    await assert.rejects(execute('acquireSession',{profileId:'p',canStartPlayback:true},device),(error:any)=>{
      assert.equal(error.code,'subscription-required');assert.equal(error.details.plansRoute,'/account/subscription');return true;
    });
    assert.deepEqual((await f.family.get()).data()?.leases,[]);
  }
});

for(const status of ['trial','active','cancelled'] as const){
  test(`server grants playback for valid ${status} rights only to an authorized device and profile`,async()=>{
    const f=await fixture();const device=await link(f.actor,f.fid);
    await f.subscription.set({status,trialEndsAt:Date.now()+TRIAL_MS,paidUntil:Date.now()+TRIAL_MS});
    await execute('saveProfile',{id:'p',name:'Profile'},f.actor);
    await assert.rejects(execute('acquireSession',{profileId:'foreign-profile'},device),/not-found/);
    await assert.rejects(execute('acquireSession',{profileId:'p'},{...device,uid:'wrong-identity'}),/permission-denied/);
    const lease=await execute('acquireSession',{profileId:'p'},device) as {id:string};
    assert.ok(lease.id);
    await f.subscription.set(expired);
    // The Control is not a remote control: key/transport commands do not exist.
    await assert.rejects(execute('sendCommand',{deviceId:device.deviceId,sessionId:lease.id,commandId:'free-control',commandType:'up'},f.actor),/invalid-action/);
    await assert.rejects(execute('heartbeat',{sessionId:lease.id},device),/subscription-required/);
    await execute('releaseSession',{sessionId:lease.id},device);
    await execute('saveProfile',{id:'another',name:'Still free'},f.actor);
    await execute('deleteDevice',{id:device.deviceId},f.actor);
    await assert.rejects(execute('acquireSession',{profileId:'p'},device),/device-revoked/);
  });
}

test('authentication, administrator role and device role remain enforced without subscriptions',async()=>{
  const f=await fixture();await f.subscription.set(expired);
  await assert.rejects(execute('createFamily',{name:'No auth'},undefined),/unauthenticated/);
  const uid='free_member';await getAuth().createUser({uid});await execute('bootstrap',{}, {uid});
  await inviteAndAccept(f.actor,{uid});
  await assert.rejects(execute('saveProfile',{name:'Denied'},{uid}),/permission-denied/);
  await assert.rejects(execute('saveSource',{name:'Denied',format:'m3u',url:'https://example.com'},{uid},key),/permission-denied/);
  const device=await link(f.actor,f.fid);
  await assert.rejects(execute('saveProfile',{name:'Denied'},device),/permission-denied/);
});
