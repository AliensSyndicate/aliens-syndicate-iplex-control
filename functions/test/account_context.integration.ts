import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {execute,Identity} from '../src/service';
import {ensurePublicCode} from '../src/account_identity';
import {TRIAL_MS} from '../src/domain';
let app:ReturnType<typeof initializeApp>,seq=0;
before(()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST)throw new Error('Emulators required');
 app=initializeApp({projectId:'demo-iplex'});
});
after(()=>deleteApp(app));
async function account(){const a:Identity={uid:`contexts_${++seq}`,authTime:Math.floor(Date.now()/1000)};await getAuth().createUser({uid:a.uid,displayName:'Public name'});await execute('bootstrap',{},a);return a;}
const user=(a:Identity)=>getFirestore().doc(`users/${a.uid}`);
async function create(a:Identity){return (await execute('createFamily',{name:'Family'},a) as {id:string}).id;}
async function request(a:Identity,to:Identity,fid?:string){return await execute('requestMembership',{code:(await user(to).get()).data()!.publicCode,...(fid?{familyId:fid}:{})},a) as {id:string};}
async function accept(id:string,a:Identity){return execute('respondMembership',{id,accept:true},a);}
async function pair(a:Identity){const p=await execute('beginDevicePair',{name:'Personal TV'},undefined) as {token:string};return execute('linkDevice',{token:p.token,contextFamilyId:null},a) as Promise<{id:string}>;}

test('signup and concurrent backfill assign one persistent unique public code without family or workspace',async()=>{
 const a=await account();await user(a).update({publicCode:(await user(a).get()).data()!.publicCode});
 const codes=await Promise.all(Array.from({length:8},()=>ensurePublicCode(a.uid)));
 assert.equal(new Set(codes).size,1);assert.match(codes[0]!,/^[A-Z0-9]{12}$/);
 const b=await account();assert.notEqual((await user(b).get()).data()!.publicCode,codes[0]);
 const data=(await user(a).get()).data()!;assert.equal(data.familyId,undefined);assert.equal(data.iptvWorkspaceId,undefined);
 await getFirestore().doc('users/legacy_context').set({uid:'legacy_context',name:'Legacy'});
 const backfill=await ensurePublicCode('legacy_context');assert.equal(await ensurePublicCode('legacy_context'),backfill);
});

test('personal TV CRUD is free, isolated, unlimited and starts exactly one seven-day trial',async()=>{
 const a=await account(),b=await account();
 const ds=await Promise.all(Array.from({length:4},()=>pair(a)));
 const data=(await user(a).get()).data()!,scope=data.iptvWorkspaceId;
 assert.equal(data.familyId,undefined);
 const sub=getFirestore().doc(`families/${scope}/private/subscription`),initial=(await sub.get()).data()!;
 assert.equal(initial.trialEndsAt-initial.trialStartedAt,TRIAL_MS);
 await pair(b);
 await assert.rejects(execute('renameDevice',{id:ds[0]!.id,name:'Stolen',contextFamilyId:null},b),/permission-denied/);
 await assert.rejects(execute('deleteDevice',{id:ds[0]!.id,contextFamilyId:null},b),/permission-denied/);
 await sub.update({status:'expired',trialEndsAt:1});
 await execute('renameDevice',{id:ds[0]!.id,name:'Renamed',contextFamilyId:null},a);
 assert.equal((await getFirestore().doc(`devices/${ds[0]!.id}`).get()).data()!.ownerId,a.uid);
 await execute('deleteDevice',{id:ds[0]!.id,contextFamilyId:null},a);
 await pair(a);assert.equal((await sub.get()).data()!.trialStartedAt,initial.trialStartedAt);
 const profile=await execute('saveProfile',{name:'Personal',contextFamilyId:null},a) as {id:string};
 const player={uid:`tv_${ds[1]!.id}`,deviceId:ds[1]!.id,familyId:scope};
 await assert.rejects(execute('acquireSession',{profileId:profile.id},player),/subscription-required/);
});

