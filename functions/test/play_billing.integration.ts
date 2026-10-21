import {createFamily} from './support/membership';
import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {execute,Identity} from '../src/service';
import {entitlementFrom,handlePlayNotification,obfuscatedAccount,PlayApi,PlaySubscription,verifyPlayPurchase,PLAY_PACKAGE} from '../src/play_billing';
import {canStartPlayback} from '../src/domain';

let app:ReturnType<typeof initializeApp>,seq=0;
before(()=>{if(!process.env.FIRESTORE_EMULATOR_HOST)throw new Error('Emulator required');app=initializeApp({projectId:'demo-iplex'});});
after(()=>deleteApp(app));
const day=86400000;
async function admin(){const a:Identity={uid:`pb_${Date.now()}_${++seq}`,authTime:Math.floor(Date.now()/1000)};await getAuth().createUser({uid:a.uid});await execute('bootstrap',{},a);
 const fid=(await createFamily(a,'Casa') as {id:string}).id;return {a,fid};}
function fakeApi(states:Record<string,PlaySubscription>){const acks:string[]=[];const api:PlayApi={async getSubscription(t){if(!states[t])throw new Error('404');return states[t]!;},async acknowledge(_p,t){acks.push(t);}};return {api,acks};}
const sub=(uid:string,state:string,expiresIn:number,plan='monthly',extra:Partial<PlaySubscription>={}):PlaySubscription=>({subscriptionState:state,acknowledgementState:'ACKNOWLEDGEMENT_STATE_PENDING',latestOrderId:'GPA.1',
 externalAccountIdentifiers:{obfuscatedExternalAccountId:obfuscatedAccount(uid)},lineItems:[{productId:'iplex_playback',expiryTime:new Date(Date.now()+expiresIn).toISOString(),offerDetails:{basePlanId:plan}}],...extra});
const setPayments=(data:Record<string,unknown>)=>getFirestore().doc('app_config/payments').set(data);
const subscription=async(fid:string)=>(await getFirestore().doc(`families/${fid}/private/subscription`).get()).data()!;

test('Play states map to playback rights; no trial or entitlement is invented', () => {
 const now=Date.now(), s=(state:string,exp:number)=>entitlementFrom(sub('u',state,exp),now);
 assert.equal(s('SUBSCRIPTION_STATE_ACTIVE',day).status,'active');
 assert.equal(s('SUBSCRIPTION_STATE_IN_GRACE_PERIOD',day).status,'active');
 assert.equal(s('SUBSCRIPTION_STATE_CANCELED',day).status,'cancelled');
 assert.equal(s('SUBSCRIPTION_STATE_CANCELED',-day).status,'expired');
 for(const state of ['SUBSCRIPTION_STATE_ON_HOLD','SUBSCRIPTION_STATE_PAUSED','SUBSCRIPTION_STATE_EXPIRED']){
  const e=s(state,day);assert.equal(e.status,'expired');assert.equal(canStartPlayback({status:e.status,paidUntil:e.paidUntil},now+1),false,state);
 }
 assert.equal(s('SUBSCRIPTION_STATE_PENDING',day).status,'pending');
});

test('checkout is disabled by default: no verification, no rights; testers can verify in isolation', async () => {
 await getFirestore().doc('app_config/payments').delete();
 const {a,fid}=await admin();const {api}=fakeApi({tok_disabled_1:sub(a.uid,'SUBSCRIPTION_STATE_ACTIVE',30*day)});
 const config=await execute('getPaymentsConfig',{},a) as {paymentsEnabled:boolean;checkoutAllowed:boolean;productId:string;basePlans:string[]};
 assert.equal(config.paymentsEnabled,false);assert.equal(config.checkoutAllowed,false);assert.deepEqual(config.basePlans,['monthly','annual']);
 await assert.rejects(verifyPlayPurchase({purchaseToken:'tok_disabled_1'},a.uid,fid,api),/payments-disabled/);
 assert.equal((await subscription(fid)).status,'notStarted');
 await setPayments({paymentsEnabled:false,testerUids:[a.uid]});
 assert.equal((await verifyPlayPurchase({purchaseToken:'tok_disabled_1'},a.uid,fid,api)).status,'active');
 await getFirestore().doc('app_config/payments').delete();
});

