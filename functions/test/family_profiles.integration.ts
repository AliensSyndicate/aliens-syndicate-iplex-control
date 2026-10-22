import {createFamily} from './support/membership';
import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {getStorage} from 'firebase-admin/storage';
import {execute,Identity} from '../src/service';
import {hash} from '../src/domain';

let app:ReturnType<typeof initializeApp>,seq=0;
before(()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST||!process.env.FIREBASE_STORAGE_EMULATOR_HOST)throw new Error('Emulators required');
 app=initializeApp({projectId:'demo-iplex',storageBucket:'demo-iplex.appspot.com'});
});
after(()=>deleteApp(app));
const db=()=>getFirestore();
async function account(name='Pessoa'){const a:Identity={uid:`fp_${Date.now()}_${++seq}`,authTime:Math.floor(Date.now()/1000)};await getAuth().createUser({uid:a.uid,displayName:name});await execute('bootstrap',{},a);return a;}
async function family(){const admin=await account('Admin');const fid=(await createFamily(admin,'Casa') as {id:string}).id;return {admin,fid,ctx:{contextFamilyId:fid}};}
const profiles=(fid:string)=>db().collection(`families/${fid}/profiles`);
async function tv(admin:Identity,fid:string):Promise<Identity>{
 const s=await execute('beginDevicePair',{name:'TV'},undefined) as {token:string};
 const d=await execute('linkDevice',{token:s.token,contextFamilyId:fid},admin) as {id:string};
 return {uid:`tv_${d.id}`,deviceId:d.id,familyId:fid,credentialVersion:(await getFirestore().doc(`families/${fid}/devices/${d.id}`).get()).data()?.credentialVersion};
}
async function seed(ref:FirebaseFirestore.CollectionReference,count:number,extra:Record<string,unknown>={}){
 for(let i=0;i<count;i+=400){const b=db().batch();for(let j=i;j<Math.min(count,i+400);j++)b.set(ref.doc(`c${j}`),{contentId:`c${j}`,...extra});await b.commit();}
}

test('profiles exist without accounts; four associates max; guest is a sixth optional profile; retries do not duplicate',async()=>{
 const {admin,fid,ctx}=await family();
 const admin_=(await profiles(fid).doc('admin').get()).data()!;
 assert.equal(admin_.type,'admin');assert.equal(admin_.linkedUid,admin.uid);
 const first=await execute('saveProfile',{name:'João',type:'kids',requestId:'req-1',...ctx},admin) as {id:string};
 assert.deepEqual(await execute('saveProfile',{name:'João',type:'kids',requestId:'req-1',...ctx},admin),first);
 assert.notEqual(first.id,admin.uid);
 const created=(await profiles(fid).doc(first.id).get()).data()!;
 assert.equal(created.type,'kids');assert.equal(created.linkedUid,null);
 for(const name of ['Ana','Bia','Caio'])await execute('saveProfile',{name,...ctx},admin);
 await assert.rejects(execute('saveProfile',{name:'Quinto',...ctx},admin),/profile-limit/);
 await execute('setGuestEnabled',{enabled:true,name:'Visitante',...ctx},admin);
 const all=(await profiles(fid).get()).docs.map(d=>d.data().type).sort();
 assert.deepEqual(all,['admin','guest','kids','regular','regular','regular']);
 await execute('saveProfile',{id:'guest',name:'Convidado',...ctx},admin);
 assert.equal((await profiles(fid).doc('guest').get()).data()!.type,'guest');
 await assert.rejects(execute('saveProfile',{id:'guest',name:'Convidado',type:'regular',...ctx},admin),/profile-type-immutable/);
 await assert.rejects(execute('saveProfile',{id:first.id,name:'João',type:'regular',...ctx},admin),/profile-type-immutable/);
 await assert.rejects(execute('deleteProfile',{id:'admin',...ctx},admin),/administrator-protected/);
 const member=await account();
 await assert.rejects(execute('saveProfile',{name:'Intruso',contextFamilyId:fid},member),/permission-denied/);
});

