'use strict';

import { validateSkill, applySkillEffect } from './skills.js';
import { defaultConfig } from './schema.js';
import { startRevealStream } from './revealStream.js';
import { getSessionSnapshot } from '../../../services/locationService.js';
import { resetCaptureState } from './captureState.js';
import { cancelCaptureTimer } from './capture.js';

function cfg(ps) {
  return ps._config ?? defaultConfig;
}

export async function handleUseSkill({ skill, targetUserId, controlPointId }, ctx) {
  const { socket, userId, sessionId, gameState, saveState, readState, io } = ctx;
  const ps = gameState.pluginState ?? {};
  const config = cfg(ps);
  const player = (ps.playerStates ?? {})[userId];
  if (!player?.isAlive) {
    return { error: 'PLAYER_DEAD' };
  }

  const { ok, effect, error: skillError } = validateSkill(player.job, skill);
  if (!ok) {
    return { error: skillError };
  }

  const cooldownSec = config.skillCooldowns?.[player.job] ?? 0;
  const lastUsed = player.skillUsedAt?.[skill] ?? 0;
  const remaining = cooldownSec * 1000 - (Date.now() - lastUsed);
  if (remaining > 0) {
    socket.emit('fw:skill_cooldown', {
      skill,
      remainSec: Math.ceil(remaining / 1000),
    });
    return true;
  }

  const targetPlayer = targetUserId ? (ps.playerStates ?? {})[targetUserId] : null;
  const cp = controlPointId ? (ps.controlPoints ?? []).find((point) => point.id === controlPointId) : null;
  const result = applySkillEffect(effect, {
    player,
    targetPlayer,
    cp,
    now: Date.now(),
  });

  if (result === null) {
    return { error: 'SKILL_CANNOT_APPLY' };
  }
  if (result.error) {
    return { error: result.error };
  }

  // 봉쇄가 점령 진행 중인 CP 에 걸린 경우: 봉쇄는 정상 적용되고 (skills.js 에서
  // blockadedBy/blockadeExpiresAt 세팅 완료), 그 효과로 점령이 강제 종료된다.
  // resetCaptureState + cancelCaptureTimer + fw:capture_cancelled 를 한 자리에서
  // 처리해 capture 필드 일관성을 유지하고 클라가 점령바를 즉시 풀게 한다.
  if (result.type === 'blockade' && result.disrupted && cp) {
    cancelCaptureTimer(`${sessionId}:${cp.id}`);
    resetCaptureState(ps, cp, cp.id, result.interruptedGuild);
    io.to(`session:${sessionId}`).emit('fw:capture_cancelled', {
      controlPointId: cp.id,
      reason: 'blockaded',
      interruptedBy: userId,
      interruptedByGuild: player.guildId,
      interruptedGuild: result.interruptedGuild,
    });
  }

  if (!player.skillUsedAt) {
    player.skillUsedAt = {};
  }
  player.skillUsedAt[skill] = Date.now();

  await saveState(gameState);

  socket.emit('fw:skill_used', { skill, effect, result });
  if (result.type === 'reveal' && result.targetUserId) {
    const snapshot = await getSessionSnapshot(sessionId, [result.targetUserId]);
    const location = snapshot[result.targetUserId];
    if (location) {
      socket.emit('location:changed', {
        userId: result.targetUserId,
        sessionId,
        ...location,
        visibility: 'revealed',
      });
    }
    // Reveal 중에는 target GPS 갱신 빈도와 무관하게 viewer 마커가 따라가도록
    // 2.5s 주기로 마지막 알려진 위치를 재방송. revealUntil 만료 시 자동 종료.
    startRevealStream({
      io,
      sessionId,
      viewerUserId: userId,
      targetUserId: result.targetUserId,
      revealUntil: result.revealUntil,
      readState,
    });
  }
  io.to(`session:${sessionId}`).emit('fw:player_skill', {
    userId,
    skill,
    job: player.job,
    result,
  });

  return true;
}
