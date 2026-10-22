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

test('now playing: the TV publishes what it plays; only with a current lease; cleared on stop and release',async()=>{
 const {admin,fid}=await family();
 const {item}=await publishCatalog(fid);
 const player=await tv(admin,fid);
 const lease=await tvCall('acquireSession',{profileId:'admin'},player) as {id:string};
 const device=()=>db().doc(`families/${fid}/devices/${player.deviceId}`).get().then(d=>d.data()?.nowPlaying);
 const report=(extra:Record<string,unknown>)=>tvCall('reportPlayback',{sessionId:lease.id,sourceId:'src1',itemId:item('m1'),state:'playing',...extra},player) as Promise<any>;
 assert.equal(await device(),undefined);
 await report({positionSec:2280,durationSec:7200});
 let now=await device();
 assert.equal(now.title,'Drama Noturno');assert.equal(now.kind,'movie');assert.equal(now.state,'playing');
 assert.equal(now.positionSec,2280);assert.equal(now.durationSec,7200);assert.equal(now.profileId,'admin');
 assert.equal(JSON.stringify(now).includes('http'),false,'no stream URL');
 // Another session id cannot publish.
 await assert.rejects(tvCall('reportPlayback',{sessionId:'other-session',sourceId:'src1',itemId:item('m1'),state:'playing'},player),/session-expired/);
 // Series episode, paused; invalid progress (position beyond duration) is not published.
 await sleep(5100);
 await report({itemId:item('s1'),episodeId:'901',state:'paused',positionSec:900,durationSec:600});
 now=await device();
 assert.equal(now.episodeId,'901');assert.equal(now.state,'paused');assert.equal('positionSec' in now,false);
 // Live channel never carries progress.
 await sleep(5100);
 await report({itemId:item('c1'),positionSec:10,durationSec:100});
 now=await device();assert.equal(now.kind,'channel');assert.equal('positionSec' in now,false);
 // Unknown content is refused.
 await assert.rejects(report({itemId:'nope0000'}),/not-found/);
 // Stop and release clear it.
 await report({state:'stopped'});
 assert.equal(await device(),undefined);
 await sleep(5100);
 await report({});
 assert.ok(await device());
 await tvCall('releaseSession',{sessionId:lease.id},player);
 assert.equal(await device(),undefined);
});
