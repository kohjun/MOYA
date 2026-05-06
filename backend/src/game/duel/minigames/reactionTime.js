'use strict';

import { sr } from './shared.js';

export function generateParams(seed) {
  return {
    signalDelayMs: Math.floor(500 + sr(seed, 1) * 1500),
  };
}

export function buildPublic(params) {
  return {
    signalDelayMs: params?.signalDelayMs ?? 1000,
  };
}

export function judge({ p1, p2, s1, s2 }) {
  const r1 = Number.isFinite(s1.reactionMs) && s1.reactionMs >= 0 ? s1.reactionMs : Infinity;
  const r2 = Number.isFinite(s2.reactionMs) && s2.reactionMs >= 0 ? s2.reactionMs : Infinity;
  if (r1 === r2) {
    return { winner: null, loser: null, reason: 'draw' };
  }

  return r1 < r2
    ? { winner: p1, loser: p2, reason: 'faster_reaction' }
    : { winner: p2, loser: p1, reason: 'faster_reaction' };
}
