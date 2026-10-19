import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {execute,Identity} from '../src/service';
import {hashPairingCode} from '../src/device_identity';
let app:ReturnType<typeof initializeApp>,seq=0;
before(()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST)throw new Error('Emulators required');
 app=initializeApp({projectId:'demo-iplex'});
});
after(()=>deleteApp(app));
async function account(){const a:Identity={uid:`pairing_${Date.now()}_${++seq}`,authTime:Math.floor(Date.now()/1000)};await getAuth().createUser({uid:a.uid,displayName:'Owner'});await execute('bootstrap',{},a);return a;}
type Session={token:string;code:string;formattedCode:string;deviceId:string;expiresAt:number};
const begin=(nativeDeviceId:string)=>execute('beginDevicePair',{name:'Sala',platform:'android_tv',manufacturer:'Test',model:'Simulated TV',
 nativeDeviceId,identitySource:'simulated'},undefined) as Promise<Session>;
const qr=(token:string)=>new URL(`iplex://pair?token=${token}`).searchParams.get('token')!;

test('real backend session: QR inspect, link without family, rename, unlink, replay denied and player revoked',async()=>{
 const a=await account(),session=await begin(`native-${seq}`);
 assert.match(session.token,/^[a-f0-9]{64}$/);assert.match(session.code,/^\d{6}$/);
 const inspected=await execute('inspectPairingSession',{token:qr(session.token),contextFamilyId:null},a) as Record<string,unknown>;
 assert.equal(inspected.deviceId,session.deviceId);assert.equal(inspected.model,'Simulated TV');assert.equal(inspected.isAlreadyLinked,false);
 const linked=await execute('linkDevice',{token:session.token,contextFamilyId:null},a) as {id:string};
 assert.equal(linked.id,session.deviceId);
 const user=(await getFirestore().doc(`users/${a.uid}`).get()).data()!;
 assert.equal(user.familyId,undefined);
 const scope=user.iptvWorkspaceId as string;
 assert.equal((await getFirestore().doc(`families/${scope}/devices/${linked.id}`).get()).exists,true);
 assert.equal((await getFirestore().doc(`devices/${linked.id}`).get()).data()!.ownership,'personal');
 // The Player exchanges the consumed session once for its own credential.
 const minted=await execute('finishDevicePair',{token:session.token},undefined) as {customToken:string};
 assert.ok(minted.customToken.length>20);
 await assert.rejects(execute('finishDevicePair',{token:session.token},undefined),/invalid-token/);
 await assert.rejects(execute('linkDevice',{token:session.token,contextFamilyId:null},a),/pairing-expired/);
 await assert.rejects(execute('inspectPairingSession',{token:session.token,contextFamilyId:null},a),/pairing-expired/);
 await execute('renameDevice',{id:linked.id,name:'Quarto',contextFamilyId:null},a);
 assert.equal((await getFirestore().doc(`devices/${linked.id}`).get()).data()!.displayName,'Quarto');
 const player:Identity={uid:`tv_${linked.id}`,deviceId:linked.id,familyId:scope};
 await execute('deleteDevice',{id:linked.id,contextFamilyId:null},a);
 assert.equal((await getFirestore().doc(`devices/${linked.id}`).get()).data()!.status,'unlinked');
 await assert.rejects(execute('heartbeat',{sessionId:'x',profileId:'p'},player),/device-revoked/);
});

test('manual six-digit code links once; expired, foreign-owned and guessed codes are rejected',async()=>{
 const a=await account(),b=await account(),native=`manual-${Date.now()}`,session=await begin(native);
 const byCode=await execute('inspectPairingSession',{code:session.code,contextFamilyId:null},a) as {token:string};
 assert.equal(byCode.token,session.token);
 await execute('linkDevice',{code:session.code,contextFamilyId:null},a);
 // Same physical TV shown again: possession of a fresh QR cannot move it to another account.
 const again=await begin(native);
 assert.equal(again.deviceId,session.deviceId);
 const seen=await execute('inspectPairingSession',{token:again.token,contextFamilyId:null},b) as {isAlreadyLinked:boolean;currentFamilyId:string|null};
 assert.equal(seen.isAlreadyLinked,true);assert.equal(seen.currentFamilyId,null);
 await assert.rejects(execute('linkDevice',{token:again.token,contextFamilyId:null},b),/device-already-linked-elsewhere/);
 const stale=await begin(`expired-${seq}`);
 await getFirestore().doc(`device_pairing_codes/${hashPairingCode(stale.code)}`).update({expiresAt:1});
 await assert.rejects(execute('inspectPairingSession',{code:stale.code,contextFamilyId:null},a),/pairing-expired/);
 await assert.rejects(execute('inspectPairingSession',{token:'f'.repeat(64),contextFamilyId:null},a),/invalid-token/);
 const guesser=await account();let limited=false;
 for(let i=0;i<25&&!limited;i++){
  try{await execute('inspectPairingSession',{code:String(100000+i),contextFamilyId:null},guesser);}
  catch(e){if(/rate-limited/.test(String(e)))limited=true;else assert.match(String(e),/invalid-token|pairing-expired/);}
 }
 assert.equal(limited,true);
});
