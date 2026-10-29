import {getFirestore} from 'firebase-admin/firestore';
import {getStorage} from 'firebase-admin/storage';
import {z} from 'zod';
import {catalogSchema, Catalog, fetchProvider, privateProvidersAllowedForTests, publicAddress} from './catalog';
import {canStartPlayback, DomainError, hash, idSchema, sourceSchema, unseal} from './domain';
import {iptvWorkspace} from './iptv_workspace';
import {requireSourceAccess} from './iptv_sources';
import {findM3uStream, normalizeSeriesDetail, playlistBody, Source, validateXtream, xtreamUrl} from './iptv_ingestion';
import {streamIndexPath} from './iptv_sync';
import {parseXtreamJson} from './iptv_adapters';
import {xtreamBase} from './iptv_server';
import {lookup} from 'node:dns/promises';
import {activePlayer,type Identity} from './service';
import {classifyAudience, isAdultContent} from './content_audience';
import {CONTENT_KINDS, profileView, ProfileView, spaceAllowed} from './family_profiles';
import {consumeAdultUnlock} from './parental';
import {mobileLease, mobileSessionRef} from './mobile_playback';
import {TitleResolver, type LibraryList} from './library';

type Kind='channel'|'movie'|'series';
const fold=(v:string)=>v.normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
/** Active profile restrictions. null = unrestricted (personal scope, unlinked manager, administrator
 * without a profile). */
export type Viewer = ProfileView | null;
export function canSee(viewer:Viewer,sourceId:string,item:{kind:Kind;title?:string;category?:string;ageRating?:string;isAdult?:boolean}) {
  if(!viewer)return true;
  // O administrador vê tudo, exceto conteúdo adulto quando ele mesmo desligou o próprio "Conteúdo adulto".
  // Content types (Canais, Filmes, Séries) apply to every profile, the administrator's own choice included.
  if(viewer.type==='admin')return viewer.permissions.kinds.includes(item.kind)&&(viewer.permissions.adult||!isAdultContent(item));
  if(!spaceAllowed(viewer.permissions,sourceId,item.kind))return false;
  // Adult content off (administrator limit or the member's own, narrower preference).
  if(!viewer.permissions.adult&&isAdultContent(item))return false;
  // Mandatory and not configurable: kids profiles only receive positively identified children's content.
  return viewer.type!=='kids'||classifyAudience(item)==='kids';
}
async function resolveViewer(tx:FirebaseFirestore.Transaction,actor:Identity,fid:string,family:FirebaseFirestore.DocumentData|undefined,requested:unknown):Promise<Viewer> {
  const db=getFirestore();
  if(actor.deviceId) {
    // The profile comes from the device's server-side lease, never from the request alone.
    const lease=(family?.leases??[]).find((l:any)=>l.deviceId===actor.deviceId&&l.expiresAt>Date.now());
    if(!lease)throw new DomainError('session-expired');
    if(requested!==undefined&&requested!==lease.profileId)throw new DomainError('permission-denied');
    const snap=await tx.get(db.doc(`families/${fid}/profiles/${lease.profileId}`));
    if(!snap.exists)throw new DomainError('profile-unavailable');
    const view=profileView(snap.id,snap.data()!);
    if(!view.enabled)throw new DomainError('profile-disabled');
    return view;
  }
  if(family?.kind==='personalIptv')return null;
  const admin=(family?.adminUid??family?.adminId)===actor.uid;
  const link=await tx.get(db.doc(`families/${fid}/profile_links/${actor.uid}`));
  const profileId=link.data()?.profileId??(admin?'admin':undefined);
  if(!profileId)return null;
  const snap=await tx.get(db.doc(`families/${fid}/profiles/${profileId}`));
  if(!snap.exists)return null;
  const view=profileView(snap.id,snap.data()!);
  // The administrator manages every profile, so the Control shows every type; adult content
  // follows the administrator's own "Conteúdo adulto", as on the TV.
  return admin?{...view,permissions:{...view.permissions,kinds:[...CONTENT_KINDS]}}:view;
}

