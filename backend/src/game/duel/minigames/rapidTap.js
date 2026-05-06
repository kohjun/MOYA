'use strict';

export function generateParams() {
  return {
    durationSec: 5,
  };
}

export function buildPublic(params) {
  return {
    durationSec: params?.durationSec ?? 5,
  };
}

export function judge({ p1, p2, s1, s2 }) {
  const rate = (submission) => (
    submission?.tapCount != null && submission?.durationMs > 0
      ? submission.tapCount / submission.durationMs
      : 0
  );
  const r1 = rate(s1);
  const r2 = rate(s2);
  if (Math.abs(r1 - r2) < 1e-6) {
    return { winner: null, loser: null, reason: 'draw' };
  }

  return r1 > r2
    ? { winner: p1, loser: p2, reason: 'faster_tap' }
    : { winner: p2, loser: p1, reason: 'faster_tap' };
}
