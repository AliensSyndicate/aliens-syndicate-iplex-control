import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {execute,Identity} from '../src/service';
import {ensurePublicCode} from '../src/account_identity';
import {authPhotoUrl,safePhotoUrl} from '../src/family_individual';
import {TRIAL_MS} from '../src/domain';
let app:ReturnType<typeof initializeApp>,seq=0;
before(()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST)throw new Error('Emulators required');
 app=initializeApp({projectId:'demo-iplex'});
});
after(()=>deleteApp(app));
const db=()=>getFirestore();
async function account(photoURL?:string){const a:Identity={uid:`contexts_${++seq}`,authTime:Math.floor(Date.now()/1000)};await getAuth().createUser({uid:a.uid,displayName:'Public name',...(photoURL?{photoURL}:{})});await execute('bootstrap',{},a);return a;}
const user=(a:Identity)=>db().doc(`users/${a.uid}`);
const familyOf=async(a:Identity)=>(await user(a).get()).data()!.familyId as string;
const family=(fid:string)=>db().doc(`families/${fid}`);
async function request(a:Identity,to:Identity,fid?:string){return await execute('requestMembership',{code:(await user(to).get()).data()!.publicCode,...(fid?{familyId:fid}:{})},a) as {id:string};}
async function accept(id:string,a:Identity){return execute('respondMembership',{id,accept:true},a);}
async function pair(a:Identity){const p=await execute('beginDevicePair',{name:'Personal TV'},undefined) as {token:string};return execute('linkDevice',{token:p.token,contextFamilyId:null},a) as Promise<{id:string}>;}

test('signup assigns one persistent unique public code and exactly one individual family, even with concurrent starts',async()=>{
 const a=await account();
 const codes=await Promise.all(Array.from({length:8},()=>ensurePublicCode(a.uid)));
 assert.equal(new Set(codes).size,1);assert.match(codes[0]!,/^[A-Z0-9]{12}$/);
 const b=await account();assert.notEqual((await user(b).get()).data()!.publicCode,codes[0]);
 await Promise.all(Array.from({length:6},()=>execute('bootstrap',{},a)));
 const data=(await user(a).get()).data()!,fid=data.familyId as string;
 assert.ok(fid);assert.equal(data.iptvWorkspaceId,undefined);assert.equal(data.homeFamilyId,fid);assert.deepEqual(data.familyIds,[fid]);
 assert.equal((await db().collection('families').where('ownerId','==',a.uid).get()).size,1);
 const f=(await family(fid).get()).data()!;
 assert.equal(f.individual,true);assert.equal(f.adminId,a.uid);assert.deepEqual(f.members,{[a.uid]:'admin'});assert.equal(f.name,'Public name');
 assert.deepEqual((await family(fid).collection('private').doc('subscription').get()).data(),{status:'notStarted'});
 assert.equal((await family(fid).collection('profiles').doc('admin').get()).data()!.linkedUid,a.uid);
 assert.equal((await family(fid).collection('members').doc(a.uid).get()).data()!.role,'admin');
 await db().doc('users/legacy_context').set({uid:'legacy_context',name:'Legacy'});
 const backfill=await ensurePublicCode('legacy_context');assert.equal(await ensurePublicCode('legacy_context'),backfill);
});

test('existing accounts keep their data: a personal IPTV space becomes the individual family, a legacy membership stays the family',async()=>{
 const owner:Identity={uid:`legacy_space_${++seq}`},member:Identity={uid:`legacy_member_${++seq}`},admin:Identity={uid:`legacy_admin_${++seq}`};
 for(const a of [owner,member,admin])await getAuth().createUser({uid:a.uid,displayName:a.uid});
 await db().doc('families/space_x').set({kind:'personalIptv',ownerId:owner.uid,adminId:owner.uid,members:{[owner.uid]:'admin'},leases:[],createdAt:1});
 await db().doc('families/space_x/sources/s1').set({name:'Kept',version:'v'});
 await db().doc(`users/${owner.uid}`).set({uid:owner.uid,name:'Owner',iptvWorkspaceId:'space_x'});
 await execute('bootstrap',{},owner);
 const promoted=(await user(owner).get()).data()!;
 assert.equal(promoted.familyId,'space_x');assert.equal(promoted.iptvWorkspaceId,undefined);
 const space=(await family('space_x').get()).data()!;
 assert.equal(space.kind,undefined);assert.equal(space.individual,true);
 assert.equal((await family('space_x').collection('sources').doc('s1').get()).data()!.name,'Kept');
 assert.equal((await family('space_x').collection('profiles').doc('admin').get()).exists,true);
 await db().doc('families/team').set({name:'Team',adminId:admin.uid,members:{[admin.uid]:'admin',[member.uid]:'member'},leases:[],createdAt:1});
 await db().doc(`users/${member.uid}`).set({uid:member.uid,name:'Member',familyIds:['team']});
 await execute('bootstrap',{},member);
 assert.equal((await user(member).get()).data()!.familyId,'team');
 assert.equal((await db().collection('families').where('ownerId','==',member.uid).get()).size,0);
});

