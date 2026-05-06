import { GamePluginRegistry } from '../../game/index.js';
import { EVENTS } from '../socketProtocol.js';
import { readGameState, saveGameState } from '../socketRuntime.js';
import { resolveDuelConfig } from '../../game/plugins/fantasy_wars_artifact/schema.js';
import { runExclusive } from '../../game/plugins/fantasy_wars_artifact/mutex.js';
import { getPairProximityEvidence } from '../../game/duel/ProximityEvidence.js';
import { getSessionSnapshot, haversineMeters } from '../../services/locationService.js';

export async function loadPluginCtx(sessionId) {
  const gameState = await readGameState(sessionId);
  if (!gameState) {
    return null;
  }

  const plugin = GamePluginRegistry.get(gameState.gameType ?? 'fantasy_wars_artifact');
  return { gameState, plugin };
}

export function emitPluginStateUpdate(io, sessionId, gameState, plugin, userIds = []) {
  const publicState = plugin.getPublicState?.(gameState) ?? {};
  io.to(`session:${sessionId}`).emit(EVENTS.GAME_STATE_UPDATE, {
    sessionId,
    gameType: gameState.gameType,
    ...publicState,
  });

  for (const targetUserId of [...new Set(userIds.filter(Boolean))]) {
    const privateState = plugin.getPrivateState?.(gameState, targetUserId) ?? {};
    io.to(`user:${targetUserId}`).emit(EVENTS.GAME_STATE_UPDATE, {
      sessionId,
      gameType: gameState.gameType,
      ...publicState,
      ...privateState,
    });
  }
}

function getFantasyWarsPlayerLabel(gameState, userId) {
  if (!userId) {
    return 'unknown player';
  }
  const nickname = gameState?.pluginState?.playerStates?.[userId]?.nickname;
  return nickname || userId;
}

export function buildFantasyWarsDuelLog(gameState, {
  stage,
  duelId,
  challengerId,
  targetId,
  winnerId,
  loserId,
  minigameType,
  reason,
}) {
  const challengerLabel = getFantasyWarsPlayerLabel(gameState, challengerId);
  const targetLabel = getFantasyWarsPlayerLabel(gameState, targetId);
  const winnerLabel = getFantasyWarsPlayerLabel(gameState, winnerId);
  const loserLabel = getFantasyWarsPlayerLabel(gameState, loserId);

  let message = `Duel | ${stage}`;
  switch (stage) {
    case 'challenged':
      message = `Duel challenged | ${challengerLabel} vs ${targetLabel}`;
      break;
    case 'started':
      message =
        `Duel started | ${challengerLabel} vs ${targetLabel}` +
        (minigameType ? ` | ${minigameType}` : '');
      break;
    case 'rejected':
      message = `Duel rejected | ${challengerLabel} vs ${targetLabel}`;
      break;
    case 'cancelled':
      message = `Duel cancelled | ${challengerLabel} vs ${targetLabel}`;
      break;
    case 'invalidated':
      message =
        `Duel invalidated | ${challengerLabel} vs ${targetLabel}` +
        (reason ? ` | ${reason}` : '');
      break;
    case 'resolved':
      message = winnerId && loserId
        ? `Duel resolved | ${winnerLabel} beat ${loserLabel}` +
            (reason ? ` | ${reason}` : '')
        : `Duel resolved | draw` + (reason ? ` | ${reason}` : '');
      break;
  }

  return {
    kind: 'duel',
    stage,
    duelId,
    challengerId,
    targetId,
    winnerId,
    loserId,
    minigameType: minigameType ?? null,
    reason: reason ?? null,
    message,
    recordedAt: Date.now(),
  };
}

export function emitFantasyWarsDuelLog(io, sessionId, payload) {
  io.to(`session:${sessionId}`).emit(EVENTS.FW_DUEL_LOG, payload);
}

function buildProximityDebugPayload(proximity, now) {
  const freshestReport = proximity.reports?.[0] ?? null;
  return {
    proximitySource: proximity.bestSource,
    bleConfirmed: proximity.bestSource === 'ble',
    gpsFallbackUsed: proximity.bestSource === 'gps_fallback',
    mutualProximity: proximity.mutual,
    recentProximityReports: proximity.reports?.length ?? 0,
    freshestEvidenceAgeMs:
      freshestReport && typeof freshestReport.seenAt === 'number'
        ? Math.max(0, Math.round(now - freshestReport.seenAt))
        : null,
  };
}

