import {DocumentReference, FieldValue, getFirestore, Transaction} from 'firebase-admin/firestore';
import {randomInt, randomUUID} from 'node:crypto';
import {z} from 'zod';
import {DomainError, hash, idSchema, nameSchema} from './domain';
import {limitIdentityAttempts, PUBLIC_CODE_ALPHABET} from './account_identity';
import {prepareJoin} from './family_individual';
import {randomBytes} from 'node:crypto';
import {hashParentalPin, matchesParentalPin, PARENTAL_PIN} from './parental';

/**
 * Media profiles are independent of Firebase accounts:
 *  families/{fid}/profiles/{pid}   type admin|regular|kids|guest, optional linkedUid
 *  families/{fid}/profile_links/{uid} -> {profileId}   one profile per account per family
 * Limits: one admin profile, four associates (regular + kids, legacy untyped
 * profiles count as regular) and one optional guest with the fixed id "guest".
 */
export type ProfileType = 'admin' | 'regular' | 'kids' | 'guest';
/** Each list has its own generation; `wishlist` falls back to `favorites` on profiles written before it existed. */
export type DataCategory = 'favorites' | 'wishlist' | 'watched' | 'progress';
export const DATA_CATEGORIES: DataCategory[] = ['favorites', 'wishlist', 'watched', 'progress'];
export const CATEGORY_COLLECTION: Record<DataCategory, string> = {favorites: 'favorites', wishlist: 'wishlist', watched: 'watched', progress: 'watch_progress'};
const LEGACY_TOP_LEVEL: Partial<Record<DataCategory, string>> = {favorites: 'profile_favorites', progress: 'profile_progress'};
export const MAX_ASSOCIATES = 4;
export const GUEST_ID = 'guest';
export const ADMIN_PROFILE_ID = 'admin';
const LINK_CODE_MS = 10 * 60000;
const CLEAR_STALE_MS = 120000;
const PAGE = 400;
export const LINK_CODE = /^[A-Z0-9]{8}$/;
export const spaceSchema = z.string().regex(/^[A-Za-z0-9_-]{1,128}:(channel|movie|series)$/);

export type ContentKind = 'channel' | 'movie' | 'series';
export const CONTENT_KINDS: ContentKind[] = ['channel', 'movie', 'series'];
const kindsSchema = z.array(z.enum(['channel', 'movie', 'series'])).max(3);
/** `kinds`: content types allowed in every IPTV source (Canais, Filmes, Séries); `spaces` narrows per source (legacy). */
export type Permissions = {allSpaces: boolean; spaces: string[]; adult: boolean; kinds: ContentKind[]};
/** The member's own restrictions (never wider than the administrator's limits). */
export type Preferences = {adult: boolean; spaces: string[] | null; kinds: ContentKind[] | null};
export type ProfileView = {id: string; name: string; type: ProfileType; linkedUid: string | null; enabled: boolean;
  /** Effective permissions: administrator limits combined with the member's preferences. */
  permissions: Permissions; limits: Permissions; preferences: Preferences;
  generations: Record<DataCategory, number>; permissionsVersion: number;
  /** The profile has a personal PIN: the TV asks for it to open the profile and to play adult content. */
  pinConfigured: boolean};

/** Whether [permissions] let a profile see [kind] content of [sourceId]. */
export function spaceAllowed(permissions: Permissions, sourceId: string, kind: string) {
  return permissions.kinds.includes(kind as ContentKind) && (permissions.allSpaces || permissions.spaces.includes(`${sourceId}:${kind}`));
}

/** Effective = limits ∩ preferences: a preference can only narrow what the administrator allows. */
export function effectivePermissions(limits: Permissions, preferences: Preferences): Permissions {
  const adult = limits.adult && preferences.adult;
  const kinds = limits.kinds.filter(k => !preferences.kinds || preferences.kinds.includes(k));
  if (!preferences.spaces) return {...limits, adult, kinds};
  if (limits.allSpaces) return {allSpaces: false, spaces: [...preferences.spaces], adult, kinds};
  return {allSpaces: false, spaces: limits.spaces.filter(s => preferences.spaces!.includes(s)), adult, kinds};
}

const storedKinds = (value: unknown): ContentKind[] | null =>
  Array.isArray(value) ? CONTENT_KINDS.filter(k => value.includes(k)) : null;

