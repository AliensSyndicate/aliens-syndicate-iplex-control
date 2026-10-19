import {getFirestore} from 'firebase-admin/firestore';
import {GoogleAuth} from 'google-auth-library';
import {z} from 'zod';
import {DomainError, hash, idSchema} from './domain';

/**
 * Google Play subscriptions for playback rights. The Manager stays free; a
 * verified purchase only writes families/{fid}/private/subscription, which the
 * Player checks through canStartPlayback. The client never writes that state.
 *
 * Catalog (Play Console): one subscription product with two auto-renewing base
 * plans and no free-trial offer.
 */
export const PLAY_PACKAGE = process.env.PLAY_PACKAGE_NAME || 'com.alienssyndicate.iplex_control';
export const PLAY_PRODUCT_ID = 'iplex_playback';
export const PLAY_BASE_PLANS = ['monthly', 'annual'] as const;
const API = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications';

export type PlaySubscription = {
  subscriptionState: string; acknowledgementState?: string; linkedPurchaseToken?: string; latestOrderId?: string;
  startTime?: string; externalAccountIdentifiers?: {obfuscatedExternalAccountId?: string};
  lineItems?: {productId: string; expiryTime?: string; offerDetails?: {basePlanId?: string; offerId?: string}; autoRenewingPlan?: {autoRenewEnabled?: boolean}}[];
  testPurchase?: Record<string, unknown>;
};
export type PlayApi = {
  getSubscription(token: string): Promise<PlaySubscription>;
  acknowledge(productId: string, token: string): Promise<void>;
};

let auth: GoogleAuth | undefined;
/** Uses the Functions runtime service account; no key leaves Google Cloud. */
export const googlePlayApi: PlayApi = {
  async getSubscription(token) {
    auth ??= new GoogleAuth({scopes: ['https://www.googleapis.com/auth/androidpublisher']});
    const client = await auth.getClient();
    const res = await client.request<PlaySubscription>({url: `${API}/${PLAY_PACKAGE}/purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}`});
    return res.data;
  },
  async acknowledge(productId, token) {
    auth ??= new GoogleAuth({scopes: ['https://www.googleapis.com/auth/androidpublisher']});
    const client = await auth.getClient();
    await client.request({method: 'POST', url: `${API}/${PLAY_PACKAGE}/purchases/subscriptions/${productId}/tokens/${encodeURIComponent(token)}:acknowledge`, data: {}});
  },
};

/** Account binding sent with the purchase (BillingFlowParams obfuscatedAccountId). */
export const obfuscatedAccount = (uid: string) => hash(`iplex-play:${uid}`).slice(0, 64);

/** Central checkout switch. Missing document = disabled. It never grants playback. */
export async function paymentsConfig(uid: string) {
  const data = (await getFirestore().doc('app_config/payments').get()).data();
  const enabled = data?.paymentsEnabled === true;
  const tester = Array.isArray(data?.testerUids) && data!.testerUids.includes(uid);
  return {paymentsEnabled: enabled, checkoutAllowed: enabled || tester, productId: PLAY_PRODUCT_ID, basePlans: [...PLAY_BASE_PLANS], packageName: PLAY_PACKAGE};
}

type Entitlement = {status: 'active' | 'cancelled' | 'expired' | 'pending'; paidUntil: number; storeState: string; basePlanId: string | null; autoRenew: boolean};
/** Maps Play's state to the existing Subscription contract used by canStartPlayback. */
export function entitlementFrom(sub: PlaySubscription, now = Date.now()): Entitlement {
  const item = sub.lineItems?.find(i => i.productId === PLAY_PRODUCT_ID);
  const expiry = item?.expiryTime ? Date.parse(item.expiryTime) : 0;
  const base = {paidUntil: Number.isFinite(expiry) ? expiry : 0, storeState: sub.subscriptionState, basePlanId: item?.offerDetails?.basePlanId ?? null, autoRenew: item?.autoRenewingPlan?.autoRenewEnabled === true};
  switch (sub.subscriptionState) {
    case 'SUBSCRIPTION_STATE_ACTIVE':
    case 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD':
      return {...base, status: expiry > now ? 'active' : 'expired'};
    case 'SUBSCRIPTION_STATE_CANCELED':
      // Cancelled keeps access until the paid period ends.
      return {...base, status: expiry > now ? 'cancelled' : 'expired'};
    case 'SUBSCRIPTION_STATE_PENDING':
      return {...base, status: 'pending', paidUntil: 0};
    default: // ON_HOLD, PAUSED, EXPIRED, PENDING_PURCHASE_CANCELED, unknown
      return {...base, status: 'expired', paidUntil: Math.min(base.paidUntil, now)};
  }
}

const tokenRef = (token: string) => getFirestore().doc(`play_purchases/${hash(token)}`);

/**
 * Applies the current Play state (always re-fetched, never trusted from the
 * client or the notification body). `fetchedAt` orders concurrent writers so an
 * older snapshot can never overwrite a newer one (out-of-order events).
 */
