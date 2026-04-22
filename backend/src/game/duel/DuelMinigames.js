'use strict';

import { createHash } from 'crypto';

// ─────────────────────────────────────────────────────────────────────────────
// DuelMinigames — 5종 미니게임 seed 기반 판정 규약
//
// 클라이언트가 제출하는 결과는 서버 seed로 재검증 가능하도록 설계.
// judgeMinigame()은 순수함수 — 동일 seed + 제출값 → 동일 결과 보장.
// ─────────────────────────────────────────────────────────────────────────────

export const MINIGAME_TYPES = [
  'reaction_time',
  'rapid_tap',
  'precision',
  'russian_roulette',
  'speed_blackjack',
];

// ── seededRandom ──────────────────────────────────────────────────────────────
// SHA-256(seed:index) → deterministic 0~1 float
function sr(seed, idx) {
  const hex = createHash('sha256').update(`${seed}:${idx}`).digest('hex');
  return parseInt(hex.slice(0, 8), 16) / 0xffffffff;
}

// ── pickMinigame ──────────────────────────────────────────────────────────────
// seed로 5종 중 1종 결정 (deterministic)
export function pickMinigame(seed) {
  const idx = Math.floor(sr(seed, 0) * MINIGAME_TYPES.length);
  return MINIGAME_TYPES[idx];
}

// ── generateMinigameParams ────────────────────────────────────────────────────
// 클라이언트에 전달할 공개 파라미터 생성.
// 일부 값(bulletChamber 등)은 서버만 보유 → 클라이언트에 노출 안 함.
export function generateMinigameParams(type, seed) {
  switch (type) {
    case 'reaction_time':
      // 클라이언트에게는 signalDelayMs만 공개 (실제 signal 타이밍 계산용)
      return {
        signalDelayMs: Math.floor(500 + sr(seed, 1) * 1500), // 500~2000ms
      };

    case 'rapid_tap':
      return {
        targetTaps:  Math.floor(20 + sr(seed, 1) * 11), // 20~30회
        durationSec: 5,
      };

    case 'precision':
      return {
        targetX: sr(seed, 1), // 0~1 (정규화 좌표)
        targetY: sr(seed, 2),
      };

    case 'russian_roulette':
      // bulletChamber는 서버만 보유 — 클라이언트에 전송 안 함
      return {
        chamberCount: 6,
        // bulletChamber: _hidden_
      };

    case 'speed_blackjack':
      // 덱은 서버가 관리, 클라이언트는 카드를 서버에서 받아 hit/stand 결정
      return {
        targetScore: 21,
        initialCards: _dealInitialCards(seed), // { p1: [c1,c2], p2: [c1,c2] }
      };

    default:
      return {};
  }
}

// ── judgeMinigame ─────────────────────────────────────────────────────────────
// 순수함수: seed + submissions + params → verdict
//
// submissions: { [userId]: result }
//   reaction_time : { reactionMs: number }
//   rapid_tap     : { tapCount: number, durationMs: number }
//   precision     : { hitX: number, hitY: number }
//   russian_roulette: { chamber: number (1~6) }
//   speed_blackjack : { finalScore: number }
//
// Returns: { winner: userId|null, loser: userId|null, reason: string }
export function judgeMinigame(type, seed, submissions, params) {
  const ids = Object.keys(submissions);
  if (ids.length < 2) return { winner: null, loser: null, reason: 'insufficient_players' };

  const [p1, p2] = ids;
  const s1 = submissions[p1] ?? {};
  const s2 = submissions[p2] ?? {};

  switch (type) {
    case 'reaction_time': {
      const r1 = Number.isFinite(s1.reactionMs) ? s1.reactionMs : Infinity;
      const r2 = Number.isFinite(s2.reactionMs) ? s2.reactionMs : Infinity;
      if (r1 === r2) return { winner: null, loser: null, reason: 'draw' };
      return r1 < r2
        ? { winner: p1, loser: p2, reason: 'faster_reaction' }
        : { winner: p2, loser: p1, reason: 'faster_reaction' };
    }

    case 'rapid_tap': {
      const rate = (s) => s.tapCount != null && s.durationMs > 0
        ? s.tapCount / s.durationMs
        : 0;
      const r1 = rate(s1);
      const r2 = rate(s2);
      if (Math.abs(r1 - r2) < 1e-6) return { winner: null, loser: null, reason: 'draw' };
      return r1 > r2
        ? { winner: p1, loser: p2, reason: 'faster_tap' }
        : { winner: p2, loser: p1, reason: 'faster_tap' };
    }

    case 'precision': {
      const dist = (s) => Math.hypot(
        (s.hitX ?? 1) - (params.targetX ?? 0.5),
        (s.hitY ?? 1) - (params.targetY ?? 0.5),
      );
      const d1 = dist(s1);
      const d2 = dist(s2);
      if (Math.abs(d1 - d2) < 1e-4) return { winner: null, loser: null, reason: 'draw' };
      return d1 < d2
        ? { winner: p1, loser: p2, reason: 'better_precision' }
        : { winner: p2, loser: p1, reason: 'better_precision' };
    }

    case 'russian_roulette': {
      // 서버 seed로 실탄 위치 재계산 (클라이언트 신뢰 불요)
      const bullet = Math.floor(sr(seed, 3) * 6) + 1; // 1~6
      const hit1   = s1.chamber === bullet;
      const hit2   = s2.chamber === bullet;
      if (hit1 && !hit2) return { winner: p2, loser: p1, reason: 'bullet_hit' };
      if (hit2 && !hit1) return { winner: p1, loser: p2, reason: 'bullet_hit' };
      if (!hit1 && !hit2) return { winner: null, loser: null, reason: 'both_survived' };
      return { winner: null, loser: null, reason: 'simultaneous_hit' };
    }

    case 'speed_blackjack': {
      // finalScore는 클라이언트가 계산해 제출; 21 초과 = bust = 0점
      const sc = (s) => {
        const score = s.finalScore ?? 0;
        return score > 21 ? 0 : score;
      };
      const sc1 = sc(s1);
      const sc2 = sc(s2);
      if (sc1 === sc2) return { winner: null, loser: null, reason: 'draw' };
      return sc1 > sc2
        ? { winner: p1, loser: p2, reason: 'higher_hand' }
        : { winner: p2, loser: p1, reason: 'higher_hand' };
    }

    default:
      return { winner: null, loser: null, reason: 'unknown_minigame' };
  }
}

// ── helpers ───────────────────────────────────────────────────────────────────

function _dealInitialCards(seed) {
  // 52장 덱 생성 후 seed 기반 Fisher-Yates shuffle
  const deck = [];
  for (let v = 1; v <= 13; v++) {
    for (let s = 0; s < 4; s++) deck.push(Math.min(v, 10)); // A=1, face=10
  }
  for (let i = deck.length - 1; i > 0; i--) {
    const j = Math.floor(sr(seed, i + 10) * (i + 1));
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  // 각 플레이어에게 2장씩
  return { p1: [deck[0], deck[2]], p2: [deck[1], deck[3]] };
}
