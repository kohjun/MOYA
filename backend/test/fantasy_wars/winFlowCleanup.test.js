import test from 'node:test';
import assert from 'node:assert/strict';

import {
  scheduleMajorityHoldTimer,
  clearMajorityHoldTimer,
  broadcastWinIfDone,
  _setMediaServerProvider,
  _setSyncMediaRoomState,
  _setAIDirectorForTest,
} from '../../src/game/plugins/fantasy_wars_artifact/winFlow.js';
import { makeGameState } from '../../testing/fantasy_wars/helpers.js';
import { makeFakeIo } from './_helpers/fakeIo.js';
import { makeFakeGameStateStore } from './_helpers/fakeGameStateStore.js';
import {
  makeFakeMediaServer,
  makeFakeSyncMediaRoomState,
} from './_helpers/fakeMediaServer.js';
import { makeFakeAIDirector } from './_helpers/fakeAIDirector.js';
import {
  makeMajorityPluginState,
  makeNoWinPluginState,
} from './_helpers/winFlowFixtures.js';
import { flushMicrotasks } from './_helpers/deferred.js';

test('clearMajorityHoldTimer cancels a scheduled majority hold timer before it fires', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'], now: 0 });

  const sessionId = 'cleanup-cancel-session';
  const holdMs = 20_000;
  const initialState = makeGameState({
    status: 'in_progress',
    pluginState: makeMajorityPluginState(0),
  });

  const store = makeFakeGameStateStore(initialState);
  const io = makeFakeIo();
  const fakeMediaServer = makeFakeMediaServer();
  const fakeSync = makeFakeSyncMediaRoomState();
  const fakeAI = makeFakeAIDirector('should not fire');

  _setMediaServerProvider(() => fakeMediaServer);
  _setSyncMediaRoomState(fakeSync);
  _setAIDirectorForTest(fakeAI);

  try {
    scheduleMajorityHoldTimer({
      sessionId,
      io,
      readState: store.readState,
      saveState: store.saveState,
      pendingVictory: initialState.pluginState.pendingVictory,
    });

    // 명시 cancel — fire 전에 정리.
    clearMajorityHoldTimer(sessionId);

    // mock 시계 진행해도 callback이 fire되면 안 됨.
    t.mock.timers.tick(holdMs);
    await flushMicrotasks(8);

    assert.equal(io.eventsFor('game:over').length, 0);
    assert.equal(io.eventsFor('game:ai_message').length, 0);
    assert.equal(fakeMediaServer.calls.length, 0);
    assert.equal(fakeSync.calls.length, 0);
    assert.equal(fakeAI.calls.length, 0);

    // store는 시작 시점 그대로 유지
    const final = store.snapshot();
    assert.equal(final.status, 'in_progress');
    assert.equal(final.pluginState.pendingVictory.winner, 'guild_alpha');
    assert.equal(final.pluginState.winCondition ?? null, null);
  } finally {
    _setMediaServerProvider(null);
    _setSyncMediaRoomState(null);
    _setAIDirectorForTest(null);
  }
});

test('broadcastWinIfDone returns false and emits nothing when no win condition holds', async () => {
  const sessionId = 'cleanup-no-win-session';
  const gameState = makeGameState({
    status: 'in_progress',
    finishedAt: null,
    pluginState: makeNoWinPluginState(),
  });

  const io = makeFakeIo();
  const fakeMediaServer = makeFakeMediaServer();
  const fakeSync = makeFakeSyncMediaRoomState();
  const fakeAI = makeFakeAIDirector('should not fire');

  _setMediaServerProvider(() => fakeMediaServer);
  _setSyncMediaRoomState(fakeSync);
  _setAIDirectorForTest(fakeAI);

  try {
    const won = broadcastWinIfDone(gameState, io, sessionId);

    await flushMicrotasks(4);

    assert.equal(won, false);
    assert.equal(gameState.status, 'in_progress');
    assert.equal(gameState.finishedAt, null);
    assert.equal(gameState.pluginState.winCondition ?? null, null);

    assert.equal(io.eventsFor('game:over').length, 0);
    assert.equal(io.eventsFor('game:ai_message').length, 0);
    assert.equal(fakeMediaServer.calls.length, 0);
    assert.equal(fakeSync.calls.length, 0);
    assert.equal(fakeAI.calls.length, 0);
  } finally {
    _setMediaServerProvider(null);
    _setSyncMediaRoomState(null);
    _setAIDirectorForTest(null);
  }
});

test('broadcastWinIfDone returns true and triggers finalizeWin chain when majority hold expired', async () => {
  const sessionId = 'cleanup-win-session';

  // hold가 이미 만료된 상태로 fixture 구성 — broadcastWinIfDone는 setTimeout을 쓰지 않으므로
  // mock Date 없이 실제 Date.now() 사용. holdUntil을 과거로 두어 evaluateWinCondition이 territory win 반환.
  const realNow = Date.now();
  const fixture = makeMajorityPluginState(realNow);
  fixture.pendingVictory.holdStartedAt = realNow - 20_000;
  fixture.pendingVictory.holdUntil = realNow - 1_000;

  const gameState = makeGameState({
    status: 'in_progress',
    finishedAt: null,
    alivePlayerIds: ['alpha-master', 'beta-master', 'gamma-master'],
    pluginState: fixture,
  });

  const io = makeFakeIo();
  const fakeMediaServer = makeFakeMediaServer();
  const fakeSync = makeFakeSyncMediaRoomState();
  const fakeAI = makeFakeAIDirector('Territory secured');

  _setMediaServerProvider(() => fakeMediaServer);
  _setSyncMediaRoomState(fakeSync);
  _setAIDirectorForTest(fakeAI);

  try {
    const before = Date.now();
    const won = broadcastWinIfDone(gameState, io, sessionId);
    const after = Date.now();

    assert.equal(won, true);
    assert.equal(gameState.status, 'finished');
    assert.ok(
      typeof gameState.finishedAt === 'number'
        && gameState.finishedAt >= before
        && gameState.finishedAt <= after,
    );
    assert.equal(gameState.pluginState.winCondition.winner, 'guild_alpha');
    assert.equal(gameState.pluginState.winCondition.reason, 'control_point_majority');
    assert.equal(gameState.pluginState.pendingVictory, null);

    const overEvents = io.eventsFor('game:over');
    assert.equal(overEvents.length, 1);
    assert.equal(overEvents[0].room, `session:${sessionId}`);
    assert.deepEqual(overEvents[0].payload, {
      winner: 'guild_alpha',
      reason: 'control_point_majority',
    });

    assert.equal(fakeMediaServer.calls.length, 1);
    assert.equal(fakeSync.calls.length, 1);
    assert.equal(fakeSync.calls[0].sessionId, sessionId);

    // AI announcement (fire-and-forget)
    await flushMicrotasks(4);
    assert.equal(fakeAI.calls.length, 1);
    assert.equal(fakeAI.calls[0].winner, 'guild_alpha');

    const aiEvents = io.eventsFor('game:ai_message');
    assert.equal(aiEvents.length, 1);
    assert.deepEqual(aiEvents[0].payload, {
      type: 'announcement',
      message: 'Territory secured',
    });
  } finally {
    _setMediaServerProvider(null);
    _setSyncMediaRoomState(null);
    _setAIDirectorForTest(null);
  }
});
