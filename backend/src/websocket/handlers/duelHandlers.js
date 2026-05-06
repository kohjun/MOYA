import { duelService } from '../../game/duel/DuelService.js';
import { recordProximityPayload } from '../../game/duel/ProximityEvidence.js';
import * as AIDirector from '../../ai/AIDirector.js';
import { cancelCaptureForPlayer } from '../../game/plugins/fantasy_wars_artifact/captureState.js';
import { cancelCaptureTimer } from '../../game/plugins/fantasy_wars_artifact/capture.js';
import { runExclusive } from '../../game/plugins/fantasy_wars_artifact/mutex.js';
import { clearMajorityHoldTimer } from '../../game/plugins/fantasy_wars_artifact/winFlow.js';
import { GamePluginRegistry } from '../../game/index.js';
import { getMediaServer } from '../../media/MediaServer.js';
import { readGameState, saveGameState, syncMediaRoomState } from '../socketRuntime.js';
import { markResult, traceAsync } from '../../observability/tracing.js';
import { EVENTS } from '../socketProtocol.js';
import {
  emitPluginStateUpdate,
  emitFantasyWarsDuelLog,
  buildFantasyWarsDuelLog,
  setDuelLockState,
  validateFantasyWarsDuelPair,
} from './gameHandlers.helpers.js';

// Test seams: default to production providers above. Tests can swap these via the
// _set*ForTest exports and reset by passing null. winFlow.js와 동일한 패턴.
let readGameStateImpl = readGameState;
let saveGameStateImpl = saveGameState;
let mediaServerProvider = () => getMediaServer();
let syncMediaRoomStateImpl = syncMediaRoomState;
let aiDirectorImpl = AIDirector;

export function _setReadGameStateForTest(fn) {
  readGameStateImpl = fn ?? readGameState;
}
export function _setSaveGameStateForTest(fn) {
  saveGameStateImpl = fn ?? saveGameState;
}
export function _setMediaServerProviderForTest(fn) {
  mediaServerProvider = fn ?? (() => getMediaServer());
}
export function _setSyncMediaRoomStateForTest(fn) {
  syncMediaRoomStateImpl = fn ?? syncMediaRoomState;
}
export function _setAIDirectorForTest(impl) {
  aiDirectorImpl = impl ?? AIDirector;
}

