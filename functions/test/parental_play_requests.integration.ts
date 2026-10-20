import {randomBytes} from 'node:crypto';
import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {getStorage} from 'firebase-admin/storage';
import {execute,Identity} from '../src/service';
import {hash} from '../src/domain';
import {firestoreQuota,runPlayer,consumePlayerRequest,type PlayerAuth} from '../src/player';

let app:ReturnType<typeof initializeApp>,seq=0;
before(()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST||!process.env.FIREBASE_STORAGE_EMULATOR_HOST)throw new Error('Emulators required');
 app=initializeApp({projectId:'demo-iplex',storageBucket:'demo-iplex.appspot.com'});
});
after(()=>deleteApp(app));
const db=()=>getFirestore();
const rid=()=>randomBytes(16).toString('hex');
const deps={execute,quota:firestoreQuota,consume:consumePlayerRequest,now:Date.now};
/** Through the real `player` entry point (closed list, anti-replay), as the TV calls it. */
const tvCall=(action:string,payload:Record<string,unknown>,auth:PlayerAuth)=>runPlayer({action,payload:{...payload,requestId:rid(),issuedAt:Date.now()},auth,ip:'203.0.113.9'},'',deps) as Promise<any>;
async function account(name='Pessoa'){const a:Identity={uid:`pp_${Date.now()}_${++seq}`,authTime:Math.floor(Date.now()/1000)};await getAuth().createUser({uid:a.uid,displayName:name});await execute('bootstrap',{},a);return a;}
async function family(){const admin=await account('Ana Admin');const fid=(await execute('createFamily',{name:'Casa'},admin) as {id:string}).id;return {admin,fid,ctx:{contextFamilyId:fid}};}
async function tv(admin:Identity,fid:string):Promise<PlayerAuth&{deviceId:string}>{
 const s=await execute('beginDevicePair',{name:'Sala',platform:'tizen'},undefined) as {token:string};
 const d=await execute('linkDevice',{token:s.token,contextFamilyId:fid},admin) as {id:string};
 const credentialVersion=(await db().doc(`families/${fid}/devices/${d.id}`).get()).data()?.credentialVersion;
 return {deviceId:d.id,uid:`tv_${d.id}`,token:{deviceId:d.id,familyId:fid,credentialVersion,firebase:{sign_in_provider:'custom'},auth_time:Math.floor(Date.now()/1000)}};
}
async function publishCatalog(fid:string){
 const catalog={schemaVersion:1,items:[
  {id:'m1',title:'Drama Noturno',titleKey:'drama noturno',kind:'movie',category:'Filmes',providerRef:'1',ageRating:'16'},
  {id:'k1',title:'Peppa',titleKey:'peppa',kind:'movie',category:'Infantil',providerRef:'2'},
  {id:'c1',title:'Canal Notícias',titleKey:'canal noticias',kind:'channel',category:'Notícias',providerRef:'3'},
  {id:'s1',title:'Série Longa',titleKey:'serie longa',kind:'series',category:'Séries',providerRef:'77'},
 ],seriesDetails:{'77':{seasons:[{seasonNumber:1}],episodes:{'1':[{id:'901',title:'Piloto',season:1,episodeNum:1}]}}}};
 const body=JSON.stringify(catalog),version=hash(body);
 await getStorage().bucket().file(`catalogs/${version}.json`).save(body);
 await db().doc(`catalogs/${version}`).set({storagePath:`catalogs/${version}.json`,integrityHash:hash(body)});
 await db().doc(`families/${fid}/sources/src1`).set({name:'Lista',enabled:true,version,revision:1});
 return {item:(id:string)=>hash(`src1:${id}`)};
}

