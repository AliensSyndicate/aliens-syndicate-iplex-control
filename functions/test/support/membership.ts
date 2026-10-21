import {getFirestore} from 'firebase-admin/firestore';
import {execute,Identity} from '../../src/service';
export async function inviteAndAccept(admin:Identity,recipient:Identity) {
  const code=(await getFirestore().doc(`users/${recipient.uid}`).get()).data()!.publicCode;
  const request=await execute('requestMembership',{code},admin) as {id:string};
  await execute('respondMembership',{id:request.id,accept:true},recipient);
  const familyId=(await getFirestore().doc(`users/${admin.uid}`).get()).data()!.familyId;
  await execute('selectContext',{familyId},recipient);
  return request;
}
/** Every account owns one family from its bootstrap; tests name it instead of creating another. */
export async function createFamily(actor:Identity,name='Family') {
  const db=getFirestore(),user=await db.doc(`users/${actor.uid}`).get();
  let fid=user.data()?.familyId as string|undefined;
  if(!fid){await execute('bootstrap',{},actor);fid=(await db.doc(`users/${actor.uid}`).get()).data()!.familyId as string;}
  await db.doc(`families/${fid}`).update({name});
  return {id:fid};
}
