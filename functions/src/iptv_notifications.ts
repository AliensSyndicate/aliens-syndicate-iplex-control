import {getFirestore, Transaction, DocumentReference} from 'firebase-admin/firestore';
import {getMessaging} from 'firebase-admin/messaging';
import {randomUUID} from 'node:crypto';
import {z} from 'zod';
import {DomainError, hash} from './domain';
import type {Identity} from './service';

/** Persisted in the SAME transaction as publication/failure. Scheduled results
 * remain in jobs only; there is no routine scheduled success/failure fan-out. */
export function completionEvent(tx:Transaction, job:FirebaseFirestore.DocumentData, jobId:string,
  source:DocumentReference, sourceName:string, status:'completed'|'failed', errorCode:string|null=null) {
  if (job.trigger!=='manual'||!job.requestedByUid) return;
  tx.set(getFirestore().doc(`users/${job.requestedByUid}/sync_notifications/${jobId}`),{
    jobId,sourceId:source.id,sourceName,familyId:source.parent.parent!.id,recipientUid:job.requestedByUid,
    status,errorCode,delivered:false,pushStatus:'pending',pushNextAttemptAt:Date.now(),createdAt:Date.now(),
  });
}

export async function registerPushToken(input:Record<string,unknown>, actor:Identity, remove=false) {
  if (actor.deviceId) throw new DomainError('permission-denied');
  const token=z.string().min(20).max(4096).parse(input.token), ref=getFirestore().doc(`device_push_tokens/${hash(token)}`);
  await getFirestore().runTransaction(async tx=>{
    const existing=await tx.get(ref);
    if (remove) {if(existing.data()?.ownerUid===actor.uid)tx.delete(ref);return;}
    tx.set(ref,{ownerUid:actor.uid,token,platform:z.enum(['android','ios','flutter']).parse(input.platform??'flutter'),updatedAt:Date.now()});
  });
  return {ok:true};
}

/** Outbox lease suppresses concurrent deliveries. FCM is at-least-once: a crash
 * after send/before ack may redeliver; stable platform tags collapse that window. */
export async function dispatchSyncCompletionNotification(ref:DocumentReference):Promise<void> {
  const db=getFirestore(), lease=randomUUID(), now=Date.now();
  const event=await db.runTransaction(async tx=>{
    const snap=await tx.get(ref), data=snap.data();
    if(!data||data.pushStatus==='sent'||data.pushStatus==='abandoned'||(data.pushLockedUntil??0)>now||(data.pushNextAttemptAt??0)>now)return null;
    tx.update(ref,{pushLease:lease,pushLockedUntil:now+120000,pushAttempts:(data.pushAttempts??0)+1});return data;
  });
  if(!event)return;
  const tokens=await db.collection('device_push_tokens').where('ownerUid','==',event.recipientUid).get();
  let retry=false;
  for(const token of tokens.docs) {
    try {
      if((await token.ref.get()).data()?.ownerUid!==event.recipientUid)continue;
      await getMessaging().send({token:token.data().token,
        notification:{title:event.status==='completed'?'IPTV sincronizada':'Falha na sincronização',body:event.status==='completed'?`Sua lista "${event.sourceName}" foi atualizada.`:`Não foi possível atualizar "${event.sourceName}".`},
        data:{jobId:event.jobId,sourceId:event.sourceId,familyId:event.familyId,recipientUid:event.recipientUid,eventType:event.status==='completed'?'sync_completed':'sync_failed'},
        android:{priority:'high',notification:{tag:event.jobId}},
        apns:{headers:{'apns-collapse-id':event.jobId},payload:{aps:{sound:'default'}}},
      });
    }catch(error:any){
      if(['messaging/registration-token-not-registered','messaging/invalid-registration-token'].includes(error.code))await token.ref.delete();
      else retry=true; // Do not log token IDs, messages or provider URLs.
    }
  }
  await db.runTransaction(async tx=>{
    const current=await tx.get(ref);if(current.data()?.pushLease!==lease)return;
    const attempts=current.data()?.pushAttempts??1;
    tx.update(ref,{pushStatus:retry?(attempts>=5?'abandoned':'pending'):'sent',pushLockedUntil:0,
      pushNextAttemptAt:Date.now()+Math.min(3600000,60000*2**attempts),pushFinishedAt:retry?null:Date.now()});
  });
}
export async function retryPushNotifications():Promise<void> {
  const events=await getFirestore().collectionGroup('sync_notifications').where('pushStatus','==','pending').where('pushNextAttemptAt','<=',Date.now()).limit(50).get();
  for(const event of events.docs)await dispatchSyncCompletionNotification(event.ref);
}
