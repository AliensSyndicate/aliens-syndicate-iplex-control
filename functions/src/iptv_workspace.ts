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
  // Without a personal space (every account created since "one account, one family"),
  // an absent context is the account's own family.
  const requested=actor.contextFamilyId;
  const id=requested===undefined?(personal??user.familyId):(requested??personal??user.familyId);
  // One account, one family: a context other than the account's own family is refused.
  if(requested&&requested!==user.familyId&&requested!==personal)throw new DomainError('permission-denied');
  if(id){
    const ref=db.doc(`families/${id}`),data=(await tx.get(ref)).data();
    if(!data||data.deleting||!data.members?.[actor.uid]||
      (manage&&(data.adminUid??data.adminId)!==actor.uid))throw new DomainError('permission-denied');
    if(data.kind==='personalIptv'&&(data.ownerId!==actor.uid||id!==personal))throw new DomainError('permission-denied');
    if(requested&&data.kind==='personalIptv')throw new DomainError('permission-denied');
    return {fid:id as string,ref,data,initialize:()=>{}};
  }
  // The individual family is created at bootstrap; a personal space is never created again.
  void create;
  throw new DomainError('not-found');
}
