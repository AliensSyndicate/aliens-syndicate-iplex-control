import {test} from 'node:test';
import assert from 'node:assert/strict';
import {acquire,addMember,canStartPlayback,startTrial,seal,unseal,sourceSchema,sourceInputSchema,Lease} from '../src/domain';
import {parseM3u,parseXtream,publicAddress,validateUpdate,fingerprint} from '../src/catalog';
const lease=(n:number,profileId=`p${n}`):Lease=>({id:`s${n}`,deviceId:`d${n}`,deviceName:`TV ${n}`,profileId,expiresAt:100});
test('fourth TV rejected with current names; expired lease reclaimed',()=>{assert.throws(()=>acquire([lease(1),lease(2),lease(3)],lease(4),1),(e:any)=>e.details.devices.join(',')==='TV 1,TV 2,TV 3');assert.equal(acquire([lease(1)],lease(2),101).length,1);});
test('profile cannot be acquired by two TVs; device can switch profile',()=>{assert.throws(()=>acquire([lease(1)],lease(2,'p1'),1),/profile-in-use/);assert.equal(acquire([lease(1)],lease(1,'p2'),1).length,1);});
test('family maximum includes administrator and rejects duplicate',()=>{assert.throws(()=>addMember({a:'admin',b:'member',c:'member',d:'member',e:'member'},'f'),/family-limit/);assert.throws(()=>addMember({a:'admin'},'a'),/already-linked/);});
test('trial starts once, expiry is strict, cancelled paid time is retained',()=>{const s=startTrial({status:'notStarted'},100);assert.deepEqual(startTrial(s,999),s);assert.equal(canStartPlayback(s,s.trialEndsAt!),false);assert.equal(canStartPlayback({status:'cancelled',paidUntil:100},99),true);});
test('playback policy fails closed without finite server-owned entitlement dates',()=>{
 for(const s of [undefined,{status:'notStarted' as const},{status:'active' as const},{status:'trial' as const,trialEndsAt:NaN},{status:'active' as const,paidUntil:Infinity},{status:'expired' as const,paidUntil:999},{status:'pending' as const,paidUntil:999}])assert.equal(canStartPlayback(s,100),false);
 assert.equal(canStartPlayback({status:'active',paidUntil:100},100),false);
 assert.equal(canStartPlayback({status:'trial',trialEndsAt:101},100),true);
 assert.equal(canStartPlayback({status:'active',paidUntil:101},100),true);
});
test('trial starts on first device only and never replaces a valid paid period',()=>{
 const paid=startTrial({status:'active',paidUntil:1000},100);
 assert.equal(paid.status,'active');assert.equal(paid.paidUntil,1000);
 assert.deepEqual(startTrial(paid,200),paid);
 assert.equal(startTrial(undefined,100).trialStartedAt,100);
});
test('AES-GCM round trip and tamper rejection',()=>{const key=Buffer.alloc(32,1).toString('base64');const data=seal({password:'fixture'},key);assert.deepEqual(unseal(data,key),{password:'fixture'});assert.throws(()=>unseal(data,Buffer.alloc(32,2).toString('base64')));});
test('source requires valid scheme and Xtream credentials',()=>{assert.equal(sourceSchema.safeParse({name:'TV',format:'m3u',url:'ftp://example.com'}).success,false);assert.equal(sourceSchema.safeParse({name:'TV',format:'m3u',url:'http://example.com'}).success,true);assert.equal(sourceSchema.safeParse({name:'TV',format:'xtream',url:'http://example.com'}).success,false);assert.equal(sourceInputSchema.safeParse({id:'s1',name:'TV',format:'xtream',url:'http://example.com',username:'user'}).success,true);assert.equal(sourceInputSchema.safeParse({name:'TV',format:'xtream',url:'http://example.com',username:'user'}).success,false);});
test('SSRF rejects loopback, mapped IPv4, metadata, private, multicast',()=>{for(const ip of ['127.0.0.1','10.0.0.1','169.254.169.254','::1','::ffff:127.0.0.1','fc00::1','224.0.0.1'])assert.equal(publicAddress(ip),false,ip);assert.equal(publicAddress('8.8.8.8'),true);});
test('M3U emits canonical metadata without playback secrets',()=>{const c=parseM3u('#EXTM3U\n#EXTINF:-1 group-title="News",News\nhttps://example.com/secret/token\n');assert.equal(c.items[0]?.title,'News');assert.equal(JSON.stringify(c).includes('secret'),false);assert.equal(c.schemaVersion,1);});
test('equivalence includes permissions; suspicious update preserves prior version',()=>{const a=parseM3u('#EXTM3U\n#EXTINF:-1,A\nhttps://example.com/a\n');const b=parseM3u('#EXTM3U\n#EXTINF:-1,A\nhttps://example.com/b\n');assert.notEqual(fingerprint(a),fingerprint(b));assert.throws(()=>validateUpdate(100,a),/suspicious-catalog/);assert.equal(parseXtream([{name:'Film',stream_id:1}],'movie')[0]?.kind,'movie');});
test('supports 4 IPTV formats with validation, EPG and PIN protection',()=>{
  // 1. URL format
  assert.equal(sourceInputSchema.safeParse({name:'URL Source',format:'url',url:'https://example.com/list.m3u8'}).success,true);
  // 2. File format
  assert.equal(sourceInputSchema.safeParse({name:'File Source',format:'file',fileContent:'#EXTM3U\n#EXTINF:-1,Ch\nhttps://s.com/1'}).success,true);
  assert.equal(sourceInputSchema.safeParse({name:'File Source',format:'file'}).success,false); // fileContent required on new
  // 3. Xtream format
  assert.equal(sourceInputSchema.safeParse({name:'Xtream',format:'xtream',url:'https://xtream.com',username:'u',password:'p'}).success,true);
  // 4. Other M3U8 format
  assert.equal(sourceInputSchema.safeParse({name:'Other M3U8',format:'other_m3u8',url:'https://example.com/live.m3u8'}).success,true);
  // Optional EPG URL
  assert.equal(sourceInputSchema.safeParse({name:'With EPG',format:'url',url:'https://example.com/list.m3u8',epgUrl:'https://epg.com/guide.xml'}).success,true);
  assert.equal(sourceInputSchema.safeParse({name:'With Bad EPG',format:'url',url:'https://example.com/list.m3u8',epgUrl:'ftp://insecure.com'}).success,false);
  // PIN protection
  assert.equal(sourceInputSchema.safeParse({name:'Protected',format:'url',url:'https://example.com/list.m3u8',isProtected:true,pin:'1234',confirmPin:'1234'}).success,true);
  assert.equal(sourceInputSchema.safeParse({name:'Protected Mismatch',format:'url',url:'https://example.com/list.m3u8',isProtected:true,pin:'1234',confirmPin:'5678'}).success,false);
  assert.equal(sourceInputSchema.safeParse({name:'Protected Missing PIN',format:'url',url:'https://example.com/list.m3u8',isProtected:true}).success,false);
});
test('Other M3U8 single stream manifest emits single channel without error',()=>{
  const hlsManifest = '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-STREAM-INF:BANDWIDTH=1280000\nchunklist.m3u8\n';
  const catalog = parseM3u(hlsManifest, 'https://stream.example.com/master.m3u8', 'My Live Channel');
  assert.equal(catalog.items.length, 1);
  assert.equal(catalog.items[0]?.title, 'My Live Channel');
  assert.equal(catalog.items[0]?.kind, 'channel');
});


