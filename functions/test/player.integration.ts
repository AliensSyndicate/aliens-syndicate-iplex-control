import {createFamily} from './support/membership';
import {randomBytes} from 'node:crypto';
import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {execute,Identity} from '../src/service';
import {firestoreQuota,runPlayer,consumePlayerRequest,type PlayerAuth} from '../src/player';
let app:ReturnType<typeof initializeApp>,seq=0;
before(()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST)throw new Error('Emulators required');
 app=initializeApp({projectId:'demo-iplex'});
});
after(()=>deleteApp(app));
const deps={execute,quota:firestoreQuota,consume:consumePlayerRequest,now:Date.now};
const call=(action:string,payload:Record<string,unknown>,auth?:PlayerAuth,ip='203.0.113.7')=>runPlayer({action,payload:{...payload,requestId:randomBytes(16).toString('hex'),issuedAt:Date.now()},auth,ip},'',deps);
async function admin(){const a:Identity={uid:`player_admin_${Date.now()}_${++seq}`,authTime:Math.floor(Date.now()/1000)};await getAuth().createUser({uid:a.uid,displayName:'Admin'});await execute('bootstrap',{},a);await createFamily(a,'Família');return a;}
/** Token verificado que o Firebase entregaria à callable depois do signInWithCustomToken. */
async function deviceAuth(deviceId:string,familyId:string):Promise<PlayerAuth>{const credentialVersion=(await getFirestore().doc(`families/${familyId}/devices/${deviceId}`).get()).data()?.credentialVersion;return {uid:`tv_${deviceId}`,token:{deviceId,familyId,credentialVersion,firebase:{sign_in_provider:'custom'},auth_time:Math.floor(Date.now()/1000)}};}

test('player: pairing confirmed in the Gestor, then only the paired TV reaches its family; unlink revokes',async()=>{
 const a=await admin();
 const session=await call('beginDevicePair',{name:'Sala',platform:'tizen',model:'UN65TU7020',nativeDeviceId:`tizen-${Date.now()}-${seq}`}) as {token:string;code:string;deviceId:string};
 assert.match(session.code,/^\d{6}$/);
 // Antes da confirmação: pendente, sem acesso a nada.
 await assert.rejects(call('finishDevicePair',{token:session.token}),/invalid-token/);
 // Administrador autenticado no Gestor (callable manager, com App Check) confirma.
 await execute('linkDevice',{token:session.token},a);
 const minted=await call('finishDevicePair',{token:session.token}) as {customToken:string};
 assert.ok(minted.customToken.length>20);
 await assert.rejects(call('finishDevicePair',{token:session.token}),/invalid-token/,'token de uso único');
 const familyId=(await getFirestore().doc(`users/${a.uid}`).get()).data()!.familyId as string;
 const tv=await deviceAuth(session.deviceId,familyId);
 const {profiles}=await call('listPlayerProfiles',{},tv) as {profiles:{id:string;type:string}[]};
 assert.ok(profiles.some(p=>p.type==='admin'));
 // Assinatura: o trial é aberto no primeiro vínculo; o lease é aplicado pelo backend.
 const lease=await call('acquireSession',{profileId:profiles[0]!.id},tv) as {id:string};
 await call('heartbeat',{sessionId:lease.id},tv);
 // Outra família não é alcançável trocando claims no corpo da requisição.
 await assert.rejects(call('listPlayerProfiles',{familyId:'outra'},await deviceAuth(session.deviceId,'outra-familia')),/device-revoked|permission-denied/);
 // Ações administrativas não existem na player.
 await assert.rejects(call('deleteDevice',{id:session.deviceId},tv),/invalid-action/);
 // Desvincular no Gestor revoga na hora.
 await execute('deleteDevice',{id:session.deviceId},a);
 await assert.rejects(call('heartbeat',{sessionId:lease.id},tv),/device-revoked/);
 await assert.rejects(call('listPlayerProfiles',{},tv),/device-revoked/);
});