test('guest toggle keeps configuration, hides it on the TV and never persists media data',async()=>{
 const {admin,fid,ctx}=await family();
 await execute('setGuestEnabled',{enabled:true,name:'Visitante',...ctx},admin);
 await execute('setProfilePermissions',{profileId:'guest',allSpaces:false,spaces:['src:movie'],...ctx},admin);
 const player=await tv(admin,fid);
 let listed=(await execute('listPlayerProfiles',{},player) as {profiles:{id:string}[]}).profiles.map(x=>x.id);
 assert.ok(listed.includes('guest'));
 const lease=await execute('acquireSession',{profileId:'guest'},player) as {id:string};
 for(const [action,extra] of [['favorite',{title:'Filme'}],['watchProgress',{position:1,duration:10}],['markWatched',{}]] as const)
  await assert.rejects(execute(action,{profileId:'guest',contentId:'film',generation:0,...extra},player),/guest-not-persisted/);
 await assert.rejects(execute('clearProfileData',{profileId:'guest',category:'favorites',requestId:'g1',...ctx},admin),/guest-not-persisted/);
 await execute('releaseSession',{sessionId:lease.id},player);
 await execute('setGuestEnabled',{enabled:false,...ctx},admin);
 listed=(await execute('listPlayerProfiles',{},player) as {profiles:{id:string}[]}).profiles.map(x=>x.id);
 assert.ok(!listed.includes('guest'));
 await assert.rejects(execute('acquireSession',{profileId:'guest'},player),/profile-disabled/);
 const kept=(await profiles(fid).doc('guest').get()).data()!;
 assert.equal(kept.enabled,false);assert.deepEqual(kept.permissions,{allSpaces:false,spaces:['src:movie'],adult:true});
 for(const c of ['favorites','watch_progress','watched'])assert.equal((await profiles(fid).doc('guest').collection(c).get()).size,0);
});

test('three independent clears delete Firebase data, block stale offline writes and are idempotent',async()=>{
 const {admin,fid,ctx}=await family();
 const joao=(await execute('saveProfile',{name:'João',...ctx},admin) as {id:string}).id,ana=(await execute('saveProfile',{name:'Ana',...ctx},admin) as {id:string}).id;
 const ref=(id:string,c:string)=>profiles(fid).doc(id).collection(c);
 await seed(ref(joao,'favorites'),450);await seed(ref(joao,'watched'),3);await seed(ref(joao,'watch_progress'),3,{position:1,duration:2});
 await seed(ref(ana,'favorites'),2);
 await db().collection('profile_favorites').doc(`legacy_${joao}`).set({familyId:fid,profileId:joao,contentId:'x'});
 const player=await tv(admin,fid);await execute('acquireSession',{profileId:joao},player);
 await assert.rejects(execute('clearProfileData',{profileId:joao,category:'favorites',requestId:'r1',...ctx},player),/permission-denied/);
 const other=await family();
 await assert.rejects(execute('clearProfileData',{profileId:joao,category:'favorites',requestId:'r1',contextFamilyId:other.fid},other.admin),/not-found/);
 await assert.rejects(execute('clearProfileData',{profileId:joao,category:'favorites',requestId:'r1',contextFamilyId:fid},other.admin),/permission-denied/);

 const result=await execute('clearProfileData',{profileId:joao,category:'favorites',requestId:'r1',...ctx},admin) as {generation:number;deleted:number};
 assert.equal(result.generation,1);assert.equal(result.deleted,451);
 assert.equal((await ref(joao,'favorites').get()).size,0);
 assert.equal((await db().collection('profile_favorites').doc(`legacy_${joao}`).get()).exists,false);
 assert.equal((await ref(joao,'watched').get()).size,3);assert.equal((await ref(joao,'watch_progress').get()).size,3);
 assert.equal((await ref(ana,'favorites').get()).size,2);
 // Duplicate delivery of the same request is a no-op with the same outcome.
 assert.equal((await execute('clearProfileData',{profileId:joao,category:'favorites',requestId:'r1',...ctx},admin) as {generation:number}).generation,1);
 // An offline TV replaying a write from before the clear cannot restore it.
 await assert.rejects(execute('favorite',{profileId:joao,contentId:'old',title:'Antigo',generation:0},player),/stale-generation/);
 await assert.rejects(execute('favorite',{profileId:joao,contentId:'old',title:'Antigo'},player),/generation-required/);
 await execute('favorite',{profileId:joao,contentId:'new',title:'Novo',generation:1},player);
 assert.equal((await ref(joao,'favorites').get()).size,1);

 await execute('clearProfileData',{profileId:joao,category:'watched',requestId:'r2',...ctx},admin);
 assert.equal((await ref(joao,'watched').get()).size,0);assert.equal((await ref(joao,'watch_progress').get()).size,3);assert.equal((await ref(joao,'favorites').get()).size,1);
 await execute('clearProfileData',{profileId:joao,category:'progress',requestId:'r3',...ctx},admin);
 assert.equal((await ref(joao,'watch_progress').get()).size,0);assert.equal((await ref(joao,'favorites').get()).size,1);
 const gens=(await profiles(fid).doc(joao).get()).data()!.generations;
 assert.deepEqual(gens,{favorites:1,watched:1,progress:1});
 // Completion writes "Assistidos" only with the current watched generation.
 await execute('watchProgress',{profileId:joao,contentId:'ep',position:95,duration:100,generation:1,watchedGeneration:0},player);
 assert.equal((await ref(joao,'watched').get()).size,0);
 await execute('watchProgress',{profileId:joao,contentId:'ep',position:95,duration:100,generation:1,watchedGeneration:1},player);
 assert.equal((await ref(joao,'watched').get()).size,1);

 // A second, different request while one runs is refused instead of interleaving.
 await profiles(fid).parent!.collection('profile_clear_jobs').doc(`${joao}_favorites`).update({status:'running',requestId:'other',updatedAt:Date.now()});
 await assert.rejects(execute('clearProfileData',{profileId:joao,category:'favorites',requestId:'r4',...ctx},admin),/clear-in-progress/);
});

