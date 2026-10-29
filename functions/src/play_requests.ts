/**
 * Remote play requests (contract v1, docs/CONTRACTS.md): the iPlex Control
 * searches the catalog and asks a linked TV to START a title. It is not a
 * remote control: there is no pause, seek, stop, volume or navigation.
 *
 *  families/{fid}/devices/{did}/play_requests/{id}
 *    {schemaVersion, deviceId, familyId, requesterUid, requesterName,
 *     sourceId, itemId, episodeId, episodeLabel, kind, title,
 *     status, errorCode, createdAt, expiresAt, updatedAt, deliveredAt, finishedAt, expireAt}
 *
 * status: pending → delivered → (confirming) → started | declined | failed
 *         pending → expired | superseded
 *         revoked: unlink marker (id device-unlinked), a signal for the TV listener only
 *
 * Only stable catalog identifiers travel: never stream URLs or IPTV credentials.
 * Writes are backend-only. The TV reads its own requests (rules) and claims them
 * through the `player` callable; a request is claimed once and only before
 * expiresAt, so an old request can never start content unexpectedly.
 */
import {createHash} from 'node:crypto';
import {FieldValue, getFirestore} from 'firebase-admin/firestore';
import {z} from 'zod';
import {canStartPlayback, DomainError, idSchema, Lease, nameSchema} from './domain';
import {playableItem} from './iptv_catalog_access';
import {chooseResume, episodeContentId, type ResumeHint, resumePosition, type SavedProgress} from './playback_progress';
import {playerContext, type Identity} from './service';

/** Written on unlink (status "revoked"): wakes open TV listeners; never a playable request. */
export const UNLINK_MARKER = 'device-unlinked';
export const PLAY_REQUEST_TTL_MS = 60_000;
/** A TV that asked for confirmation has this long to answer before the request is declined. */
export const PLAY_CONFIRM_MS = 45_000;
export type PlayRequestStatus = 'pending' | 'delivered' | 'confirming' | 'started' | 'declined' | 'failed' | 'expired' | 'superseded';
const FINAL: ReadonlySet<PlayRequestStatus> = new Set(['started', 'declined', 'failed', 'expired', 'superseded']);
/** Error codes a TV may report; anything else becomes playback-failed. */
export const PLAY_REQUEST_ERRORS = ['content-unavailable', 'content-not-allowed', 'source-protected', 'stream-unavailable', 'playback-failed', 'format-unsupported', 'session-limit', 'subscription-required', 'no-answer', 'busy'] as const;

const require_ = (ok: unknown, code = 'permission-denied'): void => { if (!ok) throw new DomainError(code); };
const db = () => getFirestore();
const requestDocId = (fid: string, deviceId: string, requestId: string) => `pr_${createHash('sha256').update(`${fid}:${deviceId}:${requestId}`).digest('hex').slice(0, 32)}`;

/** Server-side identity of the target TV, used only to evaluate what its active profile may watch. */
function tvIdentity(fid: string, deviceId: string, device: FirebaseFirestore.DocumentData): Identity {
  return {uid: `tv_${deviceId}`, deviceId, familyId: fid, ...(typeof device.credentialVersion === 'string' ? {credentialVersion: device.credentialVersion} : {})};
}

function visibilityError(error: unknown): DomainError {
  if (error instanceof DomainError) {
    if (error.code === 'pin-required') return new DomainError('source-protected');
    if (error.code === 'not-found') return new DomainError('content-not-allowed');
    if (error.code === 'session-expired') return new DomainError('tv-profile-required');
    return error;
  }
  throw error;
}

const progressContentId = (itemId: string, episodeId: string | null) => (episodeId ? episodeContentId(itemId, episodeId) : itemId);

/** Saved progress of the requester's own profile (what their Control showed, or where its
 * phone player stopped), or null. Same profile as the phone player: the account's link, else
 * `admin` for the family administrator (an individual family's owner often has no link). */
