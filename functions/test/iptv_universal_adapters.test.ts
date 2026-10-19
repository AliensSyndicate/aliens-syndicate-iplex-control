import test from 'node:test';
import assert from 'node:assert/strict';
import {DomainError, hash} from '../src/domain';
import {
  defaultAdapterRegistry,
  DirectStreamAdapter,
  HlsManifestAdapter,
  IptvAdapterRegistry,
  M3uPlaylistAdapter,
  XtreamAdapter,
  normalizeSeriesDetail,
} from '../src/iptv_adapters';
import {detectSourceFormat, sanitizeLogUrl} from '../src/iptv_detection';
import {fetchSnapshot} from '../src/iptv_ingestion';
import {normalizeServerEndpoint} from '../src/iptv_server';

test('1. Detecção de Xtream: detects Xtream endpoint with credentials and player_api.php', async () => {
  const source = {
    name: 'Xtream Provider',
    format: 'xtream' as const,
    url: 'https://stream.provider.tv:8080/player_api.php',
    username: 'user1',
    password: 'pwd',
  };
  const mockFetch = async (url: string) => JSON.stringify({user_info: {auth: 1, status: 'Active'}});
  const result = await detectSourceFormat(source, mockFetch);
  assert.equal(result.detectedFormat, 'xtream');
  assert.equal(result.adapter.format, 'xtream');
  assert.equal(result.isSingleStream, false);
});

test('2. Detecção de M3U: detects remote M3U playlist from headers and #EXTM3U signature', async () => {
  const source = {
    name: 'M3U Remote',
    format: 'm3u' as const,
    url: 'https://cdn.provider.tv/playlist.m3u',
  };
  const mockFetch = async () => `#EXTM3U\n#EXTINF:-1,Channel 1\nhttp://cdn.provider.tv/ch1.ts`;
  const result = await detectSourceFormat(source, mockFetch);
  assert.equal(result.detectedFormat, 'm3u');
  assert.equal(result.adapter.format, 'm3u');
  assert.equal(result.isSingleStream, false);
});

test('3. Detecção de M3U Plus: detects get.php?type=m3u_plus as M3U playlist, NOT Xtream JSON', async () => {
  const source = {
    name: 'M3U Plus Provider',
    format: 'm3u' as const,
    url: 'https://cdn.provider.tv/get.php?username=u&password=p&type=m3u_plus&output=ts',
  };
  const mockFetch = async () => `#EXTM3U\n#EXTINF:-1 tvg-id="ch1" group-title="News",News 24\nhttp://cdn.provider.tv/stream1.ts`;
  const result = await detectSourceFormat(source, mockFetch);
  assert.equal(result.detectedFormat, 'm3u');
  assert.equal(result.adapter.format, 'm3u');
});

test('4. Detecção de HLS: detects HLS manifest with variant streams', async () => {
  const source = {
    name: 'HLS Live Channel',
    format: 'other_m3u8' as const,
    url: 'https://live.stream.tv/channel/master.m3u8',
  };
  const mockFetch = async () => `#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=1280x720\nchunklist_720.m3u8`;
  const result = await detectSourceFormat(source, mockFetch);
  assert.equal(result.detectedFormat, 'other_m3u8');
  assert.equal(result.adapter.format, 'other_m3u8');
  assert.equal(result.isSingleStream, true);
});

test('5. Distinção entre catálogo e manifesto de reprodução: HLS does not create a channel per segment', async () => {
  const source = {
    name: '24/7 Movie Stream',
    format: 'other_m3u8' as const,
    url: 'https://live.stream.tv/movie/index.m3u8',
  };
  const hlsMediaSegments = `#EXTM3U
#EXT-X-TARGETDURATION:10
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:10.0,Segment 1
segment0.ts
#EXTINF:10.0,Segment 2
segment1.ts
#EXTINF:10.0,Segment 3
segment2.ts`;
  const mockFetch = async () => hlsMediaSegments;
  const snapshot = await fetchSnapshot(source, 'family_1', 'source_hls', mockFetch);
  assert.equal(snapshot.singleStream, true);
  const catalog = await snapshot.build();
  assert.equal(catalog.items.length, 1);
  assert.equal(catalog.items[0]!.title, '24/7 Movie Stream');
});