test('one user administers two families, joins another, and keeps personal resource permissions',async()=>{
 const a=await account(),b=await account();const first=await create(a),second=await create(a),third=await create(b);
 const r=await request(b,a);await accept(r.id,a);
 assert.deepEqual(new Set((await user(a).get()).data()!.familyIds),new Set([first,second,third]));
 for(const id of [first,second])await execute('saveProfile',{name:'Admin',contextFamilyId:id},a);
 await assert.rejects(execute('saveProfile',{name:'Denied',contextFamilyId:third},a),/permission-denied/);
 await execute('saveProfile',{name:'Personal',contextFamilyId:null},a);
 await execute('selectContext',{familyId:third},a);
 await pair(a); // explicit personal context overrides the selected family
 await assert.rejects(execute('selectContext',{familyId:first},b),/permission-denied/);
 await execute('removeMember',{familyId:third,id:a.uid},b);
 assert.equal((await user(a).get()).data()!.familyId,undefined);
 assert.deepEqual(new Set((await user(a).get()).data()!.familyIds),new Set([first,second]));
});

test('addressed requests require consent; duplicate requests and concurrent last-seat acceptance are safe',async()=>{
 const admin=await account(),fid=await create(admin),people=await Promise.all(Array.from({length:5},account));
 const requests=await Promise.all(people.map(p=>request(admin,p)));
 assert.equal(Object.keys((await getFirestore().doc(`families/${fid}`).get()).data()!.members).length,1);
 assert.equal((await request(admin,people[0]!)).id,requests[0]!.id);
 await assert.rejects(accept(requests[0]!.id,people[1]!),/permission-denied/);
 for(let i=0;i<3;i++)await accept(requests[i]!.id,people[i]!);
 const result=await Promise.allSettled([accept(requests[3]!.id,people[3]!),accept(requests[4]!.id,people[4]!)]);
 assert.equal(result.filter(x=>x.status==='fulfilled').length,1);
 assert.equal(Object.keys((await getFirestore().doc(`families/${fid}`).get()).data()!.members).length,5);
 await execute('removeMember',{id:people[0]!.uid},admin);
 // The removed account's profile stays (unlinked, data kept) and still holds the seat.
 const failed=result.findIndex(x=>x.status==='rejected')+3;
 await assert.rejects(accept(requests[failed]!.id,people[failed]!),/family-limit/);
 const kept=(await getFirestore().collection(`families/${fid}/profiles`).where('type','==','regular').get()).docs.find(d=>d.data().linkedUid===null)!;
 await execute('deleteProfile',{id:kept.id,contextFamilyId:fid},admin);
 const retry=await request(admin,people[failed]!);await accept(retry.id,people[failed]!);
 assert.equal(Object.keys((await getFirestore().doc(`families/${fid}`).get()).data()!.members).length,5);
 await assert.rejects(execute('createMemberLink',{},admin),/invalid-action/);
 await assert.rejects(execute('joinFamily',{token:'a'.repeat(64)},people[0]),/invalid-action/);
});

test('lookup discloses only public minimum and charges failed guesses; decline grants nothing',async()=>{
 const a=await account(),b=await account();await create(a);
 const code=(await user(b).get()).data()!.publicCode;
 const found=await execute('lookupPublicUser',{code},a) as object;assert.deepEqual(Object.keys(found).sort(),['code','name']);
 const r=await request(a,b);await execute('respondMembership',{id:r.id,accept:false},b);
 assert.equal((await user(b).get()).data()!.familyIds,undefined);
 for(let i=0;i<18;i++)await assert.rejects(execute('lookupPublicUser',{code:'000000000000'},a),/user-unavailable/);
 await assert.rejects(execute('lookupPublicUser',{code},a),/rate-limited/);
});

test('deletion checks all administered families including inactive contexts',async()=>{
 const a=await account(),b=await account();await create(a);const r=await request(a,b);await accept(r.id,b);
 await create(a);await execute('selectContext',{familyId:null},a);
 await assert.rejects(execute('prepareDeletion',{},a),/family-has-members/);
});