export async function validateFantasyWarsDuelPair(sessionId, challengerId, targetId) {
  const gameState = await readGameState(sessionId);
  if (!gameState) {
    return { ok: false, error: 'GAME_NOT_STARTED' };
  }

  const ps = gameState.pluginState ?? {};
  const challenger = ps.playerStates?.[challengerId];
  const target = ps.playerStates?.[targetId];
  if (!challenger || !target) {
    return { ok: false, error: 'PLAYER_NOT_IN_SESSION' };
  }
  if (!challenger.isAlive || !target.isAlive) {
    return { ok: false, error: 'PLAYER_DEAD' };
  }
  if (challenger.guildId === target.guildId) {
    return { ok: false, error: 'TARGET_NOT_ENEMY' };
  }
  // 점령 진행 중에는 결투 신청·수락이 불가능하다.
  // 점령을 먼저 취소(capture_cancel)한 뒤 결투를 시도해야 한다.
  if (challenger.captureZone) {
    return { ok: false, error: 'CHALLENGER_CAPTURING' };
  }
  if (target.captureZone) {
    return { ok: false, error: 'TARGET_CAPTURING' };
  }

  const config = ps._config ?? {};
  const duelConfig = resolveDuelConfig(config);
  const freshnessMs = duelConfig.locationFreshnessMs;
  const duelRangeMeters = duelConfig.duelRangeMeters;
  const bleEvidenceFreshnessMs = duelConfig.bleEvidenceFreshnessMs;
  const allowGpsFallbackWithoutBle = duelConfig.allowGpsFallbackWithoutBle;
  const now = Date.now();
  const snapshot = await getSessionSnapshot(sessionId, [challengerId, targetId]);
  const challengerLocation = snapshot[challengerId];
  const targetLocation = snapshot[targetId];

  if (!challengerLocation || !targetLocation) {
    return { ok: false, error: 'LOCATION_UNAVAILABLE' };
  }
  if (
    typeof challengerLocation.ts !== 'number'
    || typeof targetLocation.ts !== 'number'
    || (now - challengerLocation.ts) > freshnessMs
    || (now - targetLocation.ts) > freshnessMs
  ) {
    return { ok: false, error: 'LOCATION_STALE' };
  }

  // GPS 정확도가 임계값보다 나쁜 위치는 결투 판정에 사용하지 않는다.
  const accuracyMaxMeters = config.locationAccuracyMaxMeters
    ?? resolveDuelConfig(config).locationAccuracyMaxMeters;
  const accuracyOk = (loc) =>
    loc?.accuracy == null
      || (Number.isFinite(loc.accuracy) && loc.accuracy <= accuracyMaxMeters);
  if (!accuracyOk(challengerLocation) || !accuracyOk(targetLocation)) {
    return {
      ok: false,
      error: 'LOCATION_INACCURATE',
      challengerAccuracy: challengerLocation?.accuracy ?? null,
      targetAccuracy: targetLocation?.accuracy ?? null,
      accuracyMaxMeters,
    };
  }

  const distanceMeters = haversineMeters(
    challengerLocation.lat,
    challengerLocation.lng,
    targetLocation.lat,
    targetLocation.lng,
  );
  if (distanceMeters > duelRangeMeters) {
    return {
      ok: false,
      error: 'TARGET_OUT_OF_RANGE',
      distanceMeters: Math.round(distanceMeters),
      duelRangeMeters,
    };
  }

  const proximity = getPairProximityEvidence(
    sessionId,
    challengerId,
    targetId,
    {
      freshnessMs: bleEvidenceFreshnessMs,
      now,
    },
  );
  const proximityDebug = buildProximityDebugPayload(proximity, now);
  const { bleConfirmed } = proximityDebug;
  // GPS 폴백이 허용된 세션(에뮬레이터/실외 BLE 부재 환경)에선 GPS 거리 검증
  // (위 distanceMeters <= duelRangeMeters) 만으로 결투 신청을 허용한다. BLE
  // 강제 모드는 호스트가 명시적으로 allowGpsFallbackWithoutBle=false 로 설정한
  // 경우에만 활성화된다.
  if (!allowGpsFallbackWithoutBle && !bleConfirmed) {
    return {
      ok: false,
      error: 'BLE_PROXIMITY_REQUIRED',
      distanceMeters: Math.round(distanceMeters),
      duelRangeMeters,
      bleEvidenceFreshnessMs,
      allowGpsFallbackWithoutBle,
      ...proximityDebug,
    };
  }

  return {
    ok: true,
    gameState,
    challenger,
    target,
    distanceMeters: Math.round(distanceMeters),
    duelRangeMeters,
    bleEvidenceFreshnessMs,
    allowGpsFallbackWithoutBle,
    ...proximityDebug,
  };
}

export async function setDuelLockState(io, sessionId, participantIds, enabled, duelExpiresAt = null) {
  // 세션 락 안에서 실행되어 다른 fw 액션과 race가 차단된다.
  // 점령 중 플레이어는 결투 신청·수락 단계에서 차단되므로 여기서 점령 자동 취소 로직은 불필요.
  return runExclusive(`fw:session:${sessionId}`, async () => {
    const gameState = await readGameState(sessionId);
    if (!gameState) {
      return null;
    }

    const plugin = GamePluginRegistry.get(gameState.gameType ?? 'fantasy_wars_artifact');
    const ps = gameState.pluginState ?? {};
    participantIds.forEach((participantId) => {
      const player = ps.playerStates?.[participantId];
      if (!player) {
        return;
      }
      player.inDuel = enabled;
      player.duelExpiresAt = enabled ? duelExpiresAt : null;
    });

    await saveGameState(sessionId, gameState);
    emitPluginStateUpdate(io, sessionId, gameState, plugin, participantIds);
    return { gameState, plugin };
  });
}