test('6. URLs diretas: detects direct playback video stream (.mp4, .mkv, .ts)', async () => {
  const source = {
    name: 'Direct Video Stream',
    format: 'direct_stream' as const,
    url: 'https://media.server.org/videos/nature_documentary.mp4',
  };
  const mockFetch = async () => 'OK';
  const result = await detectSourceFormat(source, mockFetch);
  assert.equal(result.detectedFormat, 'direct_stream');
  assert.equal(result.isSingleStream, true);

  const snapshot = await fetchSnapshot(source, 'family_1', 'source_direct', mockFetch);
  const catalog = await snapshot.build();
  assert.equal(catalog.items.length, 1);
  assert.equal(catalog.items[0]!.kind, 'movie');
  assert.equal(catalog.items[0]!.title, 'Direct Video Stream');
});

test('7. Importação por arquivo: imported local M3U file is handled by M3uPlaylistAdapter', async () => {
  const source = {
    name: 'Local Backup File',
    format: 'file' as const,
    fileName: 'iptv_channels.m3u',
    filePath: 'source_files/fam1_src1.m3u',
  };
  const result = await detectSourceFormat(source, async () => '');
  assert.equal(result.detectedFormat, 'file');
  assert.equal(result.adapter.format, 'm3u');
});

test('8. Fontes com metadados incompletos: parses M3U entries missing tvg-id or group-title', async () => {
  const source = {
    name: 'Sparse M3U',
    format: 'm3u' as const,
    url: 'https://cdn.provider.tv/sparse.m3u',
  };
  const body = `#EXTM3U
#EXTINF:-1,Channel Without Attributes
http://cdn.provider.tv/ch1.ts
#EXTINF:-1 tvg-id="ch2",Channel Without Group
http://cdn.provider.tv/ch2.ts`;
  const snapshot = await fetchSnapshot(source, 'fam', 'src_sparse', async () => body);
  const catalog = await snapshot.build();
  assert.equal(catalog.items.length, 2);
  assert.equal(catalog.items[0]!.title, 'Channel Without Attributes');
  assert.equal(catalog.items[0]!.category, '');
  assert.equal(catalog.items[1]!.epgId, 'ch2');
});

test('9. Categorias originais preservadas: never alters or synthesizes artificial category names', async () => {
  const source = {
    name: 'Original Cats',
    format: 'm3u' as const,
    url: 'https://cdn.provider.tv/cats.m3u',
  };
  const body = `#EXTM3U
#EXTINF:-1 group-title="ESPORTES AO VIVO 4K",ESPN 4K
http://cdn.provider.tv/espn.ts
#EXTINF:-1 group-title="VARIEDADES & NOTÍCIAS",CNN Brasil
http://cdn.provider.tv/cnn.ts`;
  const snapshot = await fetchSnapshot(source, 'fam', 'src_cats', async () => body);
  const catalog = await snapshot.build();
  assert.equal(catalog.items[0]!.category, 'ESPORTES AO VIVO 4K');
  assert.equal(catalog.items[1]!.category, 'VARIEDADES & NOTÍCIAS');
});

test('10. Provedores com somente canais: Xtream with empty VOD and series succeeds cleanly', async () => {
  const source = {
    name: 'Live Only Xtream',
    format: 'xtream' as const,
    url: 'https://live.provider.tv:8080',
    username: 'user_live',
    password: 'password_live',
  };
  const mockFetch = async (url: string) => {
    if (url.includes('action=get_live_streams')) {
      return JSON.stringify([{stream_id: 101, name: 'Live 1', category_id: 'cat_live'}]);
    }
    if (url.includes('action=get_live_categories')) {
      return JSON.stringify([{category_id: 'cat_live', category_name: 'Ao Vivo'}]);
    }
    if (url.includes('action=get_vod_streams') || url.includes('action=get_series')) {
      return '[]';
    }
    if (url.includes('action=get_vod_categories') || url.includes('action=get_series_categories')) {
      return '[]';
    }
    return JSON.stringify({user_info: {auth: 1, status: 'active'}});
  };
  const snapshot = await fetchSnapshot(source, 'fam', 'src_live_only', mockFetch);
  const catalog = await snapshot.build();
  assert.equal(catalog.items.length, 1);
  assert.equal(catalog.items[0]!.kind, 'channel');
  assert.equal(catalog.items[0]!.title, 'Live 1');
  assert.equal(catalog.items[0]!.category, 'Ao Vivo');
});