export function profileView(id: string, data: FirebaseFirestore.DocumentData): ProfileView {
  const type = (['admin', 'regular', 'kids', 'guest'] as const).includes(data.type) ? data.type as ProfileType : 'regular';
  const limits: Permissions = {allSpaces: data.permissions?.allSpaces !== false, spaces: Array.isArray(data.permissions?.spaces) ? data.permissions.spaces : [],
    adult: type !== 'kids' && data.permissions?.adult !== false,
    // The administrator's own profile is never limited by type (only its own preferences narrow it).
    kinds: type === 'admin' ? [...CONTENT_KINDS] : storedKinds(data.permissions?.kinds) ?? [...CONTENT_KINDS]};
  const preferences: Preferences = {adult: data.preferences?.adult !== false,
    spaces: Array.isArray(data.preferences?.spaces) ? data.preferences.spaces : null,
    kinds: storedKinds(data.preferences?.kinds)};
  const favorites = data.generations?.favorites ?? 0;
  return {
    id, name: String(data.name ?? ''), type, linkedUid: data.linkedUid ?? null, enabled: data.enabled !== false,
    permissions: effectivePermissions(limits, preferences), limits, preferences,
    generations: {favorites, wishlist: data.generations?.wishlist ?? favorites, watched: data.generations?.watched ?? 0, progress: data.generations?.progress ?? 0},
    permissionsVersion: data.permissionsVersion ?? 0,
    pinConfigured: data.personalPin?.configured === true,
  };
}
/** Profile linked to the calling account in this family (own data, preferences, PIN). */
async function ownProfile(tx: Transaction, f: Scope, uid: string) {
  const link = await tx.get(f.ref.collection('profile_links').doc(uid));
  const profileId = link.data()?.profileId;
  require_(typeof profileId === 'string', 'profile-not-linked');
  const ref = f.ref.collection('profiles').doc(profileId), snap = await tx.get(ref);
  require_(snap.exists && snap.data()?.deleting !== true, 'not-found');
  return {ref, profile: profileView(ref.id, snap.data()!)};
}

const isAssociate = (data: FirebaseFirestore.DocumentData) => !['admin', 'guest'].includes(data.type);
const require_ = (ok: unknown, code = 'permission-denied'): void => { if (!ok) throw new DomainError(code); };

export type Scope = {fid: string; ref: DocumentReference; data: FirebaseFirestore.DocumentData; initialize: () => void};
export type ScopeResolver = (tx: Transaction, admin: boolean, create: boolean) => Promise<Scope>;
const familyOnly = (scope: Scope) => require_(scope.data.kind !== 'personalIptv', 'family-required');

export async function associateCount(tx: Transaction, family: DocumentReference) {
  return (await tx.get(family.collection('profiles'))).docs.filter(d => isAssociate(d.data())).length;
}

/** Admin profile created with the family; linked to the administrator account. */
export function writeAdminProfile(tx: Transaction, family: DocumentReference, uid: string, name: string, now: number) {
  tx.set(family.collection('profiles').doc(ADMIN_PROFILE_ID), {
    name: name || 'Admin', type: 'admin', linkedUid: uid, enabled: true, familyId: family.id,
    permissions: {allSpaces: true, spaces: []}, generations: {favorites: 0, wishlist: 0, watched: 0, progress: 0}, createdAt: now, updatedAt: now,
  });
  tx.set(family.collection('profile_links').doc(uid), {profileId: ADMIN_PROFILE_ID, linkedAt: now});
}

/** New associate profile linked to an account accepted through the membership flow. */
export async function linkedAssociateForAccount(tx: Transaction, family: DocumentReference, uid: string, name: string, now: number, type: 'regular' | 'kids' = 'regular') {
  const link = await tx.get(family.collection('profile_links').doc(uid));
  if (link.exists) return () => {};
  require_((await associateCount(tx, family)) < MAX_ASSOCIATES, 'family-limit');
  return () => {
    const ref = family.collection('profiles').doc();
    tx.set(ref, {name: name || 'Associado', type, linkedUid: uid, linkedAt: now, enabled: true, familyId: family.id,
      permissions: {allSpaces: true, spaces: [], adult: type !== 'kids'}, generations: {favorites: 0, wishlist: 0, watched: 0, progress: 0}, createdAt: now, updatedAt: now});
    tx.set(family.collection('profile_links').doc(uid), {profileId: ref.id, linkedAt: now});
  };
}

