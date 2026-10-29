import {assertChannelVisible, authorize} from './iptv_catalog_access';
import {getFirestore, FieldValue, Transaction, DocumentReference} from 'firebase-admin/firestore';
import {getStorage} from 'firebase-admin/storage';
import {randomUUID, timingSafeEqual} from 'node:crypto';
import {z} from 'zod';
import {DomainError, hash, idSchema, pinSchema, seal, sourceInputSchema, sourceSchema, unseal} from './domain';
import {identifyOrCreateServer} from './iptv_server';
import {terminal, writeJob} from './iptv_jobs';
import {streamIndexPath} from './iptv_sync';
import {iptvWorkspace} from './iptv_workspace';
import type {Identity} from './service';

type Source = z.infer<typeof sourceSchema>;
const db = () => getFirestore();
const requireValue = (ok: unknown, code: string) => { if (!ok) throw new DomainError(code); };
export const accessRef = (fid: string, id: string, uid: string) => db().doc(`families/${fid}/source_access/${id}_${uid}`);

export async function requireSourceAccess(tx: Transaction, ref: DocumentReference, data: FirebaseFirestore.DocumentData, uid: string) {
  if (data.isProtected !== true) return;
  const grant = (await tx.get(accessRef(ref.parent.parent!.id, ref.id, uid))).data();
  requireValue(grant && grant.expiresAt > Date.now() && grant.revision === data.revision, 'pin-required');
}