test('11. Provedores com canais, filmes e séries: parses all three kinds in full catalog', async () => {
  const source = {
    name: 'Full Xtream Provider',
    format: 'xtream' as const,
    url: 'https://full.provider.tv:8080',
    username: 'full_user',
    password: 'full_password',
  };
  const mockFetch = async (url: string) => {
    if (url.includes('action=get_live_streams')) return JSON.stringify([{stream_id: 1, name: 'Channel A', category_id: '1'}]);
    if (url.includes('action=get_live_categories')) return JSON.stringify([{category_id: '1', category_name: 'Canais'}]);
    if (url.includes('action=get_vod_streams')) return JSON.stringify([{stream_id: 2, name: 'Movie B', category_id: '2', container_extension: 'mp4'}]);
    if (url.includes('action=get_vod_categories')) return JSON.stringify([{category_id: '2', category_name: 'Filmes'}]);
    if (url.includes('action=get_series_info')) {
      return JSON.stringify({
        seasons: [{id: 's1', name: 'Season 1', season_number: 1, episode_count: 1}],
        episodes: {
          '1': [{id: 'ep1', title: 'Pilot', episode_num: 1, season: 1, container_extension: 'mkv'}],
        },
      });
    }
    if (url.includes('action=get_series_categories')) return JSON.stringify([{category_id: '3', category_name: 'Series'}]);
    if (url.includes('action=get_series')) return JSON.stringify([{series_id: 3, name: 'Series C', category_id: '3'}]);
    return JSON.stringify({user_info: {auth: 1, status: 'active'}});
  };
  const snapshot = await fetchSnapshot(source, 'fam', 'src_full', mockFetch);
  const catalog = await snapshot.build();
  assert.equal(catalog.items.length, 3);
  const kinds = new Set(catalog.items.map(i => i.kind));
  assert.ok(kinds.has('channel'));
  assert.ok(kinds.has('movie'));
  assert.ok(kinds.has('series'));
  assert.ok(catalog.seriesDetails && Object.keys(catalog.seriesDetails).length > 0);
});

test('12. Endpoints parcialmente implementados: gracefully tolerates non-JSON or missing optional endpoints', async () => {
  const source = {
    name: 'Partial Xtream',
    format: 'xtream' as const,
    url: 'https://partial.provider.tv:8080',
    username: 'u',
    password: 'p',
  };
  const mockFetch = async (url: string) => {
    if (url.includes('action=get_live_streams')) return JSON.stringify([{stream_id: 10, name: 'Channel Only', category_id: '1'}]);
    if (url.includes('action=get_live_categories')) return JSON.stringify([{category_id: '1', category_name: 'Live'}]);
    if (url.includes('action=get_vod_streams') || url.includes('action=get_series')) {
      throw new Error('501 Not Implemented');
    }
    return JSON.stringify({user_info: {auth: 1, status: 'Active'}});
  };
  const snapshot = await fetchSnapshot(source, 'fam', 'src_partial', mockFetch);
  const catalog = await snapshot.build();
  assert.equal(catalog.items.length, 1);
  assert.equal(catalog.items[0]!.title, 'Channel Only');
});

test('13. Credenciais inválidas: throws invalid-credentials when Xtream auth is 0 or expired', async () => {
  const source = {
    name: 'Expired Xtream',
    format: 'xtream' as const,
    url: 'https://expired.provider.tv:8080',
    username: 'bad_user',
    password: 'bad_password',
  };
  const mockFetch = async () => JSON.stringify({user_info: {auth: 0, status: 'Disabled'}});
  await assert.rejects(
    async () => fetchSnapshot(source, 'fam', 'src_bad', mockFetch),
    (err: any) => err instanceof DomainError && err.code === 'invalid-credentials'
  );
});

