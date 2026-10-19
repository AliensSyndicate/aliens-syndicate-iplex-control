import {getFirestore,Transaction} from 'firebase-admin/firestore';
import {DomainError} from './domain';

export type ScopeActor={uid:string;deviceId?:string;contextFamilyId?:string|null};
/** Existing namespace retained for compatibility; personalIptv is a private
 * resource scope, never a family membership. Initialize only after all reads. */
export async function iptvWorkspace(tx:Transaction,actor:ScopeActor,create=false,manage=true) {
  if(actor.deviceId)throw new DomainError('permission-denied');
  const db=getFirestore(),account=db.doc(`users/${actor.uid}`),snap=await tx.get(account);
  if(!snap.exists)throw new DomainError('account-unavailable');
  const user=snap.data()!,personal=user.iptvWorkspaceId as string|undefined;
  // Explicit context for new clients. Preserve legacy IPTV preference otherwise.
  const requested=actor.contextFamilyId;
  const id=requested===undefined?(personal??user.familyId):(requested??personal);
  if(id){
    const ref=db.doc(`families/${id}`),data=(await tx.get(ref)).data();
    if(!data||data.deleting||!data.members?.[actor.uid]||
      (manage&&(data.adminUid??data.adminId)!==actor.uid))throw new DomainError('permission-denied');
    if(data.kind==='personalIptv'&&(data.ownerId!==actor.uid||id!==personal))throw new DomainError('permission-denied');
    if(requested&&data.kind==='personalIptv')throw new DomainError('permission-denied');
    return {fid:id as string,ref,data,initialize:()=>{}};
  }
  if(!create)throw new DomainError('not-found');
  const ref=db.collection('families').doc();
  const data={kind:'personalIptv',ownerId:actor.uid,adminId:actor.uid,members:{[actor.uid]:'admin'},leases:[],createdAt:Date.now()};
  return {fid:ref.id,ref,data,initialize:()=>{
    tx.create(ref,data);
    tx.update(account,{iptvWorkspaceId:ref.id});
  }};
}
