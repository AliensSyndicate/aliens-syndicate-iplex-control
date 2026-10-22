import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore,FieldValue} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {getStorage} from 'firebase-admin/storage';
import {execute,Identity} from '../src/service';
import {hash,seal} from '../src/domain';

let app:ReturnType<typeof initializeApp>;
before(()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST||!process.env.FIREBASE_STORAGE_EMULATOR_HOST)throw new Error('Emulators required');
 app=initializeApp({projectId:'demo-iplex',storageBucket:'demo-iplex.appspot.com'});
});
after(()=>deleteApp(app));
const db=()=>getFirestore();
async function account(){
 const a:Identity={uid:`classification_${randomUUID()}`};
 await getAuth().createUser({uid:a.uid,displayName:'Pessoa'});
 await execute('bootstrap',{},a);
 const data=(await db().doc(`users/${a.uid}`).get()).data()!;
 return {a,fid:data.familyId as string,code:data.publicCode as string};
}
async function profile(fid:string,uid:string){
 const link=(await db().doc(`families/${fid}/profile_links/${uid}`).get()).data()!;
 const ref=db().doc(`families/${fid}/profiles/${link.profileId}`);
 return {ref,data:(await ref.get()).data()!};
}

test('membership classification belongs to the administrator; acceptance cannot override it or create extra accounts/profiles',async()=>{
 const admin=await account(),child=await account(),other=await account();
 for(const profileType of ['admin','guest',true,null])
  await assert.rejects(execute('requestMembership',{code:child.code,profileType},admin.a));
 const request=await execute('requestMembership',{code:child.code,profileType:'kids'},admin.a) as {id:string};
 await assert.rejects(execute('requestMembership',{code:child.code,familyId:admin.fid,profileType:'regular'},other.a),/permission-denied/);
 // Old client retry must not erase the child selection.
 assert.deepEqual(await execute('requestMembership',{code:child.code},admin.a),request);
 assert.equal((await db().doc(`family_requests/${request.id}`).get()).data()!.profileType,'kids');
 await execute('respondMembership',{id:request.id,accept:true,profileType:'regular',type:'regular'},child.a);
 await execute('respondMembership',{id:request.id,accept:true},child.a);
 const kid=await profile(admin.fid,child.a.uid);
 assert.equal(kid.data.type,'kids');assert.equal(kid.data.permissions.adult,false);
 assert.equal(kid.data.linkedUid,child.a.uid);
 assert.equal((await db().collection(`families/${admin.fid}/profiles`).get()).size,2);
 const user=(await db().doc(`users/${child.a.uid}`).get()).data()!;
 assert.equal(user.familyId,admin.fid);
 assert.equal((await db().doc(`families/${admin.fid}`).get()).data()!.members[child.a.uid],'member');
 assert.equal((await db().doc(`families/${child.fid}`).get()).data()!.parked,true);
 assert.equal((await getAuth().getUser(child.a.uid)).uid,child.a.uid);
 await assert.rejects(execute('saveProfile',{id:kid.ref.id,name:'Pessoa',type:'regular'},child.a),/permission-denied/);
 await assert.rejects(execute('requestMembership',{code:other.code,profileType:'kids'},child.a),/permission-denied/);
 await assert.rejects(execute('setProfilePreferences',{adult:true,spaces:null},child.a),/beyond-limit/);
});

test('regular is the default, old invitations remain compatible and only an administrator revises a pending selection',async()=>{
 const admin=await account(),regular=await account(),legacy=await account();
 const r=await execute('requestMembership',{code:regular.code,profileType:'kids'},admin.a) as {id:string};
 assert.deepEqual(await execute('requestMembership',{code:regular.code,profileType:'regular'},admin.a),r);
 await execute('respondMembership',{id:r.id,accept:true,profileType:'kids'},regular.a);
 assert.equal((await profile(admin.fid,regular.a.uid)).data.type,'regular');
 const old=await execute('requestMembership',{code:legacy.code},admin.a) as {id:string};
 assert.equal((await db().doc(`family_requests/${old.id}`).get()).data()!.profileType,'regular');
 await db().doc(`family_requests/${old.id}`).update({profileType:FieldValue.delete()});
 await execute('respondMembership',{id:old.id,accept:true},legacy.a);
 assert.equal((await profile(admin.fid,legacy.a.uid)).data.type,'regular');
});

