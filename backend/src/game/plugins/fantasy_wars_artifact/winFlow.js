'use strict';

import { runExclusive } from './mutex.js';
import { defaultConfig } from './schema.js';
import { checkWinCondition as evaluateWinCondition } from './winConditions.js';
import * as AIDirector from '../../../ai/AIDirector.js';
import { getMediaServer } from '../../../media/MediaServer.js';
import { syncMediaRoomState } from '../../../websocket/socketRuntime.js';

const majorityHoldTimers = new Map();

// Test seams: default to the production providers above. Tests can swap these
// via _setMediaServerProvider / _setSyncMediaRoomState / _setAIDirectorForTest
// and reset by passing null.
//
// 기본값을 lambda 로 감싸 호출 시점에 import 식별자를 resolve 한다 — winFlow 가
// socketRuntime 과 ESM 순환 import 체인에 들어가 있어, 모듈 평가 시점에
// `syncMediaRoomState` 는 아직 TDZ 라 직접 참조하면 ReferenceError 가 난다.
// (mediaServerProvider 도 같은 이유로 lambda 로 감싸져 있다.)
let mediaServerProvider = () => getMediaServer();
let syncMediaRoomStateImpl = (sessionId, room) =>
  syncMediaRoomState(sessionId, room);
let aiDirectorImpl = AIDirector;

export function _setMediaServerProvider(fn) {
  mediaServerProvider = fn ?? (() => getMediaServer());
}

export function _setSyncMediaRoomState(fn) {
  syncMediaRoomStateImpl =
    fn ?? ((sessionId, room) => syncMediaRoomState(sessionId, room));
}

export function _setAIDirectorForTest(impl) {
  aiDirectorImpl = impl ?? AIDirector;
}

export function clearMajorityHoldTimer(sessionId) {
  const timer = majorityHoldTimers.get(sessionId);
  if (timer) {
    clearTimeout(timer);
    majorityHoldTimers.delete(sessionId);
  }
}

export function finalizeWin(gameState, win, io, sessionId) {
  const ps = gameState.pluginState ?? {};
  ps.winCondition = win;
  ps.pendingVictory = null;
  gameState.status = 'finished';
  gameState.finishedAt = Date.now();

  io.to(`session:${sessionId}`).emit('game:over', {
    winner: win.winner,
    reason: win.reason,
  });

  // 게임 종료 시 음성 채널을 길드별 격리에서 lobby(전체 오픈)로 전환.
  // syncMediaRoomState가 plugin.getVoicePolicy를 다시 평가해 status='finished'면 'open'을 반환한다.
  const mediaRoom = mediaServerProvider()?.getRoom(sessionId);
  if (mediaRoom) {
    syncMediaRoomStateImpl(sessionId, mediaRoom).catch((err) => {
      console.error('[FW] voice resync on game end failed:', err);
    });
  }

  aiDirectorImpl.fwOnGameEnd(
    { roomId: sessionId, pluginState: ps },
    win.winner,
    win.reason ?? 'territory',
  ).then((message) => {
    if (message) {
      io.to(`session:${sessionId}`).emit('game:ai_message', {
        type: 'announcement',
        message,
      });
    }
  }).catch(() => {});
}

export function scheduleMajorityHoldTimer({ sessionId, io, readState, saveState, pendingVictory }) {
  clearMajorityHoldTimer(sessionId);
  if (!pendingVictory?.holdUntil) {
    return;
  }

  const delayMs = Math.max(0, pendingVictory.holdUntil - Date.now());
  const timer = setTimeout(() => runExclusive(`fw:session:${sessionId}`, async () => {
    majorityHoldTimers.delete(sessionId);

    const fresh = await readState();
    if (!fresh || fresh.status === 'finished') {
      return;
    }

    const win = evaluateWinCondition(fresh, fresh.pluginState?._config ?? defaultConfig);
    if (!win || win.reason !== 'control_point_majority') {
      return;
    }

    finalizeWin(fresh, win, io, sessionId);
    await saveState(fresh);
  }), delayMs);

  majorityHoldTimers.set(sessionId, timer);
}

export function broadcastWinIfDone(gameState, io, sessionId) {
  const ps = gameState.pluginState ?? {};
  const win = evaluateWinCondition(gameState, ps._config ?? defaultConfig);
  if (!win) {
    return false;
  }

  clearMajorityHoldTimer(sessionId);
  finalizeWin(gameState, win, io, sessionId);
  return true;
}
