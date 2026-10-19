import {getFirestore, DocumentReference, Transaction} from 'firebase-admin/firestore';
import {randomUUID} from 'node:crypto';

export const DAILY_SCHEDULE = '0 0 * * *';
export const DAILY_TIME_ZONE = 'America/Sao_Paulo';
export const terminal = (status: unknown) => ['completed','failed','cancelled'].includes(String(status));
export function writeJob(tx: Transaction, ref: DocumentReference, data: FirebaseFirestore.DocumentData,
  jobId: string, requestedByUid: string | null, trigger: 'manual'|'scheduled', now: number) {
  tx.set(getFirestore().doc(`iptv_sync_jobs/${jobId}`), {
    jobId, familyId:ref.parent.parent!.id, sourceId:ref.id, sourceRevision:data.revision,
    catalogId:data.catalogId??null, requestedByUid, trigger, status:'queued', stage:'queued', progress:null,
    createdAt:now, updatedAt:now, startedAt:null, finishedAt:null, errorCode:null, attempts:0,
  });
}

/** A durable daily scan cursor keeps large installations recoverable. No catalog
 * count or global users collection is used to decide whether a source is active. */
export async function scheduleDailySync(now = Date.now()): Promise<void> {
  const day = new Intl.DateTimeFormat('en-CA', {timeZone:DAILY_TIME_ZONE,year:'numeric',month:'2-digit',day:'2-digit'}).format(now);
  const ref = getFirestore().doc(`iptv_schedule_runs/${day}`);
  await getFirestore().runTransaction(async tx=>{
    if (!(await tx.get(ref)).exists) tx.create(ref,{day,status:'pending',cursor:null,phase:'catalogs',createdAt:now});
  });
}
export async function advanceDailyScan(): Promise<void> {
  const db=getFirestore();
  const runs=await db.collection('iptv_schedule_runs').where('status','==','pending').limit(1).get();
  for (const run of runs.docs) {
    const cursor=run.data().cursor;
    const phase=run.data().phase ?? 'catalogs';

    if (phase === 'catalogs') {
      let query=db.collection('catalogs').where('status','==','ready').orderBy('__name__').limit(50);
      if (cursor) query=query.startAfter(db.doc(cursor));
      const catalogs=await query.get();

      for (const catDoc of catalogs.docs) {
        const catData = catDoc.data();
        const activeCount = catData.activeSourceCount ?? 0;
        // Ignorar catálogos sem usuários ativos.
        if (activeCount <= 0) continue;
        if (catData.lastScheduledDay === run.id) continue;

        // Identificar uma fonte ativa autorizada para executar a sincronização deste catálogo
        const sourcesSnap = await catDoc.ref.collection('sources').limit(10).get();
        let scheduled = false;

        for (const sDoc of sourcesSnap.docs) {
          const link = sDoc.data();
          if (!link.familyId || !link.sourceId) continue;
          const sourceRef = db.doc(`families/${link.familyId}/sources/${link.sourceId}`);
          
          await db.runTransaction(async tx => {
            const snap = await tx.get(sourceRef), data = snap.data();
            const family = await tx.get(sourceRef.parent.parent!);
            if (!data?.enabled || !family.exists || family.data()?.deleting || data.authorizationStatus === 'invalid') return;
            if (data.currentJobId) {
              tx.update(sourceRef, {lastScheduledDay: run.id});
              tx.set(catDoc.ref, {lastScheduledDay: run.id}, {merge: true});
              scheduled = true;
              return;
            }
            const jobId = randomUUID(), now = Date.now();
            writeJob(tx, sourceRef, data, jobId, null, 'scheduled', now);
            const patch = {status: 'queued', currentJobId: jobId, nextSyncAt: now, lastScheduledDay: run.id};
            tx.update(sourceRef, patch);
            tx.set(db.doc(`iptv_sources/${sourceRef.id}`), {...data, ...patch}, {merge: true});
            tx.set(catDoc.ref, {lastScheduledDay: run.id, currentJobId: jobId}, {merge: true});
            tx.set(db.doc(`iptv_catalogs/${catDoc.id}`), {lastScheduledDay: run.id, currentJobId: jobId}, {merge: true});
            scheduled = true;
          });

          if (scheduled) break;
        }

        // Se nenhuma fonte ativa válida foi encontrada, reconciliar activeSourceCount
        if (!scheduled && sourcesSnap.size === 0) {
          await catDoc.ref.set({activeSourceCount: 0, updatedAt: Date.now()}, {merge: true});
          await db.doc(`iptv_catalogs/${catDoc.id}`).set({activeSourceCount: 0, updatedAt: Date.now()}, {merge: true});
        }
      }

      await db.runTransaction(async tx => {
        const latest = await tx.get(run.ref);
        if (latest.data()?.cursor !== cursor) return;
        const finished = catalogs.size < 50;
        tx.update(run.ref, {
          cursor: finished ? null : catalogs.docs.at(-1)?.ref.path,
          phase: finished ? 'sources' : 'catalogs',
          updatedAt: Date.now()
        });
      });
      return;
    }

    // Phase 2: fontes ativas sem catalogId prévio (cadastros pendentes de primeira sincronização)
    let query=db.collectionGroup('sources').where('enabled','==',true).orderBy('__name__').limit(100);
    if (cursor) query=query.startAfter(db.doc(cursor));
    const sources=await query.get();
    for (const row of sources.docs) await db.runTransaction(async tx=>{
      const snap=await tx.get(row.ref), data=snap.data();
      const family=await tx.get(row.ref.parent.parent!);
      if (!data?.enabled || !family.exists || family.data()?.deleting || data.lastScheduledDay===run.id || data.authorizationStatus==='invalid') return;
      if (data.catalogId) {
        // Já tratado ou sincronizado via agrupamento por catálogo
        tx.update(row.ref, {lastScheduledDay: run.id});
        return;
      }
      const jobId=randomUUID(), now=Date.now();
      if (data.currentJobId) {
        tx.update(row.ref,{lastScheduledDay:run.id}); return;
      }
      writeJob(tx,row.ref,data,jobId,null,'scheduled',now);
      const patch={status:'queued',currentJobId:jobId,nextSyncAt:now,lastScheduledDay:run.id};
      tx.update(row.ref,patch); tx.set(db.doc(`iptv_sources/${row.id}`),{...data,...patch},{merge:true});
    });
    await db.runTransaction(async tx=>{
      const latest=await tx.get(run.ref);
      if (latest.data()?.cursor!==cursor) return;
      tx.update(run.ref,{cursor:sources.docs.at(-1)?.ref.path??cursor,status:sources.size<100?'completed':'pending',updatedAt:Date.now()});
    });
  }
}