/** Account removal from the family keeps the profile and its data; only the link goes. */
export async function unlinkAccountProfiles(tx: Transaction, family: DocumentReference, uid: string) {
  const link = await tx.get(family.collection('profile_links').doc(uid));
  const profileId = link.data()?.profileId as string | undefined;
  return () => {
    if (profileId) {
      tx.set(family.collection('profiles').doc(profileId), {linkedUid: null, personalPin: {configured: false, updatedAt: Date.now()}, updatedAt: Date.now()}, {merge: true});
      tx.delete(family.collection('private').doc(`personal_pin_${profileId}`));
    }
    tx.delete(family.collection('profile_links').doc(uid));
  };
}

export async function familyProfiles(action: string, p: Record<string, unknown>, uid: string, resolve: ScopeResolver): Promise<unknown> {
  const db = getFirestore(), now = Date.now();
  if (action === 'saveProfile') return db.runTransaction(async tx => {
    const f = await resolve(tx, true, true);
    const requestId = p.requestId === undefined ? undefined : idSchema.parse(p.requestId);
    const id = p.id ? idSchema.parse(p.id) : requestId ? `p_${hash(`${f.fid}:${requestId}`).slice(0, 32)}` : randomUUID();
    const ref = f.ref.collection('profiles').doc(id), snap = await tx.get(ref), name = nameSchema.parse(p.name);
    const requested = p.type === undefined ? undefined : z.enum(['regular', 'kids']).parse(p.type);
    if (snap.exists) {
      const current = profileView(id, snap.data()!);
      const changingType = requested !== undefined && requested !== current.type;
      // Only an explicit administrator edit may reclassify an associate. A retry
      // of profile creation cannot change its type, nor can admin/guest be converted.
      require_(!changingType || (!!p.id && isAssociate(snap.data()!)), 'profile-type-immutable');
      require_(!snap.data()?.deleting, 'not-found');
      if (!requestId || p.id) tx.update(ref, {name, updatedAt: now,
        ...(changingType ? {type: requested, permissionsVersion: current.permissionsVersion + 1,
          ...(requested === 'kids' ? {'permissions.adult': false} : {})} : {}),
      });
      return {id};
    }
    // Reserved ids are only created by setGuestEnabled / createFamily.
    require_(id !== GUEST_ID && id !== ADMIN_PROFILE_ID, 'invalid-argument');
    require_((await associateCount(tx, f.ref)) < MAX_ASSOCIATES, 'profile-limit');
    f.initialize();
    tx.set(ref, {name, type: requested ?? 'regular', linkedUid: null, enabled: true, familyId: f.fid, ownerId: f.data.ownerId ?? f.data.adminId,
      permissions: {allSpaces: true, spaces: []}, generations: {favorites: 0, wishlist: 0, watched: 0, progress: 0}, createdAt: now, updatedAt: now});
    return {id};
  });

  if (action === 'setGuestEnabled') return db.runTransaction(async tx => {
    const f = await resolve(tx, true, false); familyOnly(f);
    const enabled = z.boolean().parse(p.enabled), ref = f.ref.collection('profiles').doc(GUEST_ID), snap = await tx.get(ref);
    if (snap.exists) tx.update(ref, {enabled, updatedAt: now});
    else tx.set(ref, {name: nameSchema.parse(p.name), type: 'guest', linkedUid: null, enabled, familyId: f.fid,
      permissions: {allSpaces: true, spaces: []}, generations: {favorites: 0, wishlist: 0, watched: 0, progress: 0}, createdAt: now, updatedAt: now});
    return {id: GUEST_ID, enabled};
  });

  /**
   * Avisa as TVs da família, na hora, que as permissões de um perfil mudaram (conteúdo adulto, fontes...): marcador
   * em families/{fid}/devices/{did}/play_requests (status "access"), que a TV já escuta. Só um sinal: a TV relê o que
   * pode ver pelo backend. Sem ele, a TV só perceberia na próxima batida de presença (até 30 s).
   */
  const accessMarkers = (tx: Transaction, devices: FirebaseFirestore.QuerySnapshot, profileId: string, version: number, at: number) => {
    for (const d of devices.docs) {
      tx.set(d.ref.collection('play_requests').doc('access-changed'), {schemaVersion: 1, status: 'access', profileId, version, createdAt: at, expiresAt: at + 120_000, expireAt: new Date(at + 86_400_000)});
    }
  };

  if (action === 'setProfilePermissions') return db.runTransaction(async tx => {
    const f = await resolve(tx, true, false);
    const ref = f.ref.collection('profiles').doc(idSchema.parse(p.profileId)), snap = await tx.get(ref);
    require_(snap.exists, 'not-found');
    const current = profileView(ref.id, snap.data()!);
    const devices = await tx.get(f.ref.collection('devices'));
    // O administrador só pode ajustar o próprio "Conteúdo adulto" (acessos e fontes seguem protegidos).
    if (current.type === 'admin') {
      const adult = z.boolean().parse(p.adult);
      tx.update(ref, {'permissions.adult': adult, permissionsVersion: current.permissionsVersion + 1, updatedAt: now});
      accessMarkers(tx, devices, ref.id, current.permissionsVersion + 1, now);
      return {ok: true, permissionsVersion: current.permissionsVersion + 1};
    }
    // Each field is kept when not sent (older clients, or a single toggle changed).
    const allSpaces = p.allSpaces === undefined ? current.limits.allSpaces : z.boolean().parse(p.allSpaces);
    const spaces = p.spaces === undefined ? current.limits.spaces : Array.from(new Set(z.array(spaceSchema).max(300).parse(p.spaces)));
    const adult = p.adult === undefined ? current.limits.adult : z.boolean().parse(p.adult);
    const kinds = p.kinds === undefined ? current.limits.kinds : CONTENT_KINDS.filter(k => kindsSchema.parse(p.kinds).includes(k));
    tx.update(ref, {permissions: {allSpaces, spaces, adult, kinds}, permissionsVersion: current.permissionsVersion + 1, updatedAt: now});
    accessMarkers(tx, devices, ref.id, current.permissionsVersion + 1, now);
    return {ok: true, permissionsVersion: current.permissionsVersion + 1};
  });

  // The member's own preferences, only on the profile linked to the calling account and
  // never beyond the administrator's limits (rejected, not silently widened).
  if (action === 'setProfilePreferences') return db.runTransaction(async tx => {
    const f = await resolve(tx, false, false);
    const {ref, profile} = await ownProfile(tx, f, uid);
    require_(profile.type !== 'guest', 'guest-not-persisted');
    // Each field is kept when not sent; `null` removes the member's own restriction.
    const adult = p.adult === undefined ? profile.preferences.adult : z.boolean().parse(p.adult);
    const spaces = p.spaces === undefined ? profile.preferences.spaces
      : p.spaces === null ? null : Array.from(new Set(z.array(spaceSchema).max(300).parse(p.spaces)));
    const kinds = p.kinds === undefined ? profile.preferences.kinds
      : p.kinds === null ? null : CONTENT_KINDS.filter(k => kindsSchema.parse(p.kinds).includes(k));
    const devices = await tx.get(f.ref.collection('devices'));
    // Adult content is decided by the administrator only: the member cannot change it.
    require_(adult === profile.preferences.adult || profile.type === 'admin', 'permission-denied');
    require_(p.adult === undefined || !adult || profile.limits.adult, 'beyond-limit');
    require_(!spaces || profile.limits.allSpaces || spaces.every(s => profile.limits.spaces.includes(s)), 'beyond-limit');
    require_(!kinds || kinds.every(k => profile.limits.kinds.includes(k)), 'beyond-limit');
    tx.update(ref, {preferences: {adult, spaces, kinds}, permissionsVersion: profile.permissionsVersion + 1, updatedAt: now});
    accessMarkers(tx, devices, ref.id, profile.permissionsVersion + 1, now);
    return {ok: true, permissionsVersion: profile.permissionsVersion + 1};
  });

  // Personal PIN: set, changed or removed only by the account linked to the profile; an
  // existing PIN is required to change or remove it. Stored hashed in private/, never
  // returned; the profile only carries {personalPin: {configured}}.
  if (action === 'setPersonalPin' || action === 'clearPersonalPin') {
    await limitIdentityAttempts(uid, 'personal-pin');
    return db.runTransaction(async tx => {
      const f = await resolve(tx, false, false);
      const {ref, profile} = await ownProfile(tx, f, uid);
      require_(profile.type !== 'guest', 'permission-denied');
      const secretRef = f.ref.collection('private').doc(`personal_pin_${ref.id}`), secret = await tx.get(secretRef);
      if (secret.exists) require_(matchesParentalPin(String(p.currentPin ?? ''), secret.data()), 'pin-invalid');
      if (action === 'clearPersonalPin') {
        tx.delete(secretRef);
        tx.update(ref, {personalPin: {configured: false, updatedAt: now}, updatedAt: now});
        return {configured: false};
      }
      const pin = z.string().regex(PARENTAL_PIN).parse(p.pin);
      require_(p.confirmPin === pin, 'pin-mismatch');
      const salt = randomBytes(16).toString('base64');
      tx.set(secretRef, {pinHash: hashParentalPin(pin, salt), salt, profileId: ref.id, uid, updatedAt: now});
      tx.update(ref, {personalPin: {configured: true, updatedAt: now}, updatedAt: now});
      return {configured: true};
    });
  }

  if (action === 'createProfileLinkCode') return db.runTransaction(async tx => {
    const f = await resolve(tx, true, false); familyOnly(f);
    const ref = f.ref.collection('profiles').doc(idSchema.parse(p.profileId)), pointer = f.ref.collection('private').doc(`profile_link_${ref.id}`);
    const [snap, previous] = await tx.getAll(ref, pointer);
    require_(snap!.exists, 'not-found');
    const profile = profileView(ref.id, snap!.data()!);
    require_(profile.type === 'regular' || profile.type === 'kids', 'profile-not-linkable');
    require_(!profile.linkedUid, 'profile-already-linked');
    const code = Array.from({length: 8}, () => PUBLIC_CODE_ALPHABET[randomInt(PUBLIC_CODE_ALPHABET.length)]).join('');
    const expiresAt = now + LINK_CODE_MS;
    if (previous!.data()?.codeHash) tx.set(db.doc(`profile_link_codes/${previous!.data()!.codeHash}`), {used: true, revokedAt: now}, {merge: true});
    tx.set(db.doc(`profile_link_codes/${hash(code)}`), {familyId: f.fid, profileId: ref.id, issuerUid: uid, expiresAt, used: false, createdAt: now});
    tx.set(pointer, {codeHash: hash(code), expiresAt});
    return {code, expiresAt};
  });

  if (action === 'redeemProfileLink') {
    // Every attempt is charged before reading: codes are short and guessable.
    await limitIdentityAttempts(uid, 'profile-link');
    const code = z.string().trim().toUpperCase().regex(LINK_CODE).parse(p.code);
    return db.runTransaction(async tx => {
      const codeRef = db.doc(`profile_link_codes/${hash(code)}`), entry = (await tx.get(codeRef)).data();
      require_(entry, 'invalid-token');
      const family = db.doc(`families/${entry!.familyId}`), profileRef = family.collection('profiles').doc(entry!.profileId);
      const [f, profileSnap, link, user] = await tx.getAll(family, profileRef, family.collection('profile_links').doc(uid), db.doc(`users/${uid}`));
      const fd = f!.data(), profile = profileSnap!.exists ? profileView(profileRef.id, profileSnap!.data()!) : undefined;
      if (profile?.linkedUid === uid && entry!.used) return {familyId: family.id, profileId: profileRef.id};
      require_(!entry!.used && entry!.expiresAt > now, 'link-code-expired');
      require_(fd && !fd.deleting && fd.kind !== 'personalIptv' && fd.members?.[entry!.issuerUid] === 'admin' && profile, 'link-code-expired');
      require_(user!.exists, 'account-unavailable');
      require_((fd!.adminUid ?? fd!.adminId) !== uid && !link!.exists, 'account-already-linked');
      require_(!profile!.linkedUid && (profile!.type === 'regular' || profile!.type === 'kids'), 'profile-already-linked');
      // Joining by code follows the same one-family rule as an accepted invitation.
      const join = fd!.members?.[uid] ? undefined : await prepareJoin(tx, uid, user!.data()!, {ref: family, data: fd!}, now);
      join?.();
      // Same profile id: favorites, history, progress and permissions are untouched.
      tx.update(profileRef, {linkedUid: uid, linkedAt: now, updatedAt: now});
      tx.set(family.collection('profile_links').doc(uid), {profileId: profileRef.id, linkedAt: now});
      tx.update(codeRef, {used: true, redeemedByUid: uid, redeemedAt: now});
      tx.delete(family.collection('private').doc(`profile_link_${profileRef.id}`));
      return {familyId: family.id, profileId: profileRef.id};
    });
  }

  if (action === 'unlinkProfileAccount') return db.runTransaction(async tx => {
    const f = await resolve(tx, true, false); familyOnly(f);
    const ref = f.ref.collection('profiles').doc(idSchema.parse(p.profileId)), snap = await tx.get(ref);
    require_(snap.exists, 'not-found');
    const profile = profileView(ref.id, snap.data()!);
    require_(profile.type !== 'admin', 'administrator-protected');
    if (!profile.linkedUid) return {ok: true};
    // The personal PIN belongs to the account: it leaves with it.
    tx.update(ref, {linkedUid: null, personalPin: {configured: false, updatedAt: now}, updatedAt: now});
    tx.delete(f.ref.collection('private').doc(`personal_pin_${ref.id}`));
    tx.delete(f.ref.collection('profile_links').doc(profile.linkedUid));
    return {ok: true};
  });

  if (action === 'clearProfileData') return clearProfileData(p, uid, resolve);
  throw new DomainError('invalid-action');
}