test('account linking keeps the profile id and data; single-use codes; conflicts are refused; unlink keeps the profile',async()=>{
 const {admin,fid,ctx}=await family();
 const pid=(await execute('saveProfile',{name:'Lia',type:'kids',...ctx},admin) as {id:string}).id;
 await profiles(fid).doc(pid).collection('favorites').doc('f1').set({contentId:'f1',generation:0});
 await profiles(fid).doc(pid).collection('watch_progress').doc('p1').set({contentId:'p1',generation:0});
 await execute('setProfilePermissions',{profileId:pid,allSpaces:false,spaces:['s1:movie'],...ctx},admin);
 const {code}=await execute('createProfileLinkCode',{profileId:pid,...ctx},admin) as {code:string};
 assert.match(code,/^[A-Z0-9]{8}$/);
 const lia=await account('Lia');
 await assert.rejects(execute('redeemProfileLink',{code:'ZZZZZZZZ'},lia),/invalid-token/);
 const linked=await execute('redeemProfileLink',{code:code.toLowerCase()},lia) as {profileId:string;familyId:string};
 assert.deepEqual(linked,{familyId:fid,profileId:pid});
 const after=(await profiles(fid).doc(pid).get()).data()!;
 assert.equal(after.linkedUid,lia.uid);assert.equal(after.type,'kids');assert.deepEqual(after.permissions,{allSpaces:false,spaces:['s1:movie'],adult:true});
 assert.equal((await profiles(fid).doc(pid).collection('favorites').get()).size,1);
 assert.equal((await profiles(fid).doc(pid).collection('watch_progress').get()).size,1);
 assert.equal((await profiles(fid).get()).size,2);
 assert.ok((await db().doc(`families/${fid}`).get()).data()!.members[lia.uid]);
 const other=await account();
 await assert.rejects(execute('redeemProfileLink',{code},other),/link-code-expired/);
 // The same account cannot take a second profile in this family: no automatic merge.
 const second=(await execute('saveProfile',{name:'Outro',...ctx},admin) as {id:string}).id;
 const code2=(await execute('createProfileLinkCode',{profileId:second,...ctx},admin) as {code:string}).code;
 await assert.rejects(execute('redeemProfileLink',{code:code2},lia),/account-already-linked/);
 // A new code revokes the previous one; expired codes are refused.
 const code3=(await execute('createProfileLinkCode',{profileId:second,...ctx},admin) as {code:string}).code;
 await assert.rejects(execute('redeemProfileLink',{code:code2},other),/link-code-expired/);
 await db().doc(`profile_link_codes/${hash(code3)}`).update({expiresAt:1});
 await assert.rejects(execute('redeemProfileLink',{code:code3},other),/link-code-expired/);
 await execute('unlinkProfileAccount',{profileId:pid,...ctx},admin);
 const unlinked=(await profiles(fid).doc(pid).get()).data()!;
 assert.equal(unlinked.linkedUid,null);assert.equal((await profiles(fid).doc(pid).collection('favorites').get()).size,1);
 assert.ok((await getAuth().getUser(lia.uid)).uid);
 await assert.rejects(execute('createProfileLinkCode',{profileId:'admin',...ctx},admin),/profile-not-linkable/);
 const guesser=await account();let limited=false;
 for(let i=0;i<25&&!limited;i++)try{await execute('redeemProfileLink',{code:`AAAA${String(1000+i)}`},guesser);}catch(e){limited=/rate-limited/.test(String(e));}
 assert.equal(limited,true);
});