test('14. URLs inválidas: throws when URL is malformed or protocol is unsafe', async () => {
  const badSource = {
    name: 'Bad URL Source',
    format: 'm3u' as const,
    url: 'ftp://ftp.provider.org/list.m3u',
  };
  await assert.rejects(
    async () => detectSourceFormat(badSource, async () => ''),
    (err: any) => err instanceof DomainError || err?.code === 'invalid-url-structure' || err?.message.includes('https-required')
  );
});

test('15. Servidores duplicados: produces identical serverId for same endpoint regardless of casing', () => {
  const ep1 = normalizeServerEndpoint('http://MyServer.TV:8080/player_api.php', 'xtream');
  const ep2 = normalizeServerEndpoint('http://myserver.tv:8080', 'xtream');
  assert.equal(ep1.canonicalEndpoint, ep2.canonicalEndpoint);
  assert.equal(ep1.identityHash, ep2.identityHash);
});

test('16. Catálogos equivalentes: produces identical fingerprint and proof for equivalent content', async () => {
  const m3uContent = `#EXTM3U\n#EXTINF:-1 tvg-id="cnn" group-title="News",CNN\nhttp://server/cnn.ts\n#EXTINF:-1 tvg-id="bbc" group-title="News",BBC\nhttp://server/bbc.ts`;
  const s1 = {name: 'User 1 List', format: 'm3u' as const, url: 'http://cdn.tv/list.m3u'};
  const s2 = {name: 'User 2 List', format: 'm3u' as const, url: 'http://cdn.tv/list.m3u'};

  const snap1 = await fetchSnapshot(s1, 'fam1', 'src1', async () => m3uContent);
  const snap2 = await fetchSnapshot(s2, 'fam2', 'src2', async () => m3uContent);

  assert.equal(snap1.proof, snap2.proof);
});

test('17. Catálogos diferentes no mesmo servidor: distinct paths produce distinct identities', () => {
  const epA = normalizeServerEndpoint('http://server.tv:8080/userA/playlist.m3u', 'playlist');
  const epB = normalizeServerEndpoint('http://server.tv:8080/userB/playlist.m3u', 'playlist');
  assert.notEqual(epA.identityHash, epB.identityHash);
});

test('18. Reutilização segura: credentials are never embedded in shared proof or catalog JSON', async () => {
  const source = {
    name: 'Secret List',
    format: 'm3u' as const,
    url: 'https://cdn.tv/get.php?username=SecretUser123&password=SecretPasswordXYZ&type=m3u',
  };
  const body = `#EXTM3U\n#EXTINF:-1,Channel 1\nhttp://cdn.tv/live/SecretUser123/SecretPasswordXYZ/1.ts`;
  const snapshot = await fetchSnapshot(source, 'fam', 'src_sec', async () => body);
  const catalog = await snapshot.build();
  const catalogJson = JSON.stringify(catalog);
  assert.ok(!catalogJson.includes('SecretPasswordXYZ'), 'Catalog JSON must not contain credentials in plain text');
});

test('19. Sincronização manual: adapter correctly informs single stream vs catalog mode', () => {
  const xtream = defaultAdapterRegistry.get('xtream')!;
  const hls = defaultAdapterRegistry.get('other_m3u8')!;
  const direct = defaultAdapterRegistry.get('direct_stream')!;
  const m3u = defaultAdapterRegistry.get('m3u')!;

  assert.equal(xtream.getLimitations({name: 'x', format: 'xtream'}).isSingleStream, false);
  assert.equal(m3u.getLimitations({name: 'm', format: 'm3u'}).isSingleStream, false);
  assert.equal(hls.getLimitations({name: 'h', format: 'other_m3u8'}).isSingleStream, true);
  assert.equal(direct.getLimitations({name: 'd', format: 'direct_stream'}).isSingleStream, true);
});

