/**
 * Real HTTP against a controlled local provider (no fetch mocks): download,
 * redirects, gzip, charset, client filtering, failures and the tolerant parsers.
 */
import {test, before, after} from 'node:test';
import assert from 'node:assert/strict';
import {createProviderFetch, decodeProviderBody, parseM3uDetailed, parseXtream, privateProvidersAllowedForTests, PROVIDER_LIMITS} from '../src/catalog';
import {fetchSnapshot} from '../src/iptv_ingestion';
import {parseXtreamJson} from '../src/iptv_adapters';
import {DomainError} from '../src/domain';
import {startFakeProvider, type FakeProvider} from './support/fake_iptv_server';

let provider: FakeProvider;
const fetch = createProviderFetch({allowPrivateAddress: true});
before(async () => { provider = await startFakeProvider(); });
after(async () => provider.close());
const code = (expected: string) => (error: unknown) => error instanceof DomainError && error.code === expected;

test('M3U Plus over gzip: one tolerant pass separates channels, movies and series with episodes', async () => {
  const body = await fetch(`${provider.base}/get.php?username=assinante&password=senha-1&type=m3u_plus&output=ts`);
  const {catalog, stats} = parseM3uDetailed(body, `${provider.base}/get.php`);
  const by = (kind: string) => catalog.items.filter(i => i.kind === kind).map(i => i.title).sort();
  assert.deepEqual(by('channel'), ['Canal Notícias', 'Canal Sem Título']);
  assert.deepEqual(by('movie'), ['Aventura no Parque (2019)', 'Missão Fictícia (2021)']);
  assert.deepEqual(by('series'), ['Série Exemplo']);
  assert.deepEqual(stats, {entries: 10, skipped: 2, duplicates: 1, episodes: 3});
  const series = catalog.items.find(i => i.kind === 'series')!;
  const details = catalog.seriesDetails![series.providerRef] as any;
  assert.deepEqual(details.seasons.map((s: any) => [s.seasonNumber, s.episodeCount]), [[1, 2], [2, 1]]);
  assert.deepEqual(details.episodes['1'].map((e: any) => [e.episodeNum, e.title]), [[1, 'Começo'], [2, 'Meio']]);
  assert.equal(catalog.items.find(i => i.title === 'Missão Fictícia (2021)')!.ageRating, '16');
  assert.equal(JSON.stringify(catalog).includes('senha-1'), false, 'no credential-bearing URL in the catalog');
});

test('identifiers are stable across syncs and independent of item order', async () => {
  const body = await fetch(`${provider.base}/get.php?username=assinante&password=senha-1&type=m3u_plus`);
  const a = parseM3uDetailed(body).catalog.items.map(i => i.id).sort();
  const reversed = body.split('\r\n#EXTINF').reverse().join('\r\n#EXTINF');
  const b = parseM3uDetailed(`#EXTM3U\r\n#EXTINF${reversed.replace(/^#EXTM3U[^\r\n]*\r\n/, '')}`).catalog.items.map(i => i.id).sort();
  assert.deepEqual(a, b);
});