test('an account cannot create another family or choose a different one',async()=>{
 const a=await account(),b=await account(),own=await familyOf(a),other=await familyOf(b);
 await assert.rejects(execute('createFamily',{name:'Second'},a),/already-in-family/);
 assert.equal((await db().collection('families').where('ownerId','==',a.uid).get()).size,1);
 assert.deepEqual(await execute('selectContext',{familyId:own},a),{ok:true});
 await assert.rejects(execute('selectContext',{familyId:other},a),/family-exclusive/);
 await assert.rejects(execute('saveProfile',{name:'Denied',contextFamilyId:other},a),/permission-denied/);
 await assert.rejects(execute('requestMembership',{code:(await user(b).get()).data()!.publicCode,familyId:other},a),/permission-denied/);
 await execute('saveProfile',{name:'Mine',contextFamilyId:own},a);
});

test('personal TV CRUD is free, isolated, unlimited and starts exactly one seven-day trial',async()=>{
 const a=await account(),b=await account();
 const ds=await Promise.all(Array.from({length:4},()=>pair(a)));
 const scope=await familyOf(a);
 const sub=family(scope).collection('private').doc('subscription'),initial=(await sub.get()).data()!;
 assert.equal(initial.trialEndsAt-initial.trialStartedAt,TRIAL_MS);
 await pair(b);
 await assert.rejects(execute('renameDevice',{id:ds[0]!.id,name:'Stolen',contextFamilyId:null},b),/permission-denied/);
 await assert.rejects(execute('deleteDevice',{id:ds[0]!.id,contextFamilyId:null},b),/permission-denied/);
 await sub.update({status:'expired',trialEndsAt:1});
 await execute('renameDevice',{id:ds[0]!.id,name:'Renamed',contextFamilyId:null},a);
 assert.equal((await db().doc(`devices/${ds[0]!.id}`).get()).data()!.ownerId,a.uid);
 await execute('deleteDevice',{id:ds[0]!.id,contextFamilyId:null},a);
 await pair(a);assert.equal((await sub.get()).data()!.trialStartedAt,initial.trialStartedAt);
 const profile=await execute('saveProfile',{name:'Personal',contextFamilyId:null},a) as {id:string};
 const player={uid:`tv_${ds[1]!.id}`,deviceId:ds[1]!.id,familyId:scope,credentialVersion:(await family(scope).collection('devices').doc(ds[1]!.id).get()).data()?.credentialVersion};
 await assert.rejects(execute('acquireSession',{profileId:profile.id},player),/subscription-required/);
});

test('an accepted invitation moves the account into the family and parks the empty individual family; other invitations become void',async()=>{
 const admin=await account(),b=await account(),c=await account();
 const adminFamily=await familyOf(admin),home=await familyOf(b);
 const r=await request(admin,b),second=await request(c,b);
 const sent=(await db().doc(`family_requests/${r.id}`).get()).data()!;
 assert.equal(sent.recipientName,'Public name');assert.equal(sent.status,'pending');
 await accept(r.id,b);
 const moved=(await user(b).get()).data()!;
 assert.equal(moved.familyId,adminFamily);assert.equal(moved.homeFamilyId,home);
 assert.deepEqual(new Set(Object.keys((await family(adminFamily).get()).data()!.members)),new Set([admin.uid,b.uid]));
 assert.equal((await family(adminFamily).get()).data()!.members[b.uid],'member');
 assert.equal((await family(adminFamily).collection('members').doc(b.uid).get()).data()!.role,'member');
 const parked=(await family(home).get()).data()!;
 assert.equal(parked.parked,true);assert.deepEqual(parked.members,{});assert.equal(parked.deleting,undefined);
 assert.equal((await family(home).collection('profiles').doc('admin').get()).exists,true,'nothing was deleted');
 assert.equal((await db().doc(`family_requests/${second.id}`).get()).data()!.status,'cancelled');
 await assert.rejects(accept(second.id,b),/invitation-expired/);
 // Accepting twice is idempotent; the member has none of the administrator rights.
 await accept(r.id,b);
 await assert.rejects(execute('removeMember',{id:admin.uid},b),/permission-denied/);
 await assert.rejects(execute('requestMembership',{code:(await user(c).get()).data()!.publicCode},b),/permission-denied/);
 await assert.rejects(execute('saveProfile',{name:'No'},b),/permission-denied/);
});