test('new public codes are 12 unambiguous uppercase characters', async () => {
  const {generatePublicCode, PUBLIC_CODE} = await import('../src/account_identity');
  for (let i = 0; i < 500; i++) {
    const code = generatePublicCode();
    assert.match(code, PUBLIC_CODE);
    assert.doesNotMatch(code, /[01OIL]/);
  }
});

test('pinned DNS lookup serves real Node requests in both lookup forms', async () => {
  const {pinnedLookup} = await import('../src/catalog');
  const http = await import('node:http');
  const lookup = pinnedLookup({address: '127.0.0.1', family: 4});
  lookup('x', {all: true}, (err: unknown, list: unknown) => assert.deepEqual([err, list], [null, [{address: '127.0.0.1', family: 4}]]));
  lookup('x', {}, (err: unknown, address: unknown, family: unknown) => assert.deepEqual([err, address, family], [null, '127.0.0.1', 4]));
  // Every checked address is offered, IPv4 first (no IPv6 egress on Cloud Run).
  pinnedLookup([{address: '::1', family: 6}, {address: '127.0.0.1', family: 4}])('x', {all: true}, (_e: unknown, list: unknown) =>
    assert.deepEqual(list, [{address: '127.0.0.1', family: 4}, {address: '::1', family: 6}]));
  const server = http.createServer((_q, r) => r.end('#EXTM3U')).listen(0);
  try {
    const port = (server.address() as {port: number}).port;
    const body = await new Promise<string>((resolve, reject) => http.get(`http://pinned.invalid:${port}/list`, {lookup: lookup as never}, res => {
      let text = ''; res.on('data', c => text += c); res.on('end', () => resolve(text));
    }).on('error', reject));
    assert.equal(body, '#EXTM3U');
  } finally { server.close(); }
});