test('redirects, Windows-1252 lists and panels that only answer player clients', async () => {
  assert.match(await fetch(`${provider.base}/redirect.m3u?username=assinante&password=senha-1`), /^#EXTM3U/);
  provider.mode.latin1 = true;
  const latin = await fetch(`${provider.base}/get.php?username=assinante&password=senha-1`);
  provider.mode.latin1 = false;
  assert.ok(latin.includes('Canal Notícias'), 'Windows-1252 decoded, not mojibake');
  assert.equal(decodeProviderBody(Buffer.from('Ação', 'latin1')), 'Ação');
  assert.match(await fetch(`${provider.base}/player-only.m3u`), /^#EXTM3U/);
  assert.ok(provider.hits['/player-only.m3u']! >= 2, 'retried with the next User-Agent');
});

test('failures are classified, never generic', async () => {
  await assert.rejects(fetch(`${provider.base}/get.php?username=assinante&password=errada`), code('invalid-credentials'));
  await assert.rejects(fetch(`${provider.base}/error500.m3u`), (e: any) => e.code === 'provider-unavailable' && e.details.statusCode === 500);
  await assert.rejects(fetch(`${provider.base}/nao-existe.m3u`), (e: any) => e.code === 'provider-unavailable' && e.details.statusCode === 404);
  await assert.rejects(fetch('http://127.0.0.1:9/fechado.m3u'), (e: any) => e.code === 'provider-unavailable' && e.details.reason === 'connection-failed');
  await assert.rejects(fetch('http://host-inexistente.invalid/x.m3u'), (e: any) => e.code === 'provider-unavailable' && e.details.reason === 'host-not-found');
  await assert.rejects(createProviderFetch({allowPrivateAddress: true, limits: {idleMs: 300}})(`${provider.base}/slow.m3u`), (e: any) => e.code === 'provider-time-budget');
  provider.mode.flaky = 1;
  await assert.rejects(fetch(`${provider.base}/flaky.m3u`), code('download-failed'));
  await assert.rejects(createProviderFetch({allowPrivateAddress: true, limits: {maxBytes: 1000}})(`${provider.base}/big.m3u?n=100`), code('catalog-too-large'));
  await assert.rejects(createProviderFetch()(`${provider.base}/get.php`), code('unsafe-provider'), 'production fetch never reaches private addresses');
  await assert.rejects(fetch('ftp://example.invalid/list.m3u'), code('unsafe-provider'));
  await assert.rejects(fetch('http://user:pass@example.invalid/list.m3u'), code('unsafe-provider'));
});

test('private providers only with emulator, demo project and explicit flag', () => {
  assert.equal(privateProvidersAllowedForTests({IPLEX_TEST_PRIVATE_PROVIDERS: '1', FIRESTORE_EMULATOR_HOST: 'x', GCLOUD_PROJECT: 'demo-iplex'}), true);
  assert.equal(privateProvidersAllowedForTests({IPLEX_TEST_PRIVATE_PROVIDERS: '1', FIRESTORE_EMULATOR_HOST: 'x', GCLOUD_PROJECT: 'iplex-2c8fc'}), false);
  assert.equal(privateProvidersAllowedForTests({IPLEX_TEST_PRIVATE_PROVIDERS: '1', GCLOUD_PROJECT: 'demo-iplex'}), false);
  assert.equal(privateProvidersAllowedForTests({FIRESTORE_EMULATOR_HOST: 'x', GCLOUD_PROJECT: 'demo-iplex'}), false);
});

test('one download per URL and sync: detection, validation and extraction share it', async () => {
  const url = `${provider.base}/big.m3u?n=200`;
  const before = provider.hits['/big.m3u'] ?? 0;
  const snapshot = await fetchSnapshot({name: 'Lista', format: 'url', url}, 'fam', 'src', fetch);
  const catalog = await snapshot.build();
  assert.equal(catalog.items.length, 200);
  assert.equal((provider.hits['/big.m3u'] ?? 0) - before, 1);
});

test('large list: 60 000 entries parsed within the item cap; above the cap the error is explicit', async () => {
  const started = Date.now();
  const body = await fetch(`${provider.base}/big.m3u?n=60000`);
  const {catalog} = parseM3uDetailed(body);
  assert.equal(catalog.items.length, 60000);
  assert.ok(Date.now() - started < 20000, `took ${Date.now() - started} ms`);
  const tooMany = ['#EXTM3U', ...Array.from({length: PROVIDER_LIMITS.maxItems + 1}, (_, i) => `#EXTINF:-1,C${i}\nhttp://example.invalid/${i}.ts`)].join('\n');
  assert.throws(() => parseM3uDetailed(tooMany), code('catalog-too-large'));
});

test('Xtream rows: malformed or repeated rows are skipped; long titles are cut, not fatal', () => {
  const counters = {skipped: 0};
  const items = parseXtream([{stream_id: 1, name: 'A'}, {stream_id: 1, name: 'A (repetido)'}, {name: 'sem id'}, {stream_id: 2, name: 'y'.repeat(500)}, null, {stream_id: 3}], 'channel', [], counters);
  assert.deepEqual(items.map(i => i.providerRef), ['1', '2', '3']);
  assert.equal(items[1]!.title.length, 300);
  assert.equal(items[2]!.title, '#3');
  assert.equal(counters.skipped, 3);
  assert.deepEqual(parseXtream({}, 'movie'), []);
});

test('Xtream wrong credentials in their usual shapes', () => {
  assert.throws(() => parseXtreamJson('', 'auth'), code('invalid-credentials'));
  assert.throws(() => parseXtreamJson('[]', 'auth'), code('invalid-credentials'));
  assert.throws(() => parseXtreamJson('<html>painel</html>', 'auth'), code('provider-unavailable'));
  assert.deepEqual(parseXtreamJson('﻿{"user_info":{"auth":1}}', 'auth'), {user_info: {auth: 1}});
});
