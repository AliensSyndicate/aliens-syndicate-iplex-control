import {test} from 'node:test';
import assert from 'node:assert/strict';
import {normalizeServerEndpoint} from '../src/iptv_server';

test('normalizeServerEndpoint strips credentials, queries, and player_api.php while preserving host and ports', () => {
  // Xtream Codes endpoint with query params, credentials, and player_api.php
  const xtream1 = normalizeServerEndpoint('http://user:pass@provider.example.com:8080/base/path/player_api.php?username=u&password=p', 'xtream');
  assert.equal(xtream1.canonicalEndpoint, 'http://provider.example.com:8080/base/path');
  assert.ok(xtream1.identityHash);

  // Another query with trailing slash
  const xtream2 = normalizeServerEndpoint('http://provider.example.com:8080/base/path/', 'xtream');
  assert.equal(xtream2.canonicalEndpoint, 'http://provider.example.com:8080/base/path');
  assert.equal(xtream1.identityHash, xtream2.identityHash); // Idempotent stable hash

  // Different port on same host produces different server identity
  const xtreamPort = normalizeServerEndpoint('http://provider.example.com:9000/base/path', 'xtream');
  assert.notEqual(xtream1.identityHash, xtreamPort.identityHash);

  // Different base path on same domain produces different server identity
  const xtreamPath = normalizeServerEndpoint('http://provider.example.com:8080/other/path', 'xtream');
  assert.notEqual(xtream1.identityHash, xtreamPath.identityHash);

  // Standard M3U URL strips query tokens and user/pass
  const m3u1 = normalizeServerEndpoint('https://token:secret@cdn.example.org/stream/playlist.m3u8?token=xyz123', 'url');
  assert.equal(m3u1.canonicalEndpoint, 'https://cdn.example.org:443');
  assert.ok(!m3u1.canonicalEndpoint.includes('token'));
  assert.ok(!m3u1.canonicalEndpoint.includes('secret'));
  assert.ok(!m3u1.canonicalEndpoint.includes('xyz123'));
});

test('identityHash is deterministic and case-insensitive on scheme and host', () => {
  const a = normalizeServerEndpoint('HTTPS://Provider.Example.COM:443/Live', 'xtream');
  const b = normalizeServerEndpoint('https://provider.example.com:443/Live', 'xtream');
  assert.equal(a.canonicalEndpoint, b.canonicalEndpoint);
  assert.equal(a.identityHash, b.identityHash);
});

test('path case, base installation and opaque credentials cannot collapse server identity',()=>{
 assert.notEqual(normalizeServerEndpoint('https://p.example/Live','xtream').identityHash,normalizeServerEndpoint('https://p.example/live','xtream').identityHash);
 const url=normalizeServerEndpoint('https://p.example/token-secret/list','url');
 assert.equal(url.canonicalEndpoint.includes('secret'),false);
 assert.notEqual(url.identityHash,normalizeServerEndpoint('https://p.example/other/list','url').identityHash);
});
