import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore, FieldValue} from 'firebase-admin/firestore';
import {onCall,HttpsError} from 'firebase-functions/v2/https';
import {onDocumentWritten} from 'firebase-functions/v2/firestore';
import {onMessagePublished} from 'firebase-functions/v2/pubsub';
import {handlePlayNotification} from './play_billing';
import {cleanupIptvResources} from './iptv_cleanup';
import {getStorage} from 'firebase-admin/storage';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {defineSecret} from 'firebase-functions/params';
import {ZodError} from 'zod';
import {DomainError} from './domain';
import {execute,Identity} from './service';
import {firestoreQuota,runPlayer,PLAYER_PUBLIC_ACTIONS,consumePlayerRequest} from './player';
import {scheduleDailySync, DAILY_SCHEDULE, DAILY_TIME_ZONE} from './iptv_jobs';
import {dispatchSyncCompletionNotification, retryPushNotifications} from './iptv_notifications';
import {syncDueSources, syncIptvCatalog} from './iptv_sync';
initializeApp();
const credentialKey=defineSecret('IPTV_CREDENTIAL_KEY');
// App Check is enforced in every deployed environment; only the local emulator,
// where the Gestor does not activate App Check, accepts calls without it.
const enforceAppCheck=process.env.FUNCTIONS_EMULATOR!=='true';
// Catalogs (up to 64 MB of JSON) are parsed in memory: bounded concurrency per instance.
export const manager=onCall({region:'us-central1',enforceAppCheck,memory:'1GiB',cpu:1,concurrency:8,secrets:[credentialKey],timeoutSeconds:60},async request=>{
 try {
  const token=request.auth?.token;
  const actor:Identity|undefined=request.auth?{uid:request.auth.uid,deviceId:token?.deviceId as string|undefined,familyId:token?.familyId as string|undefined,credentialVersion:token?.credentialVersion as string|undefined,authTime:token?.auth_time}:undefined;
  const result=await execute(request.data?.action,request.data?.payload??{},actor,credentialKey.value());
  return result;
 }catch(error){
  throw httpsErrorFrom(error);
 }
});
// iPlex Web on Smart TVs (no App Check: reCAPTCHA is incompatible with Tizen 5.5).
// Closed list of Player actions, device credential required, same execute() rules.
export const player=onCall({region:'us-central1',enforceAppCheck:false,memory:'1GiB',cpu:1,concurrency:8,secrets:[credentialKey],timeoutSeconds:60},async request=>{
 try {
  let verified=request.auth;
  if(!PLAYER_PUBLIC_ACTIONS.has(request.data?.action)){
   const bearer=/^Bearer (.+)$/.exec(request.rawRequest.get('authorization')??'')?.[1];
   if(!bearer)throw new DomainError('unauthenticated');
   try{const token=await getAuth().verifyIdToken(bearer,true);verified={uid:token.uid,token,rawToken:bearer};}
   catch{throw new DomainError('device-revoked');}
  }
  return await runPlayer({action:request.data?.action,payload:request.data?.payload,auth:verified?{uid:verified.uid,token:verified.token as Record<string,unknown>}:undefined,ip:request.rawRequest?.ip},
   credentialKey.value(),{execute,quota:firestoreQuota,consume:consumePlayerRequest,now:Date.now});
 }catch(error){
  throw httpsErrorFrom(error);
 }
});
function httpsErrorFrom(error:unknown):HttpsError {
 if(error instanceof HttpsError)return error;
 if(error instanceof ZodError)return new HttpsError('invalid-argument','invalid-input');
 if(error instanceof DomainError)return new HttpsError(error.code==='unauthenticated'?'unauthenticated':error.code==='permission-denied'?'permission-denied':'failed-precondition',error.code,error.details);
 // Never forward provider URLs, credentials, SDK errors or token-bearing payloads.
 // Logged for diagnosis with URLs and long tokens removed (an unlogged 500 hid a
 // missing signBlob permission in finishDevicePair).
 const e=error as {name?:unknown;code?:unknown;message?:unknown};
 console.error(JSON.stringify({component:'callable',event:'unexpected-error',name:String(e?.name??typeof error).slice(0,60),code:String(e?.code??'').slice(0,80),
  message:String(e?.message??'').replace(/https?:\/\/\S+/g,'<url>').replace(/[A-Za-z0-9_\-.]{40,}/g,'<redacted>').slice(0,300)}));
 return new HttpsError('internal','operation-failed');
}
export const synchronizeCatalogs=onSchedule({schedule:DAILY_SCHEDULE,timeZone:DAILY_TIME_ZONE,region:'us-central1',timeoutSeconds:60},()=>scheduleDailySync());
export const recoverIptvJobs=onSchedule({schedule:'every 1 minutes',region:'us-central1',secrets:[credentialKey],timeoutSeconds:540,memory:'1GiB',maxInstances:1},()=>syncDueSources(credentialKey.value()));
export const deliverIptvNotification=onDocumentWritten({document:'users/{uid}/sync_notifications/{jobId}',region:'us-central1',retry:true,maxInstances:2},async event=>{
 const after=event.data?.after;if(after?.exists&&after.data()?.pushStatus==='pending')await dispatchSyncCompletionNotification(after.ref);
});
export const recoverIptvNotifications=onSchedule({schedule:'every 5 minutes',region:'us-central1',timeoutSeconds:540},retryPushNotifications);
export const processIptvSyncJobTrigger=onDocumentWritten({document:'iptv_sync_jobs/{jobId}',region:'us-central1',secrets:[credentialKey],timeoutSeconds:540,memory:'1GiB',retry:true,maxInstances:5,concurrency:1},async event=>{
 const after=event.data?.after;
 if(after?.exists&&after.data()?.status==='queued'){
  const job=after.data()!;
  const db=getFirestore();
  const sourceRef=db.doc(`families/${job.familyId}/sources/${job.sourceId}`);
  const sourceSnap=await sourceRef.get();
  if(sourceSnap.exists)await syncIptvCatalog(sourceRef,credentialKey.value(),after.id);
 }
});
export const cleanupIptv=onSchedule({schedule:'every 30 minutes',region:'us-central1',timeoutSeconds:540},cleanupIptvResources);
export const purgeDeletedAccounts=onSchedule({schedule:'every 60 minutes',region:'us-central1',timeoutSeconds:540},async()=>{
 const db=getFirestore();const jobs=await db.collection('deletion_jobs').where('status','==','pending').limit(20).get();
 for(const job of jobs.docs){
  const scopes=new Set([...(job.data().familyIds??[]),job.data().familyId,job.data().iptvWorkspaceId].filter((id):id is string=>typeof id==='string'&&id.length>0));
  for(const fid of scopes){
   const devices=await db.collection(`families/${fid}/devices`).get();
   for(const device of devices.docs)await getAuth().deleteUser(`tv_${device.id}`).catch(e=>{if(e.code!=='auth/user-not-found')throw e;});
   const sources=await db.collection(`families/${fid}/sources`).get();
   for(const source of sources.docs){
    const batch=db.batch();batch.delete(db.doc(`iptv_sources/${source.id}`));
    if(source.data().catalogId){
     const catId=source.data().catalogId;
     batch.delete(db.doc(`catalogs/${catId}/sources/${source.id}`));
     batch.delete(db.doc(`iptv_catalogs/${catId}/sources/${source.id}`));
     batch.set(db.doc(`catalogs/${catId}`),{activeSourceCount:FieldValue.increment(-1),updatedAt:Date.now()},{merge:true});
     batch.set(db.doc(`iptv_catalogs/${catId}`),{activeSourceCount:FieldValue.increment(-1),updatedAt:Date.now()},{merge:true});
    }
    const pending=await db.collection('iptv_sync_jobs').where('sourceId','==',source.id).where('status','in',['queued','running']).get();
    for(const row of pending.docs)batch.update(row.ref,{status:'cancelled',finishedAt:Date.now()});
    await batch.commit();
    const filePath=source.data().filePath??(source.data().format==='file'?`source_files/${fid}_${source.id}.m3u`:null);
    if(filePath)await db.collection('iptv_cleanup').add({sourcePath:source.ref.path,filePath,notBefore:Date.now()+900000});
   }
   const secrets=await db.collection('source_secrets').where('__name__','>=',`${fid}_`).where('__name__','<',`${fid}_\uf8ff`).get();
   for(const secret of secrets.docs)await secret.ref.delete();
   await db.recursiveDelete(db.doc(`families/${fid}`));
  }
  const tokens=await db.collection('device_push_tokens').where('ownerUid','==',job.id).get();
  for(const token of tokens.docs)await token.ref.delete();
  await db.recursiveDelete(db.doc(`users/${job.id}`));
  await getAuth().deleteUser(job.id).catch(e=>{if(e.code!=='auth/user-not-found')throw e;});await job.ref.delete();
 }
});

// Google Play real-time developer notifications. The topic must be the one set in
// Play Console › Monetization setup; Play's service account needs Publisher on it.
export const playBillingNotifications=onMessagePublished({topic:process.env.PLAY_RTDN_TOPIC||'play-billing-notifications',region:'us-central1',retry:true,maxInstances:5},async event=>{
 let data:unknown;
 try{data=event.data.message.json;}catch{console.warn('play-rtdn: non-JSON message ignored');return;}
 // Malformed or foreign messages are acknowledged; API/transient failures are retried.
 try{await handlePlayNotification(data);}catch(e){if(e instanceof ZodError){console.warn('play-rtdn: invalid message ignored');return;}throw e;}
});
