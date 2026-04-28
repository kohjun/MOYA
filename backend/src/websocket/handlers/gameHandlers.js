import { GamePluginRegistry } from '../../game/index.js';
import { startGameForSession } from '../../game/startGameService.js';
import { EVENTS } from '../socketProtocol.js';
import { readGameState, saveGameState } from '../socketRuntime.js';
import { duelService } from '../../game/duel/DuelService.js';
import { SocketTransportAdapter } from '../../game/duel/TransportAdapter.js';
import { resolveDuelConfig } from '../../game/plugins/fantasy_wars_artifact/schema.js';
import {
  getPairProximityEvidence,
  recordProximityPayload,
} from '../../game/duel/ProximityEvidence.js';
import * as AIDirector from '../../ai/AIDirector.js';
import { getSessionSnapshot, haversineMeters } from '../../services/locationService.js';
import { cancelCaptureForPlayer } from '../../game/plugins/fantasy_wars_artifact/captureState.js';
import { runExclusive } from '../../game/plugins/fantasy_wars_artifact/mutex.js';

async function loadPluginCtx(sessionId) {
  const gameState = await readGameState(sessionId);
  if (!gameState) {
    return null;
  }

  const plugin = GamePluginRegistry.get(gameState.gameType ?? 'fantasy_wars_artifact');
  return { gameState, plugin };
}

