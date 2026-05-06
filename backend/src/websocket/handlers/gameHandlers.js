import { startGameForSession } from '../../game/startGameService.js';
import { EVENTS } from '../socketProtocol.js';
import { readGameState, saveGameState } from '../socketRuntime.js';
import { duelService } from '../../game/duel/DuelService.js';
import { SocketTransportAdapter } from '../../game/duel/TransportAdapter.js';
import { runExclusive } from '../../game/plugins/fantasy_wars_artifact/mutex.js';
import { markResult, traceAsync } from '../../observability/tracing.js';
import {
  loadPluginCtx,
  setDuelLockState,
} from './gameHandlers.helpers.js';
import { registerDuelHandlers } from './duelHandlers.js';

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
      await traceAsync(
        `fw.${eventName}`,
        { 'fw.event': eventName },
        async (span) => runExclusive(`fw:session:${sessionId}`, async () => {
        try {
          const ctx = await loadPluginCtx(sessionId);
          if (!ctx) {
            if (requireGame) {
              const response = { ok: false, error: 'GAME_NOT_STARTED' };
              markResult(span, response);
              respond(response);
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
            const response = { ok: false, error: result.error };
            markResult(span, response);
            respond(response);
          } else if (result === false) {
            const response = { ok: false, error: 'ACTION_REJECTED' };
            markResult(span, response);
            respond(response);
          } else if (result && typeof result === 'object') {
            const response = { ok: true, ...result };
            markResult(span, response);
            respond(response);
          } else {
            const response = { ok: true };
            markResult(span, response);
            respond(response);
          }
        } catch (err) {
          console.error(`[WS] ${eventName} error:`, err);
          const response = { ok: false, error: err.message };
          markResult(span, response);
          respond(response);
        }
      }),
      );
    };

  socket.on(EVENTS.FW_CAPTURE_START, dispatch('capture_start'));
  socket.on(EVENTS.FW_CAPTURE_CANCEL, dispatch('capture_cancel'));
  socket.on(EVENTS.FW_CAPTURE_DISRUPT, dispatch('capture_disrupt'));
  socket.on(EVENTS.FW_USE_SKILL, dispatch('use_skill'));
  socket.on(EVENTS.FW_ATTACK, dispatch('attack'));
  socket.on(EVENTS.FW_REVIVE, dispatch('revive'));
  socket.on(EVENTS.FW_DUNGEON_ENTER, dispatch('dungeon_enter'));

  const transport = new SocketTransportAdapter(io);
  registerDuelHandlers({ io, socket, userId, transport });

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