test('an administrator with members, or a member, cannot be invited into a second family',async()=>{
 const a=await account(),m=await account(),other=await account();
 await accept((await request(a,m)).id,m);
 await assert.rejects(request(other,a),/user-unavailable/);
 await assert.rejects(request(other,m),/user-unavailable/);
 await assert.rejects(execute('lookupPublicUser',{code:(await user(m).get()).data()!.publicCode},other),/user-unavailable/);
});

test('invitations accepted simultaneously from two families join exactly one',async()=>{
 const x=await account(),y=await account(),c=await account();
 const rx=await request(x,c),ry=await request(y,c);
 const result=await Promise.allSettled([accept(rx.id,c),accept(ry.id,c)]);
 assert.equal(result.filter(r=>r.status==='fulfilled').length,1);
 const joined=(await user(c).get()).data()!.familyId as string;
 assert.ok([await familyOf(x),await familyOf(y)].includes(joined));
 let seen=0;for(const a of [x,y]){const members=(await family(await familyOf(a)).get()).data()!.members;if(members[c.uid])seen++;}
 assert.equal(seen,1,'the account is a member of one family only');
});

test('addressed requests require consent; duplicate requests and concurrent last-seat acceptance are safe',async()=>{
 const admin=await account(),fid=await familyOf(admin),people=await Promise.all(Array.from({length:5},()=>account()));
 const requests=await Promise.all(people.map(p=>request(admin,p)));
 assert.equal(Object.keys((await family(fid).get()).data()!.members).length,1);
 assert.equal((await request(admin,people[0]!)).id,requests[0]!.id);
 await assert.rejects(accept(requests[0]!.id,people[1]!),/permission-denied/);
 for(let i=0;i<3;i++)await accept(requests[i]!.id,people[i]!);
 const result=await Promise.allSettled([accept(requests[3]!.id,people[3]!),accept(requests[4]!.id,people[4]!)]);
 assert.equal(result.filter(x=>x.status==='fulfilled').length,1);
 assert.equal(Object.keys((await family(fid).get()).data()!.members).length,5);
 await execute('removeMember',{id:people[0]!.uid},admin);
 // The removed account's profile stays (unlinked, data kept) and still holds the seat.
 const failed=result.findIndex(x=>x.status==='rejected')+3;
 await assert.rejects(accept(requests[failed]!.id,people[failed]!),/family-limit/);
 const kept=(await db().collection(`families/${fid}/profiles`).where('type','==','regular').get()).docs.find(d=>d.data().linkedUid===null)!;
 await execute('deleteProfile',{id:kept.id,contextFamilyId:fid},admin);
 const retry=await request(admin,people[failed]!);await accept(retry.id,people[failed]!);
 assert.equal(Object.keys((await family(fid).get()).data()!.members).length,5);
 await assert.rejects(execute('createMemberLink',{},admin),/invalid-action/);
 await assert.rejects(execute('joinFamily',{token:'a'.repeat(64)},people[0]),/invalid-action/);
});

test('removal and leaving return the account to its own individual family without deleting anything',async()=>{
 const admin=await account(),b=await account(),c=await account(),adminFamily=await familyOf(admin),homeB=await familyOf(b),homeC=await familyOf(c);
 await accept((await request(admin,b)).id,b);await accept((await request(admin,c)).id,c);
 await assert.rejects(execute('removeMember',{id:admin.uid},admin),/administrator-protected/);
 await assert.rejects(execute('leaveFamily',{},admin),/administrator-protected/);
 await assert.rejects(execute('removeMember',{id:c.uid},b),/permission-denied/);
 await execute('removeMember',{id:b.uid},admin);
 assert.equal(await familyOf(b),homeB);
 const back=(await family(homeB).get()).data()!;
 assert.deepEqual(back.members,{[b.uid]:'admin'});assert.equal(back.parked,undefined);
 assert.equal((await family(adminFamily).get()).data()!.members[b.uid],undefined);
 assert.equal((await family(adminFamily).collection('members').doc(b.uid).get()).exists,false);
 assert.equal((await family(adminFamily).collection('profile_links').doc(b.uid).get()).exists,false);
 await execute('leaveFamily',{},c);
 assert.equal(await familyOf(c),homeC);assert.deepEqual((await family(homeC).get()).data()!.members,{[c.uid]:'admin'});
 const extra=await execute('saveProfile',{name:'Again'},b) as {id:string};
 // Re-invited: the restored family now holds a profile, so it is never silently abandoned.
 await assert.rejects(accept((await request(admin,b)).id,b),/individual-family-has-resources/);
 await execute('deleteProfile',{id:extra.id},b);
 await accept((await request(admin,b)).id,b);
 assert.equal(await familyOf(b),adminFamily);
});