async function requesterProgress(tx: FirebaseFirestore.Transaction, family: FirebaseFirestore.DocumentReference, uid: string, contentId: string): Promise<ResumeHint | null> {
  const [link, familyDoc] = await tx.getAll(family.collection('profile_links').doc(uid), family);
  const admin = (familyDoc!.data()?.adminUid ?? familyDoc!.data()?.adminId) === uid;
  const profileId = link!.data()?.profileId ?? (admin ? 'admin' : undefined);
  if (typeof profileId !== 'string') return null;
  const profile = family.collection('profiles').doc(profileId);
  const [meta, progress] = await tx.getAll(profile, profile.collection('watch_progress').doc(contentId));
  const generation = meta!.data()?.generations?.progress ?? 0, d = progress!.data();
  if (!meta!.exists || meta!.data()?.deleting === true || !d || (d.generation ?? 0) !== generation) return null;
  return resumePosition(d) === null ? null : {positionSec: Math.floor(Number(d.position)), durationSec: Number(d.duration), profileId, updatedAt: Number(d.updatedAt) || 0};
}

/** Control (manager): a family member asks one of the family's TVs to start a title. */
export async function requestPlayback(p: Record<string, unknown>, actor: Identity, scopeOf: (tx: FirebaseFirestore.Transaction) => Promise<{fid: string; ref: FirebaseFirestore.DocumentReference; data: FirebaseFirestore.DocumentData}>) {
  require_(!actor.deviceId);
  const now = Date.now();
  const deviceId = idSchema.parse(p.deviceId), sourceId = idSchema.parse(p.sourceId), itemId = idSchema.parse(p.itemId);
  const episodeId = p.episodeId === undefined || p.episodeId === null ? null : idSchema.parse(p.episodeId);
  const episodeLabel = p.episodeLabel === undefined || p.episodeLabel === null ? null : nameSchema.parse(p.episodeLabel);
  const requestId = z.string().regex(/^[a-f0-9]{32}$/).parse(p.requestId);
  // "Continuar assistindo": the TV resumes from its active profile's saved progress.
  const resume = p.resume === true;

  // 1) The requester may see this item with its own profile/permissions (kids accounts stay restricted).
  const own = await playableItem(actor, sourceId, itemId);
  require_(own.kind !== 'series' || episodeId !== null || p.openSeries === true, 'episode-required');
  require_(own.kind === 'series' || episodeId === null, 'invalid-argument');

  // 2) Target TV: same scope, linked, with an active profile session, playback right.
  const target = await db().runTransaction(async tx => {
    const scope = await scopeOf(tx);
    require_(scope.fid === own.fid, 'permission-denied');
    const device = await tx.get(scope.ref.collection('devices').doc(deviceId));
    require_(device.exists && device.data()?.status !== 'unlinked', 'device-not-found');
    const lease = ((scope.data.leases ?? []) as Lease[]).find(l => l.deviceId === deviceId && l.expiresAt > now);
    require_(lease, 'device-offline');
    const subscription = (await tx.get(scope.ref.collection('private').doc('subscription'))).data();
    require_(canStartPlayback(subscription as never, now), 'subscription-required');
    return {fid: scope.fid, ref: scope.ref, device: device.data()!};
  });

  // 3) What the TV's ACTIVE profile may watch (kids profile on the TV ⇒ only kids content).
  try { await playableItem(tvIdentity(target.fid, deviceId, target.device), sourceId, itemId); }
  catch (error) { throw visibilityError(error); }

  const user = (await db().doc(`users/${actor.uid}`).get()).data();
  const requesterName = String(user?.displayName || user?.name || '').trim().slice(0, 80);
  const id = requestDocId(target.fid, deviceId, requestId);
  const deviceRef = target.ref.collection('devices').doc(deviceId), ref = deviceRef.collection('play_requests').doc(id);
  return db().runTransaction(async tx => {
    const [existing, device] = await tx.getAll(ref, deviceRef);
    // "Continuar assistindo": the position the person saw in the Control travels with the request.
    const hint = resume && own.kind !== 'channel' ? await requesterProgress(tx, target.ref, actor.uid, progressContentId(itemId, episodeId)) : null;
    if (existing!.exists) {
      // Idempotent retry of the same phone request.
      require_(existing!.data()?.requesterUid === actor.uid, 'invalid-argument');
      return {id, status: existing!.data()!.status as PlayRequestStatus, expiresAt: existing!.data()!.expiresAt as number};
    }
    require_(device!.exists, 'device-not-found');
    require_(now - ((device!.data()?.lastPlayRequestAt as number | undefined) ?? 0) >= 2_000, 'rate-limited');
    const pending = await tx.get(deviceRef.collection('play_requests').where('status', '==', 'pending'));
    // The newest request wins; older pending ones never start later.
    pending.docs.forEach(d => tx.update(d.ref, {status: 'superseded', updatedAt: now, finishedAt: now}));
    tx.create(ref, {
      schemaVersion: 1, deviceId, familyId: target.fid, requesterUid: actor.uid, requesterName,
      sourceId, itemId, episodeId, episodeLabel, kind: own.kind, title: own.title.slice(0, 300), resume: resume && own.kind !== 'channel', resumeHint: hint,
      status: 'pending', errorCode: null, createdAt: now, updatedAt: now, expiresAt: now + PLAY_REQUEST_TTL_MS,
      deliveredAt: null, finishedAt: null, expireAt: new Date(now + 86_400_000),
    });
    tx.update(deviceRef, {lastPlayRequestAt: now, pendingPlayRequest: {id, expiresAt: now + PLAY_REQUEST_TTL_MS}});
    return {id, status: 'pending' as PlayRequestStatus, expiresAt: now + PLAY_REQUEST_TTL_MS};
  });
}

