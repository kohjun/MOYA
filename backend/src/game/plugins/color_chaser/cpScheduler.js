'use strict';

import { defaultConfig } from './schema.js';

// 거점 활성화 / 만료 로직 (state mutation only).
// setTimeout 등록은 핸들러 측 (colorChaserHandlers.js) 에서 수행.

// inactive 상태인 거점 중 무작위 1개를 active 로 전환.
// 활성 거점이 이미 있으면 noop. 모든 거점이 소비됐으면 null.
export function activateNextControlPoint(pluginState, now = Date.now()) {
  const config = { ...defaultConfig, ...(pluginState._config ?? {}) };
  const lifespanMs = (config.cpLifespanSec ?? 60) * 1000;

  if (pluginState.activeControlPointId) {
    return null; // 이미 활성 거점 있음
  }

  const candidates = (pluginState.controlPoints ?? []).filter(
    (cp) => cp.status === 'inactive',
  );
  if (candidates.length === 0) {
    return null; // 모두 소비됨
  }

  const chosen = candidates[Math.floor(Math.random() * candidates.length)];
  chosen.status = 'active';
  chosen.activatedAt = now;
  chosen.expiresAt = now + lifespanMs;

  pluginState.activeControlPointId = chosen.id;
  // nextActivationAt 은 expire 또는 claim 직후 핸들러가 설정.
  pluginState.nextActivationAt = null;

  return chosen;
}

// 활성 거점이 expiresAt 지나면 expired 처리. 이미 claim/expire 되었으면 noop.
export function expireActiveControlPointIfNeeded(pluginState, now = Date.now()) {
  const activeId = pluginState.activeControlPointId;
  if (!activeId) return null;
  const cp = (pluginState.controlPoints ?? []).find((c) => c.id === activeId);
  if (!cp || cp.status !== 'active') {
    pluginState.activeControlPointId = null;
    return null;
  }
  if (now < (cp.expiresAt ?? 0)) {
    return null;
  }
  cp.status = 'expired';
  pluginState.activeControlPointId = null;
  return cp;
}

// 다음 활성화 시각 계산 (단순: now + cpActivationIntervalSec).
export function scheduleNextActivation(pluginState, now = Date.now()) {
  const config = { ...defaultConfig, ...(pluginState._config ?? {}) };
  const intervalMs = (config.cpActivationIntervalSec ?? 90) * 1000;
  pluginState.nextActivationAt = now + intervalMs;
  return pluginState.nextActivationAt;
}

// 진행 중인 mission 이 cp.status='claimed' 또는 'expired' 면 자동 취소.
// claim 직후 다른 플레이어들의 activeMission 정리용.
export function cancelStaleMissions(pluginState) {
  Object.values(pluginState.playerStates ?? {}).forEach((player) => {
    const am = player.activeMission;
    if (!am) return;
    const cp = (pluginState.controlPoints ?? []).find((c) => c.id === am.cpId);
    if (!cp || cp.status !== 'active') {
      player.activeMission = null;
    }
  });
}
