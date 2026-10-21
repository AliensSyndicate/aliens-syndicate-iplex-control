import {test,before,after} from 'node:test';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment,assertFails,assertSucceeds,RulesTestEnvironment} from '@firebase/rules-unit-testing';
import {doc,getDoc,setDoc,updateDoc,deleteDoc,collection,getDocs} from 'firebase/firestore';
let env:RulesTestEnvironment;
before(async()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST)throw new Error('Emulator required');
 env=await initializeTestEnvironment({projectId:'demo-iplex',firestore:{rules:readFileSync('../firestore.rules','utf8')}});
 await env.withSecurityRulesDisabled(async c=>{const db=c.firestore();for(const [path,data] of Object.entries({'families/f':{adminId:'admin',members:{admin:'admin',member:'member'}},'families/f/members/admin':{role:'admin'},'families/f/devices/tv':{name:'TV'},'families/f/private/subscription':{status:'trial'},'families/f/sources/s':{version:'v'},'families/f/catalog/current':{version:'v',sourceId:'s'},'families/f/catalog/old':{version:'old',sourceId:'s'},'families/f/catalog/revoked':{version:'v',sourceId:'removed'},'source_secrets/f_s':{encrypted:'fixture'},'link_tokens/token':{token:'fixture'},'users/admin':{uid:'admin',name:'Admin',email:'admin@example.invalid',updatedAt:1,familyId:'f'}}))await setDoc(doc(db,path),data);});
});
after(async()=>{await env?.cleanup();});
test('unauthenticated and foreign users cannot read family',async()=>{for(const c of [env.unauthenticatedContext(),env.authenticatedContext('outsider')])await assertFails(getDoc(doc(c.firestore(),'families/f')));});
test('members can read metadata but not billing, secrets or tokens',async()=>{const db=env.authenticatedContext('member').firestore();await assertSucceeds(getDoc(doc(db,'families/f')));for(const p of ['families/f/private/subscription','source_secrets/f_s','link_tokens/token','users/admin'])await assertFails(getDoc(doc(db,p)));});
test('administrator can read subscription but cannot change it',async()=>{const db=env.authenticatedContext('admin').firestore();await assertSucceeds(getDoc(doc(db,'families/f/private/subscription')));await assertFails(setDoc(doc(db,'families/f/private/subscription'),{status:'active'}));});
test('all clients denied privileged writes and command injection',async()=>{for(const user of ['admin','member']){const db=env.authenticatedContext(user).firestore();for(const path of ['families/f','families/f/devices/tv','families/f/profiles/p','families/f/devices/tv/commands/c','users/admin'])await assertFails(setDoc(doc(db,path),{role:'admin'}));}});
test('player scoped to its own device; no family billing or sources',async()=>{const db=env.authenticatedContext('tv_tv',{deviceId:'tv',familyId:'f'}).firestore();await assertSucceeds(getDoc(doc(db,'families/f/devices/tv')));for(const path of ['families/f','families/f/devices/other','families/f/private/subscription','families/f/sources/s'])await assertFails(getDoc(doc(db,path)));await assertFails(getDocs(collection(db,'families/f/members')));});

test('catalog reads require an active source binding and current published version',async()=>{const db=env.authenticatedContext('member').firestore();await assertSucceeds(getDoc(doc(db,'families/f/catalog/current')));await assertFails(getDoc(doc(db,'families/f/catalog/old')));await assertFails(getDoc(doc(db,'families/f/catalog/revoked')));});

test('account metadata fallback cannot change membership or privileges',async()=>{const db=env.authenticatedContext('admin').firestore();await assertSucceeds(setDoc(doc(db,'users/admin'),{name:'Updated',updatedAt:2},{merge:true}));await assertFails(setDoc(doc(db,'users/admin'),{familyId:'other'},{merge:true}));await assertFails(setDoc(doc(db,'users/admin'),{role:'admin'},{merge:true}));const other=env.authenticatedContext('new').firestore();await assertSucceeds(setDoc(doc(other,'users/new'),{uid:'new',name:'New',email:'new@example.invalid',updatedAt:1}));await assertFails(setDoc(doc(other,'users/new'),{familyId:'f'},{merge:true}));});

test('catalog and administrative reads remain available without or after playback entitlement',async()=>{
 for(const status of ['notStarted','expired']){
  await env.withSecurityRulesDisabled(async c=>{await setDoc(doc(c.firestore(),'families/f/private/subscription'),{status});});
  for(const uid of ['admin','member']){
   const db=env.authenticatedContext(uid).firestore();
   for(const path of ['families/f','families/f/members/admin','families/f/devices/tv','families/f/sources/s','families/f/catalog/current'])await assertSucceeds(getDoc(doc(db,path)));
  }
 }
});

