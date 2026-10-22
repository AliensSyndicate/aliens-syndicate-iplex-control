import {test} from 'node:test';
import assert from 'node:assert/strict';
import {chooseResume, decideProgressWrite, episodeContentId, parseProgressSession, resumePosition, type ProgressSession} from '../src/playback_progress';

const MIN = 60;
const sess = (over: Partial<ProgressSession> = {}): ProgressSession => ({playId: 'play-0001', startedAt: 1_000, seq: 1, origin: 'resume', ...over});
const saved = (over: Record<string, unknown> = {}) => ({position: 38 * MIN, duration: 120 * MIN, ...over});

test('resumePosition: 38 min of a 120 min movie resumes at 2280 s', () => {
  assert.equal(resumePosition({position: 38 * MIN, duration: 120 * MIN}), 2280);
  assert.equal(resumePosition({position: 2280.9, duration: 7200}), 2280);
});

test('resumePosition: not started, finished, unknown duration and garbage start from the beginning', () => {
  assert.equal(resumePosition({position: 4, duration: 7200}), null);
  assert.equal(resumePosition({position: 7000, duration: 7200}), null, '>= 95%');
  assert.equal(resumePosition({position: 7180, duration: 7200}), null, 'last 30 s');
  assert.equal(resumePosition({position: 600, duration: 0}), null, 'duration unavailable');
  assert.equal(resumePosition({position: Number.NaN, duration: 100}), null);
  assert.equal(resumePosition(null), null);
});

test('chooseResume: the position the Control showed wins when the TV profile has none (other profile)', () => {
  const hint = {positionSec: 2280, durationSec: 7200, profileId: 'adult', updatedAt: 5};
  assert.deepEqual(chooseResume(hint, undefined, 'kids'), {positionSec: 2280, durationSec: 7200});
  assert.deepEqual(chooseResume(hint, {position: 100, duration: 7200, updatedAt: 9}, 'kids'), {positionSec: 2280, durationSec: 7200});
});

test('chooseResume: same profile uses the newest write; nothing valid means start from the beginning', () => {
  const hint = {positionSec: 2280, durationSec: 7200, profileId: 'p', updatedAt: 5};
  assert.equal(chooseResume(hint, {position: 3000, duration: 7200, updatedAt: 9}, 'p')!.positionSec, 3000, 'watched meanwhile');
  assert.equal(chooseResume(hint, {position: 3000, duration: 7200, updatedAt: 1}, 'p')!.positionSec, 2280);
  assert.equal(chooseResume(null, undefined, 'p'), null);
  assert.equal(chooseResume(null, {position: 7100, duration: 7200, updatedAt: 1}, 'p'), null, 'finished');
});

test('episode keys match the TV (series, season/episode identity never mixes)', () => {
  assert.equal(episodeContentId('abc123', '901'), 'abc123_e901');
  assert.notEqual(episodeContentId('abc123', '901'), episodeContentId('abc123', '902'));
  assert.equal(episodeContentId('abc', 'a/b c').includes('/'), false);
});

test('legacy writers (no session) are accepted unchanged', () => {
  assert.equal(parseProgressSession({position: 1}), null);
  assert.deepEqual(decideProgressWrite(saved(), null, 0), {accept: true});
});

test('initialisation zero never erases saved progress (4)', () => {
  assert.deepEqual(decideProgressWrite(saved(), sess({origin: 'start'}), 0), {accept: false, reason: 'initial-zero'});
  assert.deepEqual(decideProgressWrite(saved(), sess({origin: 'resume'}), 0.2), {accept: false, reason: 'initial-zero'});
});

test('resume that was not applied (stream without seek) cannot overwrite; applied resume is accepted (1, 15)', () => {
  assert.deepEqual(decideProgressWrite(saved(), sess({origin: 'resume'}), 45), {accept: false, reason: 'resume-not-applied'});
  assert.deepEqual(decideProgressWrite(saved(), sess({origin: 'resume'}), 38 * MIN + 2), {accept: true});
  assert.deepEqual(decideProgressWrite(saved(), sess({origin: 'resume'}), 38 * MIN - 3), {accept: true}, 'within seek granularity');
  assert.deepEqual(decideProgressWrite(saved(), sess({origin: 'resume', userSeek: true}), 45), {accept: true}, 'person seeks back on purpose');
});

test('intentional restart is accepted, including a zero (8)', () => {
  assert.deepEqual(decideProgressWrite(saved(), sess({origin: 'restart'}), 0), {accept: true});
  assert.deepEqual(decideProgressWrite(saved(), sess({origin: 'restart'}), 30), {accept: true});
});

test('inside a session forward and backward seeks are accepted, repeated/old events are not (6, 7, 13)', () => {
  const s = (seq: number) => sess({seq});
  const row = (position: number, seq: number) => saved({position, playId: 'play-0001', startedAt: 1_000, seq});
  assert.deepEqual(decideProgressWrite(row(2300, 5), s(6), 3000), {accept: true}, 'seek forward');
  assert.deepEqual(decideProgressWrite(row(3000, 6), s(7), 600), {accept: true}, 'seek back is legitimate');
  assert.deepEqual(decideProgressWrite(row(3000, 6), s(6), 10), {accept: false, reason: 'stale-event'}, 'replay');
  assert.deepEqual(decideProgressWrite(row(3000, 6), s(4), 10), {accept: false, reason: 'stale-event'}, 'out of order');
});

test('late events of an older session (other TV, previous run) never overwrite the current one (12, 13)', () => {
  const current = saved({position: 2000, playId: 'tv-b-0001', startedAt: 9_000, seq: 3});
  assert.deepEqual(decideProgressWrite(current, sess({playId: 'tv-a-0001', startedAt: 5_000, seq: 99, origin: 'restart', userSeek: true}), 100), {accept: false, reason: 'stale-session'});
  assert.deepEqual(decideProgressWrite(current, sess({playId: 'tv-c-0001', startedAt: 10_000, origin: 'resume'}), 2001), {accept: true}, 'newer session continues');
});

test('first progress of a title, and progress below the resume threshold, are accepted', () => {
  assert.deepEqual(decideProgressWrite(undefined, sess({origin: 'start'}), 0), {accept: true});
  assert.deepEqual(decideProgressWrite(saved({position: 3}), sess({origin: 'start'}), 0), {accept: true});
});

test('session payload is validated', () => {
  assert.throws(() => parseProgressSession({playId: 'x', startedAt: 1, seq: 0, origin: 'resume'}));
  assert.throws(() => parseProgressSession({playId: 'play-0001', startedAt: 1, seq: -1, origin: 'resume'}));
  assert.throws(() => parseProgressSession({playId: 'play-0001', startedAt: 1, seq: 0, origin: 'nope'}));
  assert.equal(parseProgressSession({playId: 'play-0001', startedAt: 1, seq: 0, origin: 'resume'})!.origin, 'resume');
});
