'use strict';

import { defaultConfig, MISSION_WORDS } from './schema.js';
import { getSessionSnapshot, haversineMeters } from '../../../services/locationService.js';
import { unlockHintForPlayer } from './hint.js';

// 미션 시작:
//   1. 게임 진행 + 본인 생존 확인
//   2. cpId 존재 + cp.status === 'active' 확인 (선점 race)
//   3. GPS 검증 + 거점 반경 (controlPointRadiusMeters) 이내
//   4. 이미 활성 미션 있으면 거부 (한 번에 하나만)
//   5. 무작위 단어 발급, activeMission 저장, expiresAt 설정
export async function startMission({ gameState, sessionId, userId, cpId }) {
  const ps = gameState.pluginState ?? {};
  const config = { ...defaultConfig, ...(ps._config ?? {}) };

  if (gameState.status !== 'in_progress') {
    return { ok: false, error: 'GAME_NOT_IN_PROGRESS' };
  }
  const player = ps.playerStates?.[userId];
  if (!player) return { ok: false, error: 'PLAYER_NOT_IN_SESSION' };
  if (!player.isAlive) return { ok: false, error: 'PLAYER_DEAD' };

  const cp = (ps.controlPoints ?? []).find((c) => c.id === cpId);
  if (!cp) return { ok: false, error: 'CONTROL_POINT_NOT_FOUND' };

  // 재설계: 활성 상태인 거점만 미션 시작 가능. 만료/이미 잡힘은 거부.
  if (cp.status !== 'active') {
    return { ok: false, error: 'CONTROL_POINT_NOT_ACTIVE', status: cp.status };
  }

  if (player.activeMission) {
    return { ok: false, error: 'MISSION_ALREADY_ACTIVE' };
  }

  const now = Date.now();
  if (cp.expiresAt && now > cp.expiresAt) {
    return { ok: false, error: 'CONTROL_POINT_EXPIRED' };
  }

  // GPS 검증
  const snapshot = await getSessionSnapshot(sessionId, [userId]);
  const loc = snapshot[userId];
  if (!loc) return { ok: false, error: 'LOCATION_UNAVAILABLE' };
  if (typeof loc.ts !== 'number' || now - loc.ts > config.locationFreshnessMs) {
    return { ok: false, error: 'LOCATION_STALE' };
  }

  const distance = haversineMeters(loc.lat, loc.lng, cp.location.lat, cp.location.lng);
  if (distance > config.controlPointRadiusMeters) {
    return {
      ok: false,
      error: 'OUT_OF_RANGE',
      distanceMeters: Math.round(distance),
      radiusMeters: config.controlPointRadiusMeters,
    };
  }

  const word = MISSION_WORDS[Math.floor(Math.random() * MISSION_WORDS.length)];
  const timeoutMs = (config.missionTimeoutSec ?? 15) * 1000;
  const expiresAt = now + timeoutMs;

  player.activeMission = {
    cpId,
    word,
    startedAt: now,
    expiresAt,
  };

  return {
    ok: true,
    cpId,
    word,
    expiresAt,
    timeoutMs,
  };
}

// 미션 제출:
//   1. 활성 미션 확인
//   2. expiresAt 안에 제출했는지
//   3. word 정확히 일치 (공백 trim)
//   4. 거점이 아직 'active' 인지 (race: 다른 사람이 먼저 claim 했을 수 있음)
//   5. 성공 → cp.status='claimed', missionsCompleted++, hint 1개 unlock
//   6. 실패/timeout/이미 claimed → activeMission 만 클리어
export function submitMission({ gameState, userId, answer }) {
  const ps = gameState.pluginState ?? {};
  const player = ps.playerStates?.[userId];
  if (!player) return { ok: false, error: 'PLAYER_NOT_IN_SESSION' };

  const active = player.activeMission;
  if (!active) return { ok: false, error: 'NO_ACTIVE_MISSION' };

  player.activeMission = null;

  const now = Date.now();
  if (now > active.expiresAt) {
    return {
      ok: true,
      success: false,
      reason: 'TIMEOUT',
      cpId: active.cpId,
    };
  }

  const submitted = (answer ?? '').toString().trim();
  const expected = active.word;
  if (submitted !== expected) {
    return {
      ok: true,
      success: false,
      reason: 'WRONG_ANSWER',
      cpId: active.cpId,
      expected,
    };
  }

  // 성공 — 거점이 아직 활성 상태인지 재검증 (다른 사람이 먼저 잡았을 수 있음).
  const cp = (ps.controlPoints ?? []).find((c) => c.id === active.cpId);
  if (!cp || cp.status !== 'active') {
    return {
      ok: true,
      success: false,
      reason: 'ALREADY_CLAIMED',
      cpId: active.cpId,
    };
  }

  // 거점 즉시 claim → 다른 사람의 동시 mission_submit 차단.
  cp.status = 'claimed';
  cp.claimedBy = userId;
  cp.claimedAt = now;
  if (ps.activeControlPointId === active.cpId) {
    ps.activeControlPointId = null;
  }

  player.missionsCompleted = (player.missionsCompleted ?? 0) + 1;

  // Phase 5: 힌트 1개 unlock + candidatePool narrowing.
  const hint = unlockHintForPlayer(ps, userId);

  return {
    ok: true,
    success: true,
    cpId: active.cpId,
    missionsCompleted: player.missionsCompleted,
    hint,
    candidateCount: player.candidatePool?.length ?? 0,
  };
}
