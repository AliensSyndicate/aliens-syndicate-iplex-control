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