/** Shared objects are never public or signed into bearer download URLs. */
const cache=new Map<string,Catalog>();
/** `mobileSession`: the Control's phone player session (playback only; see mobile_playback.ts). */
export async function authorize(actor:Identity,id:string,playback=false,requestedProfile?:unknown,mobileSession?:unknown) {
  const db=getFirestore();
  return db.runTransaction(async tx=>{
    let fid:string, familyData:FirebaseFirestore.DocumentData|undefined, phoneProfile:string|undefined;
    if(actor.deviceId) {
      if(actor.uid!==`tv_${actor.deviceId}`||!actor.familyId)throw new DomainError('permission-denied');
      fid=actor.familyId;
      const [family,device,subscription]=await tx.getAll(db.doc(`families/${fid}`),db.doc(`families/${fid}/devices/${actor.deviceId}`),db.doc(`families/${fid}/private/subscription`));
      if(!family?.exists||family.data()?.deleting||!device?.exists)throw new DomainError('device-revoked');
      if(!canStartPlayback(subscription?.data() as any,Date.now()))throw new DomainError('subscription-required');
      if(!family.data()?.leases?.some((l:any)=>l.deviceId===actor.deviceId&&l.expiresAt>Date.now()))throw new DomainError('session-expired');
      if(device.data()?.credentialVersion&&device.data()?.credentialVersion!==actor.credentialVersion)throw new DomainError('device-revoked');
      familyData=family.data();
    }else {
      const scope=await iptvWorkspace(tx,actor,false,false);fid=scope.fid;familyData=scope.data;
      // The Control only plays inside its own phone session (same rules as a TV).
      if(playback){
        if(mobileSession===undefined||mobileSession===null)throw new DomainError('player-required');
        phoneProfile=mobileLease({fid,ref:scope.ref,data:scope.data},actor.uid,mobileSession).profileId;
        const subscription=await tx.get(db.doc(`families/${fid}/private/subscription`));
        if(!canStartPlayback(subscription.data() as any,Date.now()))throw new DomainError('subscription-required');
      }
    }
    const viewer=await resolveViewer(tx,actor,fid,familyData,requestedProfile);
    // The phone plays with the profile of its lease only.
    if(phoneProfile!==undefined&&viewer&&viewer.id!==phoneProfile)throw new DomainError('permission-denied');
    const ref=db.doc(`families/${fid}/sources/${id}`), source=await tx.get(ref), data=source.data();
    if(!data||!data.enabled||!data.version)throw new DomainError('not-found');
    await requireSourceAccess(tx,ref,data,actor.uid);
    if(playback&&(data.authorizationStatus!=='valid'||data.authorizationRevision!==data.revision))throw new DomainError('source-authorization-required');
    return {fid,ref,data,viewer};
  });
}
export async function load(version:string):Promise<Catalog> {
  if(cache.has(version))return cache.get(version)!;
  if(!/^[a-f0-9]{64}$/.test(version))throw new DomainError('invalid-catalog');
  const record=(await getFirestore().doc(`catalogs/${version}`).get()).data();
  const [body]=await getStorage().bucket().file(record?.storagePath??`catalogs/${version}.json`).download();
  if(body.length>64*1024*1024 || (record?.integrityHash&&hash(body.toString())!==record.integrityHash))throw new DomainError('catalog-integrity');
  const catalog=catalogSchema.parse(JSON.parse(body.toString()));
  if(cache.size>=2)cache.delete(cache.keys().next().value!);
  cache.set(version,catalog);return catalog;
}
const sortedCache=new Map<string,Catalog['items']>();
function sortedItems(version:string,catalog:Catalog):Catalog['items'] {
  let sorted=sortedCache.get(version);
  if(!sorted){
    sorted=[...catalog.items].sort((a,b)=>a.titleKey.localeCompare(b.titleKey)||a.id.localeCompare(b.id));
    if(sortedCache.size>=4)sortedCache.delete(sortedCache.keys().next().value!);
    sortedCache.set(version,sorted);
  }
  return sorted;
}
export async function readSourceCatalog(input:Record<string,unknown>,actor:Identity) {
  const id=idSchema.parse(input.id), access=await authorize(actor,id,false,input.profileId);
  const version=access.data.version as string;
  if(input.version && input.version!==version)throw new DomainError('source-conflict');
  const search=z.string().max(300).parse(input.search??'').trim().toLowerCase().normalize('NFKD');
  const offset=z.number().int().min(0).max(100000).parse(input.cursor??0);
  // Page size (Control feed: 40); the default stays 30 for older clients.
  const limit=z.number().int().min(1).max(60).parse(input.limit??30);
  // Optional: one kind only (Control tabs Canais / Filmes / Séries).
  const kind=input.kind===undefined||input.kind===null?null:z.enum(['channel','movie','series']).parse(input.kind);
  // Optional: the Control's "Adulto" tab (true) or every other list and the search (false); as on
  // the TV, adult content only exists in its own section. Absent: everything (older clients).
  const adult=input.adult===undefined||input.adult===null?null:z.boolean().parse(input.adult);
  const catalog=await load(version);
  // Sorted once per published version (a page request no longer sorts 100k titles).
  const sorted=sortedItems(version,catalog);
  const visible=sorted.filter(i=>canSee(access.viewer,id,i));
  // A space the profile cannot use does not exist for it.
  if(access.viewer&&!visible.length&&catalog.items.length)throw new DomainError('not-found');
  // Matches anywhere in the title, ignoring case and accents.
  const needle=fold(search);
  const items=visible.filter(i=>(!kind||i.kind===kind)&&(adult===null||isAdultContent(i)===adult)&&(!needle||fold(i.titleKey).includes(needle)));
  const latest=await authorize(actor,id,false,input.profileId);
  if(latest.fid!==access.fid||latest.data.version!==version||latest.data.revision!==access.data.revision)throw new DomainError('source-conflict');
  const shown=new Set(visible.map(i=>`${i.kind}:${i.categoryId??i.category}`));
  return {schemaVersion:1,version,items:items.slice(offset,offset+limit).map(i=>({...i,id:hash(`${id}:${i.id}`),catalogItemId:i.id,sourceId:id,version})),
    categories:(catalog.categories??[]).filter(c=>!access.viewer||shown.has(`${c.kind}:${c.id}`)||shown.has(`${c.kind}:${c.name}`)),cursor:offset+limit,hasMore:offset+limit<items.length};
}

/** Individual stream URLs only leave the backend for an authenticated, paired
 * Player with a current session and fresh provider validation. They are never
 * stored in a shared artifact, notification or Firestore item. */
