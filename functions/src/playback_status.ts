/**
 * What a TV is playing right now, for the Control's "Reproduzindo" bar.
 *
 *  families/{fid}/devices/{did}.nowPlaying
 *    {sourceId, itemId, episodeId, kind, title, providerRef, year, imageRef,
 *     state: playing|paused, profileId, positionSec, durationSec, updatedAt}
 *
 * Written only here (backend), by the TV with a current lease; cleared on
 * stop/release. The Control reads it through the device document (rules:
 * family members). It is a status, not a remote control: nothing in it
 * commands the TV. A status older than NOW_PLAYING_FRESH_MS is not shown.
 */
import {FieldValue, getFirestore} from 'firebase-admin/firestore';
import {z} from 'zod';
import {DomainError, idSchema, Lease} from './domain';
import {playableItem} from './iptv_catalog_access';
import {playerContext, type Identity} from './service';

export const NOW_PLAYING_FRESH_MS = 120_000;
const MIN_WRITE_GAP_MS = 5_000;

export async function reportPlayback(p: Record<string, unknown>, actor: Identity) {
  if (!actor.deviceId || !actor.familyId) throw new DomainError('permission-denied');
  const now = Date.now();
  const sessionId = idSchema.parse(p.sessionId);
  const state = z.enum(['playing', 'paused', 'stopped']).parse(p.state);
  const sourceId = idSchema.parse(p.sourceId), itemId = idSchema.parse(p.itemId);
  const episodeId = p.episodeId === undefined || p.episodeId === null ? null : idSchema.parse(p.episodeId);
  const positionSec = z.number().finite().min(0).optional().parse(p.positionSec);
  const durationSec = z.number().finite().positive().optional().parse(p.durationSec);
  // Only content this TV's active profile may watch is ever published.
  const item = state === 'stopped' ? null : await playableItem(actor, sourceId, itemId);
  const deviceRef = getFirestore().doc(`families/${actor.familyId}/devices/${actor.deviceId}`);
  return getFirestore().runTransaction(async tx => {
    const context = await playerContext(tx, actor);
    const lease = ((context.data.leases ?? []) as Lease[]).find(l => l.deviceId === actor.deviceId && l.id === sessionId && l.expiresAt > now);
    if (!lease) throw new DomainError('session-expired');
    if (state === 'stopped') { tx.update(deviceRef, {nowPlaying: FieldValue.delete()}); return {ok: true}; }
    const previous = context.deviceData.nowPlaying as {updatedAt?: number; state?: string; itemId?: string; episodeId?: string | null} | undefined;
    if (previous && previous.itemId === itemId && (previous.episodeId ?? null) === episodeId && previous.state === state && now - (previous.updatedAt ?? 0) < MIN_WRITE_GAP_MS) return {ok: true, skipped: true};
    const live = item!.kind === 'channel';
    tx.update(deviceRef, {nowPlaying: {
      sourceId, itemId, episodeId, kind: item!.kind, title: item!.title.slice(0, 300),
      ...(item!.providerRef ? {providerRef: item!.providerRef} : {}),
      ...(item!.year !== undefined ? {year: item!.year} : {}),
      ...(item!.imageRef ? {imageRef: item!.imageRef} : {}),
      state, profileId: lease.profileId, updatedAt: now,
      ...(!live && positionSec !== undefined && durationSec !== undefined && positionSec <= durationSec ? {positionSec, durationSec} : {}),
    }});
    return {ok: true};
  });
}
