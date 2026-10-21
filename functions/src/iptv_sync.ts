import {getFirestore, DocumentReference, FieldValue} from 'firebase-admin/firestore';
import {getStorage} from 'firebase-admin/storage';
import {randomUUID} from 'node:crypto';
import {catalogSchema, fetchProvider, fingerprint, validateUpdate, Catalog} from './catalog';
import {sourceSchema, unseal, seal, hash, DomainError} from './domain';
import {parseIptvEpg} from './iptv_epg';
import {identifyOrCreateServer} from './iptv_server';
import {fetchSnapshot, Source, ProviderFetch, ProviderSnapshot} from './iptv_ingestion';
import {advanceDailyScan, terminal, writeJob} from './iptv_jobs';
import {completionEvent} from './iptv_notifications';

import {classifyIptvError, isRetryableIptvError, logSyncFailure} from './iptv_errors';

const LEASE_MS=600000;
export type SyncStage='queued'|'identifying_server'|'validating_source'|'downloading'|'parsing'|'uploading_catalog'|'publishing_catalog'|'completed'|'failed';

/** Sealed providerRef → stream URL index of an M3U source (playback without re-downloading the list). */
export const streamIndexPath = (fid: string, sourceId: string) => `stream_index/${fid}_${sourceId}.bin`;

export async function syncDueSources(key: string): Promise<void> {
  await advanceDailyScan();
  const jobs=await getFirestore().collection('iptv_sync_jobs').where('status','in',['queued','running']).orderBy('createdAt').limit(100).get();
  // Individual failures cannot abort the rest of the queue. Five transactional
  // slots also bound trigger + scheduler concurrency across all instances.
  for (let i=0;i<jobs.size;i+=2) await Promise.allSettled(jobs.docs.slice(i,i+2).map(j=>{
    const data=j.data(); return syncIptvCatalog(getFirestore().doc(`families/${data.familyId}/sources/${data.sourceId}`),key,j.id);
  }));
}