// onDuelResolve: DuelService 가 verdict 확정 시 호출하는 콜백.
// closure-bound 의존성은 io 한 가지뿐이라 module-level export 로 분리해 직접 테스트 가능하게 둔다.
// runExclusive scope, emit 순서, payload 는 inline 정의 시점과 완전히 동일.
export async function onDuelResolve({
  duelId,
  challengerId,
  targetId,
  winnerId,
  loserId,
  sessionId: sid,
  reason,
  minigameType,
}, { io }) {
  if (!winnerId || !loserId) {
    const participantIds = [challengerId, targetId].filter(Boolean);
    const lockResult = participantIds.length > 0
      ? await setDuelLockState(io, sid, participantIds, false)
      : null;
    const logState = lockResult?.gameState ?? await readGameStateImpl(sid);
    emitFantasyWarsDuelLog(
      io,
      sid,
      buildFantasyWarsDuelLog(logState, {
        stage: 'resolved',
        duelId,
        challengerId,
        targetId,
        winnerId,
        loserId,
        minigameType,
        reason,
      }),
    );
    aiDirectorImpl.fwOnDuelDraw({ roomId: sid }, minigameType ?? '?').then((message) => {
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
    const gs = await readGameStateImpl(sid);
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
      ps.pendingVictory = null;
      gs.status = 'finished';
      gs.finishedAt = Date.now();
    }

    await saveGameStateImpl(sid, gs);
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
      clearMajorityHoldTimer(sid);
      const mediaRoom = mediaServerProvider()?.getRoom(sid);
      if (mediaRoom) {
        syncMediaRoomStateImpl(sid, mediaRoom).catch((err) => {
          console.error('[FW] voice resync on duel-triggered game end failed:', err);
        });
      }
      aiDirectorImpl.fwOnGameEnd(
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
      aiDirectorImpl.fwOnDuelResult(
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
}

export const registerDuelHandlers = ({ io, socket, userId, transport }) => {

  socket.on(EVENTS.FW_DUEL_CHALLENGE, async (payload, cb) => traceAsync(
    'fw.duel.challenge',
    { 'fw.event': 'duel_challenge' },
    async (span) => {
    const respond = typeof cb === 'function' ? cb : () => {};
    const sessionId = payload?.sessionId || socket.currentSessionId;
    const targetId = payload?.targetUserId;
    if (!sessionId || !targetId) {
      const response = { ok: false, error: 'MISSING_FIELDS' };
      markResult(span, response);
      respond(response);
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
      markResult(span, validation);
      respond(validation);
      return;
    }

    const result = duelService.challenge({
      challengerId: userId,
      targetId,
      sessionId,
      transport,
      onResolve: (args) => onDuelResolve({ ...args, sessionId }, { io }),
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
    const response = {
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
    };
    markResult(span, response);
    respond(response);
  }));

  socket.on(EVENTS.FW_DUEL_ACCEPT, async (payload, cb) => traceAsync(
    'fw.duel.accept',
    { 'fw.event': 'duel_accept' },
    async (span) => {
    const respond = typeof cb === 'function' ? cb : () => {};
    const { duelId } = payload ?? {};
    if (!duelId) {
      const response = { ok: false, error: 'MISSING_DUEL_ID' };
      markResult(span, response);
      respond(response);
      return;
    }

    const duel = duelService.getDuel(duelId);
    if (!duel) {
      const response = { ok: false, error: 'DUEL_NOT_PENDING' };
      markResult(span, response);
      respond(response);
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
      markResult(span, validation);
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
    const response = {
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
    };
    markResult(span, response);
    respond(response);
  }));

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

  socket.on(EVENTS.FW_DUEL_PLAY_STARTED, async (payload, cb) => {
    const respond = typeof cb === 'function' ? cb : () => {};
    const { duelId } = payload ?? {};
    if (!duelId) {
      respond({ ok: false, error: 'MISSING_DUEL_ID' });
      return;
    }
    // accept 시점에 setDuelLockState 가 (acceptTime + gameTimeoutMs) 로 duelExpiresAt 을
    // 걸어두는데, 본 게임 타이머는 markPlayStarted 가 가동한다 (VS+briefing 약 15s 뒤).
    // 그 결과 [acceptTime + 30s, playArmedTime + 30s] 윈도우에서는 서버 락이 만료된 것으로
    // 보여 priest shield 등 inDuel-게이트 보호 스킬이 결투 참가자에게 적용될 수 있다.
    // 첫 arm 에서 startedAt 이 갱신되면 같은 두 참가자에 대해 락의 expiry 도 같이 옮긴다.
    const result = duelService.markPlayStarted({ duelId, userId });
    if (result.ok && result.alreadyStarted === false) {
      const duel = duelService.getDuel(duelId);
      if (duel?.sessionId) {
        await setDuelLockState(
          io,
          duel.sessionId,
          [duel.challengerId, duel.targetId].filter(Boolean),
          true,
          (result.startedAt ?? Date.now()) + (result.gameTimeoutMs ?? 30_000),
        );
      }
    }
    respond(result);
  });

  socket.on(EVENTS.FW_DUEL_SUBMIT, async (payload, cb) => traceAsync(
    'fw.duel.submit',
    { 'fw.event': 'duel_submit' },
    async (span) => {
    const respond = typeof cb === 'function' ? cb : () => {};
    const { duelId, result } = payload ?? {};
    if (!duelId || result === undefined) {
      const response = { ok: false, error: 'MISSING_FIELDS' };
      markResult(span, response);
      respond(response);
      return;
    }
    const response = await duelService.submit({ duelId, userId, result });
    markResult(span, response);
    respond(response);
  }));

  // 턴 기반 미니게임용 액션 진입점 (RR pull 등). action 페이로드는 미니게임별 schema.
  socket.on(EVENTS.FW_DUEL_ACTION, async (payload, cb) => traceAsync(
    'fw.duel.action',
    { 'fw.event': 'duel_action' },
    async (span) => {
      const respond = typeof cb === 'function' ? cb : () => {};
      const { duelId, action } = payload ?? {};
      if (!duelId || !action || typeof action !== 'object') {
        const response = { ok: false, error: 'MISSING_FIELDS' };
        markResult(span, response);
        respond(response);
        return;
      }
      const response = await duelService.submitAction({ duelId, userId, action });
      markResult(span, response);
      respond(response);
    },
  ));
};
