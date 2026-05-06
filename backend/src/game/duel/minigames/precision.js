'use strict';

import { sr, round4, clamp01 } from './shared.js';

const PRECISION_SHOTS = 3;

function buildPrecisionTargets(seed, shots = PRECISION_SHOTS) {
  return Array.from({ length: shots }, (_, index) => ({
    x: round4(0.15 + sr(seed, 1 + index * 2) * 0.7),
    y: round4(0.18 + sr(seed, 2 + index * 2) * 0.64),
  }));
}

function scorePrecisionSubmission(submission, targets) {
  const hits = Array.isArray(submission?.hits) ? submission.hits : [];
  let totalDistance = 0;

  for (let index = 0; index < targets.length; index += 1) {
    const target = targets[index];
    const hit = hits[index];

    if (!target || !hit) {
      totalDistance += 2;
      continue;
    }

    totalDistance += Math.hypot(
      clamp01(hit.x) - target.x,
      clamp01(hit.y) - target.y,
    );
  }

  return totalDistance;
}

export function generateParams(seed) {
  return {
    shots: PRECISION_SHOTS,
    targets: buildPrecisionTargets(seed),
  };
}

export function buildPublic(params) {
  return {
    shots: params?.shots ?? PRECISION_SHOTS,
    targets: Array.isArray(params?.targets) ? params.targets : [],
  };
}

export function judge({ p1, p2, s1, s2, seed, params }) {
  const targets = Array.isArray(params?.targets) ? params.targets : buildPrecisionTargets(seed);
  const d1 = scorePrecisionSubmission(s1, targets);
  const d2 = scorePrecisionSubmission(s2, targets);
  if (Math.abs(d1 - d2) < 1e-6) {
    return { winner: null, loser: null, reason: 'draw' };
  }

  return d1 < d2
    ? { winner: p1, loser: p2, reason: 'better_precision' }
    : { winner: p2, loser: p1, reason: 'better_precision' };
}
