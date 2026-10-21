import {FieldValue,getFirestore,Transaction} from 'firebase-admin/firestore';
import {z} from 'zod';
import {DomainError,hash,idSchema} from './domain';
import {PUBLIC_CODE,limitIdentityAttempts} from './account_identity';
import {ScopeActor} from './iptv_workspace';
import {associateCount, linkedAssociateForAccount, MAX_ASSOCIATES, unlinkAccountProfiles} from './family_profiles';
import {prepareIndividual,prepareJoin,safePhotoUrl} from './family_individual';

const requireValue=(ok:unknown,code='permission-denied')=>{if(!ok)throw new DomainError(code);};
async function destination(tx:Transaction,a:ScopeActor,p:Record<string,unknown>) {
  requireValue(!a.deviceId);
  const user=(await tx.get(getFirestore().doc(`users/${a.uid}`))).data();
  const fid=idSchema.parse(p.familyId??a.contextFamilyId??user?.familyId);
  // One account, one family: the only family an account can administer is its own.
  requireValue(fid===user?.familyId);
  const ref=getFirestore().doc(`families/${fid}`),data=(await tx.get(ref)).data();
  requireValue(data&&!data.deleting&&!data.parked&&data.kind!=='personalIptv'&&data.members?.[a.uid]==='admin'&&(data.adminUid??data.adminId)===a.uid);
  return {ref,data:data!};
}
/** Removes `uid` from the family and gives the account its individual family back. */
async function detach(tx:Transaction,ref:FirebaseFirestore.DocumentReference,data:FirebaseFirestore.DocumentData,uid:string) {
  const db=getFirestore(),ur=db.doc(`users/${uid}`),u=await tx.get(ur);
  const unlink=await unlinkAccountProfiles(tx,ref,uid);
  const next=u.exists?await prepareIndividual(tx,uid,u.data()!,{exclude:ref.id}):null;
  return ()=>{
    const members={...data.members};delete members[uid];
    unlink();
    tx.update(ref,{members});
    tx.delete(ref.collection('members').doc(uid));
    tx.delete(db.doc(`family_members/${ref.id}_${uid}`));
    if(u.exists)next!.write(u.data()?.primaryFamilyId===ref.id?{primaryFamilyId:FieldValue.delete()}:{});
  };
}
export async function familyMembership(action:string,p:Record<string,unknown>,a:ScopeActor) {
  const db=getFirestore(),now=Date.now();
  requireValue(!a.deviceId);
  if(action==='createMemberLink'||action==='joinFamily')throw new DomainError('invalid-action');
  // The individual family is created at bootstrap; an account never creates another one.
  if(action==='createFamily')return db.runTransaction(async tx=>{
    const u=await tx.get(db.doc(`users/${a.uid}`));requireValue(u.exists,'account-unavailable');
    const prepared=await prepareIndividual(tx,a.uid,u.data()!);
    if(u.data()?.familyId===prepared.id)throw new DomainError('already-in-family');
    prepared.write();
    return {id:prepared.id};
  });
  // No alternation between families: the context is always the account's own family.
  if(action==='selectContext')return db.runTransaction(async tx=>{
    const u=await tx.get(db.doc(`users/${a.uid}`));requireValue(u.exists,'account-unavailable');
    const fid=p.familyId==null?null:idSchema.parse(p.familyId);
    requireValue(!fid||fid===u.data()?.familyId,'family-exclusive');
    return {ok:true};
  });
  if(action==='lookupPublicUser'||action==='requestMembership'){
    await limitIdentityAttempts(a.uid);
    const code=z.string().trim().toUpperCase().regex(PUBLIC_CODE).parse(p.code);
    return db.runTransaction(async tx=>{
      const f=await destination(tx,a,p);
      const held=(await tx.get(db.doc(`public_user_codes/${code}`))).data();
      requireValue(held?.uid&&held.uid!==a.uid,'user-unavailable');
      const target=await tx.get(db.doc(`users/${held!.uid}`));
      requireValue(target.exists&&target.data()?.publicCode===code,'user-unavailable');
      requireValue(!f.data.members[held!.uid],'already-linked');
      // The invitee must be free to move: alone in its own family (checked again on acceptance).
      const targetFamilyId=target.data()?.familyId as string|undefined,targetFamily=targetFamilyId?(await tx.get(db.doc(`families/${targetFamilyId}`))).data():undefined;
      requireValue(!targetFamily||targetFamily.deleting||targetFamily.parked||(Object.keys(targetFamily.members??{}).length<=1&&targetFamily.members?.[held!.uid]==='admin'),'user-unavailable');
      requireValue(Object.keys(f.data.members).length<5&&(await associateCount(tx,f.ref))<MAX_ASSOCIATES,'family-limit');
      const name=String(target.data()?.name??target.data()?.displayName??'').slice(0,80);
      if(action==='lookupPublicUser')return {code,name};
      const ref=db.doc(`family_requests/${hash(`${f.ref.id}:${held!.uid}`)}`),old=(await tx.get(ref)).data();
      if(old?.status==='pending'&&old.expiresAt>now)return {id:ref.id};
      const photoUrl=safePhotoUrl(target.data()?.photoUrl);
      tx.set(ref,{familyId:f.ref.id,familyName:f.data.name,issuerUid:a.uid,recipientUid:held!.uid,recipientName:name,...(photoUrl?{recipientPhotoUrl:photoUrl}:{}),status:'pending',createdAt:now,expiresAt:now+7*86400000});
      return {id:ref.id};
    });
  }
  if(action==='respondMembership')return db.runTransaction(async tx=>{
    const ref=db.doc(`family_requests/${idSchema.parse(p.id)}`),request=(await tx.get(ref)).data();
    requireValue(request&&request.recipientUid===a.uid);
    const accept=z.boolean().parse(p.accept);
    if(request!.status===(accept?'accepted':'declined'))return {ok:true};
    requireValue(request!.status==='pending'&&request!.expiresAt>now,'invitation-expired');
    if(!accept){tx.update(ref,{status:'declined',respondedAt:now});return {ok:true};}
    const fr=db.doc(`families/${request!.familyId}`),ur=db.doc(`users/${a.uid}`);
    const [f,u]=await tx.getAll(fr,ur),data=f!.data();
    requireValue(u!.exists,'account-unavailable');
    requireValue(data&&!data.deleting&&!data.parked&&data.kind!=='personalIptv'&&(data.adminUid??data.adminId)===request!.issuerUid&&data.members?.[request!.issuerUid]==='admin','invitation-expired');
    const others=await tx.get(db.collection('family_requests').where('recipientUid','==',a.uid).where('status','==','pending'));
    const join=await prepareJoin(tx,a.uid,u!.data()!,{ref:fr,data:data!},now);
    const writeProfile=await linkedAssociateForAccount(tx,fr,a.uid,u!.data()?.name??'',now);
    join();
    writeProfile();
    // The account now has its one family: every other pending invitation is void.
    others.docs.filter(d=>d.id!==ref.id).forEach(d=>tx.update(d.ref,{status:'cancelled',respondedAt:now}));
    tx.update(ref,{status:'accepted',respondedAt:now});
    return {ok:true};
  });
  if(action==='cancelMembershipRequest')return db.runTransaction(async tx=>{
    const f=await destination(tx,a,p),ref=db.doc(`family_requests/${idSchema.parse(p.id)}`),request=(await tx.get(ref)).data();
    requireValue(request&&request.familyId===f.ref.id);
    if(request!.status==='pending')tx.update(ref,{status:'cancelled',respondedAt:now});
    return {ok:true};
  });
  if(action==='removeMember')return db.runTransaction(async tx=>{
    const f=await destination(tx,a,p),uid=idSchema.parse(p.id);
    requireValue(uid!==(f.data.adminUid??f.data.adminId),'administrator-protected');requireValue(f.data.members[uid],'not-found');
    (await detach(tx,f.ref,f.data,uid))();
    return {ok:true};
  });
  // A member leaves on its own; the administrator cannot (it would orphan the family).
  if(action==='leaveFamily')return db.runTransaction(async tx=>{
    const u=await tx.get(db.doc(`users/${a.uid}`));requireValue(u.exists,'account-unavailable');
    const ref=db.doc(`families/${idSchema.parse(u.data()?.familyId)}`),data=(await tx.get(ref)).data();
    requireValue(data&&!data.deleting&&data.members?.[a.uid],'not-found');
    requireValue((data!.adminUid??data!.adminId)!==a.uid,'administrator-protected');
    (await detach(tx,ref,data!,a.uid))();
    return {ok:true};
  });
  throw new DomainError('invalid-action');
}