async function applyState(token: string, familyId: string, sub: PlaySubscription, fetchedAt: number, revoked = false) {
  const db = getFirestore(), ref = db.doc(`families/${familyId}/private/subscription`), purchase = tokenRef(token);
  const entitlement = revoked ? {...entitlementFrom(sub, fetchedAt), status: 'expired' as const, paidUntil: fetchedAt, storeState: 'REVOKED'} : entitlementFrom(sub, fetchedAt);
  await db.runTransaction(async tx => {
    const [current, bound] = await tx.getAll(ref, purchase);
    const data = current!.data() ?? {status: 'notStarted'};
    if (bound!.data()?.familyId && bound!.data()!.familyId !== familyId) throw new DomainError('purchase-already-used');
    const isCurrentToken = !data.purchaseTokenHash || data.purchaseTokenHash === hash(token) || data.purchaseTokenHash === (sub.linkedPurchaseToken ? hash(sub.linkedPurchaseToken) : undefined);
    if ((data.storeFetchedAt ?? 0) > fetchedAt && isCurrentToken) return; // stale snapshot
    tx.set(purchase, {familyId, productId: PLAY_PRODUCT_ID, basePlanId: entitlement.basePlanId, state: entitlement.storeState,
      latestOrderId: sub.latestOrderId ?? null, test: !!sub.testPurchase, updatedAt: fetchedAt, ...(revoked ? {revokedAt: fetchedAt} : {})}, {merge: true});
    // A superseded token (plan change) never downgrades the family's newer purchase.
    if (!isCurrentToken && (data.paidUntil ?? 0) > entitlement.paidUntil) return;
    tx.set(ref, {
      ...data, status: entitlement.status, paidUntil: entitlement.paidUntil, store: 'google_play', storeState: entitlement.storeState,
      basePlanId: entitlement.basePlanId, autoRenew: entitlement.autoRenew, purchaseTokenHash: hash(token), storeFetchedAt: fetchedAt,
      test: !!sub.testPurchase, updatedAt: fetchedAt,
    });
    if (sub.linkedPurchaseToken) tx.set(tokenRef(sub.linkedPurchaseToken), {supersededBy: hash(token), updatedAt: fetchedAt}, {merge: true});
  });
  return entitlement;
}

/** Called by the app after Play reports a purchase. Only the family admin may bind it. */
export async function verifyPlayPurchase(input: Record<string, unknown>, uid: string, familyId: string, api: PlayApi = googlePlayApi) {
  const config = await paymentsConfig(uid);
  if (!config.checkoutAllowed) throw new DomainError('payments-disabled');
  const token = z.string().min(10).max(4096).parse(input.purchaseToken);
  idSchema.parse(familyId);
  const sub = await api.getSubscription(token).catch(() => { throw new DomainError('purchase-invalid'); });
  const item = sub.lineItems?.find(i => i.productId === PLAY_PRODUCT_ID);
  if (!item || !(PLAY_BASE_PLANS as readonly string[]).includes(item.offerDetails?.basePlanId ?? '')) throw new DomainError('purchase-invalid');
  // Purchases are bound to the buying account; another user's token cannot be replayed here.
  if (sub.externalAccountIdentifiers?.obfuscatedExternalAccountId !== obfuscatedAccount(uid)) throw new DomainError('purchase-account-mismatch');
  const fetchedAt = Date.now();
  const entitlement = await applyState(token, familyId, sub, fetchedAt);
  if (sub.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING' && (entitlement.status === 'active' || entitlement.status === 'cancelled')) {
    await api.acknowledge(PLAY_PRODUCT_ID, token);
  }
  return {status: entitlement.status, paidUntil: entitlement.paidUntil, basePlanId: entitlement.basePlanId};
}

/**
 * Real-time developer notifications (Pub/Sub). Body content is only used to
 * locate the token; the state always comes from the Play Developer API.
 */
export async function handlePlayNotification(raw: unknown, api: PlayApi = googlePlayApi) {
  const message = z.object({
    packageName: z.string(),
    subscriptionNotification: z.object({notificationType: z.number(), purchaseToken: z.string()}).optional(),
    voidedPurchaseNotification: z.object({purchaseToken: z.string()}).optional(),
    testNotification: z.unknown().optional(),
  }).parse(raw);
  if (message.packageName !== PLAY_PACKAGE || message.testNotification) return {handled: false};
  const token = message.subscriptionNotification?.purchaseToken ?? message.voidedPurchaseNotification?.purchaseToken;
  if (!token) return {handled: false};
  const bound = (await tokenRef(token).get()).data();
  const sub = await api.getSubscription(token);
  // Unknown token (notification before the app verified it): bind via linked token or keep for later.
  const linkedFamily = !bound?.familyId && sub.linkedPurchaseToken ? (await tokenRef(sub.linkedPurchaseToken).get()).data()?.familyId : undefined;
  const familyId = bound?.familyId ?? linkedFamily;
  if (!familyId) {
    await tokenRef(token).set({pendingBinding: true, state: sub.subscriptionState, updatedAt: Date.now()}, {merge: true});
    return {handled: false};
  }
  // SUBSCRIPTION_REVOKED (12) and voided purchases (refunds/chargebacks) end access now.
  const revoked = message.voidedPurchaseNotification !== undefined || message.subscriptionNotification?.notificationType === 12;
  const entitlement = await applyState(token, familyId, sub, Date.now(), revoked);
  // Acknowledge here too, so a purchase is never auto-refunded because the app was not reopened.
  if (!revoked && sub.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING' && (entitlement.status === 'active' || entitlement.status === 'cancelled')) {
    await api.acknowledge(PLAY_PRODUCT_ID, token);
  }
  return {handled: true, familyId};
}
