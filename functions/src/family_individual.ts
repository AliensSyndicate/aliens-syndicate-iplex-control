import {DocumentData, DocumentReference, FieldValue, getFirestore, Transaction} from 'firebase-admin/firestore';
import {UserRecord} from 'firebase-admin/auth';
import {addMember, DomainError} from './domain';
import {writeAdminProfile} from './family_profiles';

/**
 * One account, one family. Every account has exactly one active family link
 * (`users/{uid}.familyId`), administrator or member. A new account gets an
 * individual family at its first bootstrap. Joining another family moves the
 * account only when the individual family holds no resources; that family is
 * then parked (`parked`, members emptied, nothing deleted) and `homeFamilyId`
 * remembers it so the account gets it back when it leaves.
 */
const required = (ok: unknown, code = 'permission-denied'): void => { if (!ok) throw new DomainError(code); };
const isLiveFamily = (data: DocumentData | undefined, uid: string) =>
  !!data && !data.deleting && !data.parked && data.kind !== 'personalIptv' && !!data.members?.[uid];

/** Provider photos only: https, bounded. Anything else is ignored, never stored. */
export function safePhotoUrl(value: unknown): string | null {
  if (typeof value !== 'string' || value.length > 1000) return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && url.hostname ? url.toString() : null;
  } catch {
    return null;
  }
}

/** Google provider photo first (freshest), then the account photo. Apple has none: null. */
export function authPhotoUrl(user: Pick<UserRecord, 'photoURL' | 'providerData'>): string | null {
  const provider = user.providerData.find(p => p.providerId === 'google.com')?.photoURL;
  return safePhotoUrl(provider) ?? safePhotoUrl(user.photoURL);
}

export function writeMemberDoc(tx: Transaction, family: DocumentReference, uid: string, user: DocumentData, role: 'admin' | 'member', now: number) {
  const photoUrl = safePhotoUrl(user.photoUrl);
  tx.set(family.collection('members').doc(uid), {uid, name: user.name ?? user.displayName ?? '', role, ...(photoUrl ? {photoUrl} : {}), joinedAt: now}, {merge: true});
}

/** True when the family holds anything that moving the account would strand. */
export async function hasResources(tx: Transaction, ref: DocumentReference, data: DocumentData) {
  const now = Date.now();
  if (((data.leases ?? []) as {expiresAt:number}[]).some(l => l.expiresAt > now)) return true;
  const [devices, sources, profiles] = await Promise.all([
    tx.get(ref.collection('devices').limit(1)), tx.get(ref.collection('sources').limit(1)), tx.get(ref.collection('profiles')),
  ]);
  if (!devices.empty || !sources.empty) return true;
  if (profiles.docs.some(d => !['admin', 'guest'].includes(d.id) && d.data().deleting !== true)) return true;
  const admin = ref.collection('profiles').doc('admin');
  for (const collection of ['favorites', 'watched', 'watch_progress']) {
    if (!(await tx.get(admin.collection(collection).limit(1))).empty) return true;
  }
  return false;
}

/**
 * Resolves the family an account must have, creating nothing until every read is
 * done. Order: current link → another live membership (legacy multi-family) →
 * parked individual family → personal IPTV space promoted in place → new family.
 * `exclude` skips a family the account is leaving.
 */
