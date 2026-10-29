import {createFamily} from './support/membership';
import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {execute,Identity} from '../src/service';
import {couponRef,type Coupon} from '../src/coupons';
import {obfuscatedAccount,verifyPlayPurchase,type PlayApi} from '../src/play_billing';
import {canStartPlayback,startTrial,type Subscription} from '../src/domain';

let app:ReturnType<typeof initializeApp>,seq=0;
before(()=>{if(!process.env.FIRESTORE_EMULATOR_HOST)throw new Error('Emulator required');app=initializeApp({projectId:'demo-iplex'});});
after(()=>deleteApp(app));
async function admin(){const a:Identity={uid:`cp_${Date.now()}_${++seq}`,authTime:Math.floor(Date.now()/1000)};await getAuth().createUser({uid:a.uid});await execute('bootstrap',{},a);
 const fid=(await createFamily(a,'Casa') as {id:string}).id;return {a,fid};}
const coupon=(code:string,data:Partial<Coupon>={})=>couponRef(code).set({plan:'lifetime',maxRedemptions:1,redemptions:0,createdAt:Date.now(),...data});
const subscription=async(fid:string)=>(await getFirestore().doc(`families/${fid}/private/subscription`).get()).data() as Subscription&Record<string,unknown>;

test('lifetime never expires and survives a later trial start', () => {
 assert.equal(canStartPlayback({status:'lifetime'},Number.MAX_SAFE_INTEGER),true);
 assert.equal(startTrial({status:'lifetime'},100).status,'lifetime');
});

test('coupon grants lifetime once per family, normalizes the code and enforces uses, expiry and disable', async () => {
 const {a,fid}=await admin(),other=await admin(),third=await admin();
 await coupon('IPLEX-TEST-AAAA-0001',{maxRedemptions:2});
 assert.deepEqual(await execute('redeemCoupon',{code:' iplex test aaaa 0001 '},a),{status:'lifetime'});
 const s=await subscription(fid);
 assert.equal(s.status,'lifetime');assert.equal(s.lifetimeSource,'coupon');assert.equal(canStartPlayback(s,Date.now()),true);
 await assert.rejects(execute('redeemCoupon',{code:'IPLEX-TEST-AAAA-0001'},a),/already-lifetime/);
 await execute('redeemCoupon',{code:'IPLEX-TEST-AAAA-0001'},other.a);
 await assert.rejects(execute('redeemCoupon',{code:'IPLEX-TEST-AAAA-0001'},third.a),/coupon-used/);
 await coupon('IPLEX-TEST-AAAA-0002',{expiresAt:Date.now()-1});
 await assert.rejects(execute('redeemCoupon',{code:'IPLEX-TEST-AAAA-0002'},third.a),/coupon-expired/);
 await coupon('IPLEX-TEST-AAAA-0003',{disabled:true});
 await assert.rejects(execute('redeemCoupon',{code:'IPLEX-TEST-AAAA-0003'},third.a),/coupon-invalid/);
 await assert.rejects(execute('redeemCoupon',{code:'nope'},third.a),/coupon-invalid/);
 await assert.rejects(execute('redeemCoupon',{code:'IPLEX-NAO-EXISTE-0000'},third.a),/coupon-invalid/);
 assert.equal((await couponRef('IPLEX-TEST-AAAA-0001').get()).data()!.redemptions,2);
});

test('a Play purchase never replaces lifetime and is left unacknowledged', async () => {
 const {a,fid}=await admin();await coupon('IPLEX-TEST-AAAA-0004');await execute('redeemCoupon',{code:'IPLEX-TEST-AAAA-0004'},a);
 await getFirestore().doc('app_config/payments').set({paymentsEnabled:false,testerUids:[a.uid]});
 const acks:string[]=[];
 const api:PlayApi={async getSubscription(){return {subscriptionState:'SUBSCRIPTION_STATE_ACTIVE',acknowledgementState:'ACKNOWLEDGEMENT_STATE_PENDING',externalAccountIdentifiers:{obfuscatedExternalAccountId:obfuscatedAccount(a.uid)},lineItems:[{productId:'iplex_playback',expiryTime:new Date(Date.now()+86400000).toISOString(),offerDetails:{basePlanId:'monthly'}}]};},async acknowledge(_p,t){acks.push(t);}};
 await assert.rejects(verifyPlayPurchase({purchaseToken:'purchase-lifetime-token'},a.uid,fid,api),/already-lifetime/);
 assert.equal(acks.length,0);assert.equal((await subscription(fid)).status,'lifetime');
 await getFirestore().doc('app_config/payments').delete();
});
