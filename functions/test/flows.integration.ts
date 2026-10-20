import {inviteAndAccept} from './support/membership';
import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {execute,Identity} from '../src/service';
let app:ReturnType<typeof initializeApp>;
const admin:Identity={uid:'owner',authTime:Math.floor(Date.now()/1000)};
let fid:string;
const key=Buffer.alloc(32,3).toString('base64');
before(async()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST)throw new Error('Emulators required');
 app=initializeApp({projectId:'demo-iplex'});
 await getAuth().createUser({uid:'owner',displayName:'Owner'});await execute('bootstrap',{},admin);fid=(await execute('createFamily',{name:'Family'},admin) as any).id;
});
after(async()=>{await deleteApp(app);});
test('addressed invitation accepts once and retries idempotently',async()=>{
 await getAuth().createUser({uid:'member1'});await execute('bootstrap',{}, {uid:'member1'});
 const request=await inviteAndAccept(admin,{uid:'member1'});
 await execute('respondMembership',{id:request.id,accept:true},{uid:'member1'});
 assert.equal(Object.keys((await getFirestore().doc(`families/${fid}`).get()).data()!.members).length,2);
});
test('unauthorized member cannot administer profiles or subscriptions',async()=>{await assert.rejects(execute('saveProfile',{name:'P'},{uid:'member1'}),/permission-denied/);await assert.rejects(execute('saveSource',{name:'IPTV',format:'m3u',url:'https://example.com/list'},{uid:'member1'},key),/permission-denied/);});
test('first TV starts trial once; four concurrent session acquisitions allow only three',async()=>{
 const identities:Identity[]=[];
 // Four associate seats: clear profiles left by earlier tests in this shared family.
 for(const d of (await getFirestore().collection(`families/${fid}/profiles`).get()).docs)if(!['admin','guest'].includes(d.data().type))await d.ref.delete();
 for(let i=0;i<4;i++){
  const token=await execute('beginDevicePair',{name:`TV ${i}`},undefined) as any;const d=await execute('linkDevice',{token:token.token},admin) as any;
  identities.push({uid:`tv_${d.id}`,deviceId:d.id,familyId:fid,credentialVersion:(await getFirestore().doc(`families/${fid}/devices/${d.id}`).get()).data()?.credentialVersion});await execute('saveProfile',{id:`p${i}`,name:`Profile ${i}`},admin);
 }
 const before=(await getFirestore().doc(`families/${fid}/private/subscription`).get()).data()!;
 const result=await Promise.allSettled(identities.map((actor,i)=>execute('acquireSession',{profileId:`p${i}`},actor)));
 assert.equal(result.filter(x=>x.status==='fulfilled').length,3);
 const failed=result.find(x=>x.status==='rejected') as PromiseRejectedResult;assert.equal(failed.reason.details.devices.length,3);
 const linked=await execute('beginDevicePair',{name:'Extra TV'},undefined) as any;await execute('linkDevice',{token:linked.token},admin);
 assert.equal((await getFirestore().doc(`families/${fid}/private/subscription`).get()).data()?.trialStartedAt,before.trialStartedAt);
});
test('profile concurrency admits one owner and remote key commands do not exist',async()=>{
 await getFirestore().doc(`families/${fid}`).update({leases:[]});
 const ds=await getFirestore().collection(`families/${fid}/devices`).limit(2).get();const actors=ds.docs.map(d=>({uid:`tv_${d.id}`,deviceId:d.id,familyId:fid,credentialVersion:d.data().credentialVersion}));
 const result=await Promise.allSettled(actors.map(a=>execute('acquireSession',{profileId:'p0'},a)));assert.equal(result.filter(x=>x.status==='fulfilled').length,1);
 await assert.rejects(execute('sendCommand',{deviceId:actors[0]!.deviceId,sessionId:'stale',commandId:'cmd',commandType:'up'},admin),/invalid-action/);
});
test('preferences and favorites persist and source credentials stay encrypted',async()=>{
 await execute('savePreferences',{locale:'pt_BR'},admin);assert.equal((await getFirestore().doc('users/owner').get()).data()?.locale,'pt_BR');
 await execute('favorite',{profileId:'p0',contentId:'film',title:'Film',generation:0},admin);assert.equal((await getFirestore().doc(`families/${fid}/profiles/p0/favorites/film`).get()).data()?.title,'Film');
 const s=await execute('saveSource',{name:'Source',format:'xtream',url:'https://example.com',username:'fixture',password:'secret-fixture'},admin,key) as any;
 const metadata=(await getFirestore().doc(`families/${fid}/sources/${s.id}`).get()).data();assert.equal(JSON.stringify(metadata).includes('secret-fixture'),false);
 const secret=(await getFirestore().doc(`source_secrets/${fid}_${s.id}`).get()).data();assert.equal(JSON.stringify(secret).includes('secret-fixture'),false);
});