test('invited children receive backend filtering in catalog, search, series, spaces and stream resolution',async()=>{
 const admin=await account(),child=await account();
 const r=await execute('requestMembership',{code:child.code,profileType:'kids'},admin.a) as {id:string};
 await execute('respondMembership',{id:r.id,accept:true},child.a);
 const catalog={schemaVersion:1,items:[
  {id:'kid',title:'Peppa',titleKey:'peppa',kind:'movie',category:'Infantil',providerRef:'1'},
  {id:'adult',title:'Drama',titleKey:'drama',kind:'movie',category:'Infantil',ageRating:'18',providerRef:'2'},
  {id:'unknown',title:'Notícias',titleKey:'noticias',kind:'channel',category:'Notícias',providerRef:'3'},
  {id:'series-kid',title:'Bluey',titleKey:'bluey',kind:'series',category:'Kids',providerRef:'77'},
  {id:'series-adult',title:'Drama adulto',titleKey:'drama adulto',kind:'series',category:'Adulto',providerRef:'88'},
 ],seriesDetails:{'77':{seasons:[]},'88':{seasons:[]}}};
 const body=JSON.stringify(catalog),version=hash(body),storagePath=`catalogs/${version}.json`;
 await getStorage().bucket().file(storagePath).save(body);
 await db().doc(`catalogs/${version}`).set({storagePath,integrityHash:version});
 await db().doc(`families/${admin.fid}/sources/src`).set({name:'Lista',enabled:true,version,revision:1,authorizationStatus:'valid',authorizationRevision:1});
 const items=await execute('readSourceCatalog',{id:'src'},child.a) as {items:{catalogItemId:string}[]};
 assert.deepEqual(items.items.map(i=>i.catalogItemId).sort(),['kid','series-kid']);
 const search=await execute('readSourceCatalog',{id:'src',search:'drama'},child.a) as {items:unknown[]};
 assert.deepEqual(search.items,[]);
 await assert.rejects(execute('readSourceSeries',{id:'src',seriesId:'88'},child.a),/not-found/);
 assert.ok(await execute('readSourceSeries',{id:'src',seriesId:'77'},child.a));
 const spaces=await execute('listProfileSpaces',{},child.a) as {spaces:{kinds:string[]}[]};
 assert.deepEqual(spaces.spaces[0]!.kinds,['movie','series']);
 // A real paired device uses the child's server-side lease, not a client type.
 const pairing=await execute('beginDevicePair',{name:'TV'},undefined) as {token:string};
 const device=await execute('linkDevice',{token:pairing.token},admin.a) as {id:string};
 const player:Identity={uid:`tv_${device.id}`,deviceId:device.id,familyId:admin.fid,
  credentialVersion:(await db().doc(`families/${admin.fid}/devices/${device.id}`).get()).data()!.credentialVersion};
 const kid=await profile(admin.fid,child.a.uid);
 await execute('acquireSession',{profileId:kid.ref.id},player);
 const key=Buffer.alloc(32,1).toString('base64');
 await db().doc(`source_secrets/${admin.fid}_src`).set({revision:1,encrypted:seal({name:'Lista',format:'m3u',url:'https://example.com/list.m3u'},key)});
 await assert.rejects(execute('resolveSourceStream',{id:'src',itemId:'adult'},player,key),/not-found/);
 // Existing member classification can be changed only by its family administrator.
 await kid.ref.collection('favorites').doc('kept').set({title:'Peppa',contentId:'kid'});
 await execute('saveProfile',{id:kid.ref.id,name:kid.data.name,type:'regular'},admin.a);
 assert.equal((await kid.ref.get()).data()!.permissionsVersion,1);
 assert.equal((await kid.ref.get()).data()!.linkedUid,child.a.uid);
 const regular=await execute('readSourceCatalog',{id:'src'},child.a) as {items:unknown[]};
 assert.ok(regular.items.length>items.items.length);
 await execute('saveProfile',{id:kid.ref.id,name:kid.data.name,type:'kids'},admin.a);
 const updated=(await kid.ref.get()).data()!;
 assert.equal(updated.permissions.adult,false);assert.equal(updated.permissionsVersion,2);
 assert.equal((await kid.ref.collection('favorites').doc('kept').get()).exists,true);
 const refreshed=await execute('readSourceCatalog',{id:'src'},player) as {items:{catalogItemId:string}[]};
 assert.deepEqual(refreshed.items.map(i=>i.catalogItemId).sort(),['kid','series-kid']);
 await assert.rejects(execute('saveProfile',{id:'admin',name:'Admin',type:'kids'},admin.a),/profile-type-immutable/);
 const outsider=await account();
 await assert.rejects(execute('saveProfile',{id:kid.ref.id,name:'Pessoa',type:'regular',contextFamilyId:admin.fid},outsider.a),/permission-denied/);
});
