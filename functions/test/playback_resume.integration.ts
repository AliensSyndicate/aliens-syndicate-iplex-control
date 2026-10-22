import {createFamily} from './support/membership';
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
async function family(){const admin=await account('Ana Admin');const fid=(await createFamily(admin,'Casa') as {id:string}).id;return {admin,fid,ctx:{contextFamilyId:fid}};}
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


const sleep=(ms:number)=>new Promise(r=>setTimeout(r,ms));
const MIN=60;
const base={schemaVersion:1};void base;

test('resume: the Control position travels to the TV and survives initialisation noise, late events and other TVs',async()=>{
 const {admin,fid,ctx}=await family();
 const {item}=await publishCatalog(fid);
 const rui=(await execute('saveProfile',{name:'Rui',...ctx},admin) as {id:string}).id;
 const player=await tv(admin,fid);
 await tvCall('acquireSession',{profileId:'admin'},player);
 const progressDoc=(contentId:string,profile='admin')=>db().doc(`families/${fid}/profiles/${profile}/watch_progress/${contentId}`);
 const write=(contentId:string,position:number,session:Record<string,unknown>,duration=120*MIN,profileId='admin',auth:PlayerAuth&{deviceId:string}=player)=>
  tvCall('watchProgress',{profileId,contentId,position,duration,generation:0,...session},auth) as Promise<{ok:boolean;ignored?:string}>;
 const request=(extra:Record<string,unknown>,auth=player)=>execute('requestPlayback',{deviceId:auth.deviceId,sourceId:'src1',requestId:rid(),...ctx,...extra},admin) as Promise<{id:string}>;
 const claim=async(id:string,auth=player)=>(await tvCall('claimPlayRequest',{playRequestId:id},auth) as any).request;

 // 1) The movie stops at 38 min (session A on the TV).
 const A={playId:'tv-a-run-0001',startedAt:Date.now()-60_000,origin:'restart'};
 assert.equal((await write(item('m1'),37*MIN,{...A,seq:1})).ignored,undefined);
 assert.equal((await write(item('m1'),38*MIN,{...A,seq:2})).ignored,undefined);

 // 2) Continue from the Control: the claimed request carries the position (2280 s), never just a flag.
 let r=await request({itemId:item('m1'),resume:true});
 let delivered=await claim(r.id);
 assert.equal(delivered.resume,true);assert.equal(delivered.resumePositionSec,38*MIN);assert.equal(delivered.resumeDurationSec,120*MIN);

 // 3) Initialisation: the new player reports 0 before restoring. Ignored; saved progress intact.
 const B={playId:'tv-a-run-0002',startedAt:Date.now(),origin:'resume'};
 assert.equal((await write(item('m1'),0,{...B,seq:1})).ignored,'initial-zero');
 assert.equal((await write(item('m1'),12,{...B,seq:2})).ignored,'resume-not-applied');
 assert.equal((await progressDoc(item('m1')).get()).data()?.position,38*MIN);
 // Restored: 38:02 accepted; then the person seeks back (userSeek) and forward; both accepted in order.
 assert.equal((await write(item('m1'),38*MIN+2,{...B,seq:3})).ignored,undefined);
 assert.equal((await write(item('m1'),10*MIN,{...B,seq:4,userSeek:true})).ignored,undefined);
 assert.equal((await progressDoc(item('m1')).get()).data()?.position,10*MIN,'rewind is a legitimate progress');
 assert.equal((await write(item('m1'),50*MIN,{...B,seq:5,userSeek:true})).ignored,undefined);
 // Out of order / replayed events of the same playback are dropped.
 assert.equal((await write(item('m1'),11*MIN,{...B,seq:4})).ignored,'stale-event');
 assert.equal((await progressDoc(item('m1')).get()).data()?.position,50*MIN);

 // 4) Stale session (e.g. another TV that started earlier) cannot overwrite the current playback.
 assert.equal((await write(item('m1'),5*MIN,{playId:'tv-b-run-0001',startedAt:B.startedAt-30_000,seq:99,origin:'restart',userSeek:true})).ignored,'stale-session');
 // Legacy TVs (no session fields) keep working.
 assert.equal((await write(item('m1'),51*MIN,{})).ignored,undefined);

 // 5) Intentional restart from the beginning is accepted.
 assert.equal((await write(item('m1'),0,{playId:'tv-a-run-0003',startedAt:Date.now()+1,seq:1,origin:'restart'})).ignored,undefined);
 assert.equal((await progressDoc(item('m1')).get()).data()?.position,0);

 // 6) Finished titles and titles never started do not resume.
 await write(item('m1'),119*MIN,{playId:'tv-a-run-0004',startedAt:Date.now()+2,seq:1,origin:'restart'});
 await sleep(2100);
 r=await request({itemId:item('m1'),resume:true});
 delivered=await claim(r.id);
 assert.equal(delivered.resume,true);assert.equal('resumePositionSec' in delivered,false,'finished: start from the beginning');

 // 7) Series: the right episode and its own position; another episode is not confused.
 await write(`${item('s1')}_e901`,20*MIN,{playId:'tv-a-run-0005',startedAt:Date.now()+3,seq:1,origin:'restart'},45*MIN);
 await sleep(2100);
 r=await request({itemId:item('s1'),episodeId:'901',episodeLabel:'T1 E1',resume:true});
 delivered=await claim(r.id);
 assert.equal(delivered.episodeId,'901');assert.equal(delivered.resumePositionSec,20*MIN);assert.equal(delivered.resumeDurationSec,45*MIN);
 await sleep(2100);
 r=await request({itemId:item('s1'),episodeId:'902',episodeLabel:'T1 E2',resume:true});
 assert.equal('resumePositionSec' in await claim(r.id),false);

 // 8) Live channels never resume.
 await sleep(2100);
 r=await request({itemId:item('c1'),resume:true});
 assert.equal('resume' in await claim(r.id),false);

 // 9) A request without resume does not carry a position (watch from the start).
 await write(item('m1'),40*MIN,{playId:'tv-a-run-0006',startedAt:Date.now()+4,seq:1,origin:'restart'});
 await sleep(2100);
 r=await request({itemId:item('m1')});
 assert.equal('resumePositionSec' in await claim(r.id),false);

 // 10) Two TVs, two profiles: the TV of another profile still opens where the requester stopped,
 //     and each TV's writes stay in its own profile.
 const tv2=await tv(admin,fid);
 await tvCall('acquireSession',{profileId:rui},tv2);
 await sleep(2100);
 r=await request({itemId:item('m1'),resume:true},tv2);
 const onTv2=await claim(r.id,tv2);
 assert.equal(onTv2.resumePositionSec,40*MIN,'the position the Control showed (admin profile)');
 assert.equal((await write(item('m1'),41*MIN,{playId:'tv-2-run-0001',startedAt:Date.now()+5,seq:1,origin:'resume'},120*MIN,rui,tv2)).ignored,undefined);
 assert.equal((await progressDoc(item('m1'),rui).get()).data()?.position,41*MIN);
 assert.equal((await progressDoc(item('m1')).get()).data()?.position,40*MIN,'TV 1 profile untouched by TV 2');
});