export async function resolveSourceStream(input:Record<string,unknown>,actor:Identity,key:string) {
  const id=idSchema.parse(input.id), itemId=idSchema.parse(input.itemId), access=await authorize(actor,id,true,input.profileId,input.sessionId);
  const secret=(await getFirestore().doc(`source_secrets/${access.fid}_${id}`).get()).data();
  if(!secret||secret.revision!==access.data.revision)throw new DomainError('source-conflict');
  const source=sourceSchema.parse(unseal<Source>(secret.encrypted,key));
  const catalog=await load(access.data.version);
  const item=catalog.items.find(i=>i.id===itemId||hash(`${id}:${i.id}`)===itemId);
  if(!item||!canSee(access.viewer,id,item))throw new DomainError('not-found');
  // Conteúdo adulto só toca depois do PIN parental (desbloqueio de uso único, por perfil e dispositivo).
  if(isAdultContent(item)){
    const unlock=actor.deviceId?getFirestore().doc(`families/${access.fid}/devices/${actor.deviceId}`):mobileSessionRef(getFirestore().doc(`families/${access.fid}`),actor.uid);
    await consumeAdultUnlock(unlock,access.viewer?.id,access.viewer?.pinConfigured===true);
  }
  let url:string|undefined;
  // Series episodes are addressed by their own reference and must belong to the item the profile may see.
  const episodeOf=()=>{
    const ref=idSchema.parse(input.episodeId);
    if(!((catalog.seriesDetails?.[item.providerRef] as any)?.episodes&&Object.values((catalog.seriesDetails![item.providerRef] as any).episodes).flat().some((e:any)=>e?.id===ref)))throw new DomainError('not-found');
    return ref;
  };
  // Catalogs built from the Xtream M3U Plus export (API unavailable) carry a sealed index of this version.
  const sealed=source.format==='xtream'&&(item.kind!=='series'||catalog.seriesDetails?.[item.providerRef])
    ?await sealedStream(access.fid,id,access.data,item.kind==='series'?episodeOf():item.providerRef,key):undefined;
  if(sealed)url=sealed;
  else if(source.format==='xtream') {
    await validateXtream(source,fetchProvider);
    const action=item.kind==='channel'?'get_live_streams':item.kind==='movie'?'get_vod_streams':'get_series';
    const rows=z.array(z.record(z.unknown())).parse(JSON.parse(await fetchProvider(xtreamUrl(source,action))));
    const row=rows.find(r=>String(r.stream_id??r.series_id)===item.providerRef);
    if(!row)throw new DomainError('source-authorization-required');
    let streamId=item.providerRef, extension=item.kind==='channel'?'ts':String(row.container_extension??'');
    if(item.kind==='series') {
      const episodeId=idSchema.parse(input.episodeId);
      const details=JSON.parse(await fetchProvider(xtreamUrl(source,'get_series_info',{series_id:item.providerRef})));
      const episodes=Object.values(details.episodes??{}).flat() as any[];
      const episode=episodes.find(e=>String(e.id)===episodeId);
      if(!episode)throw new DomainError('source-authorization-required');
      streamId=episodeId;extension=String(episode.container_extension??'');
    }
    if(!/^\d+$/.test(streamId)||!/^\w{1,10}$/.test(extension))throw new DomainError('invalid-catalog');
    const kind=item.kind==='channel'?'live':item.kind;
    url=new URL(`${kind}/${encodeURIComponent(source.username!)}/${encodeURIComponent(source.password!)}/${streamId}.${extension}`,xtreamBase(source.url!)).toString();
  } else {
    const ref=item.kind==='series'?episodeOf():item.providerRef;
    url=await sealedStream(access.fid,id,access.data,ref,key)??findM3uStream(await playlistBody(source,access.fid,id,fetchProvider),source.url??'',ref);
  }
  if(!url)throw new DomainError('source-authorization-required');
  const parsed=new URL(url);
  if(!['http:','https:'].includes(parsed.protocol)||parsed.username||parsed.password)throw new DomainError('unsafe-provider');
  const addresses=await lookup(parsed.hostname.replace(/^\[|\]$/g,''),{all:true});
  if(!addresses.length||(!privateProvidersAllowedForTests()&&addresses.some(a=>!publicAddress(a.address))))throw new DomainError('unsafe-provider');
  // Permissions are revalidated right before the URL leaves the backend.
  const latest=await authorize(actor,id,true,input.profileId,input.sessionId);
  if(latest.data.revision!==access.data.revision||latest.data.version!==access.data.version||!canSee(latest.viewer,id,item))throw new DomainError('source-conflict');
  return {url,sourceId:id,validatedAt:Date.now()};
}
export async function readSourceSeries(input:Record<string,unknown>,actor:Identity,key='') {
  const id=idSchema.parse(input.id), seriesId=idSchema.parse(input.seriesId), access=await authorize(actor,id,false,input.profileId);
  const catalog=await load(access.data.version);
  const item=catalog.items.find(i=>i.kind==='series'&&(i.providerRef===seriesId||i.id===seriesId||hash(`${id}:${i.id}`)===seriesId));
  if(access.viewer&&(!item||!canSee(access.viewer,id,item)))throw new DomainError('not-found');
  const details=catalog.seriesDetails?.[seriesId]??(item&&key?await xtreamSeriesDetails(access.fid,id,access.data,item.providerRef,key):null);
  const latest=await authorize(actor,id,false,input.profileId);
  if(latest.data.version!==access.data.version||latest.data.revision!==access.data.revision)throw new DomainError('source-conflict');
  return {schemaVersion:1,seriesId,details};
}

