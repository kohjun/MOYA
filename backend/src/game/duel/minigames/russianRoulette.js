'use strict';

import { sr } from './shared.js';

// Russian Roulette — 턴 기반 동기화 모델.
//
// generateParams 시점에 6 발 약실 중 1발이 실탄으로 결정되며 (seed deterministic),
// 양 클라에 노출되는 buildPublic 페이로드에서는 bulletChamber 가 제거된다.
// 매 턴 actor 가 { chamber, target: 'self' | 'opponent' } 액션을 보내면 서버가
// processAction 으로 검증 + 상태 전이 + 종결 판정을 수행한다.
//
// 클래식 룰:
//  - 실탄에 맞으면 그 약실을 향한 target 이 패배.
//  - self miss → 같은 actor 의 턴이 그대로 유지 (재시도).
//  - opponent miss → 턴이 상대에게 넘어감.

export function generateParams(seed, participants = []) {
  const chamberCount = 6;
  const bulletChamber = Math.floor(sr(seed, 3) * chamberCount) + 1;
  const firstActor = participants[0] ?? null;
  return {
    chamberCount,
    bulletChamber,
    state: {
      chambersFired: [],
      currentTurn: firstActor,
      history: [],
      settled: false,
    },
  };
}

export function buildPublic(params) {
  const state = params?.state ?? {
    chambersFired: [],
    currentTurn: null,
    history: [],
    settled: false,
  };
  return {
    chamberCount: params?.chamberCount ?? 6,
    state: {
      chambersFired: [...(state.chambersFired ?? [])],
      currentTurn: state.currentTurn ?? null,
      history: [...(state.history ?? [])],
      settled: !!state.settled,
    },
  };
}

export function processAction({ params, actorId, action, participants }) {
  const state = params?.state;
  if (!state) {
    return { ok: false, error: 'INVALID_STATE' };
  }
  if (state.settled) {
    return { ok: false, error: 'GAME_SETTLED' };
  }
  if (state.currentTurn !== actorId) {
    return { ok: false, error: 'NOT_YOUR_TURN' };
  }

  const chamberCount = params.chamberCount ?? 6;
  const chamber = Number(action?.chamber);
  const target = action?.target;
  if (!Number.isInteger(chamber) || chamber < 1 || chamber > chamberCount) {
    return { ok: false, error: 'INVALID_CHAMBER' };
  }
  if (state.chambersFired.includes(chamber)) {
    return { ok: false, error: 'CHAMBER_USED' };
  }
  if (target !== 'self' && target !== 'opponent') {
    return { ok: false, error: 'INVALID_TARGET' };
  }

  const opponentId = participants.find((p) => p !== actorId);
  if (!opponentId) {
    return { ok: false, error: 'NO_OPPONENT' };
  }
  const targetId = target === 'self' ? actorId : opponentId;
  const isHit = chamber === params.bulletChamber;

  const nextState = {
    chambersFired: [...state.chambersFired, chamber],
    currentTurn: state.currentTurn,
    history: [
      ...state.history,
      {
        actor: actorId,
        target: targetId,
        chamber,
        hit: isHit,
      },
    ],
    settled: false,
  };

  const nextParams = { ...params, state: nextState };

  if (isHit) {
    const loser = targetId;
    const winner = participants.find((p) => p !== loser) ?? null;
    nextState.settled = true;
    return {
      ok: true,
      terminal: true,
      verdict: { winner, loser, reason: 'bullet_hit' },
      params: nextParams,
    };
  }

  // 클래식 룰: self miss → 같은 turn 유지, opponent miss → 턴 넘김.
  nextState.currentTurn = target === 'self' ? actorId : opponentId;

  // 방어적: 6 약실 모두 소진 (정상 흐름에서는 hit 가 먼저 발생해 도달 불가).
  if (nextState.chambersFired.length >= chamberCount) {
    nextState.settled = true;
    return {
      ok: true,
      terminal: true,
      verdict: { winner: null, loser: null, reason: 'no_bullet_found' },
      params: nextParams,
    };
  }

  return { ok: true, terminal: false, params: nextParams };
}

// 레거시 submit() 경유 호환 — RR 은 더 이상 단발 제출 모델이 아니다.
// submission 기반으로 들어오면 무승부로 종료한다 (예: timeout fallback).
export function judge() {
  return { winner: null, loser: null, reason: 'rr_unresolved' };
}
