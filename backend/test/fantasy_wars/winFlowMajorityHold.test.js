import test from 'node:test';
import assert from 'node:assert/strict';

import {
  scheduleMajorityHoldTimer,
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
import { makeMajorityPluginState } from './_helpers/winFlowFixtures.js';
import { flushMicrotasks } from './_helpers/deferred.js';

test('scheduleMajorityHoldTimer fires finalizeWin chain after holdUntil', async (t) => {
  // mock Date 도 함께 enable — evaluateWinCondition이 holdUntil <= Date.now() 비교를 위해 Date.now() 사용.
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'], now: 0 });

  const sessionId = 'majority-hold-session';
  const holdMs = 20_000;
  const initialState = makeGameState({
    status: 'in_progress',
    finishedAt: null,
    alivePlayerIds: ['alpha-master', 'beta-master', 'gamma-master'],
    pluginState: makeMajorityPluginState(0),
  });

  const store = makeFakeGameStateStore(initialState);
  const io = makeFakeIo();
  const fakeMediaServer = makeFakeMediaServer();
  const fakeSync = makeFakeSyncMediaRoomState();
  const fakeAI = makeFakeAIDirector('Majority territory victory');

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

    // 시간 진행 전: 어떠한 emit도 발생하지 않아야 한다.
    assert.equal(io.eventsFor('game:over').length, 0);
    assert.equal(io.eventsFor('game:ai_message').length, 0);
    assert.equal(fakeSync.calls.length, 0);
    assert.equal(fakeAI.calls.length, 0);
    assert.equal(store.snapshot().status, 'in_progress');

    // mock 시계 진행 → setTimeout 콜백 fire → runExclusive → readState → evaluateWinCondition → finalizeWin → saveState
    t.mock.timers.tick(holdMs);
    await flushMicrotasks(8);

    // game:over emit 1회 + payload
    const overEvents = io.eventsFor('game:over');
    assert.equal(overEvents.length, 1);
    assert.equal(overEvents[0].room, `session:${sessionId}`);
    assert.deepEqual(overEvents[0].payload, {
      winner: 'guild_alpha',
      reason: 'control_point_majority',
    });

    // store 영구화 검증 (finalizeWin이 mutate한 후 saveState 호출됨)
    const final = store.snapshot();
    assert.equal(final.status, 'finished');
    assert.equal(final.pluginState.winCondition?.winner, 'guild_alpha');
    assert.equal(final.pluginState.winCondition?.reason, 'control_point_majority');
    assert.equal(final.pluginState.pendingVictory, null);
    assert.ok(typeof final.finishedAt === 'number', 'finishedAt should be set');

    // voice resync 호출
    assert.equal(fakeMediaServer.calls.length, 1);
    assert.equal(fakeMediaServer.calls[0].method, 'getRoom');
    assert.equal(fakeMediaServer.calls[0].sessionId, sessionId);
    assert.equal(fakeSync.calls.length, 1);
    assert.equal(fakeSync.calls[0].sessionId, sessionId);

    // AI announcement
    assert.equal(fakeAI.calls.length, 1);
    assert.equal(fakeAI.calls[0].winner, 'guild_alpha');
    assert.equal(fakeAI.calls[0].reason, 'control_point_majority');
    assert.equal(fakeAI.calls[0].room.roomId, sessionId);

    const aiEvents = io.eventsFor('game:ai_message');
    assert.equal(aiEvents.length, 1);
    assert.equal(aiEvents[0].room, `session:${sessionId}`);
    assert.deepEqual(aiEvents[0].payload, {
      type: 'announcement',
      message: 'Majority territory victory',
    });
  } finally {
    _setMediaServerProvider(null);
    _setSyncMediaRoomState(null);
    _setAIDirectorForTest(null);
  }
});

test('scheduleMajorityHoldTimer no-op when game already finished before hold expires', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'], now: 0 });

  const sessionId = 'majority-hold-finished';
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

    // hold 만료 전에 게임이 다른 경로(예: duel)로 종료되었다고 가정.
    const interruptedState = store.snapshot();
    interruptedState.status = 'finished';
    interruptedState.finishedAt = 5_000;
    interruptedState.pluginState.winCondition = {
      winner: 'guild_beta',
      reason: 'guild_master_eliminated',
    };
    store.set(interruptedState);

    t.mock.timers.tick(holdMs);
    await flushMicrotasks(8);

    // hold timer가 finalizeWin을 트리거하면 안 된다.
    assert.equal(
      io.eventsFor('game:over').length,
      0,
      'majority hold timer should not emit game:over when status already finished',
    );
    assert.equal(fakeSync.calls.length, 0);
    assert.equal(fakeAI.calls.length, 0);

    // store는 외부에서 set한 상태 그대로 (winFlow가 덮어쓰지 않음)
    const final = store.snapshot();
    assert.equal(final.status, 'finished');
    assert.equal(final.pluginState.winCondition.winner, 'guild_beta');
    assert.equal(final.pluginState.winCondition.reason, 'guild_master_eliminated');
  } finally {
    _setMediaServerProvider(null);
    _setSyncMediaRoomState(null);
    _setAIDirectorForTest(null);
  }
});
