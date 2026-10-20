import {FieldValue,getFirestore,Transaction} from 'firebase-admin/firestore';
import {z} from 'zod';
import {addMember,DomainError,hash,idSchema,nameSchema} from './domain';
import {PUBLIC_CODE,limitIdentityAttempts} from './account_identity';
import {ScopeActor} from './iptv_workspace';
import {associateCount, linkedAssociateForAccount, MAX_ASSOCIATES, unlinkAccountProfiles, writeAdminProfile} from './family_profiles';

const requireValue=(ok:unknown,code='permission-denied')=>{if(!ok)throw new DomainError(code);};
async function destination(tx:Transaction,a:ScopeActor,p:Record<string,unknown>) {
  requireValue(!a.deviceId);
  const user=(await tx.get(getFirestore().doc(`users/${a.uid}`))).data();
  const fid=idSchema.parse(p.familyId??a.contextFamilyId??user?.familyId);
  const ref=getFirestore().doc(`families/${fid}`),data=(await tx.get(ref)).data();
  requireValue(data&&!data.deleting&&data.kind!=='personalIptv'&&data.members?.[a.uid]==='admin'&&(data.adminUid??data.adminId)===a.uid);
  return {ref,data:data!};
}
export async function familyMembership(action:string,p:Record<string,unknown>,a:ScopeActor) {
  const db=getFirestore(),now=Date.now();
  requireValue(!a.deviceId);
  if(action==='createMemberLink'||action==='joinFamily')throw new DomainError('invalid-action');
  if(action==='createFamily')return db.runTransaction(async tx=>{
    const ur=db.doc(`users/${a.uid}`),u=await tx.get(ur);requireValue(u.exists,'account-unavailable');
    const name=nameSchema.parse(p.name),ref=db.collection('families').doc();
    tx.create(ref,{name,adminId:a.uid,ownerId:a.uid,members:{[a.uid]:'admin'},leases:[],createdAt:now});
    tx.update(ur,{familyIds:FieldValue.arrayUnion(...[u.data()?.familyId,ref.id].filter(Boolean)),familyId:ref.id,primaryFamilyId:FieldValue.delete()});
    tx.set(ref.collection('members').doc(a.uid),{uid:a.uid,name:u.data()?.name??name,role:'admin'});
    tx.set(ref.collection('private').doc('subscription'),{status:'notStarted'});
    writeAdminProfile(tx,ref,a.uid,u.data()?.name??'',now);
    return {id:ref.id};
  });
  if(action==='selectContext')return db.runTransaction(async tx=>{
    const ur=db.doc(`users/${a.uid}`),u=await tx.get(ur);requireValue(u.exists,'account-unavailable');
    const fid=p.familyId==null?null:idSchema.parse(p.familyId);
    if(fid){
      const f=(await tx.get(db.doc(`families/${fid}`))).data();
      requireValue(f&&!f.deleting&&f.kind!=='personalIptv'&&f.members?.[a.uid]);
    }
    tx.update(ur,{familyId:fid??FieldValue.delete(),primaryFamilyId:FieldValue.delete()});
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
      requireValue(Object.keys(f.data.members).length<5&&(await associateCount(tx,f.ref))<MAX_ASSOCIATES,'family-limit');
      const name=String(target.data()?.name??target.data()?.displayName??'').slice(0,80);
      if(action==='lookupPublicUser')return {code,name};
      const ref=db.doc(`family_requests/${hash(`${f.ref.id}:${held!.uid}`)}`),old=(await tx.get(ref)).data();
      if(old?.status==='pending'&&old.expiresAt>now)return {id:ref.id};
      tx.set(ref,{familyId:f.ref.id,familyName:f.data.name,issuerUid:a.uid,recipientUid:held!.uid,status:'pending',createdAt:now,expiresAt:now+7*86400000});
      return {id:ref.id};
    });
  }
  if(action==='respondMembership')return db.runTransaction(async tx=>{
    const ref=db.doc(`family_requests/${idSchema.parse(p.id)}`),request=(await tx.get(ref)).data();
    requireValue(request&&request.recipientUid===a.uid);
    const accept=z.boolean().parse(p.accept);
    if(request!.status===(accept?'accepted':'declined'))return {ok:true};
    requireValue(request!.status==='pending'&&request!.expiresAt>now,'invitation-expired');
    const fr=db.doc(`families/${request!.familyId}`),ur=db.doc(`users/${a.uid}`);
    const [f,u]=await tx.getAll(fr,ur),data=f!.data();
    requireValue(u!.exists,'account-unavailable');
    if(accept){
      requireValue(data&&!data.deleting&&data.kind!=='personalIptv'&&(data.adminUid??data.adminId)===request!.issuerUid&&data.members?.[request!.issuerUid]==='admin','invitation-expired');
      const members=addMember(data!.members,a.uid);
      const writeProfile=await linkedAssociateForAccount(tx,fr,a.uid,u!.data()?.name??'',now);
      tx.update(fr,{members});
      writeProfile();
      // First family of an account becomes its active context; otherwise the Control
      // only lists families when there are two or more and the accepted one is unreachable.
      tx.update(ur,{familyIds:FieldValue.arrayUnion(...[u!.data()?.familyId,fr.id].filter(Boolean)),...(u!.data()?.familyId?{}:{familyId:fr.id})});
      tx.set(fr.collection('members').doc(a.uid),{uid:a.uid,name:u!.data()?.name??'',role:'member'});
    }
    tx.update(ref,{status:accept?'accepted':'declined',respondedAt:now});
    return {ok:true};
  });
  if(action==='removeMember')return db.runTransaction(async tx=>{
    const f=await destination(tx,a,p),uid=idSchema.parse(p.id);
    requireValue(uid!==(f.data.adminUid??f.data.adminId),'administrator-protected');requireValue(f.data.members[uid],'not-found');
    const ur=db.doc(`users/${uid}`),u=await tx.get(ur);
    const unlink=await unlinkAccountProfiles(tx,f.ref,uid);
    const members={...f.data.members};delete members[uid];
    unlink();
    tx.update(f.ref,{members});
    if(u.exists)tx.update(ur,{familyIds:FieldValue.arrayRemove(f.ref.id),
      ...(u.data()?.familyId===f.ref.id?{familyId:FieldValue.delete()}:{}),
      ...(u.data()?.primaryFamilyId===f.ref.id?{primaryFamilyId:FieldValue.delete()}:{}),
    });
    tx.delete(f.ref.collection('members').doc(uid));
    tx.delete(db.doc(`family_members/${f.ref.id}_${uid}`));
    return {ok:true};
  });
  throw new DomainError('invalid-action');
}