test('kids and space permissions are enforced by the backend in listings, search, series and spaces',async()=>{
 const {admin,fid,ctx}=await family();
 const catalog={schemaVersion:1,items:[
  {id:'k1',title:'Peppa',titleKey:'peppa',kind:'movie',category:'Infantil',providerRef:'1'},
  {id:'k2',title:'Turma da Mônica',titleKey:'turma da monica',kind:'movie',category:'Filmes',providerRef:'2',ageRating:'l'},
  {id:'a1',title:'Drama',titleKey:'drama',kind:'movie',category:'Infantil',providerRef:'3',ageRating:'16'},
  {id:'a2',title:'XXX Night',titleKey:'xxx night',kind:'movie',category:'Infantil',providerRef:'4'},
  {id:'a3',title:'Animado adulto',titleKey:'animado adulto',kind:'movie',category:'Animação',providerRef:'5'},
  {id:'c1',title:'Canal Notícias',titleKey:'canal noticias',kind:'channel',category:'Notícias',providerRef:'6'},
  {id:'s1',title:'Bluey',titleKey:'bluey',kind:'series',category:'Kids',providerRef:'77'},
  {id:'s2',title:'Série adulta',titleKey:'serie adulta',kind:'series',category:'Séries',providerRef:'88'},
 ],seriesDetails:{'77':{seasons:[]},'88':{seasons:[]}}};
 const body=JSON.stringify(catalog),version=hash(body);
 await getStorage().bucket().file(`catalogs/${version}.json`).save(body);
 await db().doc(`catalogs/${version}`).set({storagePath:`catalogs/${version}.json`,integrityHash:hash(body)});
 await db().doc(`families/${fid}/sources/src1`).set({name:'Lista',enabled:true,version,revision:1});
 const kid=(await execute('saveProfile',{name:'Lia',type:'kids',...ctx},admin) as {id:string}).id;
 const reg=(await execute('saveProfile',{name:'Rui',...ctx},admin) as {id:string}).id;
 const link=async(pid:string)=>{const a=await account();const {code}=await execute('createProfileLinkCode',{profileId:pid,...ctx},admin) as {code:string};await execute('redeemProfileLink',{code},a);return a;};
 const kidAccount=await link(kid),regAccount=await link(reg);
 const read=async(a:Identity,search='')=>(await execute('readSourceCatalog',{id:'src1',search,contextFamilyId:fid},a) as {items:{catalogItemId:string}[]}).items.map(i=>i.catalogItemId).sort();
 assert.deepEqual(await read(kidAccount),['k1','k2','s1']);
 assert.deepEqual(await read(kidAccount,'drama'),[]);
 assert.deepEqual(await read(kidAccount,'xxx'),[]);
 const recentSearchIds=catalog.items.map(i=>hash(`src1:${i.id}`));
 const recents=async(a:Identity)=>(await execute('readHome',{sourceId:'src1',recentSearchIds,...ctx},a) as {recentSearches:{catalogItemId:string}[]}).recentSearches.map(i=>i.catalogItemId);
 assert.deepEqual(await recents(kidAccount),['k1','k2','s1'],'search recents never restore restricted titles for kids');
 // Granting every space to a kids profile cannot widen it beyond children's content.
 await execute('setProfilePermissions',{profileId:kid,allSpaces:true,spaces:[],...ctx},admin);
 assert.deepEqual(await read(kidAccount),['k1','k2','s1']);
 await assert.rejects(execute('readSourceSeries',{id:'src1',seriesId:'88',contextFamilyId:fid},kidAccount),/not-found/);
 assert.ok(await execute('readSourceSeries',{id:'src1',seriesId:'77',contextFamilyId:fid},kidAccount));
 assert.equal((await read(regAccount)).length,8);
 assert.equal((await read(admin)).length,8);
 // Revoking a space takes effect on the next request; the space disappears.
 await execute('setProfilePermissions',{profileId:reg,allSpaces:false,spaces:['src1:channel'],...ctx},admin);
 assert.deepEqual(await read(regAccount),['c1']);
 assert.deepEqual(await recents(regAccount),['c1'],'search recents respect current space permissions');
 const spaces=await execute('listProfileSpaces',{contextFamilyId:fid},regAccount) as {spaces:{sourceId:string;kinds:string[]}[];permissionsVersion:number};
 assert.deepEqual(spaces.spaces,[{sourceId:'src1',name:'Lista',kinds:['channel']}]);
 assert.equal(spaces.permissionsVersion,1);
 await execute('setProfilePermissions',{profileId:reg,allSpaces:false,spaces:[],...ctx},admin);
 await assert.rejects(execute('readSourceCatalog',{id:'src1',contextFamilyId:fid},regAccount),/not-found/);
 const kidSpaces=await execute('listProfileSpaces',{contextFamilyId:fid},kidAccount) as {spaces:{kinds:string[]}[]};
 assert.deepEqual(kidSpaces.spaces[0]!.kinds,['movie','series']);
 // The TV's profile comes from its lease, not from the request.
 const player=await tv(admin,fid);await execute('acquireSession',{profileId:kid},player);
 await assert.rejects(execute('readSourceCatalog',{id:'src1',profileId:reg},player),/permission-denied/);
 const tvItems=(await execute('readSourceCatalog',{id:'src1'},player) as {items:{catalogItemId:string}[]}).items.map(i=>i.catalogItemId).sort();
 assert.deepEqual(tvItems,['k1','k2','s1']);
});