/** Sealed index written by the sync worker; null when absent or from another revision/version. */
async function sealedStream(fid:string,sourceId:string,data:FirebaseFirestore.DocumentData,ref:string,key:string):Promise<string|undefined> {
  try{
    const [body]=await getStorage().bucket().file(streamIndexPath(fid,sourceId)).download();
    const index=unseal<{version:string;revision:number;streams:Record<string,string>}>(body.toString(),key);
    if(index.version!==data.version||index.revision!==data.revision)return undefined;
    return index.streams[ref];
  }catch{return undefined;}
}

/** Xtream episodes on demand (one get_series_info per opened series), cached per
 * catalog version for 6 h. Episode metadata carries no credential. */
const seriesCache=new Map<string,{at:number;details:unknown}>();
async function xtreamSeriesDetails(fid:string,sourceId:string,data:FirebaseFirestore.DocumentData,seriesId:string,key:string):Promise<unknown> {
  if(!/^\d{1,20}$/.test(seriesId))return null;
  const cacheKey=`${data.version}:${sourceId}:${seriesId}`,path=`series_cache/${data.version}/${sourceId}_${seriesId}.json`,now=Date.now();
  const hit=seriesCache.get(cacheKey);
  if(hit&&now-hit.at<6*3600_000)return hit.details;
  const file=getStorage().bucket().file(path);
  try{
    const [meta]=await file.getMetadata();
    if(now-Date.parse(String(meta.updated))<6*3600_000){
      const [body]=await file.download();const details=JSON.parse(body.toString());
      seriesCache.set(cacheKey,{at:now,details});return details;
    }
  }catch{/* not cached yet */}
  const secret=(await getFirestore().doc(`source_secrets/${fid}_${sourceId}`).get()).data();
  if(!secret||secret.revision!==data.revision)throw new DomainError('source-conflict');
  const source=sourceSchema.parse(unseal<Source>(secret.encrypted,key));
  if(source.format!=='xtream')return null;
  const raw=parseXtreamJson(await fetchProvider(xtreamUrl(source,'get_series_info',{series_id:seriesId})),'series-info');
  if(!raw||typeof raw!=='object'||!raw.episodes||typeof raw.episodes!=='object')return null;
  const details=normalizeSeriesDetail(raw);
  await file.save(JSON.stringify(details),{resumable:false,contentType:'application/json'}).catch(()=>undefined);
  if(seriesCache.size>500)seriesCache.delete(seriesCache.keys().next().value!);
  seriesCache.set(cacheKey,{at:now,details});
  return details;
}

/** Spaces (source + content type) available to the active profile. Kids profiles
 * only receive spaces that contain identified children's content. */
export async function listProfileSpaces(input:Record<string,unknown>,actor:Identity) {
  const db=getFirestore();
  const context=await db.runTransaction(async tx=>{
    let fid:string,familyData:FirebaseFirestore.DocumentData|undefined;
    if(actor.deviceId){
      if(actor.uid!==`tv_${actor.deviceId}`||!actor.familyId)throw new DomainError('permission-denied');
      fid=actor.familyId;
      const context=await activePlayer(tx,actor,input.profileId);
      familyData=context.data;
    } else {const scope=await iptvWorkspace(tx,actor,false,false);fid=scope.fid;familyData=scope.data;}
    const viewer=await resolveViewer(tx,actor,fid,familyData,input.profileId);
    const sources=(await tx.get(db.collection(`families/${fid}/sources`))).docs.filter(d=>d.data().enabled&&d.data().version);
    return {viewer,sources};
  });
  const spaces:{sourceId:string;name:string;kinds:Kind[];unavailable?:boolean;lastSyncAt?:number;syncing?:boolean}[]=[];
  for(const source of context.sources){
    const catalog=await load(source.data().version);
    const kinds=(['channel','movie','series'] as Kind[]).filter(kind=>catalog.items.some(i=>i.kind===kind&&canSee(context.viewer,source.id,i)));
    // The user's IPTV source is failing (invalid credentials or last sync errored): the TV shows the watermark.
    const broken=source.data().authorizationStatus==='invalid'||source.data().status==='error';
    // When the list was last updated (successful sync), shown in the TV settings.
    const synced=source.data().lastSuccessfulSyncAt??source.data().lastSyncAt;
    // A sync was requested (Gestor, TV or schedule) and has not finished: the TV settings show it.
    const syncing=source.data().status==='queued'||source.data().status==='syncing';
    if(kinds.length)spaces.push({sourceId:source.id,name:String(source.data().name??''),kinds,...(broken?{unavailable:true}:{}),...(typeof synced==='number'?{lastSyncAt:synced}:{}),...(syncing?{syncing:true}:{})});
  }
  return {profileId:context.viewer?.id??null,permissionsVersion:context.viewer?.permissionsVersion??null,spaces};
}

/** EPG follows catalog visibility: a restricted profile only gets the guide of channels it can see. */
export async function assertChannelVisible(actor:Identity,sourceId:string,channelId:string) {
  const access=await authorize(actor,sourceId);
  if(!access.viewer)return;
  const catalog=await load(access.data.version);
  if(!catalog.items.some(i=>i.kind==='channel'&&i.epgId===channelId&&canSee(access.viewer,sourceId,i)))throw new DomainError('not-found');
}

