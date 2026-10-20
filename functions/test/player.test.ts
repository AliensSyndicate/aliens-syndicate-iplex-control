import {test} from 'node:test';
import assert from 'node:assert/strict';
import {networkKey,playerIdentity,PLAYER_DEVICE_ACTIONS,PLAYER_PUBLIC_ACTIONS,runPlayer,type PlayerDeps,type QuotaRule} from '../src/player';

const device=(over:Record<string,unknown>={},uid='tv_dev1')=>({uid,token:{deviceId:'dev1',familyId:'fam1',firebase:{sign_in_provider:'custom'},auth_time:1,...over}});
function deps(){
 const calls:{action:string;actor:unknown}[]=[],quotas:{key:string;rule:QuotaRule}[]=[];
 const d:PlayerDeps={execute:async(action,_p,actor)=>{calls.push({action,actor});return {ok:true};},consume:async()=>{},quota:async(key,rule)=>{quotas.push({key,rule});},now:()=>1_000_000};
 return {d,calls,quotas};
}

test('player: device actions require the pairing credential, never the request body',async()=>{
 const {d,calls}=deps();
 await runPlayer({action:'listPlayerProfiles',payload:{deviceId:'outro',familyId:'outra'},auth:device(),ip:'1.1.1.1'},'k',d);
 assert.deepEqual(calls[0]!.actor,{uid:'tv_dev1',deviceId:'dev1',familyId:'fam1',authTime:1});
 await assert.rejects(runPlayer({action:'listPlayerProfiles',payload:{},auth:undefined,ip:'1.1.1.1'},'k',d),/unauthenticated/);
});

test('player: person accounts, inconsistent uid, missing claims or non-custom sign-in are refused',()=>{
 assert.throws(()=>playerIdentity({uid:'user1',token:{firebase:{sign_in_provider:'google.com'}}}),/device-required/);
 assert.throws(()=>playerIdentity(device({},'tv_other')),/device-required/);
 assert.throws(()=>playerIdentity(device({familyId:undefined})),/device-required/);
 assert.throws(()=>playerIdentity(device({firebase:{sign_in_provider:'password'}})),/device-required/);
 assert.throws(()=>playerIdentity(undefined),/unauthenticated/);
});

test('player: closed action list — administrative actions do not exist here',async()=>{
 const {d,calls}=deps();
 for(const action of ['linkDevice','deleteDevice','saveProfile','setProfilePermissions','saveSource','verifyPlayPurchase','prepareDeletion','sendCommand','ackCommand','requestPlayback','setParentalPin','createFamily','bootstrap','inspectPairingSession',''])
  await assert.rejects(runPlayer({action,payload:{},auth:device(),ip:'1.1.1.1'},'k',d),/invalid-action/,action);
 assert.equal(calls.length,0);
 assert.ok(!PLAYER_DEVICE_ACTIONS.has('manager'));
 for(const a of PLAYER_PUBLIC_ACTIONS)assert.ok(!PLAYER_DEVICE_ACTIONS.has(a));
});

test('player: pairing runs without identity, behind global and per-network quotas',async()=>{
 const {d,calls,quotas}=deps();
 await runPlayer({action:'beginDevicePair',payload:{name:'TV'},auth:device(),ip:'10.0.0.1'},'k',d);
 assert.equal(calls[0]!.actor,undefined,'a credencial nunca é usada no pareamento');
 assert.deepEqual(quotas.map(q=>q.rule.bucket),['player_begin_global','player_begin_net']);
 assert.equal(quotas[1]!.key,networkKey('10.0.0.1'));
 assert.notEqual(networkKey('10.0.0.1'),'10.0.0.1');
});

test('player: quota exhaustion stops pairing before any write',async()=>{
 const {d,calls}=deps();
 d.quota=async()=>{throw Object.assign(new Error('rate-limited'));};
 await assert.rejects(runPlayer({action:'beginDevicePair',payload:{name:'TV'},auth:undefined,ip:'x'},'k',d),/rate-limited/);
 assert.equal(calls.length,0);
});

test('player: oversized pairing payload is rejected',async()=>{
 const {d}=deps();
 await assert.rejects(runPlayer({action:'beginDevicePair',payload:{name:'x'.repeat(5000)},auth:undefined,ip:'x'},'k',d),/invalid-argument/);
});

test('player: malformed verified auth is refused, never a TypeError',()=>{
 assert.throws(()=>playerIdentity({uid:'tv_dev1'} as never),/device-required/);
 assert.throws(()=>playerIdentity({uid:'tv_dev1',token:null} as never),/device-required/);
});
