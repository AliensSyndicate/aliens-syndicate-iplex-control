import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseM3u, fetchProvider} from '../src/catalog';
import {sourceInputSchema} from '../src/domain';
import {parseIptvEpg, xmltvTime} from '../src/iptv_epg';

test('named HLS segments produce one stream, never one channel per segment', () => {
  const body = '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,Segment one\n01.ts\n#EXTINF:6,Segment two\n02.ts';
  assert.equal(parseM3u(body, 'https://example.com/live.m3u8', 'Channel').items.length, 1);
  assert.throws(() => parseM3u(body, '', 'Uploaded HLS'), /hls-origin-required/);
});
test('M3U preserves comma titles, trims lines and resolves relative identity per origin', () => {
  const body = '#EXTM3U\n #EXTINF:-1 group-title="News, world" tvg-id="station",News, world\nstream.ts\n';
  const a = parseM3u(body, 'https://one.example/a/'), b = parseM3u(body, 'https://two.example/a/');
  assert.equal(a.items[0]?.title, 'News, world');
  assert.equal(a.items[0]?.epgId, 'station');
  assert.notEqual(a.items[0]?.id, b.items[0]?.id);
});
test('source update can omit existing secrets; new sources cannot', () => {
  assert.equal(sourceInputSchema.safeParse({id:'s', name:'Renamed', format:'xtream'}).success, true);
  assert.equal(sourceInputSchema.safeParse({name:'New', format:'xtream'}).success, false);
});
test('upload limit measures UTF-8 bytes, not JavaScript characters', () => {
  assert.equal(sourceInputSchema.safeParse({name:'File', format:'file', fileContent:'é'.repeat(11*1024*1024)}).success, false);
});
test('real downloader rejects private IPs and unsafe schemes before connecting', async () => {
  for (const url of ['ftp://example.com', 'https://user:secret@example.com', 'https://127.0.0.1', 'https://[::1]', 'https://169.254.169.254']) await assert.rejects(fetchProvider(url));
});
test('XMLTV normalizes timezone and rejects malformed dates, DTD and reversed programmes', () => {
  const xml='<tv><programme channel="one" start="20261018100000 -0300" stop="20261018110000 -0300"><title>News</title><desc>Today</desc></programme></tv>';
  assert.equal(parseIptvEpg(xml)[0]?.startAt, Date.UTC(2026,9,18,13));
  assert.equal(parseIptvEpg(xml)[0]?.channelId, 'one');
  assert.throws(() => parseIptvEpg('<!DOCTYPE tv [<!ENTITY x "secret">]>'+xml), /invalid-epg/);
  assert.throws(() => xmltvTime('20260230100000 +0000'), /invalid-epg/);
  assert.throws(() => parseIptvEpg(xml.replace('20261018110000', '20261018090000')), /invalid-epg/);
  assert.throws(() => parseIptvEpg('<html>not a guide</html>'), /invalid-epg/);
});
