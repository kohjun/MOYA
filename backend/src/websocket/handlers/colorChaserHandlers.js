'use strict';

// Color Chaser 전용 소켓 핸들러.
// fantasy_wars 와 분리: gameType 검증 후 dispatch.

import { GamePluginRegistry } from '../../game/index.js';
import { EVENTS } from '../socketProtocol.js';
import { readGameState, saveGameState } from '../socketRuntime.js';
import { runExclusive } from '../../game/plugins/fantasy_wars_artifact/mutex.js';
import {
  activateNextControlPoint,
  expireActiveControlPointIfNeeded,
  scheduleNextActivation,
  cancelStaleMissions,
} from '../../game/plugins/color_chaser/cpScheduler.js';

const COLOR_CHASER_GAME_TYPE = 'color_chaser';

// 세션별 거점 활성화 / 만료 타이머. 단일 노드 가정.
const cpActivationTimers = new Map();
const cpExpireTimers = new Map();

function clearCpTimers(sessionId) {
  const at = cpActivationTimers.get(sessionId);
  if (at) clearTimeout(at);
  cpActivationTimers.delete(sessionId);
  const et = cpExpireTimers.get(sessionId);
  if (et) clearTimeout(et);
  cpExpireTimers.delete(sessionId);
}

// 세션별 시간 제한 종료 타이머. 단일 노드 가정.
// 게임 시작/재개 시 ensureTimeLimitTimer 호출되며,
// 만료 시 finalizeWinIfNeeded 가 자동 종료를 처리한다.
const timeLimitTimers = new Map();

function clearTimeLimitTimer(sessionId) {
  const timer = timeLimitTimers.get(sessionId);
  if (timer) {
    clearTimeout(timer);
    timeLimitTimers.delete(sessionId);
  }
}

// 거점 활성화 schedule 재설정. nextActivationAt 기반 setTimeout.
// gameState 의 nextActivationAt 이 없으면 즉시 활성화 시도.
export function ensureCpActivationTimer(io, sessionId, gameState) {
  if (!gameState || gameState.status !== 'in_progress') return;
  const ps = gameState.pluginState ?? {};

  // 이미 활성 거점이 있으면 expire timer 만 보장.
  if (ps.activeControlPointId) {
    ensureCpExpireTimer(io, sessionId, gameState);
    return;
  }

  if (cpActivationTimers.has(sessionId)) return;

  const now = Date.now();
  const fireAt = ps.nextActivationAt ?? now;
  const delay = Math.max(0, fireAt - now);

  const timer = setTimeout(
    () => runExclusive(`cc:session:${sessionId}`, async () => {
      cpActivationTimers.delete(sessionId);
      try {
        await tryActivateNext(io, sessionId);
      } catch (err) {
        console.error('[CC] cp activation failed:', err);
      }
    }),
    delay,
  );
  cpActivationTimers.set(sessionId, timer);
}

function ensureCpExpireTimer(io, sessionId, gameState) {
  const ps = gameState.pluginState ?? {};
  const activeId = ps.activeControlPointId;
  if (!activeId) return;
  const cp = (ps.controlPoints ?? []).find((c) => c.id === activeId);
  if (!cp || cp.status !== 'active') return;

  if (cpExpireTimers.has(sessionId)) return;

  const delay = Math.max(0, (cp.expiresAt ?? 0) - Date.now());
  const timer = setTimeout(
    () => runExclusive(`cc:session:${sessionId}`, async () => {
      cpExpireTimers.delete(sessionId);
      try {
        await tryExpireActive(io, sessionId);
      } catch (err) {
        console.error('[CC] cp expire failed:', err);
      }
    }),
    delay,
  );
  cpExpireTimers.set(sessionId, timer);
}

