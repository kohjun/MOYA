'use strict';

import { defaultConfig } from './schema.js';
import { inheritTargetOnElimination } from './state.js';
import { pruneCandidatePools } from './hint.js';
import { getSessionSnapshot, haversineMeters } from '../../../services/locationService.js';

// 처치 결과 타입:
//   - 'success'       : 정답 타겟 → target 사망, 내 새 타겟 갱신
//   - 'wrong'         : 오답 → 본인 사망 (selfKillOnWrongTag)
//   - 'out_of_range'  : 거리 초과 (state 변경 없음)
//   - 'stale_location': GPS 신선도 부족
//   - 'invalid'       : 자기자신/이미 죽은 사람/세션 외 등

export async function processTagAttempt({
  gameState,
  sessionId,
  attackerId,
  targetUserId,
}) {
  const ps = gameState.pluginState ?? {};
  const config = { ...defaultConfig, ...(ps._config ?? {}) };

  if (gameState.status !== 'in_progress') {
    return { ok: false, error: 'GAME_NOT_IN_PROGRESS' };
  }

  if (!targetUserId || attackerId === targetUserId) {
    return { ok: false, error: 'INVALID_TARGET' };
  }

  const attacker = ps.playerStates?.[attackerId];
  const target = ps.playerStates?.[targetUserId];
  if (!attacker || !target) {
    return { ok: false, error: 'PLAYER_NOT_IN_SESSION' };
  }
  if (!attacker.isAlive) {
    return { ok: false, error: 'ATTACKER_DEAD' };
  }
  if (!target.isAlive) {
    return { ok: false, error: 'TARGET_ALREADY_DEAD' };
  }

  // ── GPS 검증 ─────────────────────────────────────────────────────────────
  const snapshot = await getSessionSnapshot(sessionId, [attackerId, targetUserId]);
  const a = snapshot[attackerId];
  const t = snapshot[targetUserId];
  if (!a || !t) {
    return { ok: false, error: 'LOCATION_UNAVAILABLE' };
  }

  const now = Date.now();
  const freshnessMs = config.locationFreshnessMs;
  if (
    typeof a.ts !== 'number' ||
    typeof t.ts !== 'number' ||
    now - a.ts > freshnessMs ||
    now - t.ts > freshnessMs
  ) {
    return { ok: false, error: 'LOCATION_STALE' };
  }

  const accuracyMax = config.locationAccuracyMaxMeters;
  const accuracyOk = (loc) =>
    loc?.accuracy == null ||
    (Number.isFinite(loc.accuracy) && loc.accuracy <= accuracyMax);
  if (!accuracyOk(a) || !accuracyOk(t)) {
    return { ok: false, error: 'LOCATION_INACCURATE' };
  }

  const distance = haversineMeters(a.lat, a.lng, t.lat, t.lng);
  if (distance > config.tagRangeMeters) {
    return {
      ok: false,
      error: 'OUT_OF_RANGE',
      distanceMeters: Math.round(distance),
      tagRangeMeters: config.tagRangeMeters,
    };
  }

  // ── 정답 / 오답 판정 ─────────────────────────────────────────────────────
  const isCorrectTarget = attacker.targetUserId === targetUserId;

  if (isCorrectTarget) {
    return applyElimination({
      gameState,
      deceasedId: targetUserId,
      killedBy: attackerId,
      reason: 'tagged',
      success: true,
      distanceMeters: Math.round(distance),
    });
  }

  // 오답 — 오발 페널티
  if (config.selfKillOnWrongTag) {
    return applyElimination({
      gameState,
      deceasedId: attackerId,
      killedBy: attackerId,
      reason: 'wrong_tag',
      wrongTargetId: targetUserId,
      success: false,
      distanceMeters: Math.round(distance),
    });
  }

  // selfKillOnWrongTag = false 인 경우 단순 거부
  return {
    ok: true,
    success: false,
    eliminatedUserId: null,
    distanceMeters: Math.round(distance),
  };
}

// 사망 처리 + 타겟 상속 + alivePlayerIds 갱신.
function applyElimination({
  gameState,
  deceasedId,
  killedBy,
  reason,
  wrongTargetId = null,
  success,
  distanceMeters,
}) {
  const ps = gameState.pluginState;
  const deceased = ps.playerStates[deceasedId];
  const newTargetUserId = deceased.targetUserId;

  inheritTargetOnElimination(ps, deceasedId);

  deceased.isAlive = false;
  deceased.eliminatedAt = Date.now();
  deceased.eliminatedBy = killedBy;
  deceased.eliminationReason = reason;
  deceased.targetUserId = null;

  if (!ps.eliminatedPlayerIds.includes(deceasedId)) {
    ps.eliminatedPlayerIds.push(deceasedId);
  }
  gameState.alivePlayerIds = gameState.alivePlayerIds.filter(
    (id) => id !== deceasedId,
  );

  // 모든 살아있는 플레이어의 candidatePool 에서 사망자 제거.
  pruneCandidatePools(ps, deceasedId);

  // 살아있는 사람의 새 타겟 (상속 결과 — 시각적 알림용)
  // killedBy 가 attacker 인 정상 케이스에서만 의미 있음.
  let attackerNewTargetColor = null;
  if (success && killedBy && killedBy !== deceasedId) {
    const attacker = ps.playerStates[killedBy];
    if (attacker?.isAlive) {
      // 정답 처치만 tagCount 증가. 오발(자살)은 카운트 안 함.
      attacker.tagCount = (attacker.tagCount ?? 0) + 1;
      attackerNewTargetColor = {
        targetColorId: attacker.targetColorId,
        targetColorLabel: attacker.targetColorLabel,
        targetColorHex: attacker.targetColorHex,
      };
    }
  }

  return {
    ok: true,
    success,
    eliminatedUserId: deceasedId,
    eliminatedColorId: deceased.colorId,
    eliminatedColorLabel: deceased.colorLabel,
    killedBy,
    reason,
    wrongTargetId,
    inheritedTargetUserId: newTargetUserId,
    attackerNewTargetColor,
    distanceMeters,
  };
}
