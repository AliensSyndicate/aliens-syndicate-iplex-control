import {getFirestore} from 'firebase-admin/firestore';
import {getStorage} from 'firebase-admin/storage';

/** Retryable private-file/catalog cleanup. Shared catalog objects are retained:
 * deleting a family source must never remove another family's shared version. */
export async function cleanupIptvResources(): Promise<void> {
  const db = getFirestore();
  const jobs = await db.collection('iptv_cleanup').where('notBefore', '<=', Date.now()).limit(30).get();
  for (const job of jobs.docs) {
    const data = job.data();
    try {
      const source = await db.doc(data.sourcePath).get();
      if (data.deleteSource && source.exists) continue;
      if (data.filePath && source.data()?.filePath !== data.filePath) {
        await getStorage().bucket().file(data.filePath).delete({ignoreNotFound: true});
      }
      if (data.deleteSource) {
        await getStorage().bucket().deleteFiles({prefix: `epg/${source.ref.parent.parent!.id}/${source.id}/`});
        // Sealed stream index (provider URLs): also removed right away by deleteIptvSource.
        await getStorage().bucket().file(`stream_index/${source.ref.parent.parent!.id}_${source.id}.bin`).delete({ignoreNotFound: true});
        const fid = source.ref.parent.parent!.id, id = source.id;
        for (const collection of ['catalog', 'source_access']) {
          // Access grants carry source IDs in their document name for rules compatibility.
          const base = db.collection(`families/${fid}/${collection}`);
          const query = collection === 'catalog' ? base.where('sourceId', '==', id) : base.orderBy('__name__').startAt(`${id}_`).endBefore(`${id}_\uf8ff`);
          const rows = await query.limit(400).get();
          const batch = db.batch();
          for (const row of rows.docs) batch.delete(row.ref);
          if (!rows.empty) await batch.commit();
          if (rows.size === 400) throw new Error('cleanup-remaining');
        }
      }
      await job.ref.delete();
    } catch {
      // Never swallow an untracked failure or log paths/provider credentials.
      await job.ref.update({notBefore: Date.now() + 1800000, attempts: (data.attempts ?? 0) + 1});
    }
  }
}
