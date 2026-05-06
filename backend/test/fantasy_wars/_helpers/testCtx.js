// buildHandlerCtx: convenience composer for handler tests.
// Wraps fake io / socket / game-state store and returns the ctx shape that
// dispatch (gameHandlers.js) builds for plugin handlers.

import { makeFakeIo } from './fakeIo.js';
import { makeFakeSocket } from './fakeSocket.js';
import { makeFakeGameStateStore } from './fakeGameStateStore.js';

export function buildHandlerCtx({
  userId = 'u1',
  sessionId = 's1',
  gameState = null,
  store = null,
  io = null,
  socket = null,
} = {}) {
  const resolvedStore = store ?? makeFakeGameStateStore(gameState);
  const resolvedIo = io ?? makeFakeIo();
  const resolvedSocket = socket ?? makeFakeSocket({ userId, sessionId });

  const ctx = {
    io: resolvedIo,
    socket: resolvedSocket,
    userId,
    sessionId,
    gameState: resolvedStore.snapshot(),
    saveState: resolvedStore.saveState,
    readState: resolvedStore.readState,
    mediaServer: undefined,
  };

  return {
    ctx,
    io: resolvedIo,
    socket: resolvedSocket,
    store: resolvedStore,
  };
}
