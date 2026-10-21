/**
 * Real HTTP against a controlled local provider (no fetch mocks): download,
 * redirects, gzip, charset, client filtering, failures and the tolerant parsers.
 */
import {test, before, after} from 'node:test';
import assert from 'node:assert/strict';
import {createProviderFetch, decodeProviderBody, parseM3uDetailed, parseXtream, privateProvidersAllowedForTests, PROVIDER_LIMITS} from '../src/catalog';
import {fetchSnapshot} from '../src/iptv_ingestion';
import {parseXtreamJson, xtreamCatalogFromM3uPlus, xtreamFallbackAllowed} from '../src/iptv_adapters';
import {hash} from '../src/domain';
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

test('Xtream fallback to M3U Plus only when the API itself fails, never on credentials', () => {
  for (const error of [new DomainError('provider-unavailable', {reason: 'http-status', statusCode: 500}), new DomainError('provider-unavailable', {reason: 'xtream-auth-unexpected-response'}),
    new DomainError('parsing-failed'), new DomainError('download-failed'), new DomainError('provider-time-budget', {reason: 'idle-timeout'}), new SyntaxError('x')]) {
    assert.equal(xtreamFallbackAllowed(error), true, String((error as any).code ?? error.name));
  }
  for (const error of [new DomainError('invalid-credentials'), new DomainError('invalid-credentials', {statusCode: 403}), new DomainError('provider-rate-limited'),
    new DomainError('unsafe-provider'), new DomainError('catalog-too-large'), new DomainError('provider-unavailable', {reason: 'host-not-found'}),
    new DomainError('provider-unavailable', {reason: 'connection-failed'}), new DomainError('provider-unavailable', {reason: 'tls-certificate'}),
    new DomainError('provider-time-budget', {reason: 'sync-budget'}), new Error('x')]) {
    assert.equal(xtreamFallbackAllowed(error), false, `${(error as any).code} ${JSON.stringify((error as any).details)}`);
  }
});

test('M3U Plus fallback catalog keeps the API identifiers for channels and movies; URLs only in the sealed map', async () => {
  const body = await fetch(`${provider.base}/get.php?username=assinante&password=senha-1&type=m3u_plus&output=ts`);
  const {catalog, stats, streams} = xtreamCatalogFromM3uPlus(body, `${provider.base}/`);
  const channel = catalog.items.find(i => i.title === 'Canal Notícias')!, movie = catalog.items.find(i => i.title === 'Missão Fictícia (2021)')!;
  assert.deepEqual([channel.id, channel.providerRef], [hash('channel:101'), '101']);
  assert.deepEqual([movie.id, movie.providerRef, movie.containerExtension], [hash('movie:201'), '201', 'mkv']);
  assert.equal(streams['101'], `${provider.base}/live/assinante/senha-1/101.ts`);
  const series = catalog.items.find(i => i.kind === 'series')!;
  const episode = (catalog.seriesDetails![series.providerRef] as any).episodes['1'][0];
  assert.equal(streams[episode.id], `${provider.base}/series/assinante/senha-1/301.mkv`);
  assert.equal(stats.xtreamM3uPlus, 1);
  assert.equal(JSON.stringify(catalog).includes('senha-1'), false, 'no credential in the catalog');
});

test('Xtream snapshot: HTML or 5xx API falls back to get.php; wrong credentials and a dead export do not', async () => {
  const source = {name: 'Xtream', format: 'xtream' as const, url: provider.base, username: 'assinante', password: 'senha-1'};
  const build = async () => { const s = await fetchSnapshot({...source}, 'fam', 'src', fetch); return {catalog: await s.build(), snapshot: s}; };
  try {
    provider.mode.auth = 'html';
    let r = await build();
    assert.equal(r.snapshot.stats?.xtreamM3uPlus, 1);
    assert.deepEqual(['channel', 'movie', 'series'].map(k => r.catalog.items.filter(i => i.kind === k).length), [2, 2, 1]);
    assert.ok(r.snapshot.streamIndex, 'playback index for the fallback catalog');
    provider.mode.auth = 'ok'; provider.mode.apiStatus = 503;
    r = await build();
    assert.equal(r.snapshot.stats?.xtreamM3uPlus, 1);
    // Both fail: the API error is reported, not the export's 404.
    provider.mode.m3uPlus = false;
    await assert.rejects(build(), (e: any) => e.code === 'provider-unavailable' && e.details.statusCode === 503);
    provider.mode.apiStatus = 0; provider.mode.m3uPlus = true;
    // Wrong credentials never reach get.php.
    provider.mode.auth = 'zero';
    const hits = provider.hits['/get.php'] ?? 0;
    await assert.rejects(build(), code('invalid-credentials'));
    assert.equal(provider.hits['/get.php'] ?? 0, hits);
    // API healthy: no fallback, no index.
    provider.mode.auth = 'ok';
    r = await build();
    assert.equal(r.snapshot.stats?.xtreamM3uPlus, undefined);
    assert.equal(r.snapshot.streamIndex, undefined);
  } finally {
    Object.assign(provider.mode, {auth: 'ok', apiStatus: 0, m3uPlus: true});
  }
});

test('regression: host names resolve through the pinned lookup (Node happy eyeballs asks for all addresses)', async () => {
  // The deployed 18/10 build answered {all: true} with a single address and every
  // URL source failed with ERR_INVALID_IP_ADDRESS before any byte was read.
  const byName = provider.base.replace('127.0.0.1', 'localhost');
  assert.match(await fetch(`${byName}/get.php?username=assinante&password=senha-1`), /^#EXTM3U/);
});

test('source artwork and "added" date: https only, no credentials, nothing guessed', async () => {
  const {safeImageUrl, providerAddedAt} = await import('../src/catalog');
  assert.equal(safeImageUrl('https://img.example.com/a.png'), 'https://img.example.com/a.png');
  for (const bad of ['http://img.example.com/a.png', 'https://u:p@img.example.com/a.png', 'https://img.example.com/a.png?token=x', 'https://img.example.com/a.png?password=x', 'javascript:alert(1)', 42, '']) {
    assert.equal(safeImageUrl(bad), undefined, String(bad));
  }
  assert.equal(providerAddedAt('1700000000'), 1700000000000);
  for (const bad of ['abc', '0', '123', String(Math.floor(Date.now() / 1000) + 10 * 86400), undefined]) assert.equal(providerAddedAt(bad), undefined, String(bad));
  const rows = [{stream_id: 1, name: 'A', added: '1700000000', stream_icon: 'https://x.example/a.jpg'}, {stream_id: 2, name: 'B', stream_icon: 'https://x.example/b.jpg?token=t'}];
  const [a, b] = parseXtream(rows, 'movie');
  assert.deepEqual([a!.addedAt, a!.imageRef], [1700000000000, 'https://x.example/a.jpg']);
  assert.deepEqual([b!.addedAt, b!.imageRef], [undefined, undefined]);
  const m3u = parseM3uDetailed('#EXTM3U\n#EXTINF:-1 tvg-logo="https://x.example/l.png",Canal\nhttps://s.example/c.m3u8\n#EXTINF:-1 tvg-logo="http://x.example/l.png",Outro\nhttps://s.example/o.m3u8\n').catalog;
  assert.deepEqual(m3u.items.map(i => i.imageRef), ['https://x.example/l.png', undefined]);
});