/**
 * Destructive clear, backend only. The category generation is bumped before any
 * delete, so writes carrying an older generation (offline devices) are rejected
 * and cannot restore the data. Deletion is paginated; a job document blocks
 * concurrent clears and lets a retry with the same requestId resume or no-op.
 */
async function clearProfileData(p: Record<string, unknown>, uid: string, resolve: ScopeResolver) {
  const db = getFirestore(), now = Date.now();
  const profileId = idSchema.parse(p.profileId), category = z.enum(['favorites', 'wishlist', 'watched', 'progress']).parse(p.category);
  const requestId = idSchema.parse(p.requestId);
  const started = await db.runTransaction(async tx => {
    const f = await resolve(tx, false, false);
    const profileRef = f.ref.collection('profiles').doc(profileId), jobRef = f.ref.collection('profile_clear_jobs').doc(`${profileId}_${category}`);
    const [snap, job, link] = await tx.getAll(profileRef, jobRef, f.ref.collection('profile_links').doc(uid));
    require_(snap!.exists, 'not-found');
    // The administrator clears any profile; a member only the profile linked to its own account.
    require_((f.data.adminUid ?? f.data.adminId) === uid || link!.data()?.profileId === profileId);
    const profile = profileView(profileId, snap!.data()!), current = job!.data();
    require_(profile.type !== 'guest', 'guest-not-persisted');
    if (current?.requestId === requestId) {
      if (current.status === 'completed') return {fid: f.fid, profileRef, jobRef, generation: current.generation as number, done: true};
      tx.update(jobRef, {status: 'running', updatedAt: now});
      return {fid: f.fid, profileRef, jobRef, generation: current.generation as number, done: false};
    }
    require_(!(current?.status === 'running' && current.updatedAt > now - CLEAR_STALE_MS), 'clear-in-progress');
    const generation = profile.generations[category] + 1;
    // Profiles older than the wishlist generation keep its current value when favorites move on.
    tx.update(profileRef, {[`generations.${category}`]: generation, 'generations.wishlist': category === 'wishlist' ? generation : profile.generations.wishlist, updatedAt: now});
    tx.set(jobRef, {requestId, profileId, category, generation, status: 'running', startedAt: now, updatedAt: now, deleted: 0});
    return {fid: f.fid, profileRef, jobRef, generation, done: false};
  });
  if (started.done) return {ok: true, generation: started.generation};
  try {
    let deleted = await deleteOlder(started.profileRef.collection(CATEGORY_COLLECTION[category]), started.generation);
    const legacy = LEGACY_TOP_LEVEL[category];
    if (legacy) deleted += await deleteOlder(db.collection(legacy).where('familyId', '==', started.fid).where('profileId', '==', profileId), started.generation);
    await started.jobRef.update({status: 'completed', completedAt: Date.now(), updatedAt: Date.now(), deleted: FieldValue.increment(deleted)});
    return {ok: true, generation: started.generation, deleted};
  } catch (error) {
    await started.jobRef.update({status: 'failed', updatedAt: Date.now()}).catch(() => {});
    throw new DomainError('clear-failed');
  }
}

async function deleteOlder(query: FirebaseFirestore.Query, generation: number) {
  let deleted = 0, cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    let page = query.orderBy('__name__').limit(PAGE);
    if (cursor) page = page.startAfter(cursor);
    const rows = await page.get();
    if (rows.empty) return deleted;
    const batch = getFirestore().batch();
    let pending = 0;
    for (const row of rows.docs) if ((row.data().generation ?? 0) < generation) { batch.delete(row.ref); pending++; }
    if (pending) await batch.commit();
    deleted += pending; cursor = rows.docs[rows.docs.length - 1];
    if (rows.size < PAGE) return deleted;
  }
}

/** Writes of personal media data: guest never persists; stale generations are rejected. */
export function requireWritableGeneration(profile: ProfileView, category: DataCategory, value: unknown) {
  require_(profile.type !== 'guest', 'guest-not-persisted');
  require_(value !== undefined && value !== null, 'generation-required');
  const generation = z.number().int().min(0).parse(value);
  require_(generation === profile.generations[category], 'stale-generation');
  return generation;
}
