import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {getStorage} from 'firebase-admin/storage';
import {execute,Identity} from '../src/service';
import {hash,seal} from '../src/domain';
import {streamIndexPath} from '../src/iptv_sync';

let app:ReturnType<typeof initializeApp>;
before(()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST||!process.env.FIREBASE_STORAGE_EMULATOR_HOST)throw new Error('Emulators required');
 app=initializeApp({projectId:'demo-iplex',storageBucket:'demo-iplex.appspot.com'});
});
after(()=>deleteApp(app));
const db=()=>getFirestore();
const key=Buffer.alloc(32,7).toString('base64');

async function account(){
 const a:Identity={uid:`mobile_${randomUUID().replace(/-/g,'')}`};
 await getAuth().createUser({uid:a.uid,displayName:'Pessoa'});
 await execute('bootstrap',{},a);
 return {a,fid:(await db().doc(`users/${a.uid}`).get()).data()!.familyId as string};
}

test('the Control plays on the phone in its own session, with the TV rules (subscription, limits, adult PIN)',async()=>{
 const {a,fid}=await account();
 const catalog={schemaVersion:1,items:[
  {id:'m1',title:'Drama',titleKey:'drama',kind:'movie',category:'Filmes',providerRef:'1'},
  {id:'x1',title:'XXX Night',titleKey:'xxx night',kind:'movie',category:'Filmes',providerRef:'2'},
 ]};
 const body=JSON.stringify(catalog),version=hash(body);
 await getStorage().bucket().file(`catalogs/${version}.json`).save(body);
 await db().doc(`catalogs/${version}`).set({storagePath:`catalogs/${version}.json`,integrityHash:version});
 await db().doc(`families/${fid}/sources/src`).set({name:'Lista',enabled:true,version,revision:1,authorizationStatus:'valid',authorizationRevision:1});
 await db().doc(`source_secrets/${fid}_src`).set({revision:1,encrypted:seal({name:'Lista',format:'m3u',url:'https://example.com/list.m3u'},key)});
 await getStorage().bucket().file(streamIndexPath(fid,'src')).save(seal({version,revision:1,streams:{'1':'https://example.com/m1.mp4','2':'https://example.com/x1.mp4'}},key));
 const stream=(itemId:string,sessionId?:string)=>execute('resolveSourceStream',{id:'src',itemId,...(sessionId?{sessionId}:{})},a,key) as Promise<{url:string}>;

 // No subscription or trial: no playback, as on the TV.
 await assert.rejects(execute('startMobilePlayback',{},a),/subscription-required/);
 await db().doc(`families/${fid}/private/subscription`).set({status:'trial',trialStartedAt:Date.now(),trialEndsAt:Date.now()+86_400_000});

 const start=await execute('startMobilePlayback',{deviceName:'Meu celular'},a) as {sessionId:string;profileId:string;pinRequired:boolean};
 assert.equal(start.profileId,'admin');
 assert.equal(start.pinRequired,false);
 const lease=((await db().doc(`families/${fid}`).get()).data()!.leases as {deviceId:string;deviceName:string}[]).find(l=>l.deviceId===`mobile_${a.uid}`);
 assert.equal(lease?.deviceName,'Meu celular');
 // The URL only leaves inside the session.
 await assert.rejects(stream('m1'),/player-required/);
 assert.equal((await stream('m1',start.sessionId)).url,'https://example.com/m1.mp4');
 await assert.rejects(stream('m1','someone-else'),/session-expired/);
 const beat=await execute('mobilePlaybackHeartbeat',{sessionId:start.sessionId},a) as {ok:boolean;expiresAt:number};
 assert.equal(beat.ok,true);assert.ok(beat.expiresAt>Date.now());
 await execute('stopMobilePlayback',{sessionId:start.sessionId},a);
 await assert.rejects(stream('m1',start.sessionId),/session-expired/);

 // One session per profile: a TV on the same profile blocks the phone.
 const pairing=await execute('beginDevicePair',{name:'TV'},undefined) as {token:string};
 const device=await execute('linkDevice',{token:pairing.token},a) as {id:string};
 const tv:Identity={uid:`tv_${device.id}`,deviceId:device.id,familyId:fid,credentialVersion:(await db().doc(`families/${fid}/devices/${device.id}`).get()).data()!.credentialVersion};
 const tvSession=await execute('acquireSession',{profileId:'admin'},tv) as {id:string};
 await assert.rejects(execute('startMobilePlayback',{},a),/profile-in-use/);
 await execute('releaseSession',{sessionId:tvSession.id},tv);

 // Adult content with a personal PIN: one unlock per play, verified on the phone.
 await execute('setPersonalPin',{pin:'2468',confirmPin:'2468'},a);
 const session=(await execute('startMobilePlayback',{},a) as {sessionId:string;pinRequired:boolean});
 assert.equal(session.pinRequired,true);
 await assert.rejects(stream('x1',session.sessionId),/adult-pin-required/);
 assert.equal((await execute('verifyAdultPin',{sessionId:session.sessionId,pin:'1111'},a) as {verified:boolean}).verified,false);
 assert.equal((await execute('verifyAdultPin',{sessionId:session.sessionId,pin:'2468'},a) as {verified:boolean}).verified,true);
 assert.equal((await stream('x1',session.sessionId)).url,'https://example.com/x1.mp4');
 await assert.rejects(stream('x1',session.sessionId),/adult-pin-required/,'single use');
 // Movies without adult content never ask for it.
 assert.ok((await stream('m1',session.sessionId)).url);
 // A PIN check needs the phone's own session.
 await assert.rejects(execute('verifyAdultPin',{sessionId:'nope',pin:'2468'},a),/session-expired/);
});