/** Player: the TV takes a pending request once, before it expires, for its active profile. */
export async function claimPlayRequest(p: Record<string, unknown>, actor: Identity) {
  require_(actor.deviceId && actor.familyId);
  const now = Date.now(), id = idSchema.parse(p.playRequestId);
  const deviceRef = db().doc(`families/${actor.familyId}/devices/${actor.deviceId}`), ref = deviceRef.collection('play_requests').doc(id);
  const snap = await ref.get(), data = snap.data();
  require_(data && data.deviceId === actor.deviceId, 'play-request-not-found');
  // Visibility for the CURRENT lease profile is checked before claiming (permissions may have changed).
  let failure: string | null = null;
  if (data!.status === 'pending' && data!.expiresAt > now) {
    try { await playableItem(actor, data!.sourceId, data!.itemId); }
    catch (error) { const mapped = visibilityError(error); if (mapped.code === 'device-revoked' || mapped.code === 'subscription-required' || mapped.code === 'tv-profile-required') throw mapped; failure = mapped.code; }
  }
  return db().runTransaction(async tx => {
    // Linked device with the current credential (unlinked/re-paired TVs stop here).
    const ctx = await playerContext(tx, actor);
    const [current, device] = await tx.getAll(ref, deviceRef), d = current!.data()!;
    require_(current!.exists, 'play-request-not-found');
    const clearPointer = device!.data()?.pendingPlayRequest?.id === id ? {pendingPlayRequest: FieldValue.delete()} : {};
    // Resume: the TV's ACTIVE profile progress is read here, in the same transaction that delivers.
    let resumeFromTv: {profileId: string; progress: FirebaseFirestore.DocumentData | undefined} | undefined;
    if (d.resume === true && d.status === 'pending') {
      const lease = ((ctx.data.leases ?? []) as Lease[]).find(l => l.deviceId === actor.deviceId && l.expiresAt > now);
      if (lease) {
        const profile = ctx.ref.collection('profiles').doc(lease.profileId);
        const [meta, progress] = await tx.getAll(profile, profile.collection('watch_progress').doc(progressContentId(d.itemId, d.episodeId ?? null)));
        const p = progress!.data();
        resumeFromTv = {profileId: lease.profileId, progress: meta!.exists && p && (p.generation ?? 0) === (meta!.data()?.generations?.progress ?? 0) ? p : undefined};
      }
    }
    if (d.status !== 'pending') throw new DomainError(d.status === 'expired' || d.status === 'superseded' ? 'play-request-expired' : 'play-request-claimed');
    if (d.expiresAt <= now) {
      tx.update(ref, {status: 'expired', updatedAt: now, finishedAt: now});
      if (Object.keys(clearPointer).length) tx.update(deviceRef, clearPointer);
      return {id, status: 'expired' as PlayRequestStatus};
    }
    if (failure) {
      tx.update(ref, {status: 'failed', errorCode: failure, updatedAt: now, deliveredAt: now, finishedAt: now});
      if (Object.keys(clearPointer).length) tx.update(deviceRef, clearPointer);
      return {id, status: 'failed' as PlayRequestStatus, errorCode: failure};
    }
    tx.update(ref, {status: 'delivered', updatedAt: now, deliveredAt: now});
    if (Object.keys(clearPointer).length) tx.update(deviceRef, clearPointer);
    const resumeAt = resumeFromTv === undefined ? null : chooseResume(d.resumeHint as ResumeHint | null, resumeFromTv.progress as SavedProgress | undefined, resumeFromTv.profileId);
    return {id, status: 'delivered' as PlayRequestStatus, request: {sourceId: d.sourceId, itemId: d.itemId, episodeId: d.episodeId ?? null, episodeLabel: d.episodeLabel ?? null, kind: d.kind, title: d.title, requesterName: d.requesterName ?? '', ...(d.resume === true ? {resume: true, ...(resumeAt ? {resumePositionSec: resumeAt.positionSec, resumeDurationSec: resumeAt.durationSec} : {})} : {})}};
  });
}

