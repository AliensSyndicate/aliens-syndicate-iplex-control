import {getFirestore} from 'firebase-admin/firestore';
import {z} from 'zod';
import {DomainError, hash, idSchema} from './domain';

/**
 * Lifetime access by coupon. Coupons live in `coupons/{sha256(code)}` (the code
 * itself is never stored) and are created only by operators with the Admin SDK
 * (`scripts/coupons.ts`); clients never read or write them. Redeeming writes
 * families/{fid}/private/subscription, once per family, from the backend only.
 *
 * Coupon document: {plan: 'lifetime', maxRedemptions, redemptions, expiresAt?, disabled?, note?, createdAt}
 */
export type Coupon = {plan: 'lifetime'; maxRedemptions: number; redemptions: number; expiresAt?: number; disabled?: boolean; note?: string; createdAt: number};

/** Case, spaces and dashes are ignored: "iplex-ab12 cd34" = "IPLEXAB12CD34". */
export const normalizeCoupon = (code: string) => code.toUpperCase().replace(/[\s-]/g, '');
const codeSchema = z.string().max(64).transform(normalizeCoupon).pipe(z.string().regex(/^[A-Z0-9]{6,40}$/));
export const couponRef = (code: string) => getFirestore().doc(`coupons/${hash(`iplex-coupon:${normalizeCoupon(code)}`)}`);

/** Lifetime subscription fields; trial and payment history are kept for audit. */
export function lifetimeSubscription(current: Record<string, unknown> | undefined, now: number, source: Record<string, unknown>) {
  return {...(current ?? {status: 'notStarted'}), status: 'lifetime', plan: 'lifetime', lifetimeSince: now, ...source, updatedAt: now};
}

export async function redeemCoupon(input: Record<string, unknown>, uid: string, familyId: string, now = Date.now()) {
  idSchema.parse(familyId);
  const parsed = codeSchema.safeParse(input.code);
  if (!parsed.success) throw new DomainError('coupon-invalid');
  const db = getFirestore(), ref = couponRef(parsed.data), sub = db.doc(`families/${familyId}/private/subscription`);
  return db.runTransaction(async tx => {
    const [c, s] = await tx.getAll(ref, sub);
    const coupon = c!.data() as Coupon | undefined;
    if (!coupon || coupon.disabled === true || coupon.plan !== 'lifetime') throw new DomainError('coupon-invalid');
    if (s!.data()?.status === 'lifetime') throw new DomainError('already-lifetime');
    if (Number.isFinite(coupon.expiresAt) && coupon.expiresAt! <= now) throw new DomainError('coupon-expired');
    if ((coupon.redemptions ?? 0) >= coupon.maxRedemptions) throw new DomainError('coupon-used');
    tx.update(ref, {redemptions: (coupon.redemptions ?? 0) + 1, lastRedeemedAt: now});
    tx.set(ref.collection('redemptions').doc(familyId), {familyId, uid, redeemedAt: now});
    tx.set(sub, lifetimeSubscription(s!.data(), now, {lifetimeSource: 'coupon', couponId: ref.id, grantedBy: uid}));
    return {status: 'lifetime'};
  });
}