test('deleting a profile removes its media data for real and releases its account link',async()=>{
 const {admin,fid,ctx}=await family();
 const pid=(await execute('saveProfile',{name:'Rui',...ctx},admin) as {id:string}).id;
 for(const c of ['favorites','watched','watch_progress'])await profiles(fid).doc(pid).collection(c).doc('x').set({contentId:'x',generation:0});
 await db().collection('profile_progress').doc(`legacy_${pid}`).set({familyId:fid,profileId:pid});
 const {code}=await execute('createProfileLinkCode',{profileId:pid,...ctx},admin) as {code:string};
 const rui=await account('Rui');await execute('redeemProfileLink',{code},rui);
 await execute('deleteProfile',{id:pid,...ctx},admin);
 assert.equal((await profiles(fid).doc(pid).get()).exists,false);
 for(const c of ['favorites','watched','watch_progress'])assert.equal((await profiles(fid).doc(pid).collection(c).get()).size,0,c);
 assert.equal((await db().collection('profile_progress').doc(`legacy_${pid}`).get()).exists,false);
 assert.equal((await db().doc(`families/${fid}/profile_links/${rui.uid}`).get()).exists,false);
});

test('deleting an associate account clears its profile link but keeps the profile',async()=>{
 const {admin,fid,ctx}=await family();
 const pid=(await execute('saveProfile',{name:'Ana',...ctx},admin) as {id:string}).id;
 const {code}=await execute('createProfileLinkCode',{profileId:pid,...ctx},admin) as {code:string};
 const ana=await account('Ana');await execute('redeemProfileLink',{code},ana);
 await execute('prepareDeletion',{},ana);
 assert.equal((await db().doc(`families/${fid}/profile_links/${ana.uid}`).get()).exists,false);
 const kept=(await profiles(fid).doc(pid).get()).data()!;assert.equal(kept.linkedUid,null);
 assert.equal((await db().doc(`families/${fid}`).get()).data()!.members[ana.uid],undefined);
});

