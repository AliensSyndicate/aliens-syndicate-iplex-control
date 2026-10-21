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
import {classifyAudience} from './content_audience';
import {profileView, ProfileView} from './family_profiles';

type Kind='channel'|'movie'|'series';
const fold=(v:string)=>v.normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
/** Active profile restrictions. null = unrestricted (admin, personal scope, unlinked manager). */
export type Viewer = ProfileView | null;
export function canSee(viewer:Viewer,sourceId:string,item:{kind:Kind;title?:string;category?:string;ageRating?:string}) {
  if(!viewer||viewer.type==='admin')return true;
  if(!viewer.permissions.allSpaces&&!viewer.permissions.spaces.includes(`${sourceId}:${item.kind}`))return false;
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
  if(family?.kind==='personalIptv'||(family?.adminUid??family?.adminId)===actor.uid)return null;
  const link=await tx.get(db.doc(`families/${fid}/profile_links/${actor.uid}`));
  const profileId=link.data()?.profileId;
  if(!profileId)return null;
  const snap=await tx.get(db.doc(`families/${fid}/profiles/${profileId}`));
  return snap.exists?profileView(snap.id,snap.data()!):null;
}

/** Shared objects are never public or signed into bearer download URLs. */
const cache=new Map<string,Catalog>();
async function authorize(actor:Identity,id:string,playback=false,requestedProfile?:unknown) {
  const db=getFirestore();
  return db.runTransaction(async tx=>{
    let fid:string, familyData:FirebaseFirestore.DocumentData|undefined;
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
      if(playback)throw new DomainError('player-required');
    }
    const viewer=await resolveViewer(tx,actor,fid,familyData,requestedProfile);
    const ref=db.doc(`families/${fid}/sources/${id}`), source=await tx.get(ref), data=source.data();
    if(!data||!data.enabled||!data.version)throw new DomainError('not-found');
    await requireSourceAccess(tx,ref,data,actor.uid);
    if(playback&&(data.authorizationStatus!=='valid'||data.authorizationRevision!==data.revision))throw new DomainError('source-authorization-required');
    return {fid,ref,data,viewer};
  });
}
async function load(version:string):Promise<Catalog> {
  if(cache.has(version))return cache.get(version)!;
  if(!/^[a-f0-9]{64}$/.test(version))throw new DomainError('invalid-catalog');
  const record=(await getFirestore().doc(`catalogs/${version}`).get()).data();
  const [body]=await getStorage().bucket().file(record?.storagePath??`catalogs/${version}.json`).download();
  if(body.length>64*1024*1024 || (record?.integrityHash&&hash(body.toString())!==record.integrityHash))throw new DomainError('catalog-integrity');
  const catalog=catalogSchema.parse(JSON.parse(body.toString()));
  if(cache.size>=2)cache.delete(cache.keys().next().value!);
  cache.set(version,catalog);return catalog;
}
export async function readSourceCatalog(input:Record<string,unknown>,actor:Identity) {
  const id=idSchema.parse(input.id), access=await authorize(actor,id,false,input.profileId);
  const version=access.data.version as string;
  if(input.version && input.version!==version)throw new DomainError('source-conflict');
  const search=z.string().max(300).parse(input.search??'').trim().toLowerCase().normalize('NFKD');
  const offset=z.number().int().min(0).max(100000).parse(input.cursor??0);
  const catalog=await load(version);
  const visible=catalog.items.filter(i=>canSee(access.viewer,id,i));
  // A space the profile cannot use does not exist for it.
  if(access.viewer&&!visible.length&&catalog.items.length)throw new DomainError('not-found');
  // Matches anywhere in the title, ignoring case and accents.
  const needle=fold(search);
  const items=visible.filter(i=>!needle||fold(i.titleKey).includes(needle)).sort((a,b)=>a.titleKey.localeCompare(b.titleKey)||a.id.localeCompare(b.id));
  const latest=await authorize(actor,id,false,input.profileId);
  if(latest.fid!==access.fid||latest.data.version!==version||latest.data.revision!==access.data.revision)throw new DomainError('source-conflict');
  const shown=new Set(visible.map(i=>`${i.kind}:${i.categoryId??i.category}`));
  return {schemaVersion:1,version,items:items.slice(offset,offset+30).map(i=>({...i,id:hash(`${id}:${i.id}`),catalogItemId:i.id,sourceId:id,version})),
    categories:(catalog.categories??[]).filter(c=>!access.viewer||shown.has(`${c.kind}:${c.id}`)||shown.has(`${c.kind}:${c.name}`)),cursor:offset+30,hasMore:offset+30<items.length};
}