test('lookup discloses only public minimum and charges failed guesses; decline grants nothing',async()=>{
 const a=await account(),b=await account(),home=await familyOf(b);
 const code=(await user(b).get()).data()!.publicCode;
 const found=await execute('lookupPublicUser',{code},a) as object;assert.deepEqual(Object.keys(found).sort(),['code','name']);
 const r=await request(a,b);await execute('respondMembership',{id:r.id,accept:false},b);
 assert.equal(await familyOf(b),home);assert.deepEqual((await user(b).get()).data()!.familyIds,[home]);
 assert.equal((await db().doc(`family_requests/${r.id}`).get()).data()!.status,'declined');
 for(let i=0;i<18;i++)await assert.rejects(execute('lookupPublicUser',{code:'000000000000'},a),/user-unavailable/);
 await assert.rejects(execute('lookupPublicUser',{code},a),/rate-limited/);
});

test('the administrator cancels a pending invitation; nobody else can',async()=>{
 const a=await account(),b=await account(),c=await account(),r=await request(a,b);
 await assert.rejects(execute('cancelMembershipRequest',{id:r.id},c),/permission-denied/);
 await execute('cancelMembershipRequest',{id:r.id},a);
 assert.equal((await db().doc(`family_requests/${r.id}`).get()).data()!.status,'cancelled');
 await assert.rejects(accept(r.id,b),/invitation-expired/);
});

test('deletion: an administrator with members is blocked; a member leaves its family and queues its parked family',async()=>{
 const a=await account(),b=await account(),adminFamily=await familyOf(a),home=await familyOf(b);
 await accept((await request(a,b)).id,b);
 await assert.rejects(execute('prepareDeletion',{},a),/family-has-members/);
 await execute('prepareDeletion',{},b);
 assert.equal((await family(adminFamily).get()).data()!.members[b.uid],undefined);
 const job=(await db().doc(`deletion_jobs/${b.uid}`).get()).data()!;
 assert.deepEqual(job.familyIds,[home]);
 assert.equal((await family(home).get()).data()!.deleting,true);
});

test('provider photo: stored from the sign-in, never replaced by an empty one, refreshed when it changes, mirrored for family members',async()=>{
 const photo='https://lh3.googleusercontent.com/a/photo-one';
 const a=await account(photo),fid=await familyOf(a);
 assert.equal((await user(a).get()).data()!.photoUrl,photo);
 assert.equal((await family(fid).collection('members').doc(a.uid).get()).data()!.photoUrl,photo);
 await getAuth().updateUser(a.uid,{photoURL:null});
 await execute('bootstrap',{},a);
 assert.equal((await user(a).get()).data()!.photoUrl,photo);
 const next='https://lh3.googleusercontent.com/a/photo-two';
 await getAuth().updateUser(a.uid,{photoURL:next});
 await execute('bootstrap',{},a);
 assert.equal((await user(a).get()).data()!.photoUrl,next);
 assert.equal((await family(fid).collection('members').doc(a.uid).get()).data()!.photoUrl,next);
 const noPhoto=await account();
 assert.equal((await user(noPhoto).get()).data()!.photoUrl,undefined,'Apple and photo-less accounts get the default avatar');
 // Joining keeps the photo on the new membership.
 await accept((await request(noPhoto,a)).id,a);
 assert.equal((await family(await familyOf(noPhoto)).collection('members').doc(a.uid).get()).data()!.photoUrl,next);
});

test('only https provider photos are accepted',()=>{
 assert.equal(safePhotoUrl('https://lh3.googleusercontent.com/a/x'),'https://lh3.googleusercontent.com/a/x');
 for(const bad of ['http://example.com/a.png','javascript:alert(1)','data:image/png;base64,AAAA','',null,undefined,'https://'+'a'.repeat(1100)])assert.equal(safePhotoUrl(bad),null);
 const google={photoURL:'https://old.example/a',providerData:[{providerId:'google.com',photoURL:'https://new.example/a'}]} as never;
 assert.equal(authPhotoUrl(google),'https://new.example/a');
 const apple={photoURL:undefined,providerData:[{providerId:'apple.com',photoURL:undefined}]} as never;
 assert.equal(authPhotoUrl(apple),null);
});

test('the TV receives the identity of the linked account, never a viewing profile or credentials',async()=>{
 const photo='https://lh3.googleusercontent.com/a/tv-photo';
 const a=await account(photo),plain=await account();
 for(const [owner,expected] of [[a,photo],[plain,null]] as const){
  const linked=await pair(owner),scope=await familyOf(owner);
  const player:Identity={uid:`tv_${linked.id}`,deviceId:linked.id,familyId:scope,credentialVersion:(await family(scope).collection('devices').doc(linked.id).get()).data()?.credentialVersion};
  const listed=await execute('listPlayerProfiles',{},player) as {account:{name:string;photoUrl:string|null};profiles:{id:string}[]};
  assert.deepEqual(listed.account,{name:'Public name',photoUrl:expected});
  assert.deepEqual(listed.profiles.map(p=>p.id),['admin']);
 }
});