/** TMDB only enriches a catalog item the current leased profile can see. */
export async function authorizeMetadata(input:Record<string,unknown>,actor:Identity) {
 const sourceId=idSchema.parse(input.sourceId),itemId=idSchema.parse(input.itemId);
 const access=await authorize(actor,sourceId),catalog=await load(access.data.version);
 const item=catalog.items.find(i=>hash(`${sourceId}:${i.id}`)===itemId||i.id===itemId);
 if(!item||item.kind==='channel'||!canSee(access.viewer,sourceId,item))throw new DomainError('not-found');
 const latest=await authorize(actor,sourceId);
 if(latest.data.version!==access.data.version||!canSee(latest.viewer,sourceId,item))throw new DomainError('source-conflict');
 return {kind:item.kind,title:item.title,year:item.year??null};
}

/** Remote play requests: the item exists in the published catalog and the actor's
 * profile (person) or the TV's leased profile (device) may see it. */
export async function playableItem(actor:Identity,sourceId:string,itemId:string) {
 const access=await authorize(actor,sourceId),catalog=await load(access.data.version);
 const item=catalog.items.find(i=>hash(`${sourceId}:${i.id}`)===itemId);
 if(!item||!canSee(access.viewer,sourceId,item))throw new DomainError('not-found');
 return {fid:access.fid,kind:item.kind,title:item.title,providerRef:item.providerRef,year:item.year,imageRef:item.imageRef};
}

/** Public id (the one readSourceCatalog returns) → catalog item, per published version. */
const indexes=new Map<string,Map<string,Catalog['items'][number]>>();
function itemIndex(version:string,sourceId:string,catalog:Catalog) {
  const key=`${version}:${sourceId}`;
  let index=indexes.get(key);
  if(!index){
    index=new Map(catalog.items.map(i=>[hash(`${sourceId}:${i.id}`),i]));
    if(indexes.size>=4)indexes.delete(indexes.keys().next().value!);
    indexes.set(key,index);
  }
  return index;
}
const HOME_ROW=10;
/** Sections of the Control Home that "Ver tudo" can open whole. */
export const HOME_SECTIONS=['favorites','continueWatching','wishlist','releases','watched','recentMovies','recentSeries','recentSearches'] as const;
/** "Lançamentos" of the Home: the newest titles of each kind, merged (same rule as the TV "Meu iPlex"). */
const RELEASES_PER_KIND=5;
const SECTION_MAX=100;
type Item=Catalog['items'][number];
type Visible={sourceId:string;sourceName:string;version:string;item:Item};
const publicItem=(v:Visible,id:string)=>({...v.item,id,catalogItemId:v.item.id,sourceId:v.sourceId,sourceName:v.sourceName,version:v.version});

/** Items of every enabled, unlocked source the actor's profile can see, by public id.
 * `known` also holds the ids the profile cannot see (a saved link to one hides the entry). */
async function visibleCatalog(actor:Identity,sources:FirebaseFirestore.QueryDocumentSnapshot[],onSource?:(source:FirebaseFirestore.QueryDocumentSnapshot,access:Awaited<ReturnType<typeof authorize>>,catalog:Catalog,name:string)=>void) {
  const visible=new Map<string,Visible>(),known=new Set<string>();
  for(const source of sources){
    let access;
    try{access=await authorize(actor,source.id);}
    catch(e){if(e instanceof DomainError&&['not-found','pin-required'].includes(e.code))continue;throw e;}
    const version=access.data.version as string,catalog=await load(version),name=String(source.data().name??'');
    for(const [id,item] of itemIndex(version,source.id,catalog)){known.add(id);if(canSee(access.viewer,source.id,item))visible.set(id,{sourceId:source.id,sourceName:name,version,item});}
    onSource?.(source,access,catalog,name);
  }
  return {visible,known};
}
const candidates=(visible:Map<string,Visible>)=>new Map([...visible].map(([id,v])=>[id,{id,sourceId:v.sourceId,kind:v.item.kind,title:v.item.title,year:v.item.year,tmdbId:v.item.tmdbId}]));

async function homeScope(actor:Identity) {
  const db=getFirestore();
  return db.runTransaction(async tx=>{
    const scope=await iptvWorkspace(tx,actor,false,false);
    const profileId=(await tx.get(scope.ref.collection('profile_links').doc(actor.uid))).data()?.profileId;
    const snap=typeof profileId==='string'?await tx.get(scope.ref.collection('profiles').doc(profileId)):null;
    const sources=(await tx.get(scope.ref.collection('sources'))).docs.filter(d=>d.data().enabled&&d.data().version);
    return {ref:scope.ref,profile:snap?.exists&&snap.data()?.deleting!==true?profileView(snap.id,snap.data()!):null,sources};
  });
}

/** Control Home ("Meu iPlex" of the account's own profile): favorites, wishlist, progress
 * and the recently added titles of the selected source. Catalog items are resolved with
 * the same scope and visibility rules as readSourceCatalog; saved titles that no catalog
 * offers (yet) are returned as editorial entries (`available: false`) for non-kids
 * profiles. Generations cleared in the Gestor are ignored, as on the TV.
 * `favorites`/`myList`/`favoriteIds` keep the previous contract for older builds. */