test('adult content and member preferences: limits by the administrator, narrower preferences by the member; personal PIN and library by owner',async()=>{
 const {admin,fid,ctx}=await family();
 const catalog={schemaVersion:1,items:[
  {id:'m1',title:'Drama',titleKey:'drama',kind:'movie',category:'Filmes',providerRef:'1',ageRating:'14'},
  {id:'m2',title:'XXX Night',titleKey:'xxx night',kind:'movie',category:'Filmes',providerRef:'2'},
  {id:'c1',title:'Canal Notícias',titleKey:'canal noticias',kind:'channel',category:'Notícias',providerRef:'3'},
 ]};
 const body=JSON.stringify(catalog),version=hash(body);
 await getStorage().bucket().file(`catalogs/${version}.json`).save(body);
 await db().doc(`catalogs/${version}`).set({storagePath:`catalogs/${version}.json`,integrityHash:hash(body)});
 await db().doc(`families/${fid}/sources/src1`).set({name:'Lista',enabled:true,version,revision:1});
 const pid=(await execute('saveProfile',{name:'Rui',...ctx},admin) as {id:string}).id;
 const rui=await account('Rui');
 const {code}=await execute('createProfileLinkCode',{profileId:pid,...ctx},admin) as {code:string};
 await execute('redeemProfileLink',{code},rui);
 const read=async()=>(await execute('readSourceCatalog',{id:'src1',contextFamilyId:fid},rui) as {items:{catalogItemId:string}[]}).items.map(i=>i.catalogItemId).sort();
 assert.deepEqual(await read(),['c1','m1','m2']);
 // Administrator turns adult content off: hidden for the member, kept for the administrator.
 await execute('setProfilePermissions',{profileId:pid,allSpaces:true,spaces:[],adult:false,...ctx},admin);
 assert.deepEqual(await read(),['c1','m1']);
 assert.equal((await execute('readSourceCatalog',{id:'src1',contextFamilyId:fid},admin) as {items:unknown[]}).items.length,3);
 // The member cannot widen it…
 await assert.rejects(execute('setProfilePreferences',{adult:true,spaces:null},rui),/beyond-limit/);
 // …but can narrow its own access further (only the channels), and undo it.
 await execute('setProfilePreferences',{adult:false,spaces:['src1:channel']},rui);
 assert.deepEqual(await read(),['c1']);
 await execute('setProfilePermissions',{profileId:pid,allSpaces:false,spaces:['src1:movie'],adult:true,...ctx},admin);
 await assert.rejects(execute('setProfilePreferences',{adult:true,spaces:['src1:channel']},rui),/beyond-limit/);
 await execute('setProfilePreferences',{adult:false,spaces:null},rui);
 assert.deepEqual(await read(),['m1'],'effective = administrator limits ∩ member preferences');
 // Preferences belong to the linked account: the administrator's call changes its own profile only.
 await execute('setProfilePreferences',{adult:true,spaces:null,...ctx},admin);
 assert.equal((await profiles(fid).doc(pid).get()).data()!.preferences.adult,false);

 // Personal PIN: only the account linked to the profile; current PIN required to change or remove.
 await execute('setPersonalPin',{pin:'1234',confirmPin:'1234'},rui);
 assert.deepEqual((await profiles(fid).doc(pid).get()).data()!.personalPin.configured,true);
 const secret=(await db().doc(`families/${fid}/private/personal_pin_${pid}`).get()).data()!;
 assert.notEqual(secret.pinHash,'1234');
 await assert.rejects(execute('setPersonalPin',{pin:'9999',confirmPin:'9999'},rui),/pin-invalid/);
 await execute('setPersonalPin',{currentPin:'1234',pin:'9999',confirmPin:'9999'},rui);
 // The administrator's call never reaches the member's PIN (it acts on its own profile).
 await execute('setPersonalPin',{pin:'1111',confirmPin:'1111',...ctx},admin);
 assert.ok((await db().doc(`families/${fid}/private/personal_pin_admin`).get()).exists);
 await assert.rejects(execute('clearPersonalPin',{currentPin:'1111'},rui),/pin-invalid/);
 await execute('clearPersonalPin',{currentPin:'9999'},rui);
 assert.equal((await db().doc(`families/${fid}/private/personal_pin_${pid}`).get()).exists,false);

 // Library of a profile: its own account or the administrator; never another member.
 await profiles(fid).doc(pid).collection('watch_progress').doc(hash('src1:m1')).set({contentId:hash('src1:m1'),position:30,duration:100,generation:0,updatedAt:Date.now()});
 await profiles(fid).doc(pid).collection('watched').doc(hash('src1:c1')).set({contentId:hash('src1:c1'),generation:0,completedAt:Date.now()});
 const lib=await execute('readProfileLibrary',{profileId:pid,...ctx},admin) as {continueWatching:{id:string;progress:{position:number}}[];watched:{id:string}[]};
 assert.deepEqual(lib.continueWatching.map(i=>[i.id,i.progress.position]),[[hash('src1:m1'),30]]);
 assert.deepEqual(lib.watched.map(i=>i.id),[hash('src1:c1')]);
 assert.ok(await execute('readProfileLibrary',{profileId:pid},rui));
 const other=(await execute('saveProfile',{name:'Bia',...ctx},admin) as {id:string}).id;
 await assert.rejects(execute('readProfileLibrary',{profileId:other},rui),/permission-denied/);
 await assert.rejects(execute('readProfileLibrary',{profileId:pid,contextFamilyId:fid},await account()),/permission|family/);
});
