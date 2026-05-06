'use strict';

import {
  captureValidator,
  captureHoldValidator,
  pruneCaptureIntents,
  isCaptureReady,
  scheduleCaptureComplete,
  cancelCaptureTimer,
} from './capture.js';
import {
  findControlPointById,
  clearCaptureIntents,
  clearCaptureZoneForControlPoint,
  resetCaptureState,
  cancelCaptureForPlayer,
} from './captureState.js';
import { defaultConfig } from './schema.js';
import {
  scheduleMajorityHoldTimer,
  clearMajorityHoldTimer,
  broadcastWinIfDone,
} from './winFlow.js';
import { syncPendingMajorityVictory } from './winConditions.js';
import { runExclusive } from './mutex.js';
import * as AIDirector from '../../../ai/AIDirector.js';
import { getSessionSnapshot, haversineMeters } from '../../../services/locationService.js';

function cfg(ps) {
  return ps._config ?? defaultConfig;
}

async function getControlPointPresence(sessionId, ps, cp, config, requesterUserId, guildId) {
  const playerStates = ps.playerStates ?? {};
  const memberIds = Object.keys(playerStates);
  const snapshot = await getSessionSnapshot(sessionId, memberIds);
  const now = Date.now();
  const freshnessMs = config.locationFreshnessMs ?? 45_000;
  const accuracyMaxMeters = config.locationAccuracyMaxMeters ?? 50;
  const radiusMeters = config.captureRadiusMeters ?? 30;
  const entries = [];

  memberIds.forEach((memberUserId) => {
    const player = playerStates[memberUserId];
    const location = snapshot[memberUserId];
    // 정확도가 임계값보다 나쁜(=값이 큰) 위치는 신뢰하지 않는다. accuracy가 누락된 경우는 통과시킨다.
    const accuracyOk = location?.accuracy == null
      || (Number.isFinite(location.accuracy) && location.accuracy <= accuracyMaxMeters);
    const isFresh = Boolean(
      location
      && typeof location.ts === 'number'
      && (now - location.ts) <= freshnessMs
      && accuracyOk,
    );

    let inZone = false;
    if (isFresh && cp?.location) {
      const distance = haversineMeters(location.lat, location.lng, cp.location.lat, cp.location.lng);
      inZone = distance <= radiusMeters;
    }

    entries.push({
      userId: memberUserId,
      player,
      location: location ?? null,
      isFresh,
      inZone,
    });
  });

  const requester = entries.find((entry) => entry.userId === requesterUserId) ?? null;
  const aliveInZone = entries.filter((entry) => entry.player?.isAlive && !entry.player?.inDuel && entry.inZone);
  const friendlyInZone = aliveInZone.filter((entry) => entry.player.guildId === guildId);
  const enemyInZone = aliveInZone.filter((entry) => entry.player.guildId !== guildId);

  return {
    requester,
    friendlyInZone,
    enemyInZone,
  };
}

function setCaptureIntent(ps, controlPointId, userId, ts) {
  if (!ps.captureIntents) {
    ps.captureIntents = {};
  }
  if (!ps.captureIntents[controlPointId]) {
    ps.captureIntents[controlPointId] = {};
  }

  ps.captureIntents[controlPointId][userId] = ts;
}

function markPlayersCapturing(ps, controlPointId, participantUserIds) {
  const participantSet = new Set(participantUserIds);
  Object.values(ps.playerStates ?? {}).forEach((player) => {
    if (participantSet.has(player.userId)) {
      player.captureZone = controlPointId;
    }
  });
}