export async function readHome(input:Record<string,unknown>,actor:Identity) {
  if(actor.deviceId)throw new DomainError('permission-denied');
  const selected=input.sourceId===undefined||input.sourceId===null?null:idSchema.parse(input.sourceId);
  const recentSearchIds=z.array(idSchema).max(HOME_ROW).parse(input.recentSearchIds??[]);
  // "Ver tudo": one section returned whole (bounded); the others keep the Home size.
  const full=input.section===undefined||input.section===null?null:z.enum(HOME_SECTIONS).parse(input.section);
  const rowLimit=(section:typeof HOME_SECTIONS[number])=>full===section?SECTION_MAX:HOME_ROW;
  const context=await homeScope(actor);
  const recentMovies:Record<string,unknown>[]=[],recentSeries:Record<string,unknown>[]=[],releases:Record<string,unknown>[]=[];
  // Kinds with adult content the profile can see in the selected source: the "Adulto" tab.
  const adultKinds:Kind[]=[];
  const {visible,known}=await visibleCatalog(actor,context.sources,(source,access,catalog,name)=>{
    if(source.id!==selected)return;
    // Only providers that publish an "added" date: nothing is guessed for the others.
    for(const kind of CONTENT_KINDS)if(catalog.items.some(i=>i.kind===kind&&isAdultContent(i)&&canSee(access.viewer,source.id,i)))adultKinds.push(kind);
    // Never adult: it only exists in the "Adulto" tab.
    const newest=(kind:Kind)=>catalog.items.filter(i=>i.kind===kind&&i.addedAt&&!isAdultContent(i)&&canSee(access.viewer,source.id,i))
      .sort((a,b)=>b.addedAt!-a.addedAt!||a.titleKey.localeCompare(b.titleKey));
    const pub=(i:Item)=>publicItem({sourceId:source.id,sourceName:name,version:access.data.version,item:i},hash(`${source.id}:${i.id}`));
    const movies=newest('movie'),series=newest('series');
    recentMovies.push(...movies.slice(0,rowLimit('recentMovies')).map(pub));recentSeries.push(...series.slice(0,rowLimit('recentSeries')).map(pub));
    // Lançamentos: never adult (even when allowed, adult content stays in its own category).
    const perKind=full==='releases'?SECTION_MAX:RELEASES_PER_KIND;
    releases.push(...[...movies.slice(0,perKind),...series.slice(0,perKind)]
      .sort((a,b)=>b.addedAt!-a.addedAt!||a.titleKey.localeCompare(b.titleKey)).slice(0,full==='releases'?SECTION_MAX:RELEASES_PER_KIND*2).map(pub));
  });
  const profile=context.profile;
  const resolved=(id:string)=>{const v=visible.get(id);return v?publicItem(v,id):null;};
  const recentSearches:Record<string,unknown>[]=[];
  if(profile?.type!=='guest')for(const id of new Set(recentSearchIds)){const item=resolved(id);if(item&&!isAdultContent(item))recentSearches.push(item);}
  // Personal rows (guest: none) never carry adult content, as on the TV "Meu iPlex".
  const {favoriteIds,favorites,myList,continueWatching,library,saved}=profile&&profile.type!=='guest'
    ?await profileLibrary(context.ref,profile,visible,known,selected,rowLimit,full==='continueWatching'?SECTION_MAX:50,true)
    :emptyLibrary();
  const watched=profile&&profile.type!=='guest'?await watchedTitles(context.ref,profile,visible,rowLimit('watched'),true):[];
  return {schemaVersion:2,selectedSourceId:selected,
    profile:profile?{id:profile.id,name:profile.name,type:profile.type,generations:profile.generations}:null,
    favoriteIds,favorites,myList,continueWatching,releases,watched,recentMovies,recentSeries,recentSearches,library,saved,adultKinds};
}

type RowLimit=(section:typeof HOME_SECTIONS[number])=>number;
const emptyLibrary=()=>({favoriteIds:[] as string[],favorites:[] as Record<string,unknown>[],myList:[] as Record<string,unknown>[],
  continueWatching:[] as Record<string,unknown>[],library:{favorites:[],wishlist:[]} as Record<LibraryList,Record<string,unknown>[]>,
  saved:{favorites:[],wishlist:[]} as Record<LibraryList,string[]>});

/** Favorites, wishlist and progress of one profile resolved against the visible catalog
 * (shared by the Home and the member details page). Saved titles that no catalog offers
 * are editorial entries (`available: false`) for non-kids profiles. */