test('parental PIN: adult profiles need a backend-verified PIN when the family has a kids profile',async()=>{
 const {admin,fid,ctx}=await family();
 const kid=(await execute('saveProfile',{name:'Lia',type:'kids',...ctx},admin) as {id:string}).id;
 const reg=(await execute('saveProfile',{name:'Rui',...ctx},admin) as {id:string}).id;
 const player=await tv(admin,fid);
 const listed=await tvCall('listPlayerProfiles',{},player) as {parentalPin:{configured:boolean};profiles:{id:string;pinRequired:boolean}[]};
 assert.equal(listed.parentalPin.configured,false);
 assert.deepEqual(Object.fromEntries(listed.profiles.map(p=>[p.id,p.pinRequired])),{admin:true,[kid]:false,[reg]:true});
 // Fail closed: without a PIN the adult profile does not open, whatever the client says.
 await assert.rejects(tvCall('acquireSession',{profileId:'admin',pinVerified:true},player),/profile-pin-required/);
 await assert.rejects(tvCall('verifyProfilePin',{profileId:'admin',pin:'1234'},player),/parental-pin-not-configured/);
 // Only the administrator sets it; the PIN is never stored in clear.
 const member=await account();
 await assert.rejects(execute('setParentalPin',{pin:'1234',confirmPin:'1234',...ctx},member),/permission-denied/);
 await assert.rejects(execute('setParentalPin',{pin:'1234',confirmPin:'4321',...ctx},admin),/pin-mismatch/);
 await assert.rejects(execute('setParentalPin',{pin:'12a4',confirmPin:'12a4',...ctx},admin),/invalid/);
 await execute('setParentalPin',{pin:'1234',confirmPin:'1234',...ctx},admin);
 assert.equal((await db().doc(`families/${fid}`).get()).data()?.parental?.pinConfigured,true);
 assert.equal(JSON.stringify((await db().doc(`families/${fid}/private/parental`).get()).data()).includes('1234'),false);
 // Wrong PIN: no unlock. Right PIN: one session for that profile only.
 assert.deepEqual(await tvCall('verifyProfilePin',{profileId:'admin',pin:'0000'},player),{verified:false,required:true,attemptsLeft:4});
 await assert.rejects(tvCall('acquireSession',{profileId:'admin'},player),/profile-pin-required/);
 assert.deepEqual(await tvCall('verifyProfilePin',{profileId:'admin',pin:'1234'},player),{verified:true,required:true});
 await assert.rejects(tvCall('acquireSession',{profileId:reg},player),/profile-pin-required/,'the unlock is bound to one profile');
 const lease=await tvCall('acquireSession',{profileId:'admin'},player) as {id:string};
 const beat=await tvCall('heartbeat',{sessionId:lease.id},player) as {ok:boolean;playRequest:unknown};
 assert.deepEqual(beat,{ok:true,playRequest:null});
 // Multitasking keeps the PIN session; leaving the profile locks it again.
 await tvCall('releaseSession',{sessionId:lease.id,suspend:true},player);
 const resumed=await tvCall('acquireSession',{profileId:'admin'},player) as {id:string};
 await tvCall('releaseSession',{sessionId:resumed.id},player);
 await assert.rejects(tvCall('acquireSession',{profileId:'admin'},player),/profile-pin-required/);
 // Kids profile opens directly.
 const kidLease=await tvCall('acquireSession',{profileId:kid},player) as {id:string};
 await tvCall('releaseSession',{sessionId:kidLease.id},player);
 // Lockout after five wrong attempts, even for the right PIN afterwards.
 for(let i=0;i<4;i++)await tvCall('verifyProfilePin',{profileId:'admin',pin:'9999'},player);
 const last=await tvCall('verifyProfilePin',{profileId:'admin',pin:'9999'},player) as {verified:boolean;attemptsLeft:number;retryAt:number};
 assert.equal(last.verified,false);assert.equal(last.attemptsLeft,0);assert.ok(last.retryAt>Date.now());
 await assert.rejects(tvCall('verifyProfilePin',{profileId:'admin',pin:'1234'},player),/pin-locked/);
 // Clearing the PIN keeps adults locked (fail closed) while the kids profile exists.
 await execute('clearParentalPin',{...ctx},admin);
 assert.equal((await db().doc(`families/${fid}/private/parental`).get()).exists,false);
});