export async function handleCaptureStart({ controlPointId }, ctx) {
  // dispatch에서 세션 락을 잡고 gameState를 fresh하게 읽어 ctx에 넣어주므로 여기서는 ctx.gameState를 그대로 사용한다.
  const { userId, sessionId, gameState, saveState, readState, io } = ctx;
  if (!controlPointId) {
    return { error: 'CP_NOT_FOUND' };
  }
  const ps = gameState.pluginState ?? {};
  const config = cfg(ps);
  const cp = findControlPointById(ps, controlPointId);
  if (!cp) {
    return { error: 'CP_NOT_FOUND' };
  }

  const player = (ps.playerStates ?? {})[userId];
  const presence = await getControlPointPresence(
    sessionId,
    ps,
    cp,
    config,
    userId,
    player?.guildId,
  );
  const timerKey = `${sessionId}:${controlPointId}`;

  // 다른 길드가 이미 점령 진행 중이면 capture_start 는 막는다. 방해는 별도
  // capture_disrupt 이벤트로만 가능하다.
  if (
    cp.capturingGuild
    && cp.capturingGuild !== player?.guildId
  ) {
    return { error: 'ENEMY_CAPTURE_IN_PROGRESS' };
  }

  const check = captureValidator(cp, player, {
    hasFreshLocation: presence.requester?.isFresh ?? false,
    requesterInZone: presence.requester?.inZone ?? false,
    friendlyInZoneCount: presence.friendlyInZone.length,
    enemyInZoneCount: presence.enemyInZone.length,
  });
  if (!check.ok) {
    return { error: check.error };
  }

  if (player.captureZone && player.captureZone !== controlPointId) {
    const previousCapture = cancelCaptureForPlayer(ps, userId);
    if (previousCapture?.cancelledActiveCapture) {
      cancelCaptureTimer(`${sessionId}:${previousCapture.controlPointId}`);
    }
  }

  const readyWindowMs = config.captureReadyWindowMs ?? 5000;
  const requiredUserIds = presence.friendlyInZone.map((entry) => entry.userId);
  const now = Date.now();
  setCaptureIntent(ps, controlPointId, userId, now);
  ps.captureIntents[controlPointId] = pruneCaptureIntents(
    ps.captureIntents[controlPointId],
    requiredUserIds,
    now,
    readyWindowMs,
  );
  cp.readyCount = Object.keys(ps.captureIntents[controlPointId] ?? {}).length;
  cp.requiredCount = requiredUserIds.length;

  if (cp.capturingGuild === player.guildId) {
    await saveState(gameState);
    io.to(`session:${sessionId}`).emit('fw:capture_progress', {
      controlPointId,
      guildId: player.guildId,
      readyCount: cp.readyCount,
      requiredCount: cp.requiredCount,
      intentWindowMs: readyWindowMs,
    });
    return true;
  }

  if (!isCaptureReady(ps.captureIntents[controlPointId], requiredUserIds)) {
    await saveState(gameState);
    io.to(`session:${sessionId}`).emit('fw:capture_progress', {
      controlPointId,
      guildId: player.guildId,
      readyCount: cp.readyCount,
      requiredCount: cp.requiredCount,
      intentWindowMs: readyWindowMs,
    });
    return true;
  }

  cp.capturingGuild = player.guildId;
  cp.captureStartedAt = now;
  cp.captureProgress = 0;
  cp.readyCount = 0;
  cp.requiredCount = 0;
  cp.captureParticipantUserIds = requiredUserIds;
  markPlayersCapturing(ps, controlPointId, requiredUserIds);

  await saveState(gameState);

  io.to(`session:${sessionId}`).emit('fw:capture_started', {
    controlPointId,
    guildId: player.guildId,
    userId,
    durationSec: config.captureDurationSec,
    startedAt: cp.captureStartedAt,
  });

  const captureDurationMs = (config.captureDurationSec ?? 30) * 1000;
  const captureGuildId = player.guildId;

  scheduleCaptureComplete(timerKey, captureDurationMs, () => runExclusive(
    `fw:session:${sessionId}`,
    async () => {
    const fresh = await readState();
    if (!fresh) {
      return;
    }

    const freshPluginState = fresh.pluginState ?? {};
    const freshCp = (freshPluginState.controlPoints ?? []).find((point) => point.id === controlPointId);
    if (!freshCp || freshCp.capturingGuild !== captureGuildId) {
      return;
    }

    const freshPresence = await getControlPointPresence(
      sessionId,
      freshPluginState,
      freshCp,
      freshPluginState._config ?? config,
      userId,
      captureGuildId,
    );
    const holdCheck = captureHoldValidator(freshCp, {
      friendlyInZoneCount: freshPresence.friendlyInZone.length,
      enemyInZoneCount: freshPresence.enemyInZone.length,
    });
    if (!holdCheck.ok) {
      resetCaptureState(freshPluginState, freshCp, controlPointId, captureGuildId);
      await saveState(fresh);
      io.to(`session:${sessionId}`).emit('fw:capture_cancelled', {
        controlPointId,
        reason: holdCheck.error,
        interruptedByGuild: freshPresence.enemyInZone[0]?.player?.guildId ?? null,
      });
      return;
    }

    freshCp.capturedBy = captureGuildId;
    freshCp.capturingGuild = null;
    freshCp.captureProgress = 100;
    freshCp.captureStartedAt = null;
    freshCp.readyCount = 0;
    freshCp.requiredCount = 0;
    freshCp.lastCaptureAt = Date.now();
    freshCp.captureParticipantUserIds = [];

    const guild = freshPluginState.guilds?.[captureGuildId];
    if (guild) {
      guild.score = (guild.score ?? 0) + 10;
    }

    clearCaptureZoneForControlPoint(freshPluginState, controlPointId, captureGuildId);
    clearCaptureIntents(freshPluginState, controlPointId);
    const pendingVictory = syncPendingMajorityVictory(fresh, cfg(freshPluginState));

    if (pendingVictory) {
      scheduleMajorityHoldTimer({
        sessionId,
        io,
        readState,
        saveState,
        pendingVictory,
      });
    } else {
      clearMajorityHoldTimer(sessionId);
    }

    const won = broadcastWinIfDone(fresh, io, sessionId);
    await saveState(fresh);

    io.to(`session:${sessionId}`).emit('fw:capture_complete', {
      controlPointId,
      capturedBy: captureGuildId,
      newScore: guild?.score ?? 0,
    });

    if (won) {
      return;
    }

    AIDirector.fwOnCpCaptured(
      { roomId: sessionId, pluginState: fresh.pluginState ?? {} },
      captureGuildId,
      freshCp.displayName ?? controlPointId,
    ).then((message) => {
      if (message) {
        io.to(`session:${sessionId}`).emit('game:ai_message', {
          type: 'announcement',
          message,
        });
      }
    }).catch(() => {});
    },
  ));

  return true;
}

