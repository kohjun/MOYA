'use strict';

import { defaultConfig, BODY_ATTRIBUTES, sanitizeBodyProfile } from './schema.js';
import { processTagAttempt } from './elimination.js';
import { startMission, submitMission } from './mission.js';
import {
  checkWinCondition as evaluateWinCondition,
  getFinalScoreboard,
} from './winConditions.js';

// Phase 1+2 범위:
//   - getPublicState : 게임 상태 + 살아있는 사람의 색 분포 (정체 노출 X)
//   - getPrivateState: 본인 색, 본인 타겟 색 (타겟 userId 는 노출 X)
//   - handleEvent / checkWinCondition : 빈 구현 (Phase 3+ 에서 채움)

export function getPublicState(gameState) {
  const ps = gameState.pluginState ?? {};
  const palette = ps.palette ?? [];
  const playerStates = ps.playerStates ?? {};

  // 살아있는 색 목록만 노출. 정체(userId↔color) 매핑은 숨긴다.
  const aliveColors = Object.values(playerStates)
    .filter((p) => p.isAlive)
    .map((p) => p.colorId);

  const colorCounts = palette.map((color) => ({
    colorId: color.id,
    colorLabel: color.label,
    colorHex: color.hex,
    aliveCount: aliveColors.filter((c) => c === color.id).length,
  }));

  const config = ps._config ?? defaultConfig;

  return {
    status: gameState.status,
    startedAt: gameState.startedAt,
    finishedAt: gameState.finishedAt,
    aliveCount: gameState.alivePlayerIds.length,
    alivePlayerIds: gameState.alivePlayerIds,
    eliminatedPlayerIds: ps.eliminatedPlayerIds ?? [],
    palette,
    colorCounts,
    // 거점 위치는 inactive 상태에서는 비공개 (id 만). 활성/claimed/expired 만 위치 노출.
    controlPoints: (ps.controlPoints ?? []).map((cp) => ({
      id: cp.id,
      displayName: cp.displayName,
      status: cp.status,
      location: cp.status === 'inactive' ? null : cp.location,
      activatedAt: cp.activatedAt,
      expiresAt: cp.expiresAt,
      claimedBy: cp.claimedBy,
    })),
    activeControlPointId: ps.activeControlPointId ?? null,
    nextActivationAt: ps.nextActivationAt ?? null,
    playableArea: ps.playableArea ?? [],
    controlPointRadiusMeters: config.controlPointRadiusMeters ?? 15,
    tagRangeMeters: config.tagRangeMeters ?? 5,
    missionTimeoutSec: config.missionTimeoutSec ?? 15,
    cpActivationIntervalSec: config.cpActivationIntervalSec ?? 90,
    cpLifespanSec: config.cpLifespanSec ?? 60,
    bodyAttributes: BODY_ATTRIBUTES,
    // 신체정보 입력한 사람 ID 목록 (정체 노출은 안 됨, 입력 진행률 표시용)
    bodyProfileSubmittedUserIds: Object.keys(ps.bodyProfiles ?? {}),
    timeLimitSec: config.timeLimitSec ?? 1200,
    winCondition: enrichWinCondition(ps),
    // 게임 종료 후에는 정체 전부 공개 (scoreboard).
    scoreboard: gameState.status === 'finished' ? getFinalScoreboard(ps) : null,
  };
}

// winCondition 에 winner nickname/colorLabel 추가 (UI 즉시 표시용).
function enrichWinCondition(ps) {
  const win = ps.winCondition;
  if (!win) return null;
  const winnerId = win.winner;
  const winnerPlayer = winnerId ? ps.playerStates?.[winnerId] : null;
  return {
    ...win,
    winnerNickname: winnerPlayer?.nickname ?? null,
    winnerColorLabel: winnerPlayer?.colorLabel ?? null,
    winnerColorHex: winnerPlayer?.colorHex ?? null,
  };
}

export function getPrivateState(gameState, userId) {
  const ps = gameState.pluginState ?? {};
  const player = (ps.playerStates ?? {})[userId];
  if (!player) {
    return {
      colorId: null,
      colorLabel: null,
      colorHex: null,
      targetColorId: null,
      targetColorLabel: null,
      targetColorHex: null,
      isAlive: false,
    };
  }

  const active = player.activeMission;
  const myProfile = (ps.bodyProfiles ?? {})[userId] ?? {};
  const candidatePool = Array.isArray(player.candidatePool) ? player.candidatePool : [];

  // candidatePool 멤버 nickname 매핑 (클라이언트가 멤버 ID → 이름 변환 안 해도 되도록)
  const candidates = candidatePool
    .map((uid) => {
      const c = ps.playerStates?.[uid];
      return c ? { userId: uid, nickname: c.nickname ?? uid } : null;
    })
    .filter(Boolean);

  return {
    colorId: player.colorId,
    colorLabel: player.colorLabel,
    colorHex: player.colorHex,
    // ⚠️ targetUserId 는 클라이언트에 노출하지 않는다.
    //    cc:tag_target 검증은 서버에서 수행한다.
    targetColorId: player.targetColorId,
    targetColorLabel: player.targetColorLabel,
    targetColorHex: player.targetColorHex,
    isAlive: player.isAlive,
    missionsCompleted: player.missionsCompleted ?? 0,
    activeMission: active
      ? {
          cpId: active.cpId,
          word: active.word,
          startedAt: active.startedAt,
          expiresAt: active.expiresAt,
        }
      : null,
    // Phase 5: 본인 신체정보 + 누적 힌트 + 현재 후보군
    myBodyProfile: myProfile,
    myBodyProfileComplete:
      Object.keys(myProfile).length === Object.keys(BODY_ATTRIBUTES).length,
    unlockedHints: Array.isArray(player.unlockedHints) ? player.unlockedHints : [],
    candidates,
  };
}

export function checkWinCondition(gameState) {
  return evaluateWinCondition(gameState);
}

export { getFinalScoreboard };

export async function handleEvent(eventName, payload, ctx) {
  if (eventName === 'tag_target') {
    return processTagAttempt({
      gameState: ctx.gameState,
      sessionId: ctx.sessionId,
      attackerId: ctx.userId,
      targetUserId: payload?.targetUserId,
    });
  }
  if (eventName === 'mission_start') {
    return startMission({
      gameState: ctx.gameState,
      sessionId: ctx.sessionId,
      userId: ctx.userId,
      cpId: payload?.cpId,
    });
  }
  if (eventName === 'mission_submit') {
    return submitMission({
      gameState: ctx.gameState,
      userId: ctx.userId,
      answer: payload?.answer,
    });
  }
  if (eventName === 'set_body_profile') {
    const ps = ctx.gameState.pluginState ?? {};
    const sanitized = sanitizeBodyProfile(payload?.profile);
    ps.bodyProfiles = ps.bodyProfiles ?? {};
    ps.bodyProfiles[ctx.userId] = sanitized;
    return {
      ok: true,
      profile: sanitized,
      missingAttributes: Object.keys(BODY_ATTRIBUTES).filter(
        (k) => !(k in sanitized),
      ),
    };
  }
  return false;
}

// fantasy_wars 와 동일하게 config 폴백 제공.
export function resolveConfig(config = {}) {
  return { ...defaultConfig, ...config };
}