test('clients cannot create, upgrade, delete or inject playback entitlements',async()=>{
 for(const uid of ['admin','member']){
  const db=env.authenticatedContext(uid).firestore();
  await assertFails(updateDoc(doc(db,'families/f/private/subscription'),{status:'active',paidUntil:Date.now()+86400000}));
  await assertFails(deleteDoc(doc(db,'families/f/private/subscription')));
  await assertFails(setDoc(doc(db,'families/f/private/entitlement'),{canStartPlayback:true}));
  await assertFails(setDoc(doc(db,`users/${uid}`),{subscription:{status:'active'},isActive:true},{merge:true}));
 }
});

test('personal IPTV metadata/catalog is private and its account pointer cannot be forged',async()=>{
 await env.withSecurityRulesDisabled(async c=>{
  const db=c.firestore();
  for(const [path,data] of Object.entries({
   'families/personal':{kind:'personalIptv',ownerId:'personal-owner',adminId:'personal-owner',members:{'personal-owner':'admin'}},
   'families/personal/sources/source':{version:'v'},
   'families/personal/catalog/item':{sourceId:'source',version:'v',titleKey:'film'},
   'source_secrets/personal_source':{encrypted:'protected'},
  }))await setDoc(doc(db,path),data);
 });
 const owner=env.authenticatedContext('personal-owner').firestore();
 for(const path of ['families/personal/sources/source','families/personal/catalog/item'])await assertSucceeds(getDoc(doc(owner,path)));
 for(const ctx of [env.unauthenticatedContext(),env.authenticatedContext('admin'),env.authenticatedContext('member')]){
  for(const path of ['families/personal','families/personal/sources/source','families/personal/catalog/item'])await assertFails(getDoc(doc(ctx.firestore(),path)));
 }
 await assertFails(getDoc(doc(owner,'source_secrets/personal_source')));
 await assertFails(setDoc(doc(owner,'families/personal/sources/forged'),{status:'ready'}));
 await assertFails(setDoc(doc(env.authenticatedContext('admin').firestore(),'users/admin'),{iptvWorkspaceId:'personal'},{merge:true}));
});

test('PIN-protected catalogs require an unexpired server grant for this source revision',async()=>{
 await env.withSecurityRulesDisabled(async c=>{
  const db=c.firestore();
  await setDoc(doc(db,'families/f/sources/locked'),{version:'v',isProtected:true,revision:2});
  await setDoc(doc(db,'families/f/catalog/locked-item'),{version:'v',sourceId:'locked'});
 });
 const db=env.authenticatedContext('member').firestore();
 await assertFails(getDoc(doc(db,'families/f/catalog/locked-item')));
 await assertFails(setDoc(doc(db,'families/f/source_access/locked_member'),{revision:2,expiresAt:Date.now()+60000}));
 for(const grant of [{revision:1,expiresAt:Date.now()+60000},{revision:2,expiresAt:0}]){
  await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'families/f/source_access/locked_member'),grant));
  await assertFails(getDoc(doc(db,'families/f/catalog/locked-item')));
 }
 await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'families/f/source_access/locked_member'),{revision:2,expiresAt:Date.now()+60000}));
 await assertSucceeds(getDoc(doc(db,'families/f/catalog/locked-item')));
});

test('public codes, membership pointers and requests are backend-owned and recipient-private',async()=>{
 await env.withSecurityRulesDisabled(async c=>{
  const db=c.firestore();
  await setDoc(doc(db,'public_user_codes/ABC123DEF456'),{uid:'member'});
  await setDoc(doc(db,'family_requests/r'),{familyId:'f',recipientUid:'member',issuerUid:'admin',status:'pending'});
  await setDoc(doc(db,'subscriptions/f'),{familyId:'f',status:'trial'});
 });
 for(const uid of ['admin','member','outsider']){
  const db=env.authenticatedContext(uid).firestore();
  await assertFails(getDoc(doc(db,'public_user_codes/ABC123DEF456')));
  await assertFails(setDoc(doc(db,`users/${uid}`),{publicCode:'ABC123DEF456',familyIds:['f']},{merge:true}));
  await assertFails(updateDoc(doc(db,'family_requests/r'),{status:'accepted'}));
  // The invitee and the inviting family's administrator follow the request; nobody else.
  if(uid==='member'||uid==='admin')await assertSucceeds(getDoc(doc(db,'family_requests/r')));
  else await assertFails(getDoc(doc(db,'family_requests/r')));
  if(uid==='admin')await assertSucceeds(getDoc(doc(db,'subscriptions/f')));
  else await assertFails(getDoc(doc(db,'subscriptions/f')));
 }
});

