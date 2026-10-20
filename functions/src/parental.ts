/**
 * Parental PIN (contract v1, docs/CONTRACTS.md).
 *
 * One 4-digit PIN per family, set by the administrator in the iPlex Control.
 * On a TV, when the family has a kids profile, entering an adult profile
 * (admin or regular) requires that PIN. The rule is enforced by the backend in
 * acquireSession; the TV interface only asks for the PIN.
 *
 *  families/{fid}/private/parental  {pinHash, salt, updatedAt, updatedByUid}  (no client access)
 *  families/{fid}.parental          {pinConfigured, updatedAt}                (members read it)
 *  families/{fid}/devices/{did}     pinUnlock {profileId, expiresAt}: one correct PIN, consumed by acquireSession
 *                                   pinSession {profileId, until}: re-acquire the same profile without a new PIN
 *  identity_attempts/parental_{fid}_{did} {failures, lockedUntil}           (no client access)
 *
 * The PIN is never stored in clear, never returned and never compared on a client.
 */
import {randomBytes, scryptSync, timingSafeEqual} from 'node:crypto';
import {FieldValue, getFirestore, type DocumentReference, type Transaction} from 'firebase-admin/firestore';
import {z} from 'zod';
import {DomainError, idSchema} from './domain';
import {profileView, type ProfileView} from './family_profiles';

export const PARENTAL_PIN = /^\d{4}$/;
/** Window to start the session after a correct PIN. */
export const PIN_UNLOCK_MS = 2 * 60_000;
/** Lease recovery, multitasking and heartbeat failures keep the unlock for this long. */
export const PIN_SESSION_MS = 15 * 60_000;
export const PIN_MAX_FAILURES = 5;
export const PIN_LOCK_MS = 15 * 60_000;

const pinSchema = z.string().regex(PARENTAL_PIN);
const require_ = (ok: unknown, code = 'permission-denied'): void => { if (!ok) throw new DomainError(code); };

export function hashParentalPin(pin: string, salt: string): string {
  return scryptSync(pin, Buffer.from(salt, 'base64'), 32, {N: 16384, r: 8, p: 1}).toString('base64');
}
export function matchesParentalPin(pin: string, stored: {pinHash?: unknown; salt?: unknown} | undefined): boolean {
  if (!stored || typeof stored.pinHash !== 'string' || typeof stored.salt !== 'string') return false;
  const expected = Buffer.from(stored.pinHash, 'base64'), actual = Buffer.from(hashParentalPin(pin, stored.salt), 'base64');
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

export const isAdultProfile = (view: Pick<ProfileView, 'type'>) => view.type === 'admin' || view.type === 'regular';

/** Kids profiles that still exist (deleting profiles no longer protect anything). */
export async function familyHasKids(tx: Transaction, family: DocumentReference): Promise<boolean> {
  return (await tx.get(family.collection('profiles'))).docs.some(d => d.data().type === 'kids' && d.data().deleting !== true);
}

/** Admin-only management from the Control (callable manager). */
export async function manageParentalPin(action: string, p: Record<string, unknown>, uid: string, scope: {fid: string; ref: DocumentReference}, tx: Transaction) {
  const now = Date.now(), ref = scope.ref.collection('private').doc('parental');
  if (action === 'setParentalPin') {
    const pin = pinSchema.parse(p.pin);
    require_(p.confirmPin === pin, 'pin-mismatch');
    const salt = randomBytes(16).toString('base64');
    tx.set(ref, {pinHash: hashParentalPin(pin, salt), salt, updatedAt: now, updatedByUid: uid});
    tx.set(scope.ref, {parental: {pinConfigured: true, updatedAt: now}}, {merge: true});
    return {pinConfigured: true, updatedAt: now};
  }
  // clearParentalPin: adult profiles stay locked on TVs while a kids profile exists (fail closed).
  tx.delete(ref);
  tx.set(scope.ref, {parental: {pinConfigured: false, updatedAt: now}}, {merge: true});
  return {pinConfigured: false, updatedAt: now};
}

/** Player: validates the PIN for one adult profile and arms a short, single-use unlock on this device. */
export async function verifyProfilePin(p: Record<string, unknown>, context: {ref: DocumentReference; device: DocumentReference; fid: string; deviceId: string}) {
  const db = getFirestore(), now = Date.now();
  const profileId = idSchema.parse(p.profileId);
  // Format is checked before any attempt is charged; a malformed PIN is a client bug, not a guess.
  const pin = pinSchema.parse(p.pin);
  const attemptsRef = db.doc(`identity_attempts/parental_${context.fid}_${context.deviceId}`);
  return db.runTransaction(async tx => {
    const [profile, secret, attempts] = await tx.getAll(context.ref.collection('profiles').doc(profileId), context.ref.collection('private').doc('parental'), attemptsRef);
    require_(profile!.exists && profile!.data()?.deleting !== true, 'profile-unavailable');
    const view = profileView(profileId, profile!.data()!);
    require_(view.enabled, 'profile-disabled');
    const kids = await familyHasKids(tx, context.ref);
    if (!isAdultProfile(view) || !kids) return {verified: true, required: false};
    require_(secret!.exists, 'parental-pin-not-configured');
    const lockedUntil = (attempts!.data()?.lockedUntil as number | undefined) ?? 0;
    if (lockedUntil > now) throw new DomainError('pin-locked', {retryAt: lockedUntil});
    if (matchesParentalPin(pin, secret!.data())) {
      tx.set(attemptsRef, {failures: 0, lockedUntil: 0, expireAt: new Date(now + PIN_LOCK_MS)});
      tx.update(context.device, {pinUnlock: {profileId, expiresAt: now + PIN_UNLOCK_MS}});
      return {verified: true, required: true};
    }
    const failures = ((attempts!.data()?.failures as number | undefined) ?? 0) + 1;
    const locked = failures >= PIN_MAX_FAILURES;
    tx.set(attemptsRef, {failures: locked ? 0 : failures, lockedUntil: locked ? now + PIN_LOCK_MS : 0, expireAt: new Date(now + 2 * PIN_LOCK_MS)});
    return {verified: false, required: true, attemptsLeft: locked ? 0 : PIN_MAX_FAILURES - failures, ...(locked ? {retryAt: now + PIN_LOCK_MS} : {})};
  });
}

/**
 * Called inside acquireSession (after all its reads): an adult profile on a family with
 * kids needs a fresh unlock (PIN) or a still valid PIN session for the SAME profile.
 * Returns the device fields to write.
 */
export function parentalGate(view: ProfileView, kids: boolean, device: FirebaseFirestore.DocumentData, now: number): Record<string, unknown> {
  if (!isAdultProfile(view) || !kids) return {pinUnlock: FieldValue.delete(), pinSession: FieldValue.delete()};
  const unlock = device.pinUnlock as {profileId?: string; expiresAt?: number} | undefined;
  const session = device.pinSession as {profileId?: string; until?: number} | undefined;
  const unlocked = unlock?.profileId === view.id && (unlock.expiresAt ?? 0) > now;
  const resumed = session?.profileId === view.id && (session.until ?? 0) > now;
  require_(unlocked || resumed, 'profile-pin-required');
  return {pinUnlock: FieldValue.delete(), pinSession: {profileId: view.id, until: now + PIN_SESSION_MS}};
}