const TRANSITIONS: Record<string, PlayRequestStatus[]> = {delivered: ['confirming', 'started', 'declined', 'failed'], confirming: ['started', 'declined', 'failed']};

/** Player: the TV reports what happened (confirmation shown, started, declined, failed). */
export async function updatePlayRequest(p: Record<string, unknown>, actor: Identity) {
  require_(actor.deviceId && actor.familyId);
  const now = Date.now(), id = idSchema.parse(p.playRequestId);
  const status = z.enum(['confirming', 'started', 'declined', 'failed']).parse(p.status);
  const code = status === 'failed' || status === 'declined'
    ? (PLAY_REQUEST_ERRORS as readonly string[]).includes(String(p.errorCode)) ? String(p.errorCode) : status === 'failed' ? 'playback-failed' : null
    : null;
  const ref = db().doc(`families/${actor.familyId}/devices/${actor.deviceId}/play_requests/${id}`);
  return db().runTransaction(async tx => {
    await playerContext(tx, actor);
    const snap = await tx.get(ref), d = snap.data();
    require_(d && d.deviceId === actor.deviceId, 'play-request-not-found');
    if (d!.status === status) return {id, status};
    require_(!FINAL.has(d!.status) && (TRANSITIONS[d!.status] ?? []).includes(status), 'invalid-transition');
    // An unanswered confirmation cannot be accepted long after the phone gave up.
    if (status === 'started' && d!.status === 'confirming' && (d!.updatedAt ?? 0) + PLAY_CONFIRM_MS < now) {
      tx.update(ref, {status: 'declined', errorCode: 'no-answer', updatedAt: now, finishedAt: now});
      return {id, status: 'declined' as PlayRequestStatus};
    }
    tx.update(ref, {status, errorCode: code, updatedAt: now, ...(FINAL.has(status) ? {finishedAt: now} : {})});
    return {id, status};
  });
}

/** Heartbeat fallback when the TV listener is unavailable: the device pointer, no extra read. */
export function pendingPointer(device: FirebaseFirestore.DocumentData, now: number): {id: string; expiresAt: number} | null {
  const pointer = device.pendingPlayRequest as {id?: unknown; expiresAt?: unknown} | undefined;
  return pointer && typeof pointer.id === 'string' && typeof pointer.expiresAt === 'number' && pointer.expiresAt > now ? {id: pointer.id, expiresAt: pointer.expiresAt} : null;
}