export async function prepareIndividual(tx: Transaction, uid: string, user: DocumentData, opts: {exclude?: string} = {}): Promise<{id: string; write: (extra?: Record<string, unknown>) => void}> {
  const db = getFirestore(), ur = db.doc(`users/${uid}`), now = Date.now();
  // Explicit list (no array transforms): a caller can merge its own changes into the same update.
  const index = (id: string) => Array.from(new Set([...((user.familyIds ?? []) as string[]).filter(x => x !== opts.exclude), id]));
  const ids = Array.from(new Set([user.familyId, ...(user.familyIds ?? []), user.homeFamilyId, user.iptvWorkspaceId]
    .filter((id): id is string => typeof id === 'string' && !!id && id !== opts.exclude)));
  const rows = ids.length ? (await tx.getAll(...ids.map(id => db.doc(`families/${id}`)))).map(s => ({id: s.id, ref: s.ref, data: s.data()})) : [];
  const active = rows.filter(r => isLiveFamily(r.data, uid));
  const pick = active.find(r => r.id === user.familyId) ?? active.find(r => r.data!.members[uid] === 'admin') ?? active[0];
  if (pick) {
    return {id: pick.id, write: extra => {
      if (user.familyId !== pick.id || extra) tx.update(ur, {familyId: pick.id, familyIds: index(pick.id), ...extra});
      writeMemberDoc(tx, pick.ref, uid, user, pick.data!.members[uid], now);
    }};
  }
  const home = rows.find(r => r.id === user.homeFamilyId && r.data && !r.data.deleting && r.data.parked && (r.data.adminUid ?? r.data.adminId) === uid);
  if (home) {
    return {id: home.id, write: extra => {
      tx.update(home.ref, {members: {[uid]: 'admin'}, parked: FieldValue.delete(), parkedFor: FieldValue.delete(), parkedAt: FieldValue.delete(), updatedAt: now});
      tx.update(ur, {familyId: home.id, familyIds: index(home.id), homeFamilyId: home.id, ...extra});
      writeMemberDoc(tx, home.ref, uid, user, 'admin', now);
    }};
  }
  const space = rows.find(r => r.id === user.iptvWorkspaceId && r.data && !r.data.deleting && r.data.kind === 'personalIptv' && r.data.ownerId === uid);
  const name = String(user.name ?? user.displayName ?? '').trim().slice(0, 80);
  if (space) {
    // The personal IPTV space becomes the individual family: sources, devices and
    // history keep their identifiers, nothing is copied or removed.
    const [profile, subscription] = await tx.getAll(space.ref.collection('profiles').doc('admin'), space.ref.collection('private').doc('subscription'));
    return {id: space.id, write: extra => {
      tx.update(space.ref, {kind: FieldValue.delete(), individual: true, name: name || 'iPlex', members: {[uid]: 'admin'}, updatedAt: now});
      tx.update(ur, {familyId: space.id, familyIds: index(space.id), homeFamilyId: space.id, iptvWorkspaceId: FieldValue.delete(), ...extra});
      writeMemberDoc(tx, space.ref, uid, user, 'admin', now);
      if (!subscription!.exists) tx.set(space.ref.collection('private').doc('subscription'), {status: 'notStarted'});
      if (!profile!.exists) writeAdminProfile(tx, space.ref, uid, name, now);
    }};
  }
  const ref = db.collection('families').doc();
  return {id: ref.id, write: extra => {
    tx.create(ref, {name: name || 'iPlex', individual: true, adminId: uid, ownerId: uid, members: {[uid]: 'admin'}, leases: [], createdAt: now});
    tx.set(ref.collection('private').doc('subscription'), {status: 'notStarted'});
    writeAdminProfile(tx, ref, uid, name, now);
    tx.update(ur, {familyId: ref.id, familyIds: index(ref.id), homeFamilyId: ref.id, ...extra});
    writeMemberDoc(tx, ref, uid, user, 'admin', now);
  }};
}

/** Idempotent: an account with a live family is returned untouched. */
export async function ensureFamily(uid: string): Promise<string> {
  const db = getFirestore();
  return db.runTransaction(async tx => {
    const snap = await tx.get(db.doc(`users/${uid}`));
    required(snap.exists, 'account-unavailable');
    const prepared = await prepareIndividual(tx, uid, snap.data()!);
    prepared.write();
    return prepared.id;
  });
}

/**
 * Moves an account into `family`. Reads first; returns the writes. Refuses when the
 * account already belongs to a family that has other people or resources.
 */
export async function prepareJoin(tx: Transaction, uid: string, user: DocumentData, family: {ref: DocumentReference; data: DocumentData}, now: number): Promise<() => void> {
  const db = getFirestore(), ur = db.doc(`users/${uid}`);
  const members = addMember(family.data.members ?? {}, uid);
  const others = Array.from(new Set([user.familyId, ...(user.familyIds ?? [])].filter((id): id is string => typeof id === 'string' && !!id && id !== family.ref.id)));
  const rows = others.length ? (await tx.getAll(...others.map(id => db.doc(`families/${id}`)))).map(s => ({ref: s.ref, data: s.data()})) : [];
  const memberships = rows.filter(r => isLiveFamily(r.data, uid));
  let park: DocumentReference | null = null;
  for (const row of memberships) {
    const solo = Object.keys(row.data!.members).length === 1 && row.data!.members[uid] === 'admin' && (row.data!.adminUid ?? row.data!.adminId) === uid;
    required(solo && !park, 'already-in-family');
    required(!(await hasResources(tx, row.ref, row.data!)), 'individual-family-has-resources');
    park = row.ref;
  }
  return () => {
    tx.update(family.ref, {members});
    writeMemberDoc(tx, family.ref, uid, user, 'member', now);
    if (park) tx.update(park, {members: {}, parked: true, parkedAt: now, parkedFor: family.ref.id, updatedAt: now});
    tx.update(ur, {familyId: family.ref.id, familyIds: Array.from(new Set([...((user.familyIds ?? []) as string[]), family.ref.id])), ...(park ? {homeFamilyId: park.id} : {})});
  };
}