test('player: subscription expired blocks the session, not the pairing',async()=>{
 const a=await admin();
 const session=await call('beginDevicePair',{name:'Quarto',platform:'tizen',nativeDeviceId:`tizen-exp-${Date.now()}`}) as {token:string;deviceId:string};
 await execute('linkDevice',{token:session.token},a);
 await call('finishDevicePair',{token:session.token});
 const familyId=(await getFirestore().doc(`users/${a.uid}`).get()).data()!.familyId as string;
 await getFirestore().doc(`families/${familyId}/private/subscription`).set({status:'expired',trialStartedAt:1,trialEndsAt:2});
 const tv=await deviceAuth(session.deviceId,familyId);
 const {profiles}=await call('listPlayerProfiles',{},tv) as {profiles:{id:string}[]};
 await assert.rejects(call('acquireSession',{profileId:profiles[0]!.id},tv),/subscription-required/);
});

test('player: pairing quota per network',async()=>{
 const ip=`198.51.100.${(Date.now()%200)+1}`;
 for(let i=0;i<20;i++)await runPlayer({action:'beginDevicePair',payload:{name:'TV',platform:'tizen'},auth:undefined,ip},'',deps);
 await assert.rejects(runPlayer({action:'beginDevicePair',payload:{name:'TV',platform:'tizen'},auth:undefined,ip},'',deps),/rate-limited/);
});


test('player: sensitive request replay and stale timestamps are rejected',async()=>{
 const actor={uid:'tv_nonce',deviceId:'nonce',familyId:'f'},now=Date.now();
 const payload={requestId:randomBytes(16).toString('hex'),issuedAt:now};
 await consumePlayerRequest(actor,'acquireSession',payload,now);
 await assert.rejects(consumePlayerRequest(actor,'acquireSession',payload,now),/request-replayed/);
 await assert.rejects(consumePlayerRequest(actor,'acquireSession',{...payload,issuedAt:now-121000},now),/request-expired/);
});

test('player: a prior credential never revives after re-pairing the same local device identifier',async()=>{
 const a=await admin(),nativeDeviceId=`same-${Date.now()}`;
 const pair=async()=>{
  const session=await call('beginDevicePair',{name:'TV',platform:'tizen',nativeDeviceId}) as any;
  await execute('linkDevice',{token:session.token},a);
  await call('finishDevicePair',{token:session.token});
  const fid=(await getFirestore().doc(`users/${a.uid}`).get()).data()!.familyId;
  return {session,auth:await deviceAuth(session.deviceId,fid)};
 };
 const old=await pair();
 await execute('deleteDevice',{id:old.session.deviceId},a);
 const fresh=await pair();
 await assert.rejects(call('listPlayerProfiles',{},old.auth),/device-revoked/);
 await call('listPlayerProfiles',{},fresh.auth);
});

test('player: expired pairing, disabled profiles and removed families fail closed',async()=>{
 const a=await admin();
 const session=await call('beginDevicePair',{name:'TV',platform:'tizen'}) as any;
 await execute('linkDevice',{token:session.token},a);
 const fid=(await getFirestore().doc(`users/${a.uid}`).get()).data()!.familyId;
 const auth=await deviceAuth(session.deviceId,fid);
 const profiles=await call('listPlayerProfiles',{},auth) as any;
 await call('acquireSession',{profileId:profiles.profiles[0].id},auth);
 await getFirestore().doc(`families/${fid}/profiles/${profiles.profiles[0].id}`).update({enabled:false});
 await assert.rejects(call('readPlayerGenerations',{profileId:profiles.profiles[0].id},auth),/profile-disabled/);
 await getFirestore().doc(`families/${fid}`).update({deleting:true});
 await assert.rejects(call('listPlayerProfiles',{},auth),/device-revoked/);
 const {hash}=await import('../src/domain');
 await getFirestore().doc(`link_tokens/${hash(session.token)}`).update({expiresAt:1});
 await assert.rejects(call('finishDevicePair',{token:session.token}),/pairing-expired/);
});
