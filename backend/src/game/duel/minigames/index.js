'use strict';

import { sr } from './shared.js';
import * as reactionTime from './reactionTime.js';
import * as rapidTap from './rapidTap.js';
import * as precision from './precision.js';
import * as russianRoulette from './russianRoulette.js';
import * as speedBlackjack from './speedBlackjack.js';
import * as councilBidding from './councilBidding.js';

export const MINIGAME_TYPES = [
  'reaction_time',
  'rapid_tap',
  'precision',
  'russian_roulette',
  'speed_blackjack',
  'council_bidding',
];

const REGISTRY = {
  reaction_time: reactionTime,
  rapid_tap: rapidTap,
  precision,
  russian_roulette: russianRoulette,
  speed_blackjack: speedBlackjack,
  council_bidding: councilBidding,
};

export function pickMinigame(seed) {
  const idx = Math.floor(sr(seed, 0) * MINIGAME_TYPES.length);
  return MINIGAME_TYPES[idx];
}

export function generateMinigameParams(type, seed, participants = []) {
  return REGISTRY[type]?.generateParams(seed, participants) ?? {};
}

export function buildPublicMinigameParams(type, params, participantId) {
  return REGISTRY[type]?.buildPublic(params, participantId) ?? (params ?? {});
}

export function judgeMinigame(type, seed, submissions, params) {
  const ids = Object.keys(submissions);
  if (ids.length < 2) {
    return { winner: null, loser: null, reason: 'insufficient_players' };
  }

  const [p1, p2] = ids;
  const s1 = submissions[p1] ?? {};
  const s2 = submissions[p2] ?? {};

  return (
    REGISTRY[type]?.judge({ p1, p2, s1, s2, seed, params }) ??
    { winner: null, loser: null, reason: 'unknown_minigame' }
  );
}

// 턴 기반(action-stream) 미니게임용 진입점. RR 처럼 매 턴 actor 가 액션을 보내고
// 서버가 검증 + 상태 갱신 + 종결 여부를 반환하는 모델에서 사용한다.
// processAction 미구현 모듈은 null 을 돌려준다 (레거시 submit-only).
export function processMinigameAction(type, { params, actorId, action, participants }) {
  const handler = REGISTRY[type];
  if (!handler || typeof handler.processAction !== 'function') {
    return null;
  }
  return handler.processAction({ params, actorId, action, participants });
}

export function isActionMinigame(type) {
  return typeof REGISTRY[type]?.processAction === 'function';
}
