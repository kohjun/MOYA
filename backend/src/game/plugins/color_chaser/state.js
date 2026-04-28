'use strict';

import { pickColorsForPlayers } from './schema.js';
import { buildControlPoints } from './controlPoints.js';

// 플레이어들에게 무지개색을 무작위 배정하고 원형 연결 리스트를 만든다.
// targetUserId 는 다음 색을 가진 플레이어 (e.g. red → orange).
export function buildInitialPluginState(members, config, session = null) {
  const palette = pickColorsForPlayers(members.length);

  // 멤버 순서 셔플 (색 ↔ 사람 매핑이 매 게임 다르게).
  const shuffled = [...members].sort(() => Math.random() - 0.5);

  const playerStates = {};
  shuffled.forEach((member, index) => {
    const userId = member.user_id;
    const color = palette[index % palette.length];
    const nextIndex = (index + 1) % shuffled.length;
    const targetUserId = shuffled[nextIndex].user_id;
    const targetColor = palette[(index + 1) % palette.length];

    playerStates[userId] = {
      userId,
      nickname: member.nickname ?? userId,
      colorId: color.id,
      colorLabel: color.label,
      colorHex: color.hex,
      targetUserId,
      targetColorId: targetColor.id,
      targetColorLabel: targetColor.label,
      targetColorHex: targetColor.hex,
      isAlive: true,
      // Phase 6: 처치 카운트 (정답 처치만 카운트, 오발 제외)
      tagCount: 0,
      // Phase 4 (재설계): 미션 누적 카운트만 유지. per-CP 쿨다운은 의미 없음 (한 거점은 한 번만 잡힘).
      missionsCompleted: 0,
      activeMission: null, // { cpId, word, startedAt, expiresAt }
      // Phase 5: 힌트 narrowing
      // unlockedHints: [{ attribute, value, label, optionLabel }]
      // candidatePool: 본인 타겟 후보 userId 집합 (배열로 저장)
      // 게임 시작 시 candidatePool = 자기 자신 제외 모든 살아있는 멤버
      unlockedHints: [],
      candidatePool: shuffled
        .filter((m) => m.user_id !== userId)
        .map((m) => m.user_id),
    };
  });

  // 거점 — playable_area 가 있을 때만 생성. 없으면 빈 배열 (미션 비활성).
  const controlPoints = buildControlPoints(
    session?.playable_area,
    config.controlPointCount ?? 5,
  );

  return {
    palette,
    playerStates,
    controlPoints,
    activeControlPointId: null, // 현재 활성 거점 1개 (단일 활성)
    nextActivationAt: null,     // 다음 활성화 예정 시각 (ms)
    playableArea: Array.isArray(session?.playable_area) ? session.playable_area : [],
    eliminatedPlayerIds: [],
    winCondition: null,
    // Phase 5: userId → bodyProfile (sanitized)
    bodyProfiles: {},
    _config: config,
  };
}

// targetUserId 상속 헬퍼 (Phase 3에서 호출 예정).
// 죽은 사람을 가리키던 prev 의 targetUserId 를 deceased.targetUserId 로 갱신.
// Phase 5: 타겟이 변경된 prev 의 unlockedHints 를 reset 하고 candidatePool 재계산.
export function inheritTargetOnElimination(pluginState, deceasedUserId) {
  const deceased = pluginState.playerStates?.[deceasedUserId];
  if (!deceased) return;

  const inheritedTargetId = deceased.targetUserId;
  const inheritedTargetState = pluginState.playerStates?.[inheritedTargetId] ?? null;

  Object.values(pluginState.playerStates).forEach((player) => {
    if (player.targetUserId === deceasedUserId && player.isAlive) {
      player.targetUserId = inheritedTargetId;
      if (inheritedTargetState) {
        player.targetColorId = inheritedTargetState.colorId;
        player.targetColorLabel = inheritedTargetState.colorLabel;
        player.targetColorHex = inheritedTargetState.colorHex;
      }
      // 새 타겟이 정해졌으므로 누적 힌트 reset.
      player.unlockedHints = [];
      player.candidatePool = computeFreshCandidatePool(pluginState, player.userId);
    }
  });
}

// 살아있는 다른 플레이어들로 candidate 초기화.
export function computeFreshCandidatePool(pluginState, ownerUserId) {
  return Object.values(pluginState.playerStates ?? {})
    .filter((p) => p.isAlive && p.userId !== ownerUserId)
    .map((p) => p.userId);
}