test('verified purchase grants rights, acknowledges once, rejects foreign, wrong-product and reused tokens', async () => {
 const {a,fid}=await admin(),other=await admin();await setPayments({paymentsEnabled:false,testerUids:[a.uid,other.a.uid]});
 const {api,acks}=fakeApi({
  'purchase-t_ok-token':sub(a.uid,'SUBSCRIPTION_STATE_ACTIVE',30*day,'annual'),
  'purchase-t_foreign-token':sub('someone-else','SUBSCRIPTION_STATE_ACTIVE',30*day),
  'purchase-t_weekly-token':sub(a.uid,'SUBSCRIPTION_STATE_ACTIVE',7*day,'weekly'),
 });
 const r=await verifyPlayPurchase({purchaseToken:'purchase-t_ok-token'},a.uid,fid,api);
 assert.equal(r.status,'active');assert.equal(r.basePlanId,'annual');assert.deepEqual(acks,['purchase-t_ok-token']);
 const s=await subscription(fid);assert.equal(s.store,'google_play');assert.equal(canStartPlayback(s as any,Date.now()),true);
 await assert.rejects(verifyPlayPurchase({purchaseToken:'purchase-t_foreign-token'},a.uid,fid,api),/purchase-account-mismatch/);
 await assert.rejects(verifyPlayPurchase({purchaseToken:'purchase-t_weekly-token'},a.uid,fid,api),/purchase-invalid/);
 await assert.rejects(verifyPlayPurchase({purchaseToken:'purchase-t_missing-token'},a.uid,fid,api),/purchase-invalid/);
 // The same token can never grant a second family.
 await assert.rejects(verifyPlayPurchase({purchaseToken:'purchase-t_ok-token'},a.uid,other.fid,api),/purchase-account-mismatch|purchase-already-used/);
 // Only the scope administrator can bind a purchase through the callable.
 const member:Identity={uid:`pbm_${Date.now()}`,authTime:Math.floor(Date.now()/1000)};await getAuth().createUser({uid:member.uid});await execute('bootstrap',{},member);
 await assert.rejects(execute('verifyPlayPurchase',{purchaseToken:'purchase-t_ok-token',contextFamilyId:fid},member),/permission-denied/);
 await getFirestore().doc('app_config/payments').delete();
});

test('notifications re-fetch state: renewal, cancel, payment failure, expiry, refund/revoke, plan change and out-of-order', async () => {
 const {a,fid}=await admin();await setPayments({paymentsEnabled:true});
 const states:Record<string,PlaySubscription>={'purchase-t1-token':sub(a.uid,'SUBSCRIPTION_STATE_ACTIVE',30*day)};const {api}=fakeApi(states);
 await verifyPlayPurchase({purchaseToken:'purchase-t1-token'},a.uid,fid,api);
 const notify=(token:string,type:number)=>handlePlayNotification({packageName:PLAY_PACKAGE,subscriptionNotification:{notificationType:type,purchaseToken:token}},api);
 states['purchase-t1-token']=sub(a.uid,'SUBSCRIPTION_STATE_ACTIVE',60*day);await notify('purchase-t1-token',2); // renewed
 assert.ok((await subscription(fid)).paidUntil>Date.now()+59*day);
 states['purchase-t1-token']=sub(a.uid,'SUBSCRIPTION_STATE_CANCELED',60*day);await notify('purchase-t1-token',3);
 assert.equal((await subscription(fid)).status,'cancelled');
 states['purchase-t1-token']=sub(a.uid,'SUBSCRIPTION_STATE_ON_HOLD',-day);await notify('purchase-t1-token',5); // payment failure
 assert.equal((await subscription(fid)).status,'expired');
 // Plan change: the new token links to the old one and takes over the family.
 states['purchase-t2-token']=sub(a.uid,'SUBSCRIPTION_STATE_ACTIVE',365*day,'annual',{linkedPurchaseToken:'purchase-t1-token'});await notify('purchase-t2-token',4);
 let s=await subscription(fid);assert.equal(s.status,'active');assert.equal(s.basePlanId,'annual');
 // A late event for the superseded token cannot downgrade the family.
 states['purchase-t1-token']=sub(a.uid,'SUBSCRIPTION_STATE_EXPIRED',-day);await notify('purchase-t1-token',13);
 assert.equal((await subscription(fid)).status,'active');
 // Refund/chargeback: voided purchase ends access immediately.
 await handlePlayNotification({packageName:PLAY_PACKAGE,voidedPurchaseNotification:{purchaseToken:'purchase-t2-token'}},api);
 s=await subscription(fid);assert.equal(s.status,'expired');assert.equal(canStartPlayback(s as any,Date.now()+1),false);
 // Foreign package and test notifications are ignored; unknown tokens wait for binding.
 assert.equal((await handlePlayNotification({packageName:'com.other',subscriptionNotification:{notificationType:4,purchaseToken:'purchase-t2-token'}},api)).handled,false);
 assert.equal((await handlePlayNotification({packageName:PLAY_PACKAGE,testNotification:{version:'1.0'}},api)).handled,false);
 states['purchase-t9-token']=sub(a.uid,'SUBSCRIPTION_STATE_ACTIVE',day);assert.equal((await notify('purchase-t9-token',4)).handled,false);
 await getFirestore().doc('app_config/payments').delete();
});