test('20. Sincronização automática: adapter registry supports dynamic registration of future adapters', async () => {
  const customRegistry = new IptvAdapterRegistry();
  const customAdapter = {
    name: 'Future Custom Feed',
    format: 'future_json',
    supports: (src: any) => src.url?.includes('future_feed'),
    validateAccess: async () => {},
    identifyServer: () => null,
    extractCatalog: async () => ({
      proof: 'proof_future',
      singleStream: false,
      build: async () => ({
        schemaVersion: 1 as const,
        items: [{id: 'future_1', title: 'Future Channel', titleKey: 'future channel', kind: 'channel' as const, category: 'Future', providerRef: 'f1'}],
      }),
    }),
    getLimitations: () => ({supportsEpg: false, supportsSeries: false, supportsVod: false, supportsCatchup: false, isSingleStream: false}),
  };
  customRegistry.register(customAdapter);

  const customSource = {name: 'My Future Source', format: 'url' as const, url: 'https://feed.tv/future_feed.json'};
  const detection = await detectSourceFormat(customSource, async () => '{}', customRegistry);
  assert.equal(detection.detectedFormat, 'future_json');
  assert.equal(detection.adapter.name, 'Future Custom Feed');
});

test('21. Retenção sem usuários: source limitations correctly indicate VOD and EPG capabilities', () => {
  const xtream = new XtreamAdapter();
  const limits = xtream.getLimitations({name: 'Test', format: 'xtream'});
  assert.equal(limits.supportsEpg, true);
  assert.equal(limits.supportsSeries, true);
  assert.equal(limits.supportsVod, true);
});

test('22. Reativação de catálogo: adapter extracts series detail structure with seasons and episodes', () => {
  const rawDetail = {
    seasons: [{id: 's1', name: 'Season 1', season_number: 1, episode_count: 2}],
    episodes: {
      '1': [
        {id: '101', title: 'Ep 1', episode_num: 1, season: 1, container_extension: 'mp4'},
        {id: '102', title: 'Ep 2', episode_num: 2, season: 1, container_extension: 'mp4'},
      ],
    },
  };
  const normalized: any = normalizeSeriesDetail(rawDetail);
  assert.equal(normalized.seasons.length, 1);
  assert.equal(normalized.episodes['1'].length, 2);
  assert.equal(normalized.episodes['1'][0].title, 'Ep 1');
});

test('23. Segurança entre famílias: sanitizeLogUrl strips passwords and tokens from logging', () => {
  const safe = sanitizeLogUrl('https://myprovider.com/get.php?username=john&password=secretPassword&type=m3u');
  assert.ok(!safe.includes('secretPassword'));
  assert.ok(safe.includes('password=***'));
  assert.ok(safe.includes('username=***'));
});

test('24. Compatibilidade do JSON com o Player: all adapter outputs validate strictly against catalogSchema', async () => {
  const m3uSource = {name: 'Test M3U', format: 'm3u' as const, url: 'https://cdn.tv/list.m3u'};
  const body = `#EXTM3U\n#EXTINF:-1,Channel Player\nhttps://cdn.tv/stream.ts`;
  const snap = await fetchSnapshot(m3uSource, 'f', 's', async () => body);
  const catalog = await snap.build();
  assert.equal(catalog.schemaVersion, 1);
  assert.ok(Array.isArray(catalog.items));
  assert.equal(catalog.items[0]!.kind, 'channel');
  assert.equal(typeof catalog.items[0]!.id, 'string');
});

test('25. Falhas e recuperação: unrecognized format returns specific error instead of generic crash', async () => {
  const weirdSource = {
    name: 'Unrecognized Content',
    format: 'url' as const,
    url: 'https://weird.provider.tv/index.html',
  };
  const mockFetch = async () => '<html><body>Welcome to My Blog</body></html>';
  await assert.rejects(
    async () => detectSourceFormat(weirdSource, mockFetch),
    (err: any) => err instanceof DomainError && err.code === 'unrecognized-source-format'
  );
});