export async function saveIptvSource(payload: unknown, actor: Identity, key: string) {
  const input = sourceInputSchema.parse(payload), now = Date.now();
  const id = input.id ?? (input.requestId ? hash(`${actor.uid}:${input.requestId}`).slice(0, 40) : randomUUID());
  const requestHash = hash(JSON.stringify(input));
  const receipt = input.requestId ? db().doc(`iptv_requests/${hash(`${actor.uid}:${input.requestId}`)}`) : null;
  // Authorize before any upload; transactions below recheck authorization and revision.
  const scope = await db().runTransaction(async tx => {
    const f = await iptvWorkspace(tx, actor, !input.id);
    const prior = await tx.get(f.ref.collection('sources').doc(id));
    if (input.id) {
      requireValue(prior.exists, 'not-found');
      await requireSourceAccess(tx, prior.ref, prior.data()!, actor.uid);
    }
    return f.fid;
  });
  let uploadedPath: string | undefined;
  const uploadCleanup = db().collection('iptv_cleanup').doc();
  if (input.format === 'file' && input.fileContent !== undefined) {
    requireValue(input.fileContent.trimStart().startsWith('#EXTM3U'), 'invalid-catalog');
    requireValue(!input.fileName || /\.(m3u|m3u8)$/i.test(input.fileName), 'invalid-catalog');
    uploadedPath = `source_files/${scope}_${id}/${randomUUID()}.m3u`;
    // Durable orphan record precedes the external side effect. A crash or a failed
    // transaction leaves a retryable job, never an untracked uploaded credential.
    await uploadCleanup.set({filePath: uploadedPath, sourcePath: `families/${scope}/sources/${id}`, notBefore: now + 86400000});
    await getStorage().bucket().file(uploadedPath).save(input.fileContent, {resumable: false, contentType: 'application/x-mpegURL'});
  }
  const result = await db().runTransaction(async tx => {
    if (receipt) {
      const previous = await tx.get(receipt);
      if (previous.exists) {
        requireValue(previous.data()?.requestHash === requestHash, 'request-conflict');
        return {id: previous.data()!.sourceId, jobId: previous.data()!.jobId};
      }
    }
    const f = await iptvWorkspace(tx, actor, !input.id);
    // A concurrent first creation can choose another workspace. Uploaded files
    // remain private and carry an explicit source binding in the committed data.
    const ref = f.ref.collection('sources').doc(id), prior = await tx.get(ref);
    if (input.id) requireValue(prior.exists, 'not-found');
    else requireValue(!prior.exists, 'request-conflict');
    if (prior.exists) await requireSourceAccess(tx, ref, prior.data()!, actor.uid);
    if (input.expectedRevision !== undefined) requireValue(prior.data()?.revision === input.expectedRevision, 'source-conflict');
    const secretRef = db().doc(`source_secrets/${f.fid}_${id}`), secret = await tx.get(secretRef);
    const old = secret.exists ? unseal<Source>(secret.data()!.encrypted, key) : undefined;
    if (prior.exists) requireValue(old, 'source-secret-unavailable');
    const sameFormat = old?.format === input.format || (['m3u', 'url', 'other_m3u8'].includes(old?.format ?? '') && ['m3u', 'url', 'other_m3u8'].includes(input.format));
    const isProtected = input.isProtected ?? old?.isProtected ?? false;
    const pinHash = isProtected ? (input.pin ? hash(`${id}:${input.pin}:${key}`) : old?.pinHash) : undefined;
    if (isProtected) requireValue(pinHash, 'pin-required');
    const filePath = input.format === 'file' ? uploadedPath ?? (sameFormat ? old?.filePath ?? `source_files/${f.fid}_${id}.m3u` : undefined) : undefined;
    if (input.format === 'file') requireValue(filePath, 'file-required');
    const complete = sourceSchema.parse({
      name: input.name, format: input.format,
      url: input.format === 'file' ? undefined : input.url || (sameFormat ? old?.url : undefined),
      username: input.format === 'xtream' ? input.username || (sameFormat ? old?.username : undefined) : undefined,
      password: input.format === 'xtream' ? input.password || (sameFormat ? old?.password : undefined) : undefined,
      epgUrl: input.epgUrl === undefined ? old?.epgUrl : input.epgUrl,
      fileName: input.format === 'file' ? input.fileName || old?.fileName || 'playlist.m3u' : undefined,
      filePath, isProtected, pinHash,
    });
    // Serialize/validate before issuing writes (including workspace creation).
    const encrypted = seal(complete, key), revision = (prior.data()?.revision ?? 0) + 1;
    const oldFile = old?.format === 'file' ? old.filePath ?? `source_files/${f.fid}_${id}.m3u` : null;
    const sources = !prior.exists ? await tx.get(f.ref.collection('sources').limit(100)) : null;
    requireValue(!sources || sources.size < 100, 'source-limit');
    const previousJob = prior.data()?.currentJobId ? await tx.get(db().doc(`iptv_sync_jobs/${prior.data()!.currentJobId}`)) : null;
    const serverId = await identifyOrCreateServer(tx, complete, now);
    if (previousJob?.exists && !terminal(previousJob.data()?.status)) tx.update(previousJob.ref,{status:'cancelled',stage:'cancelled',finishedAt:now});
    const jobId = randomUUID();
    f.initialize();
    const sourceData = {
      sourceId: id,
      id,
      familyId: f.fid,
      ownerUid: prior.data()?.ownerUid ?? actor.uid,
      createdByUid: prior.data()?.createdByUid ?? actor.uid,
      createdAt: prior.data()?.createdAt ?? now,
      lastSuccessfulSyncAt: prior.data()?.lastSuccessfulSyncAt ?? prior.data()?.lastSyncAt ?? null,
      authorizationStatus: 'pending',
      updatedByUid: actor.uid,
      serverId: serverId ?? null,
      name: complete.name,
      format: complete.format,
      type: complete.format,
      host: complete.url ? new URL(complete.url).hostname : complete.fileName,
      fileName: complete.fileName ?? null,
      filePath: filePath ?? null,
      epgUrl: FieldValue.delete(),
      hasEpg: !!complete.epgUrl,
      epgEnabled: !!complete.epgUrl,
      isProtected,
      pinProtected: isProtected,
      status: 'queued',
      enabled: true,
      nextSyncAt: now,
      updatedAt: now,
      lastAttemptAt: now,
      revision,
      lockedUntil: 0,
      runId: null,
      errorCode: null,
      failureCount: 0,
      catalogId: prior.data()?.catalogId ?? null,
      currentJobId: jobId,
    };
    tx.set(ref, sourceData, {merge: true});
    tx.set(db().doc(`iptv_sources/${id}`), sourceData, {merge: true});
    writeJob(tx,ref,sourceData,jobId,actor.uid,'manual',now);
    tx.set(secretRef, {encrypted, revision, failedAttempts: secret.data()?.failedAttempts ?? 0, lockedUntil: secret.data()?.lockedUntil ?? 0});
    if (isProtected) tx.set(accessRef(f.fid, id, actor.uid), {revision, expiresAt: now + 15 * 60000});
    if (oldFile && oldFile !== filePath) tx.create(db().collection('iptv_cleanup').doc(), {filePath: oldFile, sourcePath: ref.path, notBefore: now + 15 * 60000});
    if (uploadedPath) tx.set(uploadCleanup, {filePath: uploadedPath, sourcePath: ref.path, notBefore: now + 86400000});
    if (receipt) tx.create(receipt, {sourceId: id, jobId, requestHash, createdAt: now});
    return {id, jobId, ref};
  });
  return {id: result.id, jobId: result.jobId};
}

export async function syncIptvSource(payload: Record<string, unknown>, actor: Identity) {
  const result = await db().runTransaction(async tx => {
    const f = await iptvWorkspace(tx, actor), ref = f.ref.collection('sources').doc(idSchema.parse(payload.id));
    const snap = await tx.get(ref); requireValue(snap.exists, 'not-found');
    await requireSourceAccess(tx, ref, snap.data()!, actor.uid);
    return queueSourceSync(tx, ref, snap.data()!, actor.uid);
  });
  return {id: result.id, jobId: result.jobId};
}

