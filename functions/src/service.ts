import {calculateCanonicalDeviceId, calculateIdentityFingerprint, maskIdentityFingerprint, generatePairingCode, hashPairingCode, PlatformType} from './device_identity';
import {readSourceCatalog, readSourceSeries, resolveSourceStream} from './iptv_catalog_access';
import {registerPushToken} from './iptv_notifications';
import {getFirestore, FieldValue, Transaction, DocumentReference} from 'firebase-admin/firestore';
import {getStorage} from 'firebase-admin/storage';
import {getAuth} from 'firebase-admin/auth';
import {randomUUID} from 'node:crypto';
import {ensurePublicCode,limitIdentityAttempts} from './account_identity';
import {familyMembership} from './family_membership';
import {familyProfiles, profileView, requireWritableGeneration, ADMIN_PROFILE_ID} from './family_profiles';
import {listProfileSpaces} from './iptv_catalog_access';
import {obfuscatedAccount, paymentsConfig, verifyPlayPurchase} from './play_billing';
import {iptvWorkspace} from './iptv_workspace';
import {z} from 'zod';
import {saveIptvSource, syncIptvSource, verifyIptvPin, deleteIptvSource, readIptvEpg} from './iptv_sources';
import {acquire, addMember, canStartPlayback, DomainError, hash, idSchema, Lease, LEASE_MS, nameSchema, newToken, pinSchema, seal, sourceInputSchema, sourceSchema, startTrial, Subscription, TOKEN_MS, tokenSchema, unseal} from './domain';
export type Identity = {uid:string; deviceId?:string; familyId?:string; authTime?:number; contextFamilyId?:string|null};
const db=()=>getFirestore();
const required=(ok:unknown,code='permission-denied'):void=>{if(!ok)throw new DomainError(code);};
async function family(tx:Transaction,actor:Identity,admin=false,create=false) {
 required(!actor.deviceId);
 const u=await tx.get(db().doc(`users/${actor.uid}`));
 const requested=actor.contextFamilyId===undefined?u.data()?.familyId:actor.contextFamilyId;
 return iptvWorkspace(tx,{...actor,contextFamilyId:requested??null},create,admin);
}
async function player(tx:Transaction,actor:Identity) {
 required(actor.deviceId && actor.familyId && actor.uid === `tv_${actor.deviceId}`);
 const ref=db().doc(`families/${actor.familyId}`), device=db().doc(`families/${actor.familyId}/devices/${actor.deviceId}`);
 const [f,d,s]=await tx.getAll(ref,device,db().doc(`families/${actor.familyId}/private/subscription`));
 required(f!.exists&&d!.exists&&!f!.data()?.deleting,'device-revoked');
 return {ref,device,fid:actor.familyId!,data:f!.data()!,deviceData:d!.data()!,subscription:s!.data() as Subscription | undefined};
}
export async function execute(action:string,input:unknown,actor:Identity|undefined,key=''):Promise<unknown> {
 const p=z.record(z.unknown()).parse(input); const now=Date.now();
 if(action==='beginDevicePair') {
  const token=newToken(); const name=nameSchema.parse(p.name);
  const platform=(p.platform as PlatformType) || 'android_tv';
  const nativeDeviceId=typeof p.nativeDeviceId==='string'?p.nativeDeviceId.trim():undefined;
  const canonicalId=nativeDeviceId?calculateCanonicalDeviceId(platform,nativeDeviceId):randomUUID();
  const fingerprint=nativeDeviceId?calculateIdentityFingerprint(platform,nativeDeviceId):'';
  const pairingCode=generatePairingCode();
  const tokenHash=hash(token);
  const sessionData={
   kind:'device',
   name,
   token,
   deviceId:canonicalId,
   platform,
   manufacturer:typeof p.manufacturer==='string'?p.manufacturer:'',
   model:typeof p.model==='string'?p.model:'',
   nativeIdentityFingerprint:fingerprint,
   identitySource:typeof p.identitySource==='string'?p.identitySource:'standard',
   identityScope:typeof p.identityScope==='string'?p.identityScope:'app_scoped',
   identityStability:typeof p.identityStability==='string'?p.identityStability:'os_reinstall_stable',
   code:pairingCode.code,
   formattedCode:pairingCode.formatted,
   pairingCodeHash:pairingCode.hash,
   expiresAt:now+TOKEN_MS,
   used:false,
   claimed:false,
   createdAt:now
  };
  await Promise.all([
   db().doc(`link_tokens/${tokenHash}`).set(sessionData),
   db().doc(`device_pairing_sessions/${tokenHash}`).set(sessionData),
   db().doc(`device_pairing_codes/${pairingCode.hash}`).set({tokenHash,expiresAt:now+TOKEN_MS})
  ]);
  return {token,code:pairingCode.code,formattedCode:pairingCode.formatted,deviceId:canonicalId,expiresAt:now+TOKEN_MS};
 }
 if(action==='finishDevicePair') {
  const token=tokenSchema.parse(p.token), ref=db().doc(`link_tokens/${hash(token)}`);
  const data=await db().runTransaction(async tx=>{
   const snap=await tx.get(ref), d=snap.data(); required(d&&d.kind==='device'&&d.expiresAt>now&&d.used&&!d.claimed,'invalid-token');
   tx.update(ref,{claimed:true});
   tx.set(db().doc(`device_pairing_sessions/${hash(token)}`),{claimed:true,completedAt:now},{merge:true});
   return d!;
  });
  // A failed token mint requires pairing again; tokens are never reusable.
  return {customToken:await getAuth().createCustomToken(`tv_${data.deviceId}`,{deviceId:data.deviceId,familyId:data.familyId})};
 }
 required(actor,'unauthenticated'); const a:Identity={...actor!,
  ...(!actor!.deviceId&&Object.prototype.hasOwnProperty.call(p,'contextFamilyId')?
    {contextFamilyId:p.contextFamilyId===null?null:idSchema.parse(p.contextFamilyId)}:{}),
 };
 if(action==='bootstrap') {
  required(!a.deviceId); const user=await getAuth().getUser(a.uid);
  await ensurePublicCode(a.uid,{uid:a.uid,name:user.displayName??'',email:user.email??'',updatedAt:now});
  return {ok:true};
 }
 if(['createFamily','selectContext','createMemberLink','joinFamily','removeMember','lookupPublicUser','requestMembership','respondMembership'].includes(action))return familyMembership(action,p,a);
 if(['saveProfile','setGuestEnabled','setProfilePermissions','createProfileLinkCode','redeemProfileLink','unlinkProfileAccount','clearProfileData'].includes(action)){
  required(!a.deviceId);
  return familyProfiles(action,p,a.uid,(tx,admin,create)=>family(tx,a,admin,create));
 }
 if(action==='deleteProfile'){
  // 1) Bump every generation so no device can write into the profile while it goes away.
  const target=await db().runTransaction(async tx=>{
   const f=await family(tx,a,true), id=idSchema.parse(p.id),ref=f.ref.collection('profiles').doc(id),snap=await tx.get(ref);
   required(snap.exists,'not-found');
   required(id!==ADMIN_PROFILE_ID&&snap.data()?.type!=='admin','administrator-protected');
   required(!((f.data.leases??[]) as Lease[]).some(x=>x.profileId===id&&x.expiresAt>now),'profile-in-use');
   const g=profileView(id,snap.data()!).generations;
   tx.update(ref,{generations:{favorites:g.favorites+1,watched:g.watched+1,progress:g.progress+1},deleting:true,updatedAt:now});
   return {fid:f.fid,ref,id};
  });
  // 2) Delete the personal media data for real (subcollections and legacy top-level copies).
  try{
   for(const legacy of ['profile_favorites','profile_progress']){
    const rows=await db().collection(legacy).where('familyId','==',target.fid).where('profileId','==',target.id).get();
    for(let i=0;i<rows.size;i+=400){const b=db().batch();rows.docs.slice(i,i+400).forEach(d=>b.delete(d.ref));await b.commit();}
   }
   // Descendants first, the profile document last: a partial failure keeps it retryable.
   await db().recursiveDelete(target.ref);
  }catch{throw new DomainError('clear-failed');}
  // 3) Release the account link last; a retry after a failure above finds the profile again.
  await db().runTransaction(async tx=>{
   const links=await tx.get(db().collection(`families/${target.fid}/profile_links`).where('profileId','==',target.id));
   links.docs.forEach(d=>tx.delete(d.ref));
  });
  return {id:target.id};
 }
 if(action==='listPlayerProfiles')return db().runTransaction(async tx=>{
  const f=await player(tx,a);
  const docs=(await tx.get(f.ref.collection('profiles'))).docs,rows=docs.map(d=>profileView(d.id,d.data())),profilesDeleting=docs.map(d=>d.data().deleting===true);
  // A disabled guest keeps its configuration but is not offered on the TV.
  return {profiles:rows.filter((x,i)=>(x.type!=='guest'||x.enabled)&&!profilesDeleting[i]).map(x=>({id:x.id,name:x.name,type:x.type,generations:x.generations,permissionsVersion:x.permissionsVersion}))};
 });
 if(action==='listProfileSpaces')return listProfileSpaces(p,a);
 if(action==='getPaymentsConfig'){required(!a.deviceId);return {...await paymentsConfig(a.uid),obfuscatedAccountId:obfuscatedAccount(a.uid)};}
 if(action==='verifyPlayPurchase'){
  // Playback rights belong to the scope's administrator (family admin or personal owner).
  const scope=await db().runTransaction(tx=>family(tx,a,true,false));
  return verifyPlayPurchase(p,a.uid,scope.fid);
 }
 if(action==='inspectPairingSession') {
  let tokenHash: string | undefined;
  if(typeof p.token === 'string' && p.token) {
   tokenHash = hash(tokenSchema.parse(p.token));
  } else if(typeof p.code === 'string' && p.code) {
   // Six digits are guessable: every manual-code lookup is charged before reading.
   required(!a.deviceId);
   await limitIdentityAttempts(a.uid,'pairing');
   const codeHash = hashPairingCode(p.code);
   const codeSnap = await db().doc(`device_pairing_codes/${codeHash}`).get();
   required(codeSnap.exists, 'invalid-token');
   required((codeSnap.data()?.expiresAt ?? 0) > now, 'pairing-expired');
   tokenHash = codeSnap.data()?.tokenHash;
  }
  required(tokenHash, 'invalid-token');
  const snap = await db().doc(`device_pairing_sessions/${tokenHash}`).get();
  const d = snap.data()!;
  required(d && d.kind === 'device', 'invalid-token');
  required(!d.used && d.expiresAt > now, 'pairing-expired');
  
  const actorUser = await db().doc(`users/${a.uid}`).get();
  required(!a.deviceId);
  const actorFamilyId = a.contextFamilyId===undefined?(actorUser.data()?.familyId??actorUser.data()?.iptvWorkspaceId):(a.contextFamilyId??actorUser.data()?.iptvWorkspaceId);
  const canonicalId = d.deviceId || snap.id;
  
  const existingDevice = await db().doc(`devices/${canonicalId}`).get();
  const isLinked = existingDevice.exists && !!existingDevice.data()?.familyId;
  const currentFamilyId = isLinked ? existingDevice.data()?.familyId : null;
  const isSameFamily = isLinked && currentFamilyId === actorFamilyId;
  
  return {
   token: d.token,
   deviceId: canonicalId,
   displayName: d.name,
   platform: d.platform ?? 'android_tv',
   manufacturer: d.manufacturer ?? '',
   model: d.model ?? '',
   nativeIdentityMasked: maskIdentityFingerprint(canonicalId),
   fingerprint: d.nativeIdentityFingerprint ?? '',
   identitySource: d.identitySource ?? 'standard',
   identityStability: d.identityStability ?? 'os_reinstall_stable',
   isAlreadyLinked: isLinked,
   isSameFamily,
   // Do not disclose the other owner’s scope.
   currentFamilyId: isSameFamily ? currentFamilyId : null,
  };
 }
 if(action==='linkDevice')return db().runTransaction(async tx=>{
  const f=await family(tx,a,true,true);
  let tokenHash: string | undefined;
  if(typeof p.token === 'string' && p.token) {
   tokenHash = hash(tokenSchema.parse(p.token));
  } else if(typeof p.code === 'string' && p.code) {
   const codeHash = hashPairingCode(p.code);
   const codeSnap = await tx.get(db().doc(`device_pairing_codes/${codeHash}`));
   required(codeSnap.exists, 'invalid-token');
   required((codeSnap.data()?.expiresAt ?? 0) > now, 'pairing-expired');
   tokenHash = codeSnap.data()?.tokenHash;
  }
  required(tokenHash, 'invalid-token');

  const tr=db().doc(`link_tokens/${tokenHash}`),sr=f.ref.collection('private').doc('subscription');
  const [t,s]=await tx.getAll(tr,sr),d=t!.data();required(d&&d.kind==='device','invalid-token');
  required(!d!.used&&d!.expiresAt>now,'pairing-expired');
  
  const canonicalId = (d!.deviceId || d!.playerId || f.ref.collection('devices').doc().id) as string;
  const topRef = db().doc(`devices/${canonicalId}`);
  const topSnap = await tx.get(topRef);
  if(topSnap.exists && topSnap.data()?.familyId && topSnap.data()?.familyId !== f.fid) {
   throw new DomainError('device-already-linked-elsewhere');
  }

  const legacyRef = f.ref.collection('devices').doc(canonicalId);
  const deviceData = {
   deviceId: canonicalId,
   familyId: f.fid,
   ownerId: f.data.ownerId??f.data.adminId,
   ownership: f.data.kind==='personalIptv'?'personal':'family',
   displayName: nameSchema.parse(p.name ?? d!.displayName ?? d!.name),
   name: nameSchema.parse(p.name ?? d!.displayName ?? d!.name),
   platform: d!.platform ?? 'android_tv',
   manufacturer: d!.manufacturer ?? '',
   model: d!.model ?? '',
   nativeIdentityFingerprint: d!.nativeIdentityFingerprint ?? '',
   identitySource: d!.identitySource ?? 'standard',
   identityScope: d!.identityScope ?? 'app_scoped',
   identityStability: d!.identityStability ?? 'os_reinstall_stable',
   linkedAt: now,
   linkedByUid: a.uid,
   status: 'linked',
   lastSeenAt: topSnap.data()?.lastSeenAt ?? 0,
   onlineUntil: topSnap.data()?.onlineUntil ?? 0,
   sessionId: topSnap.data()?.sessionId ?? null,
   createdAt: topSnap.data()?.createdAt ?? now,
   updatedAt: now,
  };

  f.initialize();
  tx.set(topRef, deviceData, {merge: true});
  tx.set(legacyRef, deviceData, {merge: true});
  tx.update(tr, {used: true, familyId: f.fid, deviceId: canonicalId, claimedByUid: a.uid, completedAt: now});
  tx.set(db().doc(`device_pairing_sessions/${tokenHash}`), {used: true, familyId: f.fid, deviceId: canonicalId, claimedByUid: a.uid, completedAt: now}, {merge: true});
  tx.set(sr, startTrial(s!.data() as Subscription, now));
  return {id: canonicalId, displayName: deviceData.displayName, platform: deviceData.platform, status: 'linked'};
 });
 if(action==='renameDevice'||action==='deleteDevice')return db().runTransaction(async tx=>{
  const f=await family(tx,a,true),id=idSchema.parse(p.id);
  const legacyRef=f.ref.collection('devices').doc(id);
  const topRef=db().doc(`devices/${id}`);
  const [d, topSnap]=await tx.getAll(legacyRef, topRef);
  required(d!.exists || topSnap!.exists,'not-found');
  required(!topSnap!.exists || topSnap!.data()?.familyId===f.fid);
  required(d!.exists,'not-found');
  if(action==='renameDevice') {
   const newName = nameSchema.parse(p.name);
   if (d!.exists) tx.update(legacyRef, {name: newName, displayName: newName, updatedAt: now});
   if (topSnap!.exists) tx.update(topRef, {name: newName, displayName: newName, updatedAt: now});
  } else {
   if (d!.exists) tx.delete(legacyRef);
   if (topSnap!.exists) tx.set(topRef, {status: 'unlinked', familyId: FieldValue.delete(), updatedAt: now}, {merge: true});
   tx.update(f.ref, {leases: ((f.data.leases??[]) as Lease[]).filter(x=>x.deviceId!==id)});
  }
  return {ok:true};
 });
 if(action==='acquireSession'||action==='heartbeat'||action==='releaseSession')return db().runTransaction(async tx=>{
  const f=await player(tx,a);let leases=((f.data.leases??[]) as Lease[]).filter(x=>x.expiresAt>now);
  if(action==='acquireSession') {
   if(!canStartPlayback(f.subscription,now))throw new DomainError('subscription-required',{plansRoute:'/account/subscription'});
   const profileId=idSchema.parse(p.profileId);const profile=await tx.get(f.ref.collection('profiles').doc(profileId));required(profile.exists,'not-found');
   required(profileView(profileId,profile.data()!).enabled,'profile-disabled');
   const lease={id:randomUUID(),deviceId:a.deviceId!,deviceName:f.deviceData.name,profileId,expiresAt:now+LEASE_MS};leases=acquire(leases,lease,now);
   tx.update(f.ref,{leases});tx.update(f.device,{sessionId:lease.id,lastSeenAt:now,onlineUntil:lease.expiresAt});return lease;
  }
  const sessionId=idSchema.parse(p.sessionId), current=leases.find(x=>x.deviceId===a.deviceId&&x.id===sessionId);required(current,'session-expired');
  if(action==='releaseSession')leases=leases.filter(x=>x.id!==sessionId);
  else {if(!canStartPlayback(f.subscription,now))throw new DomainError('subscription-required',{plansRoute:'/account/subscription'});leases=leases.map(x=>x.id===sessionId?{...x,expiresAt:now+LEASE_MS}:x);}
  tx.update(f.ref,{leases});tx.update(f.device,{sessionId:action==='releaseSession'?null:sessionId,lastSeenAt:now,onlineUntil:action==='releaseSession'?0:now+LEASE_MS});return {ok:true};
 });
 if(action==='sendCommand')return db().runTransaction(async tx=>{
  const f=await family(tx,a),id=idSchema.parse(p.deviceId),sessionId=idSchema.parse(p.sessionId),commandId=idSchema.parse(p.commandId);
  const type=z.enum(['up','down','left','right','ok','back','playPause']).parse(p.commandType);
  const device=f.ref.collection('devices').doc(id),ref=device.collection('commands').doc(commandId);
  const [d,c]=await tx.getAll(device,ref);required(d!.exists,'not-found');
  required(((f.data.leases??[]) as Lease[]).some(x=>x.deviceId===id&&x.id===sessionId&&x.expiresAt>now),'device-offline');
  if(c!.exists){required(c!.data()?.senderId===a.uid&&c!.data()?.sessionId===sessionId&&c!.data()?.commandType===type,'invalid-command');return {commandId};}
  required(now-(d!.data()?.lastCommandAt??0)>=80,'rate-limited');
  tx.create(ref,{commandId,deviceId:id,sessionId,commandType:type,timestamp:now,expiresAt:now+5000,senderId:a.uid,status:'sent',deleteAfter:new Date(now+86400000)});tx.update(device,{lastCommandAt:now});return {commandId};
 });
 if(action==='ackCommand')return db().runTransaction(async tx=>{
  const f=await player(tx,a),ref=f.device.collection('commands').doc(idSchema.parse(p.commandId)),c=await tx.get(ref),d=c!.data();
  required(d&&d.sessionId===p.sessionId&&d.expiresAt>now&&d.status==='sent','invalid-command');required(((f.data.leases??[]) as Lease[]).some(x=>x.id===p.sessionId&&x.deviceId===a.deviceId),'session-expired');tx.update(ref,{status:'acknowledged',acknowledgedAt:now});return {ok:true};
 });
 if(action==='readSourceCatalog')return readSourceCatalog(p,a);
 if(action==='readSourceSeries')return readSourceSeries(p,a);
 if(action==='resolveSourceStream')return resolveSourceStream(p,a,key);
 if(action==='registerPushToken'||action==='unregisterPushToken')return registerPushToken(p,a,action==='unregisterPushToken');
 if(action==='readSourceEpg')return readIptvEpg(p,a);
 if(action==='saveSource')return saveIptvSource(p,a,key);
 if(action==='syncSource')return syncIptvSource(p,a);
 if(action==='verifySourcePin')return verifyIptvPin(p,a,key);
 if(action==='deleteSource')return deleteIptvSource(p,a);
 if(action==='savePreferences') {
  required(!a.deviceId);const locale=z.enum(['system','en','pt_BR','es']).parse(p.locale);await db().doc(`users/${a.uid}`).set({locale},{merge:true});return {ok:true};
 }
 if(action==='favorite'||action==='watchProgress'||action==='markWatched')return db().runTransaction(async tx=>{
  const f=a.deviceId?await player(tx,a):await family(tx,a);const profileId=idSchema.parse(p.profileId),contentId=idSchema.parse(p.contentId);const profile=f.ref.collection('profiles').doc(profileId);const snap=await tx.get(profile);required(snap.exists,'not-found');
  if(a.deviceId)required(((f.data.leases??[]) as Lease[]).some(x=>x.deviceId===a.deviceId&&x.profileId===profileId&&x.expiresAt>now),'session-expired');
  const view=profileView(profileId,snap.data()!);
  if(action==='favorite') {
   const ref=profile.collection('favorites').doc(contentId);
   if(p.remove===true){required(view.type!=='guest','guest-not-persisted');tx.delete(ref);}
   else {const generation=requireWritableGeneration(view,'favorites',p.generation);tx.set(ref,{contentId,title:nameSchema.parse(p.title),generation,updatedAt:now},{merge:true});}
  } else if(action==='markWatched') {
   const generation=requireWritableGeneration(view,'watched',p.generation);
   tx.set(profile.collection('watched').doc(contentId),{contentId,title:p.title===undefined?null:nameSchema.parse(p.title),generation,completedAt:now});
  } else {
   const generation=requireWritableGeneration(view,'progress',p.generation);
   const position=z.number().finite().min(0).parse(p.position),duration=z.number().finite().positive().parse(p.duration);required(position<=duration,'invalid-argument');
   tx.set(profile.collection('watch_progress').doc(contentId),{contentId,position,duration,generation,updatedAt:now});
   // Completion feeds "Assistidos" only with the caller's current watched generation.
   if(position/duration>=0.9&&p.watchedGeneration!==undefined&&p.watchedGeneration===view.generations.watched)
    tx.set(profile.collection('watched').doc(contentId),{contentId,title:null,generation:view.generations.watched,completedAt:now});
  }
  return {ok:true};
 });
 if(action==='prepareDeletion')return db().runTransaction(async tx=>{
  required(!a.deviceId);required(a.authTime && now-a.authTime*1000<300000,'requires-recent-login');
  const ur=db().doc(`users/${a.uid}`),u=await tx.get(ur);const fid=u!.data()?.familyId;
  required(u.exists,'not-found');
  const ids=Array.from(new Set<string>([...(u.data()?.familyIds??[]),fid].filter(Boolean)));
  const families=await Promise.all(ids.map(async id=>{const ref=db().doc(`families/${id}`);return {ref,data:(await tx.get(ref)).data()};}));
  const owned:string[]=[];
  for(const {ref,data} of families)if(data&&(data.adminUid??data.adminId)===a.uid){
    required(Object.keys(data.members??{}).filter(uid=>uid!==a.uid).length===0,'family-has-members');owned.push(ref.id);
  }
  const workspaceId=u.data()?.iptvWorkspaceId as string|undefined;
  const workspace=workspaceId?db().doc(`families/${workspaceId}`):undefined;
  if(workspace){const data=(await tx.get(workspace)).data();required(data?.kind==='personalIptv'&&data.ownerId===a.uid);}
  // Families where the account is only an associate: its profile link must not outlive the account.
  const links=await Promise.all(families.map(async ({ref,data})=>{
    if(!data||owned.includes(ref.id))return undefined;
    const pid=(await tx.get(ref.collection('profile_links').doc(a.uid))).data()?.profileId as string|undefined;
    return pid&&(await tx.get(ref.collection('profiles').doc(pid))).exists?pid:undefined;
  }));
  families.forEach(({ref,data},i)=>{
    if(!data)return;
    if(owned.includes(ref.id))tx.update(ref,{members:{},deleting:true,leases:[]});
    else {
      const members={...data.members};delete members[a.uid];tx.update(ref,{members});tx.delete(ref.collection('members').doc(a.uid));
      tx.delete(ref.collection('profile_links').doc(a.uid));
      if(links[i])tx.update(ref.collection('profiles').doc(links[i]!),{linkedUid:null,updatedAt:now});
    }
  });
  if(workspace)tx.update(workspace,{members:{},deleting:true,leases:[]});
  tx.set(db().doc(`deletion_jobs/${a.uid}`),{familyId:owned[0]??null,familyIds:owned,iptvWorkspaceId:workspaceId??null,createdAt:now,status:'pending'});tx.delete(ur);return {ok:true};
 });
 throw new DomainError('invalid-action');
}