export async function syncIptvCatalog(ref: DocumentReference, key: string, expectedJobId?: string, fetch: ProviderFetch=fetchProvider): Promise<void> {
  const db=getFirestore(), now=Date.now(), runId=randomUUID(), fid=ref.parent.parent!.id;
  const locked=await db.runTransaction(async tx=>{
    const current=await tx.get(ref), family=await tx.get(ref.parent.parent!), data=current.data();
    if (!data?.enabled || !family.exists || family.data()?.deleting) return null;
    if (expectedJobId && data.currentJobId!==expectedJobId) return null;
    if ((data.nextSyncAt??Infinity)>now || (data.lockedUntil??0)>now) return null;
    const jobId=data.currentJobId??randomUUID(), jobRef=db.doc(`iptv_sync_jobs/${jobId}`), job=(await tx.get(jobRef)).data();
    if (job && (terminal(job.status)||job.sourceRevision!==data.revision)) return null;
    const secret=await tx.get(db.doc(`source_secrets/${fid}_${ref.id}`));
    const slots=await tx.getAll(...Array.from({length:5},(_,i)=>db.doc(`iptv_worker_slots/${i}`)));
    const slot=slots.find(s=>(s.data()?.expiresAt??0)<=now);
    const serverRef=db.doc(`iptv_server_leases/${data.serverId??`file_${ref.id}`}`), server=await tx.get(serverRef);
    if (!slot || (server.data()?.expiresAt??0)>now) return null;
    if (!job) writeJob(tx,ref,data,jobId,null,'scheduled',now);
    const lease={runId,expiresAt:now+LEASE_MS};
    tx.set(slot.ref,lease);tx.set(serverRef,lease);
    tx.update(ref,{lockedUntil:now+LEASE_MS,runId,status:'syncing',lastAttemptAt:now,currentJobId:jobId});
    tx.set(db.doc(`iptv_sources/${ref.id}`),{...data,lockedUntil:now+LEASE_MS,runId,status:'syncing',lastAttemptAt:now,currentJobId:jobId},{merge:true});
    tx.set(jobRef,{status:'running',stage:'identifying_server',progress:null,runId,attempts:(job?.attempts??0)+1,startedAt:job?.startedAt??now,updatedAt:now},{merge:true});
    return {data,secret:secret.data(),jobId,job:job??{trigger:'scheduled',requestedByUid:null},slot:slot.ref,serverRef,attempts:(job?.attempts??0)+1};
  });
  if (!locked) return;
  const jobRef=db.doc(`iptv_sync_jobs/${locked.jobId}`);
  const owns=(d:FirebaseFirestore.DocumentData|undefined)=>!!d&&d.enabled&&d.revision===locked.data.revision&&d.runId===runId&&d.currentJobId===locked.jobId;
  let currentStage: SyncStage = 'identifying_server';
  const stage = async (value: SyncStage) => {
    currentStage = value;
    return db.runTransaction(async tx => {
      if (!owns((await tx.get(ref)).data())) throw new DomainError('job-superseded');
      tx.update(jobRef, {stage: value, progress: null, updatedAt: Date.now()});
    });
  };
  let source: Source | undefined;
  try {
    if (locked.attempts > 3) throw new DomainError('worker-retries-exhausted');
    if (!locked.secret || locked.secret.revision !== locked.data.revision) throw new DomainError('source-secret-unavailable');
    try {
      source = sourceSchema.parse(unseal<Source>(locked.secret.encrypted, key));
    } catch {
      throw new DomainError('invalid-source-url', {reason: 'invalid-source-configuration'});
    }
    const serverId = await db.runTransaction(tx => identifyOrCreateServer(tx, source!, Date.now()));
    await stage('downloading');
    let snapshot: ProviderSnapshot;
    try {
      snapshot = await fetchSnapshot(source!, fid, ref.id, fetch);
    } catch (err: any) {
      if (err instanceof DomainError) throw err;
      throw new DomainError('download-failed', {message: err?.message});
    }
    const proofRef = db.doc(`iptv_catalog_proofs/${hash(`${serverId ?? 'file'}:${snapshot.proof}`)}`);
    const proof = (await proofRef.get()).data();
    let catalog: Catalog, version: string, storagePath: string;
    let reused = false;
    if (proof) {
      const record = (await db.doc(`catalogs/${proof.catalogId}`).get()).data() ?? (await db.doc(`iptv_catalogs/${proof.catalogId}`).get()).data();
      if (record?.status === 'ready') {
        const [body] = await getStorage().bucket().file(record.storagePath).download();
        catalog = catalogSchema.parse(JSON.parse(body.toString()));
        version = hash(`${serverId ?? 'file'}:${fingerprint(catalog)}`);
        if (version !== proof.catalogId || hash(body.toString()) !== record.integrityHash) throw new DomainError('catalog-integrity');
        storagePath = record.storagePath; reused = true;
      } else {
        await stage('parsing');
        try {
          catalog = await snapshot.build();
        } catch (err: any) {
          if (err instanceof DomainError) throw err;
          throw new DomainError('parsing-failed', {message: err?.message});
        }
        version = ''; storagePath = '';
      }
    } else {
      await stage('parsing');
      try {
        catalog = await snapshot.build();
      } catch (err: any) {
        if (err instanceof DomainError) throw err;
        throw new DomainError('parsing-failed', {message: err?.message});
      }
      version = ''; storagePath = '';
    }
    validateUpdate(locked.data.count ?? 0, catalog);
    // Playback must not depend on downloading the whole list again: the worker
    // seals providerRef → URL once (same key as source secrets; no client access).
    if (snapshot.streamIndex) {
      const sealed = seal({schemaVersion: 1, version: hash(`${serverId ?? 'file'}:${fingerprint(catalog)}`), revision: locked.data.revision, streams: snapshot.streamIndex()}, key);
      try {
        await getStorage().bucket().file(streamIndexPath(fid, ref.id)).save(sealed, {resumable: false, contentType: 'application/octet-stream'});
      } catch (err: any) {
        throw new DomainError('storage-upload-failed', {reason: 'stream-index', message: err?.message});
      }
    } else {
      // An Xtream source back on its API must not keep a stale index of provider URLs.
      try { await getStorage().bucket().file(streamIndexPath(fid, ref.id)).delete({ignoreNotFound: true}); } catch { /* cleanup worker retries on removal */ }
    }
    if (!reused) {
      version = hash(`${serverId ?? 'file'}:${fingerprint(catalog)}`);
      storagePath = `catalogs/${version}.json`;
      await stage('uploading_catalog');
      try {
        await getStorage().bucket().file(storagePath).save(JSON.stringify(catalog), {resumable: false, contentType: 'application/json', preconditionOpts: {ifGenerationMatch: 0}})
          .catch(error => { if (Number(error.code) !== 412) throw error; });
      } catch (err: any) {
        if (err instanceof DomainError) throw err;
        throw new DomainError('storage-upload-failed', {message: err?.message});
      }
    }
    let epgVersion: string | null = null, epgCount = 0;
    if (source!.epgUrl) {
      try {
        const programmes = parseIptvEpg(await fetch(source!.epgUrl)), body = JSON.stringify({schemaVersion: 1, programmes});
        epgVersion = hash(body); epgCount = programmes.length;
        await getStorage().bucket().file(`epg/${fid}/${ref.id}/${epgVersion}.json`).save(body, {resumable: false, contentType: 'application/json'});
      } catch {
        // EPG parsing error is logged but optional unless required
      }
    }
    const kinds = {channel: 0, movie: 0, series: 0};
    for (const item of catalog.items) kinds[item.kind]++;
    await stage('publishing_catalog');
    const catalogRef = db.doc(`catalogs/${version}`);
    const iptvCatalogRef = db.doc(`iptv_catalogs/${version}`);
    const finishedAt = Date.now();
    await db.runTransaction(async tx => {
      // Firestore transactions reject reads issued after a write: every read happens first.
      const current = await tx.get(ref), family = await tx.get(ref.parent.parent!), existing = await tx.get(catalogRef), finalJob = await tx.get(jobRef);
      const sourceLink = await tx.get(catalogRef.collection('sources').doc(ref.id));
      const pendingSiblingJobs = await tx.get(db.collection('iptv_sync_jobs').where('catalogId', '==', version).where('status', 'in', ['queued', 'running']));
      if (!owns(current.data()) || !family.exists || family.data()?.deleting) throw new DomainError('job-superseded');
      const patch = {
        serverId, catalogId: version, version, catalogSchemaVersion: 1, catalogStorage: 'object', count: catalog.items.length, contentCount: catalog.items.length,
        channelCount: kinds.channel, movieCount: kinds.movie, seriesCount: kinds.series, errorReason: null,
        epgVersion, epgCount, isSingleStream: snapshot.singleStream, status: 'ready', authorizationStatus: 'valid', authorizationRevision: locked.data.revision,
        lastSuccessfulSyncAt: finishedAt, lastSyncAt: finishedAt, lastAttemptAt: now, nextSyncAt: Number.MAX_SAFE_INTEGER,
        lockedUntil: 0, runId: null, errorCode: null, failureCount: 0, currentJobId: null, updatedAt: finishedAt
      };
      tx.update(ref, patch); tx.set(db.doc(`iptv_sources/${ref.id}`), {...current.data(), ...patch}, {merge: true});

      const previousActiveCount = existing.data()?.activeSourceCount ?? 0;
      const newActiveCount = existing.exists ? (sourceLink.exists ? previousActiveCount : previousActiveCount + 1) : 1;

      const catalogData = {
        catalogId: version,
        serverId: serverId ?? null,
        schemaVersion: 1,
        version,
        storagePath,
        status: 'ready',
        contentCount: catalog.items.length,
        activeSourceCount: newActiveCount,
        integrityHash: hash(JSON.stringify(catalog)),
        createdAt: existing.data()?.createdAt ?? finishedAt,
        lastSuccessfulSyncAt: finishedAt,
        lastAttemptAt: now,
        updatedAt: finishedAt
      };

      tx.set(catalogRef, catalogData, {merge: true});
      tx.set(iptvCatalogRef, catalogData, {merge: true});
      tx.set(proofRef, {catalogId: version, parserVersion: 2, validatedAt: finishedAt});

      const old = current.data()?.catalogId;
      if (old && old !== version) {
        tx.delete(db.doc(`catalogs/${old}/sources/${ref.id}`));
        tx.delete(db.doc(`iptv_catalogs/${old}/sources/${ref.id}`));
        tx.set(db.doc(`catalogs/${old}`), {activeSourceCount: FieldValue.increment(-1), updatedAt: finishedAt}, {merge: true});
        tx.set(db.doc(`iptv_catalogs/${old}`), {activeSourceCount: FieldValue.increment(-1), updatedAt: finishedAt}, {merge: true});
      }

      const linkData = {sourceId: ref.id, familyId: fid, sourceRevision: locked.data.revision, validatedAt: finishedAt, active: true};
      tx.set(catalogRef.collection('sources').doc(ref.id), linkData);
      tx.set(iptvCatalogRef.collection('sources').doc(ref.id), linkData);

      tx.update(jobRef, {catalogId: version, status: 'completed', stage: 'completed', progress: 100, finishedAt, updatedAt: finishedAt, reusedCatalog: reused});
      completionEvent(tx, finalJob.data()!, locked.jobId, ref, source!.name, 'completed');

      // Also complete any other pending jobs that were waiting on this exact catalogId
      for (const sJob of pendingSiblingJobs.docs) {
        const sibling = sJob.data();
        if (sJob.id !== locked.jobId && sibling.sourceId !== ref.id && sibling.familyId && sibling.sourceId) {
          tx.update(sJob.ref, {catalogId: version, status: 'completed', stage: 'completed', progress: 100, finishedAt, updatedAt: finishedAt, reusedCatalog: true});
          completionEvent(tx, sibling, sJob.id, db.doc(`families/${sibling.familyId}/sources/${sibling.sourceId}`), sibling.sourceName ?? source!.name, 'completed');
        }
      }
    });
    console.info(JSON.stringify({component: 'iptv-sync', event: 'completed', jobId: locked.jobId, sourceId: ref.id, adapter: source?.format ?? 'unknown',
      items: catalog.items.length, ...kinds, stats: snapshot.stats ?? null, reusedCatalog: reused, elapsedMs: Date.now() - now, attempts: locked.attempts}));
  } catch (error: any) {
    const {code, details} = classifyIptvError(error, currentStage);
    // Only non-sensitive diagnostic fields leave the worker (no URL, user or password).
    const errorReason = typeof details?.statusCode === 'number' ? `http-${details.statusCode}` : typeof details?.reason === 'string' ? details.reason.slice(0, 80) : null;
    const traceId = randomUUID();
    // 400/404/410 on the provider's own endpoint mean a wrong URL or a cancelled
    // line: retrying only delays the message the user needs to fix the source.
    const definitive = [400, 404, 410].includes(Number(details?.statusCode));
    const retryable = isRetryableIptvError(code) && !definitive;
    const retry = retryable && locked.attempts < 3;

    logSyncFailure({
      level: 'error',
      jobId: locked.jobId,
      sourceId: ref.id,
      catalogId: locked.data.catalogId ?? null,
      stage: currentStage,
      errorCode: code,
      errorRetryable: retry,
      traceId,
      elapsedMs: Date.now() - now,
      adapter: source?.format ?? locked.data.format ?? 'unknown',
      attempts: locked.attempts,
      message: `${error?.constructor?.name ?? 'Error'}:${error?.code ?? ''} ${errorReason ?? ''} ${error instanceof Error && !(error instanceof DomainError) ? error.message : ''}`.trim(),
    });

    await db.runTransaction(async tx => {
      const current = (await tx.get(ref)).data(), job = (await tx.get(jobRef)).data();
      if (!owns(current)) {
        if (job && !terminal(job.status)) {
          tx.update(jobRef, {status: 'cancelled', stage: 'cancelled', finishedAt: Date.now(), updatedAt: Date.now()});
        }
        return;
      }
      const patch = {
        status: retry ? 'queued' : 'error',
        errorCode: code,
        errorReason,
        failureCount: (current!.failureCount ?? 0) + 1,
        nextSyncAt: retry ? Date.now() + 60000 * 2 ** locked.attempts : Number.MAX_SAFE_INTEGER,
        lockedUntil: 0,
        runId: null,
        currentJobId: retry ? locked.jobId : null,
        ...(code === 'invalid-credentials' ? {authorizationStatus: 'invalid'} : {}),
        updatedAt: Date.now(),
      };
      tx.update(ref, patch);
      tx.set(db.doc(`iptv_sources/${ref.id}`), patch, {merge: true});
      tx.update(jobRef, {
        status: retry ? 'queued' : 'failed',
        stage: retry ? 'queued' : currentStage,
        errorCode: code,
        errorReason,
        errorRetryable: retry,
        traceId,
        progress: null,
        finishedAt: retry ? null : Date.now(),
        updatedAt: Date.now(),
      });
      if (!retry) {
        completionEvent(tx, job!, locked.jobId, ref, current!.name ?? 'IPTV', 'failed', code);
      }
    });
  } finally {
    await db.runTransaction(async tx=>{
      const leases=await tx.getAll(locked.slot,locked.serverRef);
      for (const lease of leases) if (lease.data()?.runId===runId) tx.delete(lease.ref);
    });
  }
}

export async function reconcileCatalogActiveSources(catalogId: string): Promise<number> {
  const db = getFirestore();
  const catalogRef = db.doc(`catalogs/${catalogId}`);
  const snap = await catalogRef.get();
  if (!snap.exists) return 0;
  const sourcesSnap = await catalogRef.collection('sources').get();
  let activeCount = 0;
  for (const doc of sourcesSnap.docs) {
    const data = doc.data();
    if (!data.familyId || !data.sourceId) continue;
    const sourceSnap = await db.doc(`families/${data.familyId}/sources/${data.sourceId}`).get();
    if (sourceSnap.exists && sourceSnap.data()?.enabled === true && sourceSnap.data()?.catalogId === catalogId) {
      activeCount++;
    } else {
      await doc.ref.delete();
      await db.doc(`iptv_catalogs/${catalogId}/sources/${doc.id}`).delete().catch(() => {});
    }
  }
  await catalogRef.set({activeSourceCount: activeCount, updatedAt: Date.now()}, {merge: true});
  await db.doc(`iptv_catalogs/${catalogId}`).set({activeSourceCount: activeCount, updatedAt: Date.now()}, {merge: true});
  return activeCount;
}

