'use strict';

import { defaultConfig } from './schema.js';

// 승리 조건:
//   1) last_survivor : 살아있는 사람이 1명 이하
//   2) time_up       : startedAt + timeLimitSec 경과 → tagCount 1위 (동률 시 무작위)
//   3) all_dead      : 살아있는 사람이 0명 → 무승부 (winner=null)
export function checkWinCondition(gameState, now = Date.now()) {
  if (gameState.status !== 'in_progress') return null;

  const ps = gameState.pluginState ?? {};
  const config = { ...defaultConfig, ...(ps._config ?? {}) };
  const aliveIds = gameState.alivePlayerIds ?? [];

  // 1. 마지막 1인 / 전멸
  if (aliveIds.length === 0) {
    return { winner: null, reason: 'all_dead' };
  }
  if (aliveIds.length === 1) {
    return { winner: aliveIds[0], reason: 'last_survivor' };
  }

  // 2. 시간 종료
  const timeLimitMs = (config.timeLimitSec ?? 1200) * 1000;
  const elapsed = now - (gameState.startedAt ?? now);
  if (elapsed >= timeLimitMs) {
    return resolveTimeUpWinner(ps);
  }

  return null;
}

// tagCount 1위 결정. 동률 시 후보 중 무작위 1명.
function resolveTimeUpWinner(ps) {
  const alive = Object.values(ps.playerStates ?? {}).filter((p) => p.isAlive);
  if (alive.length === 0) {
    return { winner: null, reason: 'all_dead' };
  }

  const maxTags = Math.max(...alive.map((p) => p.tagCount ?? 0));
  const leaders = alive.filter((p) => (p.tagCount ?? 0) === maxTags);
  const winner = leaders[Math.floor(Math.random() * leaders.length)];

  return {
    winner: winner.userId,
    reason: leaders.length > 1 ? 'time_up_tied' : 'time_up',
    tagCount: maxTags,
    leaderCount: leaders.length,
  };
}

// 클라이언트 종료 화면용 — 색별 처치 수 / 생존 정보.
export function getFinalScoreboard(ps) {
  return Object.values(ps.playerStates ?? {})
    .map((p) => ({
      userId: p.userId,
      nickname: p.nickname,
      colorId: p.colorId,
      colorLabel: p.colorLabel,
      colorHex: p.colorHex,
      tagCount: p.tagCount ?? 0,
      isAlive: p.isAlive,
      missionsCompleted: p.missionsCompleted ?? 0,
    }))
    .sort((a, b) => {
      // 생존 우선, 그 다음 tagCount 내림차순.
      if (a.isAlive !== b.isAlive) return a.isAlive ? -1 : 1;
      return (b.tagCount ?? 0) - (a.tagCount ?? 0);
    });
}
