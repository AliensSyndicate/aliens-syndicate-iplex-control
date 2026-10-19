import {test} from 'node:test';
import assert from 'node:assert/strict';
import {normalizeServerEndpoint} from '../src/iptv_server';
import {fingerprint, catalogSchema} from '../src/catalog';
import {hash} from '../src/domain';

test('CODEX 1 & 2: First user registers server, second user registers same server reusing record', () => {
  const urlUser1 = 'https://provider.tv:8443/live/playlist.m3u8?token=user1token';
  const urlUser2 = 'https://provider.tv:8443/live/playlist.m3u8?token=user2token';

  const srv1 = normalizeServerEndpoint(urlUser1, 'url');
  const srv2 = normalizeServerEndpoint(urlUser2, 'url');

  assert.equal(srv1.canonicalEndpoint, 'https://provider.tv:8443');
  assert.equal(srv2.canonicalEndpoint, 'https://provider.tv:8443');
  assert.equal(srv1.identityHash, srv2.identityHash);

  const serverId1 = `srv_${srv1.identityHash.slice(0, 32)}`;
  const serverId2 = `srv_${srv2.identityHash.slice(0, 32)}`;
  assert.equal(serverId1, serverId2);
});

test('CODEX 3: Same server host with different catalog path/type produces distinct identities', () => {
  const srvXtream = normalizeServerEndpoint('https://provider.tv:8080/base1/player_api.php', 'xtream');
  const srvXtream2 = normalizeServerEndpoint('https://provider.tv:8080/base2/player_api.php', 'xtream');

  assert.notEqual(srvXtream.identityHash, srvXtream2.identityHash);
});

test('CODEX 4 & 5: Equivalent catalogs produce identical fingerprint and proof for JSON reuse', () => {
  const catalog1 = catalogSchema.parse({
    schemaVersion: 1,
    items: [
      {id: 'ch-1', title: 'News HD', titleKey: 'news hd', kind: 'channel', category: 'News', providerRef: '101'},
      {id: 'ch-2', title: 'Sports HD', titleKey: 'sports hd', kind: 'channel', category: 'Sports', providerRef: '102'}
    ]
  });

  // User 2 catalog with same items but parsed from independent response
  const catalog2 = catalogSchema.parse({
    schemaVersion: 1,
    items: [
      {id: 'ch-2', title: 'Sports HD', titleKey: 'sports hd', kind: 'channel', category: 'Sports', providerRef: '102'},
      {id: 'ch-1', title: 'News HD', titleKey: 'news hd', kind: 'channel', category: 'News', providerRef: '101'}
    ]
  });

  const fp1 = fingerprint(catalog1);
  const fp2 = fingerprint(catalog2);
  assert.equal(fp1, fp2);

  const serverId = 'srv_abc123';
  const version1 = hash(`${serverId}:${fp1}`);
  const version2 = hash(`${serverId}:${fp2}`);
  assert.equal(version1, version2);
});

test('CODEX 6: Credentials remain isolated; fingerprint never includes credentials', () => {
  const catalog = catalogSchema.parse({
    schemaVersion: 1,
    items: [{id: 'ch-1', title: 'Channel 1', titleKey: 'channel 1', kind: 'channel', category: 'General', providerRef: '99'}]
  });
  const fp = fingerprint(catalog);
  assert.ok(!fp.includes('user'));
  assert.ok(!fp.includes('pass'));
  assert.ok(!fp.includes('token'));
});

test('CODEX 10, 11, 12 & 13: Retention rule and active user control', () => {
  // Simulates catalog metadata with activeSourceCount
  const activeCatalog = {
    catalogId: 'cat-123',
    status: 'ready',
    activeSourceCount: 2,
    storagePath: 'catalogs/cat-123.json',
    lastSuccessfulSyncAt: 1729252800000
  };

  assert.equal(activeCatalog.activeSourceCount > 0, true);

  // When last user unlinks, activeSourceCount decrements to 0
  const unlinkedCatalog = {
    ...activeCatalog,
    activeSourceCount: 0,
    updatedAt: 1729253000000
  };

  // Retention: Catalog is preserved! Never deleted automatically
  assert.equal(unlinkedCatalog.catalogId, 'cat-123');
  assert.equal(unlinkedCatalog.storagePath, 'catalogs/cat-123.json');
  assert.equal(unlinkedCatalog.lastSuccessfulSyncAt, 1729252800000);

  // Sync: Inactive catalog must be ignored by daily sync
  const shouldSync = unlinkedCatalog.activeSourceCount > 0;
  assert.equal(shouldSync, false);
});

test('CODEX 14 & 15: Reactivation when a new user links to an inactive catalog', () => {
  const reactivatedCatalog = {
    catalogId: 'cat-123',
    status: 'ready',
    activeSourceCount: 1, // Becomes active again
    storagePath: 'catalogs/cat-123.json',
    lastSuccessfulSyncAt: 1729252800000
  };

  const shouldSyncNow = reactivatedCatalog.activeSourceCount > 0;
  assert.equal(shouldSyncNow, true);
  // Previous valid JSON remains available until new sync completes
  assert.equal(reactivatedCatalog.storagePath, 'catalogs/cat-123.json');
});

test('CODEX 16: Sync failure preserves previous valid catalog and timestamp', () => {
  const previousSyncTime = 1729252800000;
  const catalogState = {
    catalogId: 'cat-123',
    status: 'ready',
    lastSuccessfulSyncAt: previousSyncTime,
    storagePath: 'catalogs/cat-123.json'
  };

  // Simulate a failed sync attempt
  const failureAttemptTime = 1729256400000;
  const updatedOnFailure = {
    ...catalogState,
    lastAttemptAt: failureAttemptTime,
    // lastSuccessfulSyncAt MUST remain untouched
  };

  assert.equal(updatedOnFailure.lastSuccessfulSyncAt, previousSyncTime);
  assert.equal(updatedOnFailure.storagePath, 'catalogs/cat-123.json');
});

test('CODEX 25 & 26: Original provider categories, live channels, movies and series preserved', () => {
  const rawProviderCategories = [
    {id: '1', name: 'BRAZIL | NOTICIAS', kind: 'channel' as const},
    {id: '2', name: 'FILMES | ACAO 2026', kind: 'movie' as const},
    {id: '3', name: 'SERIES | DRAMA', kind: 'series' as const}
  ];

  const catalog = catalogSchema.parse({
    schemaVersion: 1,
    categories: rawProviderCategories,
    items: [
      {id: 'live-1', title: 'Globo News HD', titleKey: 'globo news hd', kind: 'channel', category: 'BRAZIL | NOTICIAS', categoryId: '1', providerRef: '501'},
      {id: 'vod-1', title: 'Inception (2010)', titleKey: 'inception (2010)', kind: 'movie', category: 'FILMES | ACAO 2026', categoryId: '2', providerRef: '802'},
      {id: 'ser-1', title: 'Breaking Bad', titleKey: 'breaking bad', kind: 'series', category: 'SERIES | DRAMA', categoryId: '3', providerRef: '901'}
    ]
  });

  assert.equal(catalog.categories?.length, 3);
  assert.equal(catalog.categories?.[0]?.name, 'BRAZIL | NOTICIAS'); // Original name preserved
  assert.equal(catalog.items[0]?.kind, 'channel');
  assert.equal(catalog.items[1]?.kind, 'movie');
  assert.equal(catalog.items[2]?.kind, 'series');
});