/**
 * TV (Configurações › Listas IPTV): pede a mesma sincronização manual do Gestor para uma lista que o perfil em uso
 * (lease ativo) pode ver. A autorização é a mesma da leitura do catálogo pela TV.
 */
export async function syncPlayerSource(payload: Record<string, unknown>, actor: Identity) {
  requireValue(actor.deviceId, 'permission-denied');
  const access = await authorize(actor, idSchema.parse(payload.sourceId));
  const result = await db().runTransaction(async tx => {
    const snap = await tx.get(access.ref); requireValue(snap.exists && snap.data()?.enabled, 'not-found');
    return queueSourceSync(tx, access.ref, snap.data()!, actor.uid);
  });
  return {id: result.id, jobId: result.jobId};
}

/** Enfileira (ou promove) a sincronização manual de uma fonte já autorizada. */
async function queueSourceSync(tx: Transaction, ref: DocumentReference, data: FirebaseFirestore.DocumentData, uid: string) {
  const now = Date.now();
  const previous = data.currentJobId ? await tx.get(db().doc(`iptv_sync_jobs/${data.currentJobId}`)) : null;
  if (previous?.exists && !terminal(previous.data()?.status) && previous.data()?.sourceRevision===data.revision) {
    // Promote a scheduled run to this user's explicit request; no new worker.
    tx.update(previous.ref,{trigger:'manual',requestedByUid:uid});
    return {id:ref.id,jobId:previous.id};
  }
  requireValue(now - (data.lastAttemptAt ?? 0) >= 10000, 'rate-limited');
  if (data.catalogId) {
    const runningCatalogJobs = await tx.get(
      db().collection('iptv_sync_jobs')
        .where('catalogId', '==', data.catalogId)
        .where('status', 'in', ['queued', 'running'])
        .limit(1)
    );
    if (!runningCatalogJobs.empty) {
      const cJob = runningCatalogJobs.docs[0]!;
      const jobId = randomUUID();
      writeJob(tx, ref, data, jobId, uid, 'manual', now);
      tx.update(db().doc(`iptv_sync_jobs/${jobId}`), {
        catalogId: data.catalogId,
        stage: cJob.data().stage ?? 'downloading',
        progress: cJob.data().progress ?? null,
        status: 'running',
        startedAt: cJob.data().startedAt ?? now,
      });
      tx.update(ref, {status: 'syncing', updatedAt: now, lastAttemptAt: now, errorCode: null, currentJobId: jobId});
      tx.set(db().doc(`iptv_sources/${ref.id}`), {status: 'syncing', updatedAt: now, lastAttemptAt: now, errorCode: null, currentJobId: jobId}, {merge: true});
      return {id: ref.id, jobId};
    }
  }

  const jobId = randomUUID();
  writeJob(tx,ref,data,jobId,uid,'manual',now);
  tx.update(ref, {nextSyncAt: now, status: 'queued', updatedAt: now, lastAttemptAt: now, errorCode: null, currentJobId: jobId});
  tx.set(db().doc(`iptv_sources/${ref.id}`), {status: 'queued', updatedAt: now, lastAttemptAt: now, errorCode: null, currentJobId: jobId}, {merge: true});
  return {id: ref.id, jobId};
}

export async function verifyIptvPin(payload: Record<string, unknown>, actor: Identity, key: string) {
  const id = idSchema.parse(payload.id), pin = pinSchema.parse(payload.pin), now = Date.now();
  const result = await db().runTransaction(async tx => {
    const f = await iptvWorkspace(tx, actor, false, false);
    const source = await tx.get(f.ref.collection('sources').doc(id));
    requireValue(source.exists && source.data()?.isProtected, 'not-found');
    const secret = await tx.get(db().doc(`source_secrets/${f.fid}_${id}`));
    requireValue(secret.exists, 'not-found');
    const data = secret.data()!;
    if (now < (data.lockedUntil ?? 0)) throw new DomainError('pin-locked', {lockedUntil: data.lockedUntil});
    const prior = unseal<Source>(data.encrypted, key);
    requireValue(prior.pinHash, 'not-found');
    const expected = Buffer.from(prior.pinHash!, 'hex'), actual = Buffer.from(hash(`${id}:${pin}:${key}`), 'hex');
    if (expected.length === actual.length && timingSafeEqual(expected, actual)) {
      tx.update(secret.ref, {failedAttempts: 0, lockedUntil: 0});
      tx.set(accessRef(f.fid, id, actor.uid), {revision: source.data()!.revision, expiresAt: now + 15 * 60000});
      return {verified: true, remainingAttempts: 5};
    }
    const attempts = ((data.lockedUntil ?? 0) > 0 ? 0 : data.failedAttempts ?? 0) + 1;
    tx.update(secret.ref, {failedAttempts: attempts, lockedUntil: attempts >= 5 ? now + 300000 : 0});
    return {verified: false, remainingAttempts: Math.max(0, 5 - attempts)};
  });
  if (!result.verified) throw new DomainError('invalid-pin', {remainingAttempts: result.remainingAttempts});
  return {ok: true, verified: true};
}

