/**
 * Profile PIN on the TV (contract v1, docs/CONTRACTS.md).
 *
 * Each profile may have a personal 4-digit PIN, set only by the account linked
 * to it in the iPlex Control (family_profiles.ts). When it is set, the TV asks
 * for it to open the profile (enforced in acquireSession) and to play adult
 * content (enforced in resolveSourceStream). Without it, neither is asked.
 *
 *  families/{fid}/private/personal_pin_{pid} {pinHash, salt, ...}           (no client access)
 *  families/{fid}/profiles/{pid}.personalPin {configured, updatedAt}        (members read it)
 *  families/{fid}/devices/{did}     pinUnlock {profileId, expiresAt}: one correct PIN, consumed by acquireSession
 *                                   pinSession {profileId, until}: re-acquire the same profile without a new PIN
 *                                   adultUnlock {profileId, expiresAt}: one adult title, consumed by resolveSourceStream
 *  identity_attempts/parental_{fid}_{did}, adult_{fid}_{did} {failures, lockedUntil} (no client access)
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
/** Janela para tocar um conteúdo adulto depois do PIN correto (uso único). */
export const ADULT_UNLOCK_MS = 2 * 60_000;
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

const personalSecret = (family: DocumentReference, profileId: string) => family.collection('private').doc(`personal_pin_${profileId}`);

/** Player: validates the personal PIN of one profile and arms a short, single-use unlock on this device. */
export async function verifyProfilePin(p: Record<string, unknown>, context: {ref: DocumentReference; device: DocumentReference; fid: string; deviceId: string}) {
  const db = getFirestore(), now = Date.now();
  const profileId = idSchema.parse(p.profileId);
  // Format is checked before any attempt is charged; a malformed PIN is a client bug, not a guess.
  const pin = pinSchema.parse(p.pin);
  const attemptsRef = db.doc(`identity_attempts/parental_${context.fid}_${context.deviceId}`);
  return db.runTransaction(async tx => {
    const [profile, secret, attempts] = await tx.getAll(context.ref.collection('profiles').doc(profileId), personalSecret(context.ref, profileId), attemptsRef);
    require_(profile!.exists && profile!.data()?.deleting !== true, 'profile-unavailable');
    const view = profileView(profileId, profile!.data()!);
    require_(view.enabled, 'profile-disabled');
    if (!view.pinConfigured || !secret!.exists) return {verified: true, required: false};
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
 * Player: PIN pessoal do perfil para TOCAR conteúdo adulto, só quando o perfil tem PIN (sem PIN, não é pedido).
 * Perfis sem conteúdo adulto liberado são recusados. Arma um desbloqueio de uso único neste dispositivo,
 * consumido por resolveSourceStream.
 */
export async function verifyAdultPin(p: Record<string, unknown>, context: {ref: DocumentReference; device: DocumentReference; fid: string; deviceId: string; view: Pick<ProfileView, 'id' | 'type' | 'permissions' | 'pinConfigured'>}) {
  const db = getFirestore(), now = Date.now();
  require_(context.view.permissions.adult, 'permission-denied');
  if (!context.view.pinConfigured) return {verified: true, required: false};
  const pin = pinSchema.parse(p.pin);
  const attemptsRef = db.doc(`identity_attempts/adult_${context.fid}_${context.deviceId}`);
  return db.runTransaction(async tx => {
    const [secret, attempts] = await tx.getAll(personalSecret(context.ref, context.view.id), attemptsRef);
    if (!secret!.exists) return {verified: true, required: false};
    const lockedUntil = (attempts!.data()?.lockedUntil as number | undefined) ?? 0;
    if (lockedUntil > now) throw new DomainError('pin-locked', {retryAt: lockedUntil});
    if (matchesParentalPin(pin, secret!.data())) {
      tx.set(attemptsRef, {failures: 0, lockedUntil: 0, expireAt: new Date(now + PIN_LOCK_MS)});
      tx.update(context.device, {adultUnlock: {profileId: context.view.id, expiresAt: now + ADULT_UNLOCK_MS}});
      return {verified: true, required: true};
    }
    const failures = ((attempts!.data()?.failures as number | undefined) ?? 0) + 1;
    const locked = failures >= PIN_MAX_FAILURES;
    tx.set(attemptsRef, {failures: locked ? 0 : failures, lockedUntil: locked ? now + PIN_LOCK_MS : 0, expireAt: new Date(now + 2 * PIN_LOCK_MS)});
    return {verified: false, required: true, attemptsLeft: locked ? 0 : PIN_MAX_FAILURES - failures, ...(locked ? {retryAt: now + PIN_LOCK_MS} : {})};
  });
}

/** Consome o desbloqueio de uso único do conteúdo adulto (mesmo perfil, ainda válido); senão `adult-pin-required`. Sem PIN pessoal, nada é exigido. */
/** `ref`: the TV's device document, or the phone's mobile session (iPlex Control). */
export async function consumeAdultUnlock(ref: DocumentReference, profileId: string | undefined, pinConfigured: boolean): Promise<void> {
  if (!pinConfigured) return;
  const db = getFirestore(), now = Date.now();
  await db.runTransaction(async tx => {
    const unlock = (await tx.get(ref)).data()?.adultUnlock as {profileId?: string; expiresAt?: number} | undefined;
    require_(unlock && unlock.profileId === profileId && (unlock.expiresAt ?? 0) > now, 'adult-pin-required');
    tx.update(ref, {adultUnlock: FieldValue.delete()});
  });
}

/**
 * Called inside acquireSession (after all its reads): a profile with a personal PIN needs a
 * fresh unlock (PIN) or a still valid PIN session for the SAME profile.
 * Returns the device fields to write.
 */
export function parentalGate(view: ProfileView, device: FirebaseFirestore.DocumentData, now: number): Record<string, unknown> {
  if (!view.pinConfigured) return {pinUnlock: FieldValue.delete(), pinSession: FieldValue.delete()};
  const unlock = device.pinUnlock as {profileId?: string; expiresAt?: number} | undefined;
  const session = device.pinSession as {profileId?: string; until?: number} | undefined;
  const unlocked = unlock?.profileId === view.id && (unlock.expiresAt ?? 0) > now;
  const resumed = session?.profileId === view.id && (session.until ?? 0) > now;
  require_(unlocked || resumed, 'profile-pin-required');
  return {pinUnlock: FieldValue.delete(), pinSession: {profileId: view.id, until: now + PIN_SESSION_MS}};
}