test('parental PIN: families without kids profiles open adult profiles directly',async()=>{
 const {admin,fid}=await family();
 const player=await tv(admin,fid);
 const listed=await tvCall('listPlayerProfiles',{},player) as {profiles:{pinRequired:boolean}[]};
 assert.ok(listed.profiles.every(p=>!p.pinRequired));
 assert.deepEqual(await tvCall('verifyProfilePin',{profileId:'admin',pin:'1234'},player),{verified:true,required:false});
 assert.ok(((await tvCall('acquireSession',{profileId:'admin'},player)) as {id:string}).id);
});

test('play requests: Control asks a linked TV to start a title; single claim, expiry, supersede, kids and family isolation',async()=>{
 const {admin,fid,ctx}=await family();
 const {item}=await publishCatalog(fid);
 const kid=(await execute('saveProfile',{name:'Lia',type:'kids',...ctx},admin) as {id:string}).id;
 await execute('setParentalPin',{pin:'2468',confirmPin:'2468',...ctx},admin);
 const player=await tv(admin,fid);
 const request=(extra:Record<string,unknown>,actor:Identity=admin)=>execute('requestPlayback',{deviceId:player.deviceId,sourceId:'src1',requestId:rid(),...ctx,...extra},actor) as Promise<{id:string;status:string;expiresAt:number}>;
 // TV with no active profile session: the phone is told to open iPlex on the TV.
 await assert.rejects(request({itemId:item('m1')}),/device-offline/);
 await tvCall('verifyProfilePin',{profileId:'admin',pin:'2468'},player);
 const lease=await tvCall('acquireSession',{profileId:'admin'},player) as {id:string};
 // Idempotent per phone request id; only stable identifiers are stored.
 const requestId=rid();
 const first=await request({itemId:item('m1'),requestId});
 assert.equal(first.status,'pending');
 assert.deepEqual(await request({itemId:item('m1'),requestId}),first);
 const doc=(await db().doc(`families/${fid}/devices/${player.deviceId}/play_requests/${first.id}`).get()).data()!;
 assert.equal(doc.title,'Drama Noturno');assert.equal(doc.kind,'movie');assert.equal(doc.requesterName,'Ana Admin');
 assert.equal(JSON.stringify(doc).includes('http'),false,'no stream URL or provider address in the request');
 // Heartbeat fallback points at the pending request.
 assert.equal(((await tvCall('heartbeat',{sessionId:lease.id},player)) as {playRequest:{id:string}}).playRequest.id,first.id);
 // A newer request supersedes the older one, which can never start later.
 await assert.rejects(request({itemId:item('c1')}),/rate-limited/);
 await new Promise(r=>setTimeout(r,2100));
 const second=await request({itemId:item('c1')});
 await assert.rejects(tvCall('claimPlayRequest',{playRequestId:first.id},player),/play-request-expired/);
 const claimed=await tvCall('claimPlayRequest',{playRequestId:second.id},player) as {status:string;request:{sourceId:string;itemId:string;kind:string;title:string}};
 assert.equal(claimed.status,'delivered');
 assert.deepEqual(claimed.request,{sourceId:'src1',itemId:item('c1'),episodeId:null,episodeLabel:null,kind:'channel',title:'Canal Notícias',requesterName:'Ana Admin'});
 await assert.rejects(tvCall('claimPlayRequest',{playRequestId:second.id},player),/play-request-claimed/,'claimed once');
 // Confirmation on the TV, then the result reaches the phone.
 assert.equal((await tvCall('updatePlayRequest',{playRequestId:second.id,status:'confirming'},player)).status,'confirming');
 assert.equal((await tvCall('updatePlayRequest',{playRequestId:second.id,status:'started'},player)).status,'started');
 await assert.rejects(tvCall('updatePlayRequest',{playRequestId:second.id,status:'declined'},player),/invalid-transition/);
 assert.equal((await db().doc(`families/${fid}/devices/${player.deviceId}/play_requests/${second.id}`).get()).data()?.status,'started');
 // Old requests expire instead of starting content.
 await new Promise(r=>setTimeout(r,2100));
 const stale=await request({itemId:item('k1')});
 await db().doc(`families/${fid}/devices/${player.deviceId}/play_requests/${stale.id}`).update({expiresAt:Date.now()-1});
 assert.equal((await tvCall('claimPlayRequest',{playRequestId:stale.id},player)).status,'expired');
 // Series need an episode (or explicitly opening the series).
 await new Promise(r=>setTimeout(r,2100));
 await assert.rejects(request({itemId:item('s1')}),/episode-required/);
 const episode=await request({itemId:item('s1'),episodeId:'901',episodeLabel:'T1 E1 · Piloto'});
 const ep=await tvCall('claimPlayRequest',{playRequestId:episode.id},player) as {request:{episodeId:string}};
 assert.equal(ep.request.episodeId,'901');
 await tvCall('updatePlayRequest',{playRequestId:episode.id,status:'failed',errorCode:'stream-unavailable'},player);
 // Kids profile active on the TV: adult content is refused before it reaches the TV.
 await tvCall('releaseSession',{sessionId:lease.id},player);
 await tvCall('acquireSession',{profileId:kid},player);
 await new Promise(r=>setTimeout(r,2100));
 await assert.rejects(request({itemId:item('m1')}),/content-not-allowed/);
 const kidsOk=await request({itemId:item('k1')});
 assert.equal((await tvCall('claimPlayRequest',{playRequestId:kidsOk.id},player)).status,'delivered');
 // A kids account on the phone cannot pick adult content either.
 const kidAccount=await account('Lia');
 const {code}=await execute('createProfileLinkCode',{profileId:kid,...ctx},admin) as {code:string};
 await execute('redeemProfileLink',{code},kidAccount);
 await assert.rejects(request({itemId:item('m1')},kidAccount),/not-found/);
 // Another family cannot target this TV; the TV cannot address another device's requests.
 const other=await family();
 await assert.rejects(execute('requestPlayback',{deviceId:player.deviceId,sourceId:'src1',itemId:item('k1'),requestId:rid(),contextFamilyId:other.fid},other.admin),/not-found|permission-denied|device-not-found/);
 const otherTv=await tv(admin,fid);
 await assert.rejects(tvCall('claimPlayRequest',{playRequestId:kidsOk.id},otherTv),/play-request-not-found/);
 // The phone cannot play the role of the TV.
 await assert.rejects(execute('claimPlayRequest',{playRequestId:kidsOk.id},admin),/permission-denied/);
});