export async function deleteIptvSource(payload: Record<string, unknown>, actor: Identity) {
  const removed = await db().runTransaction(async tx => {
    const f = await iptvWorkspace(tx, actor), id = idSchema.parse(payload.id), ref = f.ref.collection('sources').doc(id);
    const source = await tx.get(ref);
    if (source.exists) await requireSourceAccess(tx, ref, source.data()!, actor.uid);
    const jobs = await tx.get(db().collection('iptv_sync_jobs').where('sourceId', '==', id).where('status', 'in', ['queued', 'running']));
    tx.delete(ref);
    tx.delete(db().doc(`iptv_sources/${id}`));
    tx.delete(db().doc(`source_secrets/${f.fid}_${id}`));
    if (source.data()?.catalogId) {
      const catId = source.data()!.catalogId;
      tx.delete(db().doc(`catalogs/${catId}/sources/${id}`));
      tx.delete(db().doc(`iptv_catalogs/${catId}/sources/${id}`));
      tx.set(db().doc(`catalogs/${catId}`), {activeSourceCount: FieldValue.increment(-1), updatedAt: Date.now()}, {merge: true});
      tx.set(db().doc(`iptv_catalogs/${catId}`), {activeSourceCount: FieldValue.increment(-1), updatedAt: Date.now()}, {merge: true});
    }
    for (const j of jobs.docs) tx.update(j.ref, {status:'cancelled',stage:'cancelled',finishedAt:Date.now()});
    tx.set(db().doc(`iptv_cleanup/source_${f.fid}_${id}`), {sourcePath: ref.path, deleteSource: true, filePath: source.data()?.filePath ?? (source.data()?.format === 'file' ? `source_files/${f.fid}_${id}.m3u` : null), notBefore: Date.now() + 15 * 60000});
    return {fid: f.fid, id};
  });
  // The sealed stream index holds provider URLs (credentials): removed at once, not deferred.
  // The deferred cleanup (iptv_cleanup) deletes it again if this attempt fails.
  try { await getStorage().bucket().file(streamIndexPath(removed.fid, removed.id)).delete({ignoreNotFound: true}); } catch { /* retried by cleanup */ }
  return {ok: true};
}

/** Bounded EPG read; no bearer Storage URL or provider credentials reach clients. */
export async function readIptvEpg(payload: Record<string, unknown>, actor: Identity) {
  const id = idSchema.parse(payload.id), channelId = z.string().min(1).max(300).parse(payload.channelId);
  // A paired TV is authorized first (credential, lease, subscription, profile visibility of the channel).
  if (actor.deviceId) await assertChannelVisible(actor, id, channelId);
  const scope = async (tx: Transaction) => actor.deviceId ? {fid: actor.familyId!, ref: db().doc(`families/${actor.familyId}`)} : iptvWorkspace(tx, actor, false, false);
  const binding = await db().runTransaction(async tx => {
    const f = await scope(tx), source = await tx.get(f.ref.collection('sources').doc(id));
    requireValue(source.exists, 'not-found');
    await requireSourceAccess(tx, source.ref, source.data()!, actor.uid);
    return {fid: f.fid, version: source.data()!.epgVersion};
  });
  if (!binding.version) return {programmes: []};
  await assertChannelVisible(actor, id, channelId);
  const [buffer] = await getStorage().bucket().file(`epg/${binding.fid}/${id}/${binding.version}.json`).download();
  const now = Date.now();
  const programmes = (JSON.parse(buffer.toString('utf8')).programmes as import('./iptv_epg').IptvProgramme[])
    .filter(row => row.channelId === channelId && row.endAt > now).sort((a, b) => a.startAt - b.startAt).slice(0, 100);
  // Recheck after I/O: membership, PIN or published version may have changed.
  await db().runTransaction(async tx => {
    const f = await scope(tx), source = await tx.get(f.ref.collection('sources').doc(id));
    requireValue(f.fid === binding.fid && source.data()?.epgVersion === binding.version, 'source-conflict');
    await requireSourceAccess(tx, source.ref, source.data()!, actor.uid);
  });
  return {programmes};
}
