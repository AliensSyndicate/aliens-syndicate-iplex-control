import {getFirestore, Transaction} from 'firebase-admin/firestore';
import {DomainError, hash} from './domain';

export interface IptvServerRecord {
  serverId: string;
  type: string;
  canonicalEndpoint: string;
  identityHash: string;
  status: 'active' | 'inactive';
  createdAt: number;
  updatedAt: number;
}

export function xtreamBase(raw: string): URL {
  const url = new URL(raw);
  url.username = ''; url.password = ''; url.search = ''; url.hash = '';
  url.pathname = url.pathname.replace(/\/(player_api|get|xmltv)\.php\/?$/i, '').replace(/\/+$/, '') + '/';
  return url;
}

/** An opaque M3U path may itself be a credential. Never persist that path in a
 * global server record. Hashing only the origin for those URLs is conservative:
 * endpoint discrimination is retained in the private equivalence proof. */
export function normalizeServerEndpoint(rawUrl: string, type: string): {canonicalEndpoint: string; identityHash: string} {
  const url = type === 'xtream' ? xtreamBase(rawUrl) : new URL(rawUrl);
  if (!['http:', 'https:'].includes(url.protocol)) throw new DomainError('unsafe-provider');
  const port = url.port || (url.protocol === 'https:' ? '443' : '80');
  const path = type === 'xtream' ? url.pathname.replace(/\/+$/, '') : '';
  const canonicalEndpoint = `${url.protocol}//${url.hostname.toLowerCase()}:${port}${path}`;
  // Opaque path discriminates installations without exposing tokens. URL aliases
  // are the same method; path case is significant on HTTP servers.
  const endpointIdentity = type === 'xtream' ? canonicalEndpoint : `${canonicalEndpoint}:${hash(url.pathname)}`;
  return {canonicalEndpoint, identityHash: hash(endpointIdentity)};
}

export async function identifyOrCreateServer(tx: Transaction, source: {format: string; url?: string}, now: number): Promise<string | null> {
  if (source.format === 'file' || !source.url) return null;
  const {canonicalEndpoint, identityHash} = normalizeServerEndpoint(source.url, source.format);
  const serverId = `srv_${identityHash.slice(0, 32)}`;
  const ref = getFirestore().doc(`servers/${serverId}`), snap = await tx.get(ref);
  tx.set(ref, {serverId, type: source.format === 'xtream' ? 'xtream' : 'playlist', canonicalEndpoint, identityHash,
    status: 'active', createdAt: snap.data()?.createdAt ?? now, updatedAt: now});
  return serverId;
}