async function profileLibrary(family:FirebaseFirestore.DocumentReference,profile:ProfileView,visible:Map<string,Visible>,known:Set<string>,selected:string|null,rowLimit:RowLimit,progressLimit:number,noAdult=false) {
  const resolved=(id:string)=>{const v=visible.get(id);return v?publicItem(v,id):null;};
  // Home rows: adult titles stay saved (keys) but are not listed.
  const listed=(item:Record<string,unknown>)=>!(noAdult&&isAdultContent(item));
  const favoriteIds:string[]=[],favorites:Record<string,unknown>[]=[],myList:Record<string,unknown>[]=[],continueWatching:Record<string,unknown>[]=[];
  const library:Record<LibraryList,Record<string,unknown>[]>={favorites:[],wishlist:[]};
  const saved:Record<LibraryList,string[]>={favorites:[],wishlist:[]};
  {
    const ref=family.collection('profiles').doc(profile.id);
    const [fav,wish,progress]=await Promise.all([
      ref.collection('favorites').orderBy('updatedAt','desc').limit(100).get(),
      ref.collection('wishlist').orderBy('updatedAt','desc').limit(100).get(),
      ref.collection('watch_progress').orderBy('updatedAt','desc').limit(progressLimit).get(),
    ]);
    const resolver=new TitleResolver(candidates(visible),known,selected);
    const links=getFirestore().batch();let linkWrites=0;
    for(const [list,rows] of [['favorites',fav],['wishlist',wish]] as const){
      const seen=new Set<string>();
      for(const doc of rows.docs){
        const d=doc.data();
        if(d.generation!==profile.generations[list]||typeof d.contentId!=='string')continue;
        const link=resolver.resolve(d);
        if(link.hidden)continue;
        const item=link.id?resolved(link.id):null;
        const canonical=typeof d.tmdbKey==='string'?`tmdb:${d.tmdbKey}`:item?`item:${item.id}`:`doc:${doc.id}`;
        if(seen.has(canonical)||(item&&seen.has(`item:${item.id}`)))continue;
        seen.add(canonical);if(item)seen.add(`item:${item.id}`);
        saved[list].push(...new Set([doc.id,d.contentId,...(typeof d.catalogContentId==='string'?[d.catalogContentId]:[]),...(item?[item.id as string]:[]),...(typeof d.tmdbKey==='string'?[`tmdb:${d.tmdbKey}`]:[])]));
        // Associate a saved title with the catalog item found later (same library row).
        if(item&&link.via!=='link'&&linkWrites<50){links.update(doc.ref,{contentId:item.id,catalogContentId:item.id,sourceId:item.sourceId});linkWrites++;}
        if(item&&!listed(item))continue;
        if(item){
          const entry={...item,library:{id:doc.id,...(typeof d.tmdbId==='number'?{tmdbId:d.tmdbId}:{})},available:true};
          if(library[list].length<rowLimit(list))library[list].push(entry);
          if(list==='favorites'){favoriteIds.push(item.id as string);const row=item.kind==='channel'?favorites:myList;if(row.length<HOME_ROW)row.push(item);}
        }else if(typeof d.tmdbId==='number'&&(d.kind==='movie'||d.kind==='series')&&profile.type!=='kids'){
          if(library[list].length<rowLimit(list))library[list].push({id:doc.id,kind:d.kind,title:String(d.title??''),tmdbId:d.tmdbId,
            ...(typeof d.originalTitle==='string'?{originalTitle:d.originalTitle}:{}),...(typeof d.year==='number'?{year:d.year}:{}),
            ...(typeof d.poster==='string'?{poster:d.poster}:{}),library:{id:doc.id,tmdbId:d.tmdbId},available:false});
        }
      }
    }
    // Best effort: a row removed or cleared meanwhile makes update fail, never resurrects it.
    if(linkWrites)await links.commit().catch(()=>{});
    // One entry per title (movies and series only), chosen before excluding completed playback:
    // an older unfinished episode never replaces a newer completed one (same rule as the TV).
    const seenTitles=new Set<string>();
    for(const doc of progress.docs){
      const d=doc.data();
      if(continueWatching.length>=rowLimit('continueWatching')||d.generation!==profile.generations.progress||typeof d.contentId!=='string')continue;
      // Episodes are saved as `<seriesItemId>_e<episodeId>` (same contract as the TV).
      const episode=/^([A-Za-z0-9-]+)_e([A-Za-z0-9_-]+)$/.exec(d.contentId);
      const item=resolved(episode?episode[1]!:d.contentId);
      if(!item||!listed(item)||item.kind==='channel'||(episode&&item.kind!=='series')||(item.kind==='series'&&!episode)||seenTitles.has(item.id as string))continue;
      seenTitles.add(item.id as string);
      if(!(Number(d.duration)>0)||Number(d.position)/Number(d.duration)>=0.95)continue;
      continueWatching.push({...item,progress:{position:Number(d.position),duration:Number(d.duration),updatedAt:Number(d.updatedAt)||0},...(episode?{episodeId:episode[2]}:{})});
    }
  }
  return {favoriteIds,favorites,myList,continueWatching,library,saved};
}

/** Member details (Família › integrante): the library of one profile of the caller's
 * family, by kind, for the account linked to it or the family administrator only.
 * Also the history ("assistidos"). The guest never persists anything. */
export async function readProfileLibrary(input:Record<string,unknown>,actor:Identity) {
  if(actor.deviceId)throw new DomainError('permission-denied');
  const profileId=idSchema.parse(input.profileId);
  const db=getFirestore();
  const scope=await db.runTransaction(async tx=>{
    const ws=await iptvWorkspace(tx,actor,false,false);
    const [family,link,snap]=await tx.getAll(ws.ref,ws.ref.collection('profile_links').doc(actor.uid),ws.ref.collection('profiles').doc(profileId));
    const fd=family!.data()??{};
    const admin=(fd.adminUid??fd.adminId)===actor.uid||fd.members?.[actor.uid]==='admin';
    if(!snap!.exists||snap!.data()?.deleting===true)throw new DomainError('not-found');
    if(!admin&&link!.data()?.profileId!==profileId)throw new DomainError('permission-denied');
    const sources=(await tx.get(ws.ref.collection('sources'))).docs.filter(d=>d.data().enabled&&d.data().version);
    return {ref:ws.ref,profile:profileView(snap!.id,snap!.data()!),sources};
  });
  const profile=scope.profile;
  if(profile.type==='guest')return {profile:{id:profile.id,type:profile.type},favorites:[],wishlist:[],continueWatching:[],watched:[]};
  const {visible,known}=await visibleCatalog(actor,scope.sources);
  const lib=await profileLibrary(scope.ref,profile,visible,known,null,()=>SECTION_MAX,SECTION_MAX,true);
  // As on the TV, adult content is never listed with the profile's lists.
  const watched=(await watchedTitles(scope.ref,profile,visible,SECTION_MAX)).filter(i=>!isAdultContent(i));
  return {profile:{id:profile.id,type:profile.type},favorites:lib.library.favorites,wishlist:lib.library.wishlist,continueWatching:lib.continueWatching,watched};
}