export async function handleCaptureCancel({ controlPointId }, ctx) {
  const { userId, sessionId, gameState, saveState, io } = ctx;
  if (!controlPointId) {
    return { error: 'CP_NOT_FOUND' };
  }
  const ps = gameState.pluginState ?? {};
  const config = cfg(ps);
  const cp = findControlPointById(ps, controlPointId);
  if (!cp) {
    return { error: 'CP_NOT_FOUND' };
  }

  const player = (ps.playerStates ?? {})[userId];
  if (!player?.isAlive) {
    return { error: 'PLAYER_DEAD' };
  }

  const presence = await getControlPointPresence(
    sessionId,
    ps,
    cp,
    config,
    userId,
    player.guildId,
  );
  const requesterInZone = presence.requester?.inZone ?? false;
  if (!requesterInZone) {
    return { error: 'NOT_IN_CAPTURE_ZONE' };
  }

  // 다른 길드 점령 진행 취소는 capture_disrupt 전용 경로로 분리. 여기서는 내
  // 길드의 점령/intent 만 정리한다.
  if (cp.capturingGuild === player.guildId) {
    cancelCaptureTimer(`${sessionId}:${controlPointId}`);
    resetCaptureState(ps, cp, controlPointId, player.guildId);
  } else if (cp.capturingGuild && cp.capturingGuild !== player.guildId) {
    return { error: 'NOT_OWNER' };
  } else {
    clearCaptureIntents(ps, controlPointId);
    player.captureZone = null;
  }

  await saveState(gameState);
  io.to(`session:${sessionId}`).emit('fw:capture_cancelled', {
    controlPointId,
    userId,
    guildId: player.guildId,
  });
  return true;
}

// 다른 길드의 점령 진행을 명시적으로 방해(=취소). zone 안에 살아있는 적군이
// capture_disrupt 이벤트를 emit 했을 때만 실행된다.
export async function handleCaptureDisrupt({ controlPointId }, ctx) {
  const { userId, sessionId, gameState, saveState, io } = ctx;
  if (!controlPointId) {
    return { error: 'CP_NOT_FOUND' };
  }
  const ps = gameState.pluginState ?? {};
  const config = cfg(ps);
  const cp = findControlPointById(ps, controlPointId);
  if (!cp) {
    return { error: 'CP_NOT_FOUND' };
  }

  const player = (ps.playerStates ?? {})[userId];
  if (!player?.isAlive) {
    return { error: 'PLAYER_DEAD' };
  }
  // 결투 진행 중인 플레이어는 점령/방해 동작에서 제외 (UI 가드만으론
  // 직접 emit 우회 가능). DuelService 의 lock 경계와 동일한 제약.
  if (player.inDuel) {
    return { error: 'PLAYER_IN_DUEL' };
  }
  if (!cp.capturingGuild) {
    return { error: 'CAPTURE_NOT_ACTIVE' };
  }
  if (cp.capturingGuild === player.guildId) {
    return { error: 'NOT_ENEMY_CAPTURE' };
  }

  const presence = await getControlPointPresence(
    sessionId,
    ps,
    cp,
    config,
    userId,
    player.guildId,
  );
  if (!presence.requester?.isFresh) {
    return { error: 'LOCATION_UNAVAILABLE' };
  }
  if (!presence.requester?.inZone) {
    return { error: 'NOT_IN_CAPTURE_ZONE' };
  }

  const interruptedGuildId = cp.capturingGuild;
  cancelCaptureTimer(`${sessionId}:${controlPointId}`);
  resetCaptureState(ps, cp, controlPointId, interruptedGuildId);

  await saveState(gameState);
  io.to(`session:${sessionId}`).emit('fw:capture_cancelled', {
    controlPointId,
    reason: 'disrupted',
    interruptedBy: userId,
    interruptedByGuild: player.guildId,
    interruptedGuild: interruptedGuildId,
  });
  return true;
}
