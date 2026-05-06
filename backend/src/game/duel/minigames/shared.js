'use strict';

import { createHash } from 'crypto';

export function sr(seed, idx) {
  const hex = createHash('sha256').update(`${seed}:${idx}`).digest('hex');
  return parseInt(hex.slice(0, 8), 16) / 0xffffffff;
}

export function clamp01(value, fallback = 1) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return fallback;
  }

  return Math.min(1, Math.max(0, numeric));
}

export function clampInt(value, min, max, fallback = min) {
  const numeric = Number.parseInt(value, 10);
  if (!Number.isFinite(numeric)) {
    return fallback;
  }

  return Math.min(max, Math.max(min, numeric));
}

export function round4(value) {
  return Math.round(value * 10_000) / 10_000;
}