function emitPluginStateUpdate(io, sessionId, gameState, plugin, userIds = []) {
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

function buildFantasyWarsDuelLog(gameState, {
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

function emitFantasyWarsDuelLog(io, sessionId, payload) {
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

async function validateFantasyWarsDuelPair(sessionId, challengerId, targetId) {
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
  const { bleConfirmed, gpsFallbackUsed } = proximityDebug;
  if (!bleConfirmed && !(allowGpsFallbackWithoutBle && gpsFallbackUsed)) {
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

async function setDuelLockState(io, sessionId, participantIds, enabled, duelExpiresAt = null) {
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

export const registerGameHandlers = ({ io, socket, mediaServer, userId }) => {
  socket.on(EVENTS.GAME_START, async ({ sessionId: sid } = {}) => {
    const sessionId = sid || socket.currentSessionId;
    if (!sessionId) {
      return;
    }

    try {
      await startGameForSession({ io, sessionId, requesterUserId: userId });
    } catch (err) {
      console.error('[WS] game:start error:', err);
      socket.emit(EVENTS.ERROR, {
        code: err.message || 'GAME_START_FAILED',
        ...(err.details ?? {}),
      });
    }
  });

  socket.on(EVENTS.GAME_REQUEST_STATE, async ({ sessionId: sid } = {}) => {
    const sessionId = sid || socket.currentSessionId;
    if (!sessionId) {
      return;
    }

    try {
      const ctx = await loadPluginCtx(sessionId);
      if (!ctx) {
        socket.emit(EVENTS.GAME_STATE_UPDATE, { sessionId, status: 'none' });
        return;
      }

      const { gameState, plugin } = ctx;
      const publicState = plugin.getPublicState?.(gameState) ?? {};
      const privateState = plugin.getPrivateState?.(gameState, userId) ?? {};
      socket.emit(EVENTS.GAME_STATE_UPDATE, {
        sessionId,
        gameType: gameState.gameType,
        ...publicState,
        ...privateState,
      });
    } catch (err) {
      console.error('[WS] game:request_state error:', err);
    }
  });

  const dispatch = (eventName, { requireGame = true } = {}) =>
    async (payload, cb) => {
      const sessionId = payload?.sessionId || socket.currentSessionId;
      const respond = typeof cb === 'function' ? cb : () => {};
      if (!sessionId) {
        respond({ ok: false, error: 'MISSING_SESSION_ID' });
        return;
      }

      // 세션 단위 mutex로 모든 fw 액션을 직렬화한다.
      // 락 안에서 fresh state를 읽고 핸들러에 ctx.gameState로 전달하므로
      // 다른 핸들러(setDuelLockState, onDuelResolve 등)와의 race가 차단된다.
      await runExclusive(`fw:session:${sessionId}`, async () => {
        try {
          const ctx = await loadPluginCtx(sessionId);
          if (!ctx) {
            if (requireGame) {
              respond({ ok: false, error: 'GAME_NOT_STARTED' });
            }
            return;
          }

          const { gameState, plugin } = ctx;
          const result = await plugin.handleEvent(eventName, payload ?? {}, {
            io,
            socket,
            userId,
            sessionId,
            gameState,
            saveState: (gs) => saveGameState(sessionId, gs),
            readState: () => readGameState(sessionId),
            mediaServer,
          });

          if (result && typeof result === 'object' && result.error) {
            respond({ ok: false, error: result.error });
          } else if (result === false) {
            respond({ ok: false, error: 'ACTION_REJECTED' });
          } else if (result && typeof result === 'object') {
            respond({ ok: true, ...result });
          } else {
            respond({ ok: true });
          }
        } catch (err) {
          console.error(`[WS] ${eventName} error:`, err);
          respond({ ok: false, error: err.message });
        }
      });
    };

  socket.on(EVENTS.FW_CAPTURE_START, dispatch('capture_start'));
  socket.on(EVENTS.FW_CAPTURE_CANCEL, dispatch('capture_cancel'));
  socket.on(EVENTS.FW_USE_SKILL, dispatch('use_skill'));
  socket.on(EVENTS.FW_ATTACK, dispatch('attack'));
  socket.on(EVENTS.FW_REVIVE, dispatch('revive'));
  socket.on(EVENTS.FW_DUNGEON_ENTER, dispatch('dungeon_enter'));

  const transport = new SocketTransportAdapter(io);

  const onDuelResolve = async ({ duelId, winnerId, loserId, sessionId: sid, reason, minigameType }) => {
    if (!winnerId || !loserId) {
      const logState = await readGameState(sid);
      emitFantasyWarsDuelLog(
        io,
        sid,
        buildFantasyWarsDuelLog(logState, {
          stage: 'resolved',
          duelId,
          winnerId,
          loserId,
          minigameType,
          reason,
        }),
      );
      AIDirector.fwOnDuelDraw({ roomId: sid }, minigameType ?? '?').then((message) => {
        if (message) {
          io.to(`session:${sid}`).emit('game:ai_message', {
            type: 'announcement',
            message,
          });
        }
      }).catch(() => {});
      return null;
    }

    // 결투 결과 반영 구간을 세션 락으로 보호한다. 동시에 다른 fw 액션이 gameState를 만지지 못하도록 직렬화.
    return runExclusive(`fw:session:${sid}`, async () => {
    const gs = await readGameState(sid);
    if (!gs) {
      return null;
    }

    const plugin = GamePluginRegistry.get(gs.gameType ?? 'fantasy_wars_artifact');
    const ps = gs.pluginState ?? {};
    const loser = ps.playerStates?.[loserId];
    const winner = ps.playerStates?.[winnerId];
    if (!loser || !winner) {
      return null;
    }

    // 안전장치: 점령 중에는 결투 진입이 차단되지만, 클라/네트워크 엣지케이스로 도달 가능성이 있어 유지.
    if (loser.captureZone) {
      const activeCaptureId = loser.captureZone;
      const capture = cancelCaptureForPlayer(ps, loserId);
      if (capture?.cancelledActiveCapture) {
        const { cancelCaptureTimer } = await import('../../game/plugins/fantasy_wars_artifact/capture.js');
        cancelCaptureTimer(`${sid}:${activeCaptureId}`);
      }
    }

    const resolution = plugin.resolveDuelOutcome?.(gs, {
      winnerId,
      loserId,
      reason,
      minigameType,
    }) ?? {
      verdict: { winner: winnerId, loser: loserId, reason },
      effects: {},
      eliminated: false,
    };
    const resolvedWinnerId = resolution?.verdict?.winner ?? winnerId;
    const resolvedLoserId = resolution?.verdict?.loser ?? loserId;
    const resolvedReason = resolution?.verdict?.reason ?? reason;

    const win = plugin.checkWinCondition?.(gs);
    if (win) {
      ps.winCondition = win;
      gs.status = 'finished';
      gs.finishedAt = Date.now();
    }

    await saveGameState(sid, gs);
    emitPluginStateUpdate(io, sid, gs, plugin, [winnerId, loserId]);
    emitFantasyWarsDuelLog(
      io,
      sid,
      buildFantasyWarsDuelLog(gs, {
        stage: 'resolved',
        duelId,
        challengerId: resolvedWinnerId,
        targetId: resolvedLoserId,
        winnerId: resolvedWinnerId,
        loserId: resolvedLoserId,
        minigameType,
        reason: resolvedReason,
      }),
    );

    if (resolution.eliminated) {
      io.to(`session:${sid}`).emit('fw:player_eliminated', {
        userId: loserId,
        killedBy: winnerId,
        method: 'duel',
        duelReason: reason,
      });
    }

    if (win) {
      io.to(`session:${sid}`).emit('game:over', {
        winner: win.winner,
        reason: win.reason,
      });
      AIDirector.fwOnGameEnd(
        { roomId: sid, pluginState: ps },
        win.winner,
        win.reason ?? 'territory',
      ).then((message) => {
        if (message) {
          io.to(`session:${sid}`).emit('game:ai_message', {
            type: 'announcement',
            message,
          });
        }
      }).catch(() => {});
    } else {
      AIDirector.fwOnDuelResult(
        { roomId: sid, pluginState: ps },
        { userId: winnerId, nickname: winner.nickname ?? winnerId },
        { userId: loserId, nickname: loser.nickname ?? loserId },
        minigameType ?? '?',
        resolution.effects?.executionTriggered === true,
      ).then((message) => {
        if (message) {
          io.to(`session:${sid}`).emit('game:ai_message', {
            type: 'announcement',
            message,
          });
        }
      }).catch(() => {});
    }

    return resolution;
    });
  };

  socket.on(EVENTS.FW_DUEL_CHALLENGE, async (payload, cb) => {
    const respond = typeof cb === 'function' ? cb : () => {};
    const sessionId = payload?.sessionId || socket.currentSessionId;
    const targetId = payload?.targetUserId;
    if (!sessionId || !targetId) {
      respond({ ok: false, error: 'MISSING_FIELDS' });
      return;
    }

    recordProximityPayload({
      sessionId,
      observerId: userId,
      expectedTargetId: targetId,
      proximity: payload?.proximity,
    });

    const validation = await validateFantasyWarsDuelPair(sessionId, userId, targetId);
    if (!validation.ok) {
      respond(validation);
      return;
    }

    const result = duelService.challenge({
      challengerId: userId,
      targetId,
      sessionId,
      transport,
      onResolve: (args) => onDuelResolve({ ...args, sessionId }),
      onInvalidate: async (args) => {
        // 결투가 무효화되면 양 플레이어의 inDuel 잠금을 풀어 점령/이동을 재개시킨다.
        // (start_game/accept 시점의 setDuelLockState(true)와 짝)
        await setDuelLockState(
          io,
          sessionId,
          [args.challengerId, args.targetId].filter(Boolean),
          false,
        );
        const logState = await readGameState(sessionId);
        emitFantasyWarsDuelLog(
          io,
          sessionId,
          buildFantasyWarsDuelLog(logState, {
            stage: 'invalidated',
            duelId: args.duelId,
            challengerId: args.challengerId,
            targetId: args.targetId,
            reason: args.reason,
          }),
        );
      },
    });
    if (result.ok) {
      const logState = await readGameState(sessionId);
      emitFantasyWarsDuelLog(
        io,
        sessionId,
        buildFantasyWarsDuelLog(logState, {
          stage: 'challenged',
          duelId: result.duelId,
          challengerId: userId,
          targetId,
        }),
      );
    }
    respond({
      ...result,
      distanceMeters: validation.distanceMeters,
      proximitySource: validation.proximitySource,
      bleConfirmed: validation.bleConfirmed,
      gpsFallbackUsed: validation.gpsFallbackUsed,
      mutualProximity: validation.mutualProximity,
      recentProximityReports: validation.recentProximityReports,
      freshestEvidenceAgeMs: validation.freshestEvidenceAgeMs,
      duelRangeMeters: validation.duelRangeMeters,
      bleEvidenceFreshnessMs: validation.bleEvidenceFreshnessMs,
      allowGpsFallbackWithoutBle: validation.allowGpsFallbackWithoutBle,
    });
  });

  socket.on(EVENTS.FW_DUEL_ACCEPT, async (payload, cb) => {
    const respond = typeof cb === 'function' ? cb : () => {};
    const { duelId } = payload ?? {};
    if (!duelId) {
      respond({ ok: false, error: 'MISSING_DUEL_ID' });
      return;
    }

    const duel = duelService.getDuel(duelId);
    if (!duel) {
      respond({ ok: false, error: 'DUEL_NOT_PENDING' });
      return;
    }

    recordProximityPayload({
      sessionId: duel.sessionId,
      observerId: userId,
      expectedTargetId: duel.challengerId,
      proximity: payload?.proximity,
    });

    const validation = await validateFantasyWarsDuelPair(
      duel.sessionId,
      duel.challengerId,
      duel.targetId,
    );
    if (!validation.ok) {
      duelService.invalidate(duelId, validation.error);
      respond(validation);
      return;
    }

    const result = duelService.accept({ duelId, userId });
    if (result.ok) {
      await setDuelLockState(
        io,
        duel.sessionId,
        [duel.challengerId, duel.targetId],
        true,
        (result.startedAt ?? Date.now()) + (result.gameTimeoutMs ?? 30_000),
      );
      const logState = await readGameState(duel.sessionId);
      emitFantasyWarsDuelLog(
        io,
        duel.sessionId,
        buildFantasyWarsDuelLog(logState, {
          stage: 'started',
          duelId,
          challengerId: duel.challengerId,
          targetId: duel.targetId,
          minigameType: duel.minigameType,
        }),
      );
    }
    respond({
      ...result,
      distanceMeters: validation.distanceMeters,
      proximitySource: validation.proximitySource,
      bleConfirmed: validation.bleConfirmed,
      gpsFallbackUsed: validation.gpsFallbackUsed,
      mutualProximity: validation.mutualProximity,
      recentProximityReports: validation.recentProximityReports,
      freshestEvidenceAgeMs: validation.freshestEvidenceAgeMs,
      duelRangeMeters: validation.duelRangeMeters,
      bleEvidenceFreshnessMs: validation.bleEvidenceFreshnessMs,
      allowGpsFallbackWithoutBle: validation.allowGpsFallbackWithoutBle,
    });
  });

  socket.on(EVENTS.FW_DUEL_REJECT, async (payload, cb) => {
    const respond = typeof cb === 'function' ? cb : () => {};
    const { duelId } = payload ?? {};
    if (!duelId) {
      respond({ ok: false, error: 'MISSING_DUEL_ID' });
      return;
    }
    const duel = duelService.getDuel(duelId);
    const result = duelService.reject({ duelId, userId });
    if (result.ok && duel) {
      const logState = await readGameState(duel.sessionId);
      emitFantasyWarsDuelLog(
        io,
        duel.sessionId,
        buildFantasyWarsDuelLog(logState, {
          stage: 'rejected',
          duelId,
          challengerId: duel.challengerId,
          targetId: duel.targetId,
        }),
      );
    }
    respond(result);
  });

  socket.on(EVENTS.FW_DUEL_CANCEL, async (payload, cb) => {
    const respond = typeof cb === 'function' ? cb : () => {};
    const { duelId } = payload ?? {};
    if (!duelId) {
      respond({ ok: false, error: 'MISSING_DUEL_ID' });
      return;
    }
    const duel = duelService.getDuel(duelId);
    const result = duelService.cancel({ duelId, userId });
    if (result.ok && duel) {
      const logState = await readGameState(duel.sessionId);
      emitFantasyWarsDuelLog(
        io,
        duel.sessionId,
        buildFantasyWarsDuelLog(logState, {
          stage: 'cancelled',
          duelId,
          challengerId: duel.challengerId,
          targetId: duel.targetId,
        }),
      );
    }
    respond(result);
  });

  socket.on(EVENTS.FW_DUEL_SUBMIT, async (payload, cb) => {
    const respond = typeof cb === 'function' ? cb : () => {};
    const { duelId, result } = payload ?? {};
    if (!duelId || result === undefined) {
      respond({ ok: false, error: 'MISSING_FIELDS' });
      return;
    }
    respond(await duelService.submit({ duelId, userId, result }));
  });

  socket.once('disconnect', async () => {
    const duel = duelService.getDuelForUser(userId);
    const shouldClearDuelLock = duel?.status === 'in_game';
    duelService.handleDisconnect(userId);
    if (duel && shouldClearDuelLock) {
      await setDuelLockState(
        io,
        duel.sessionId,
        [duel.challengerId, duel.targetId],
        false,
      );
    }
  });
};
