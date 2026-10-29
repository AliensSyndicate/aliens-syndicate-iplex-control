/**
 * Reprodução no celular (iPlex Control): o celular é um player com sessão própria, nas mesmas
 * regras da TV — assinatura ou teste ativo, até 3 reproduções simultâneas, 1 por perfil e o PIN
 * pessoal para conteúdo adulto. O perfil é o da própria conta (vínculo em profile_links; o
 * administrador sem vínculo usa `admin`). O lease usa o id virtual `mobile_{uid}` (nunca um
 * documento de dispositivo) e o estado do celular (desbloqueio do adulto) fica em
 * families/{fid}/mobile_sessions/{uid}. A URL do vídeo só sai por resolveSourceStream com uma
 * sessão móvel válida (authorize revalida lease, assinatura e permissões).
 */
import {randomUUID} from 'node:crypto';
import {FieldValue, type Transaction} from 'firebase-admin/firestore';
import {acquire, canStartPlayback, DomainError, idSchema, LEASE_MS, nameSchema, type Lease} from './domain';
import {profileView, type ProfileView} from './family_profiles';

export const mobileDeviceId = (uid: string) => `mobile_${uid}`;
export const mobileSessionRef = (family: FirebaseFirestore.DocumentReference, uid: string) => family.collection('mobile_sessions').doc(uid);

type Scope = {fid: string; ref: FirebaseFirestore.DocumentReference; data: FirebaseFirestore.DocumentData};
const require_ = (ok: unknown, code = 'permission-denied'): void => { if (!ok) throw new DomainError(code); };

/** Profile the account plays with on its phone (its own). */
export async function mobileProfile(tx: Transaction, scope: Scope, uid: string): Promise<ProfileView> {
  const link = await tx.get(scope.ref.collection('profile_links').doc(uid));
  const admin = (scope.data.adminUid ?? scope.data.adminId) === uid;
  const profileId = link.data()?.profileId ?? (admin ? 'admin' : undefined);
  require_(typeof profileId === 'string', 'profile-unavailable');
  const snap = await tx.get(scope.ref.collection('profiles').doc(profileId));
  require_(snap.exists && snap.data()?.deleting !== true, 'profile-unavailable');
  const view = profileView(snap.id, snap.data()!);
  require_(view.enabled, 'profile-disabled');
  return view;
}

/** The phone's current lease, checked against the session it holds. */
export function mobileLease(scope: Scope, uid: string, sessionId: unknown, now = Date.now()): Lease {
  const id = idSchema.parse(sessionId);
  const lease = ((scope.data.leases ?? []) as Lease[]).find(l => l.deviceId === mobileDeviceId(uid) && l.id === id && l.expiresAt > now);
  require_(lease, 'session-expired');
  return lease!;
}

/** startMobilePlayback / mobilePlaybackHeartbeat / stopMobilePlayback. */
export async function mobilePlayback(action: string, p: Record<string, unknown>, uid: string, tx: Transaction, scope: Scope) {
  const now = Date.now();
  const subscription = (await tx.get(scope.ref.collection('private').doc('subscription'))).data();
  const sessionRef = mobileSessionRef(scope.ref, uid);
  let leases = ((scope.data.leases ?? []) as Lease[]).filter(l => l.expiresAt > now);
  if (action === 'startMobilePlayback') {
    const view = await mobileProfile(tx, scope, uid);
    if (!canStartPlayback(subscription as never, now)) throw new DomainError('subscription-required', {plansRoute: '/account/subscription'});
    const deviceName = p.deviceName === undefined ? 'Celular' : nameSchema.parse(p.deviceName);
    const lease: Lease = {id: randomUUID(), deviceId: mobileDeviceId(uid), deviceName, profileId: view.id, expiresAt: now + LEASE_MS};
    leases = acquire(leases, lease, now);
    tx.update(scope.ref, {leases});
    // A new session starts locked (any earlier adult unlock goes).
    tx.set(sessionRef, {sessionId: lease.id, profileId: view.id, updatedAt: now});
    return {sessionId: lease.id, profileId: view.id, pinRequired: view.pinConfigured, generations: view.generations, expiresAt: lease.expiresAt};
  }
  const current = mobileLease(scope, uid, p.sessionId, now);
  if (action === 'stopMobilePlayback') {
    tx.update(scope.ref, {leases: leases.filter(l => l.id !== current.id)});
    tx.set(sessionRef, {sessionId: null, adultUnlock: FieldValue.delete(), updatedAt: now}, {merge: true});
    return {ok: true};
  }
  if (!canStartPlayback(subscription as never, now)) throw new DomainError('subscription-required', {plansRoute: '/account/subscription'});
  const expiresAt = now + LEASE_MS;
  tx.update(scope.ref, {leases: leases.map(l => (l.id === current.id ? {...l, expiresAt} : l))});
  return {ok: true, expiresAt};
}