test('unlink with the TV open: protected calls fail at once and the refresh token is revoked',async()=>{
 const {admin,fid}=await family();
 const player=await tv(admin,fid);
 await getAuth().createUser({uid:player.uid}).catch(()=>undefined);
 const lease=await tvCall('acquireSession',{profileId:'admin'},player) as {id:string};
 const before=(await getAuth().getUser(player.uid)).tokensValidAfterTime;
 await new Promise(r=>setTimeout(r,1100));
 await execute('deleteDevice',{id:player.deviceId,contextFamilyId:fid},admin);
 assert.notEqual((await getAuth().getUser(player.uid)).tokensValidAfterTime,before);
 await assert.rejects(tvCall('heartbeat',{sessionId:lease.id},player),/device-revoked/);
 await assert.rejects(tvCall('listPlayerProfiles',{},player),/device-revoked/);
 assert.equal(((await db().doc(`families/${fid}`).get()).data()?.leases??[]).length,0);
});

test('first accepted family becomes the active context (no manual selection needed)',async()=>{
 const {admin,fid}=await family();
 const member=await account('Bia');
 const code=(await db().doc(`users/${member.uid}`).get()).data()!.publicCode;
 const request=await execute('requestMembership',{code,contextFamilyId:fid},admin) as {id:string};
 await execute('respondMembership',{id:request.id,accept:true},member);
 const user=(await db().doc(`users/${member.uid}`).get()).data()!;
 assert.equal(user.familyId,fid);
 assert.deepEqual(user.familyIds,[fid]);
 // A second family keeps the current choice.
 const other=await family();
 const second=await execute('requestMembership',{code,contextFamilyId:other.fid},other.admin) as {id:string};
 await execute('respondMembership',{id:second.id,accept:true},member);
 assert.equal((await db().doc(`users/${member.uid}`).get()).data()!.familyId,fid);
});