async function tryActivateNext(io, sessionId) {
  const gs = await readGameState(sessionId);
  if (!gs || gs.status !== 'in_progress') return;
  if (gs.gameType !== COLOR_CHASER_GAME_TYPE) return;

  const ps = gs.pluginState ?? {};
  const activated = activateNextControlPoint(ps);
  if (!activated) {
    // 모든 거점 소비됨 → 더 활성화하지 않음.
    await saveGameState(sessionId, gs);
    return;
  }

  await saveGameState(sessionId, gs);

  io.to(`session:${sessionId}`).emit(EVENTS.CC_CP_ACTIVATED, {
    sessionId,
    cpId: activated.id,
    displayName: activated.displayName,
    location: activated.location,
    activatedAt: activated.activatedAt,
    expiresAt: activated.expiresAt,
  });

  // 모두에게 state_update (activeControlPointId 갱신)
  const plugin = GamePluginRegistry.get(COLOR_CHASER_GAME_TYPE);
  emitPluginStateUpdate(
    io,
    sessionId,
    gs,
    plugin,
    Object.keys(ps.playerStates ?? {}),
  );

  // 만료 timer 등록
  ensureCpExpireTimer(io, sessionId, gs);
}

async function tryExpireActive(io, sessionId) {
  const gs = await readGameState(sessionId);
  if (!gs || gs.status !== 'in_progress') return;
  if (gs.gameType !== COLOR_CHASER_GAME_TYPE) return;

  const ps = gs.pluginState ?? {};
  const expired = expireActiveControlPointIfNeeded(ps);
  if (!expired) return;

  cancelStaleMissions(ps);
  scheduleNextActivation(ps);

  await saveGameState(sessionId, gs);

  io.to(`session:${sessionId}`).emit(EVENTS.CC_CP_EXPIRED, {
    sessionId,
    cpId: expired.id,
    expiredAt: Date.now(),
  });

  const plugin = GamePluginRegistry.get(COLOR_CHASER_GAME_TYPE);
  emitPluginStateUpdate(
    io,
    sessionId,
    gs,
    plugin,
    Object.keys(ps.playerStates ?? {}),
  );

  // 다음 활성화 timer
  ensureCpActivationTimer(io, sessionId, gs);
}

// claim 직후 호출 — broadcast + 다음 활성화 schedule.
async function emitCpClaimedAndScheduleNext(io, sessionId, gs, claimResult) {
  const ps = gs.pluginState ?? {};
  cancelStaleMissions(ps);
  scheduleNextActivation(ps);

  io.to(`session:${sessionId}`).emit(EVENTS.CC_CP_CLAIMED, {
    sessionId,
    cpId: claimResult.cpId,
    claimedBy: claimResult.userId,
    claimedAt: Date.now(),
  });

  // 활성/만료 timer 정리 + 다음 schedule
  const at = cpActivationTimers.get(sessionId);
  if (at) {
    clearTimeout(at);
    cpActivationTimers.delete(sessionId);
  }
  const et = cpExpireTimers.get(sessionId);
  if (et) {
    clearTimeout(et);
    cpExpireTimers.delete(sessionId);
  }

  ensureCpActivationTimer(io, sessionId, gs);
}

export function ensureTimeLimitTimer(io, sessionId, gameState) {
  if (!gameState || gameState.status !== 'in_progress') return;
  if (timeLimitTimers.has(sessionId)) return;

  const config = gameState.pluginState?._config ?? {};
  const limitMs = (config.timeLimitSec ?? 1200) * 1000;
  const remaining = Math.max(0, (gameState.startedAt ?? Date.now()) + limitMs - Date.now());

  const timer = setTimeout(
    () => runExclusive(`cc:session:${sessionId}`, async () => {
      timeLimitTimers.delete(sessionId);
      try {
        await finalizeWinIfNeeded(io, sessionId, 'timer');
      } catch (err) {
        console.error('[CC] time limit finalize failed:', err);
      }
    }),
    remaining,
  );
  timeLimitTimers.set(sessionId, timer);
}