test('media profiles sync to members and the family TV; clear jobs, links and link codes stay protected',async()=>{
 await env.withSecurityRulesDisabled(async c=>{
  const db=c.firestore();
  for(const [path,data] of Object.entries({
   'families/f/profiles/joao':{name:'João',type:'regular',generations:{favorites:1,watched:0,progress:0}},
   'families/f/profiles/joao/favorites/c1':{contentId:'c1',generation:1},
   'families/f/profiles/joao/watched/c2':{contentId:'c2',generation:0},
   'families/f/profile_links/member':{profileId:'joao'},
   'families/f/profile_clear_jobs/joao_favorites':{status:'completed'},
   'profile_link_codes/h':{familyId:'f',profileId:'joao'},
   'families/g':{adminId:'other',members:{other:'admin'}},
   'families/g/profiles/x':{name:'X'},
  }))await setDoc(doc(db,path),data);
 });
 const tvDb=env.authenticatedContext('tv_tv',{deviceId:'tv',familyId:'f'}).firestore();
 for(const path of ['families/f/profiles/joao','families/f/profiles/joao/favorites/c1','families/f/profiles/joao/watched/c2'])await assertFails(getDoc(doc(tvDb,path)));
 await assertFails(getDoc(doc(tvDb,'families/g/profiles/x')));
 await assertFails(setDoc(doc(tvDb,'families/f/profiles/joao/favorites/c9'),{contentId:'c9',generation:0}));
 await assertFails(setDoc(doc(tvDb,'families/f/profiles/joao'),{generations:{favorites:0}},{merge:true}));
 const member=env.authenticatedContext('member').firestore();
 await assertSucceeds(getDoc(doc(member,'families/f/profile_links/member')));
 await assertFails(getDoc(doc(member,'families/f/profile_clear_jobs/joao_favorites')));
 await assertFails(deleteDoc(doc(member,'families/f/profiles/joao/favorites/c1')));
 const admin=env.authenticatedContext('admin').firestore();
 await assertSucceeds(getDoc(doc(admin,'families/f/profile_clear_jobs/joao_favorites')));
 await assertFails(deleteDoc(doc(admin,'families/f/profiles/joao/favorites/c1')));
 for(const db of [admin,member,tvDb])await assertFails(getDoc(doc(db,'profile_link_codes/h')));
 await assertFails(getDoc(doc(env.authenticatedContext('outsider').firestore(),'families/f/profiles/joao')));
});

test('play requests: the TV reads only its own (current credential); the requester follows its own; nobody writes',async()=>{
 await env.withSecurityRulesDisabled(async c=>{
  const db=c.firestore();
  for(const [path,data] of Object.entries({
   'families/f/devices/tv2':{name:'Quarto',credentialVersion:'cv2'},
   'families/f/devices/tv2/play_requests/r1':{requesterUid:'member',status:'pending',deviceId:'tv2'},
   'families/f/devices/tv/play_requests/r2':{requesterUid:'admin',status:'pending',deviceId:'tv'},
  }))await setDoc(doc(db,path),data);
 });
 const tv2=env.authenticatedContext('tv_tv2',{deviceId:'tv2',familyId:'f',credentialVersion:'cv2'}).firestore();
 await assertSucceeds(getDoc(doc(tv2,'families/f/devices/tv2/play_requests/r1')));
 await assertSucceeds(getDocs(collection(tv2,'families/f/devices/tv2/play_requests')));
 await assertFails(getDoc(doc(tv2,'families/f/devices/tv/play_requests/r2')));
 await assertFails(setDoc(doc(tv2,'families/f/devices/tv2/play_requests/r1'),{status:'started'}));
 // A TV credential from before re-pairing (old credentialVersion) is refused.
 const stale=env.authenticatedContext('tv_tv2',{deviceId:'tv2',familyId:'f',credentialVersion:'old'}).firestore();
 await assertFails(getDoc(doc(stale,'families/f/devices/tv2/play_requests/r1')));
 const member=env.authenticatedContext('member').firestore();
 await assertSucceeds(getDoc(doc(member,'families/f/devices/tv2/play_requests/r1')));
 await assertFails(getDoc(doc(member,'families/f/devices/tv/play_requests/r2')));
 await assertFails(setDoc(doc(member,'families/f/devices/tv2/play_requests/new'),{requesterUid:'member',status:'pending'}));
 const admin=env.authenticatedContext('admin').firestore();
 await assertSucceeds(getDoc(doc(admin,'families/f/devices/tv2/play_requests/r1')));
 await assertFails(getDoc(doc(env.authenticatedContext('outsider').firestore(),'families/f/devices/tv2/play_requests/r1')));
 // The parental PIN hash is never readable by any client.
 await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'families/f/private/parental'),{pinHash:'x',salt:'y'}));
 for(const db of [admin,member,tv2])await assertFails(getDoc(doc(db,'families/f/private/parental')));
});

test('one account, one family: clients cannot create families, move themselves or read other families',async()=>{
 const db=env.authenticatedContext('outsider').firestore();
 await assertFails(setDoc(doc(db,'families/mine'),{adminId:'outsider',members:{outsider:'admin'}}));
 await assertFails(setDoc(doc(db,'users/outsider'),{uid:'outsider',name:'O',email:'o@example.invalid',updatedAt:1,familyId:'mine',homeFamilyId:'mine',photoUrl:'https://example.invalid/a.png'}));
 const member=env.authenticatedContext('member').firestore();
 await assertFails(updateDoc(doc(member,'families/f'),{members:{member:'admin',admin:'member'}}));
 await assertFails(setDoc(doc(member,'users/member'),{photoUrl:'https://example.invalid/a.png'},{merge:true}));
 await assertFails(getDoc(doc(db,'families/f/members/admin')));
});
