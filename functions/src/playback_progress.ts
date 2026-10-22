/**
 * Playback progress rules shared by `requestPlayback`, `claimPlayRequest` and `watchProgress`.
 *
 * Pure functions (no Firestore): the invariants are unit-tested in
 * test/playback_progress.test.ts.
 *
 * Resume: the position travels WITH the play request (taken from the requester's saved
 * progress and re-read for the TV's active profile at claim time), so the TV never depends on
 * a local library snapshot that may still be loading or may belong to another profile.
 *
 * Writes: every playback is a session (`playId`, `startedAt`, `seq`, `origin`). The server
 * keeps the last accepted session on the progress document and rejects, without error:
 *  - a late event of an older event sequence or older session (out of order, other TV);
 *  - an initialisation zero (new session, position ~0) that would erase saved progress;
 *  - a "resume" session whose first write is far BEHIND the saved position without a user seek
 *    (the restore failed, e.g. a stream that cannot seek).
 * Legitimate rewinds are always accepted: inside a session any position is valid.
 */
import {z} from 'zod';

/** Below this the title is considered "not started": resume opens from the beginning. */
export const RESUME_MIN_SEC = 10;
/** Past this fraction (or inside the last RESUME_END_SEC) the title is finished: no resume. */
export const RESUME_DONE_FRACTION = 0.95;
export const RESUME_END_SEC = 30;
/** A new session may start this far behind the saved position (seek granularity of players). */
export const RESTORE_TOLERANCE_SEC = 5;

export type ProgressOrigin = 'start' | 'resume' | 'restart';
export interface SavedProgress {position: number; duration: number; playId?: string; startedAt?: number; seq?: number; updatedAt?: number; generation?: number}
export interface ResumeHint {positionSec: number; durationSec: number; profileId: string; updatedAt: number}

/** Position (whole seconds) to resume from, or null when the title must start from the beginning. */
export function resumePosition(progress: {position?: unknown; duration?: unknown} | null | undefined): number | null {
  const position = Number(progress?.position), duration = Number(progress?.duration);
  if (!Number.isFinite(position) || !Number.isFinite(duration) || duration <= 0 || position < RESUME_MIN_SEC) return null;
  if (position / duration >= RESUME_DONE_FRACTION || duration - position < RESUME_END_SEC) return null;
  return Math.floor(position);
}

/**
 * Which saved progress the TV restores: what the requester's Control showed wins (that is the
 * "38 min" the person saw); the TV profile's own progress is the fallback. The newest wins
 * when both exist for the same profile, so a title watched meanwhile is not rewound.
 */
export function chooseResume(hint: ResumeHint | null | undefined, tvProgress: SavedProgress | null | undefined, tvProfileId: string): {positionSec: number; durationSec: number} | null {
  const own = tvProgress && resumePosition(tvProgress) !== null ? {positionSec: resumePosition(tvProgress)!, durationSec: Number(tvProgress.duration), updatedAt: Number(tvProgress.updatedAt) || 0} : null;
  const asked = hint && resumePosition({position: hint.positionSec, duration: hint.durationSec}) !== null
    ? {positionSec: Math.floor(hint.positionSec), durationSec: hint.durationSec, updatedAt: hint.updatedAt}
    : null;
  if (asked && own && hint!.profileId === tvProfileId) return own.updatedAt >= asked.updatedAt ? own : asked;
  const pick = asked ?? own;
  return pick ? {positionSec: pick.positionSec, durationSec: pick.durationSec} : null;
}

export const progressSessionSchema = z.object({
  playId: z.string().regex(/^[A-Za-z0-9_-]{8,64}$/),
  startedAt: z.number().int().positive(),
  seq: z.number().int().min(0).max(2_000_000_000),
  origin: z.enum(['start', 'resume', 'restart']),
  userSeek: z.boolean().optional(),
});
export type ProgressSession = z.infer<typeof progressSessionSchema>;

/** Optional on purpose: TVs running the previous player send none and keep the legacy behaviour. */
export function parseProgressSession(p: Record<string, unknown>): ProgressSession | null {
  return p.playId === undefined ? null : progressSessionSchema.parse({playId: p.playId, startedAt: p.startedAt, seq: p.seq, origin: p.origin, userSeek: p.userSeek});
}

export type ProgressDecision = {accept: true} | {accept: false; reason: 'stale-event' | 'stale-session' | 'initial-zero' | 'resume-not-applied'};

export function decideProgressWrite(saved: SavedProgress | null | undefined, session: ProgressSession | null, position: number): ProgressDecision {
  if (!session || !saved) return {accept: true};
  if (saved.playId === session.playId) return typeof saved.seq === 'number' && session.seq <= saved.seq ? {accept: false, reason: 'stale-event'} : {accept: true};
  if (typeof saved.startedAt === 'number' && session.startedAt < saved.startedAt) return {accept: false, reason: 'stale-session'};
  // New session: protect valid saved progress from initialisation noise.
  if (!(saved.position >= RESUME_MIN_SEC)) return {accept: true};
  if (session.origin === 'restart' || session.userSeek === true) return {accept: true};
  if (position < 1) return {accept: false, reason: 'initial-zero'};
  if (session.origin === 'resume' && position + RESTORE_TOLERANCE_SEC < saved.position) return {accept: false, reason: 'resume-not-applied'};
  return {accept: true};
}

/** Episode progress key; identical to the TV's `episodeContentId`. */
export function episodeContentId(seriesItemId: string, episodeId: string): string {
  return `${seriesItemId}_e${episodeId.replace(/[^A-Za-z0-9_-]/g, '')}`.slice(0, 128);
}