// 승리 조건 검사 → 종료 처리 (state save + emit). 이미 종료됐으면 noop.
async function finalizeWinIfNeeded(io, sessionId, source = 'action') {
  const gs = await readGameState(sessionId);
  if (!gs || gs.status !== 'in_progress') return null;
  const plugin = GamePluginRegistry.get(gs.gameType ?? COLOR_CHASER_GAME_TYPE);
  if (gs.gameType !== COLOR_CHASER_GAME_TYPE) return null;

  const win = plugin.checkWinCondition?.(gs);
  if (!win) return null;

  const ps = gs.pluginState ?? {};
  ps.winCondition = win;
  gs.status = 'finished';
  gs.finishedAt = Date.now();
  await saveGameState(sessionId, gs);

  clearTimeLimitTimer(sessionId);
  clearCpTimers(sessionId);

  emitPluginStateUpdate(
    io,
    sessionId,
    gs,
    plugin,
    Object.keys(ps.playerStates ?? {}),
  );

  io.to(`session:${sessionId}`).emit(EVENTS.GAME_OVER, {
    sessionId,
    winner: win.winner,
    reason: win.reason,
    source, // 'timer' | 'action'
  });

  return win;
}

async function loadColorChaserCtx(sessionId) {
  const gameState = await readGameState(sessionId);
  if (!gameState || gameState.gameType !== COLOR_CHASER_GAME_TYPE) {
    return null;
  }
  const plugin = GamePluginRegistry.get(COLOR_CHASER_GAME_TYPE);
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

// 미션 시작/제출 등 단순 액션을 ack 응답으로 처리. broadcast 없음 (개인 작업).
function ccDispatch(eventName, { io, socket, userId }) {
  return async (payload, cb) => {
    const respond = typeof cb === 'function' ? cb : () => {};
    const sessionId = payload?.sessionId || socket.currentSessionId;
    if (!sessionId) {
      respond({ ok: false, error: 'MISSING_SESSION_ID' });
      return;
    }

    await runExclusive(`cc:session:${sessionId}`, async () => {
      try {
        const ctx = await loadColorChaserCtx(sessionId);
        if (!ctx) {
          respond({ ok: false, error: 'GAME_NOT_STARTED' });
          return;
        }

        const { gameState, plugin } = ctx;
        ensureTimeLimitTimer(io, sessionId, gameState);
        ensureCpActivationTimer(io, sessionId, gameState);

        const result = await plugin.handleEvent(eventName, payload ?? {}, {
          io,
          socket,
          userId,
          sessionId,
          gameState,
          saveState: (gs) => saveGameState(sessionId, gs),
          readState: () => readGameState(sessionId),
        });

        if (!result || result.ok === false) {
          respond(result || { ok: false, error: 'ACTION_REJECTED' });
          return;
        }

        // mission_submit 성공으로 거점이 claim 됐으면 broadcast + 다음 활성화.
        const cpClaimed = eventName === 'mission_submit' && result.success && result.cpId;
        if (cpClaimed) {
          await emitCpClaimedAndScheduleNext(io, sessionId, gameState, {
            cpId: result.cpId,
            userId,
          });
        }

        await saveGameState(sessionId, gameState);

        // claim 시엔 모두에게, 그 외엔 본인에게만 private state 갱신.
        const targets = cpClaimed
          ? Object.keys(gameState.pluginState?.playerStates ?? {})
          : [userId];
        emitPluginStateUpdate(io, sessionId, gameState, plugin, targets);
        respond({ ok: true, ...result });
      } catch (err) {
        console.error(`[CC] ${eventName} error:`, err);
        respond({ ok: false, error: err.message || 'ACTION_FAILED' });
      }
    });
  };
}

export const registerColorChaserHandlers = ({ io, socket, userId }) => {
  socket.on(
    EVENTS.CC_MISSION_START,
    ccDispatch('mission_start', { io, socket, userId }),
  );
  socket.on(
    EVENTS.CC_MISSION_SUBMIT,
    ccDispatch('mission_submit', { io, socket, userId }),
  );
  socket.on(
    EVENTS.CC_SET_BODY_PROFILE,
    ccDispatch('set_body_profile', { io, socket, userId }),
  );

  socket.on(EVENTS.CC_TAG_TARGET, async (payload, cb) => {
    const respond = typeof cb === 'function' ? cb : () => {};
    const sessionId = payload?.sessionId || socket.currentSessionId;
    const targetUserId = payload?.targetUserId;

    if (!sessionId || !targetUserId) {
      respond({ ok: false, error: 'MISSING_FIELDS' });
      return;
    }

    await runExclusive(`cc:session:${sessionId}`, async () => {
      try {
        const ctx = await loadColorChaserCtx(sessionId);
        if (!ctx) {
          respond({ ok: false, error: 'GAME_NOT_STARTED' });
          return;
        }

        const { gameState, plugin } = ctx;
        ensureTimeLimitTimer(io, sessionId, gameState);
        ensureCpActivationTimer(io, sessionId, gameState);

        const result = await plugin.handleEvent('tag_target', payload ?? {}, {
          io,
          socket,
          userId,
          sessionId,
          gameState,
          saveState: (gs) => saveGameState(sessionId, gs),
          readState: () => readGameState(sessionId),
        });

        if (!result || result.ok === false) {
          respond(result || { ok: false, error: 'TAG_REJECTED' });
          return;
        }

        // 처치가 발생한 경우 (정답 또는 오발 페널티)
        if (result.eliminatedUserId) {
          // 승패 검사
          const win = plugin.checkWinCondition?.(gameState);
          if (win) {
            const ps = gameState.pluginState ?? {};
            ps.winCondition = win;
            gameState.status = 'finished';
            gameState.finishedAt = Date.now();
          }

          await saveGameState(sessionId, gameState);

          // 1) 처치 알림 broadcast (정체 공개)
          io.to(`session:${sessionId}`).emit(EVENTS.CC_PLAYER_TAGGED, {
            sessionId,
            success: result.success,
            eliminatedUserId: result.eliminatedUserId,
            eliminatedColorId: result.eliminatedColorId,
            eliminatedColorLabel: result.eliminatedColorLabel,
            killedBy: result.killedBy,
            reason: result.reason,
            wrongTargetId: result.wrongTargetId,
            occurredAt: Date.now(),
          });

          // 2) 기존 player:eliminated 이벤트도 emit (map_session_provider 호환)
          io.to(`session:${sessionId}`).emit(EVENTS.PLAYER_ELIMINATED, {
            userId: result.eliminatedUserId,
            killedBy: result.killedBy,
            reason: result.reason,
          });

          // 3) state_update — 사망자 + 어태커 + 상속받은 사람 전체에게 private 갱신
          const affectedUserIds = [
            result.eliminatedUserId,
            result.killedBy,
            // 상속이 발생한 사람들 (사망자를 가리켰던 모든 살아있는 플레이어)
            ...Object.keys(gameState.pluginState?.playerStates ?? {}),
          ];
          emitPluginStateUpdate(io, sessionId, gameState, plugin, affectedUserIds);

          // 4) 게임 종료
          if (win) {
            io.to(`session:${sessionId}`).emit(EVENTS.GAME_OVER, {
              winner: win.winner,
              reason: win.reason,
            });
          }
        } else {
          await saveGameState(sessionId, gameState);
        }

        respond({
          ok: true,
          success: result.success,
          eliminatedUserId: result.eliminatedUserId ?? null,
          eliminatedColorLabel: result.eliminatedColorLabel ?? null,
          reason: result.reason ?? null,
          distanceMeters: result.distanceMeters ?? null,
        });
      } catch (err) {
        console.error('[CC] tag_target error:', err);
        respond({ ok: false, error: err.message || 'TAG_FAILED' });
      }
    });
  });
};