/** History ("assistidos") of one profile, newest first, resolved against the visible catalog.
 * `home`: the Home row — one entry per title, movies and series only, never adult. */
async function watchedTitles(family:FirebaseFirestore.DocumentReference,profile:ProfileView,visible:Map<string,Visible>,limit:number,home=false) {
  const watched:Record<string,unknown>[]=[],seen=new Set<string>();
  const rows=await family.collection('profiles').doc(profile.id).collection('watched').orderBy('completedAt','desc').limit(SECTION_MAX).get();
  for(const doc of rows.docs){
    if(watched.length>=limit)break;
    const d=doc.data();
    if(d.generation!==profile.generations.watched||typeof d.contentId!=='string')continue;
    const episode=/^([A-Za-z0-9-]+)_e([A-Za-z0-9_-]+)$/.exec(d.contentId);
    const id=episode?episode[1]!:d.contentId,v=visible.get(id);
    if(!v||(episode&&v.item.kind!=='series'))continue;
    if(home&&(v.item.kind==='channel'||isAdultContent(v.item)||seen.has(id)))continue;
    seen.add(id);
    watched.push({...publicItem(v,id),watchedAt:Number(d.completedAt)||0,...(episode?{episodeId:episode[2]}:{})});
  }
  return watched;
}

const titleQuerySchema=z.object({kind:z.enum(['movie','series']),tmdbId:z.number().int().positive().max(999_999_999),
  title:z.string().trim().max(300).optional(),originalTitle:z.string().trim().max(300).optional(),year:z.number().int().min(1870).max(2100).optional(),sourceId:idSchema.nullish()});
/** Is an editorial title (TMDB) playable from the catalog this account's profile can see?
 * Returns the public catalog item only for a confident correspondence (see TitleResolver). */
export async function resolveTitle(input:Record<string,unknown>,actor:Identity) {
  if(actor.deviceId)throw new DomainError('permission-denied');
  const q=titleQuerySchema.parse({kind:input.kind,tmdbId:input.tmdbId,title:input.title,originalTitle:input.originalTitle,year:input.year,sourceId:input.sourceId});
  const context=await homeScope(actor);
  const {visible,known}=await visibleCatalog(actor,context.sources);
  // An editorial title never opens adult content (as on the TV).
  for(const [id,v] of visible)if(isAdultContent(v.item))visible.delete(id);
  const link=new TitleResolver(candidates(visible),known,q.sourceId??null).resolve(q);
  const v=link.id?visible.get(link.id):undefined;
  return {item:v?publicItem(v,link.id!):null,match:v?link.via:null};
}

/** Catalog item the account's profile can see right now (library writes). */
export async function libraryItem(actor:Identity,sourceId:string,itemId:string) {
  const access=await authorize(actor,sourceId),catalog=await load(access.data.version);
  const item=itemIndex(access.data.version,sourceId,catalog).get(itemId);
  if(!item||!canSee(access.viewer,sourceId,item))return null;
  return {kind:item.kind,title:item.title,year:item.year,tmdbId:item.tmdbId};
}

/** Library reads are now server-authorized; direct Firestore access is closed. */
export async function readPlayerLibrary(input:Record<string,unknown>,actor:Identity) {
 const db=getFirestore(),context=await db.runTransaction(tx=>activePlayer(tx,actor,input.profileId));
 if(context.view.type==='guest')return {favorites:[],wishlist:[],progress:[],watched:[]};
 const allowed=new Set<string>();
 const sources=await context.ref.collection('sources').where('enabled','==',true).get();
 for(const source of sources.docs){
  try{
   const access=await authorize(actor,source.id),catalog=await load(access.data.version);
   for(const item of catalog.items)if(canSee(access.viewer,source.id,item))allowed.add(hash(`${source.id}:${item.id}`));
  }catch(e){if(!(e instanceof DomainError)||!['not-found','pin-required'].includes(e.code))throw e;}
 }
 const profile=context.ref.collection('profiles').doc(context.view.id);
 const read=async(name:string,order:string)=> (await profile.collection(name).orderBy(order,'desc').limit(100).get()).docs
  .map(d=>d.data()).filter(d=>typeof d.contentId==='string'&&allowed.has(d.contentId.replace(/_e[A-Za-z0-9_-]+$/,'')));
 const [favorites,wishlist,progress,watched]=await Promise.all([read('favorites','updatedAt'),read('wishlist','updatedAt'),read('watch_progress','updatedAt'),read('watched','completedAt')]);
 const latest=await db.runTransaction(tx=>activePlayer(tx,actor,input.profileId));
 if(latest.view.permissionsVersion!==context.view.permissionsVersion)throw new DomainError('source-conflict');
 return {favorites,wishlist,progress,watched};
}