/** Individual stream URLs only leave the backend for an authenticated, paired
 * Player with a current session and fresh provider validation. They are never
 * stored in a shared artifact, notification or Firestore item. */
export async function resolveSourceStream(input:Record<string,unknown>,actor:Identity,key:string) {
  const id=idSchema.parse(input.id), itemId=idSchema.parse(input.itemId), access=await authorize(actor,id,true,input.profileId);
  const secret=(await getFirestore().doc(`source_secrets/${access.fid}_${id}`).get()).data();
  if(!secret||secret.revision!==access.data.revision)throw new DomainError('source-conflict');
  const source=sourceSchema.parse(unseal<Source>(secret.encrypted,key));
  const catalog=await load(access.data.version);
  const item=catalog.items.find(i=>i.id===itemId||hash(`${id}:${i.id}`)===itemId);
  if(!item||!canSee(access.viewer,id,item))throw new DomainError('not-found');
  let url:string|undefined;
  if(source.format==='xtream') {
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
    // M3U series episodes are addressed by their own stream reference.
    const ref=item.kind==='series'?idSchema.parse(input.episodeId):item.providerRef;
    if(item.kind==='series'&&!((catalog.seriesDetails?.[item.providerRef] as any)?.episodes&&Object.values((catalog.seriesDetails![item.providerRef] as any).episodes).flat().some((e:any)=>e?.id===ref)))throw new DomainError('not-found');
    url=await sealedStream(access.fid,id,access.data,ref,key)??findM3uStream(await playlistBody(source,access.fid,id,fetchProvider),source.url??'',ref);
  }
  if(!url)throw new DomainError('source-authorization-required');
  const parsed=new URL(url);
  if(!['http:','https:'].includes(parsed.protocol)||parsed.username||parsed.password)throw new DomainError('unsafe-provider');
  const addresses=await lookup(parsed.hostname.replace(/^\[|\]$/g,''),{all:true});
  if(!addresses.length||(!privateProvidersAllowedForTests()&&addresses.some(a=>!publicAddress(a.address))))throw new DomainError('unsafe-provider');
  // Permissions are revalidated right before the URL leaves the backend.
  const latest=await authorize(actor,id,true,input.profileId);
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
  const spaces:{sourceId:string;name:string;kinds:Kind[]}[]=[];
  for(const source of context.sources){
    const catalog=await load(source.data().version);
    const kinds=(['channel','movie','series'] as Kind[]).filter(kind=>catalog.items.some(i=>i.kind===kind&&canSee(context.viewer,source.id,i)));
    if(kinds.length)spaces.push({sourceId:source.id,name:String(source.data().name??''),kinds});
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
 return {fid:access.fid,kind:item.kind,title:item.title};
}

/** Library reads are now server-authorized; direct Firestore access is closed. */
export async function readPlayerLibrary(input:Record<string,unknown>,actor:Identity) {
 const db=getFirestore(),context=await db.runTransaction(tx=>activePlayer(tx,actor,input.profileId));
 if(context.view.type==='guest')return {favorites:[],progress:[],watched:[]};
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
 const [favorites,progress,watched]=await Promise.all([read('favorites','updatedAt'),read('watch_progress','updatedAt'),read('watched','completedAt')]);
 const latest=await db.runTransaction(tx=>activePlayer(tx,actor,input.profileId));
 if(latest.view.permissionsVersion!==context.view.permissionsVersion)throw new DomainError('source-conflict');
 return {favorites,progress,watched};
}
