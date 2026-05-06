import test from 'node:test';
import assert from 'node:assert/strict';

import {
  finalizeWin,
  _setMediaServerProvider,
  _setSyncMediaRoomState,
  _setAIDirectorForTest,
} from '../../src/game/plugins/fantasy_wars_artifact/winFlow.js';
import { makeGameState } from '../../testing/fantasy_wars/helpers.js';
import { makeFakeIo } from './_helpers/fakeIo.js';
import {
  makeFakeMediaServer,
  makeFakeSyncMediaRoomState,
} from './_helpers/fakeMediaServer.js';
import { makeFakeAIDirector } from './_helpers/fakeAIDirector.js';
import { flushMicrotasks } from './_helpers/deferred.js';

test('finalizeWin emits game:over, mutates state, and triggers voice resync', async () => {
  const sessionId = 'finalize-session-1';
  const win = {
    winner: 'guild_alpha',
    reason: 'control_point_majority',
    threshold: 3,
    holdStartedAt: Date.now() - 20_000,
    holdUntil: Date.now() - 1_000,
  };

  const gameState = makeGameState({
    status: 'in_progress',
    finishedAt: null,
    pluginState: {
      pendingVictory: {
        winner: 'guild_alpha',
        reason: 'control_point_majority',
        holdStartedAt: Date.now() - 20_000,
        holdUntil: Date.now() - 1_000,
      },
      winCondition: null,
    },
  });

  const io = makeFakeIo();
  const fakeMediaServer = makeFakeMediaServer();
  const fakeSync = makeFakeSyncMediaRoomState();
  const fakeAI = makeFakeAIDirector('알파 길드의 승리!');

  _setMediaServerProvider(() => fakeMediaServer);
  _setSyncMediaRoomState(fakeSync);
  _setAIDirectorForTest(fakeAI);

  try {
    const before = Date.now();
    finalizeWin(gameState, win, io, sessionId);
    const after = Date.now();

    // 1. status / finishedAt mutation
    assert.equal(gameState.status, 'finished');
    assert.ok(
      typeof gameState.finishedAt === 'number'
        && gameState.finishedAt >= before
        && gameState.finishedAt <= after,
      'finishedAt should be set to a recent timestamp',
    );

    // 2. pluginState mutation: winCondition assigned, pendingVictory cleared
    assert.equal(gameState.pluginState.winCondition, win);
    assert.equal(gameState.pluginState.pendingVictory, null);

    // 3. game:over emit
    const overEvents = io.eventsFor('game:over');
    assert.equal(overEvents.length, 1, 'expected exactly one game:over emit');
    assert.equal(overEvents[0].room, `session:${sessionId}`);
    assert.deepEqual(overEvents[0].payload, {
      winner: win.winner,
      reason: win.reason,
    });

    // 4. mediaServer.getRoom call
    assert.deepEqual(fakeMediaServer.calls, [
      { method: 'getRoom', sessionId },
    ]);

    // 5. syncMediaRoomState invocation with the room returned by getRoom
    assert.equal(fakeSync.calls.length, 1, 'expected one syncMediaRoomState call');
    assert.equal(fakeSync.calls[0].sessionId, sessionId);
    assert.equal(fakeSync.calls[0].room.sessionId, sessionId);

    // 6. AIDirector.fwOnGameEnd invocation + game:ai_message emit (fire-and-forget)
    await flushMicrotasks(4);

    assert.equal(fakeAI.calls.length, 1, 'expected one fwOnGameEnd call');
    assert.equal(fakeAI.calls[0].winner, win.winner);
    assert.equal(fakeAI.calls[0].reason, win.reason);
    assert.equal(fakeAI.calls[0].room.roomId, sessionId);

    const aiEvents = io.eventsFor('game:ai_message');
    assert.equal(aiEvents.length, 1, 'expected one game:ai_message emit when AI returns text');
    assert.equal(aiEvents[0].room, `session:${sessionId}`);
    assert.deepEqual(aiEvents[0].payload, {
      type: 'announcement',
      message: '알파 길드의 승리!',
    });
  } finally {
    _setMediaServerProvider(null);
    _setSyncMediaRoomState(null);
    _setAIDirectorForTest(null);
  }
});

test('finalizeWin skips voice resync when mediaServer returns no room', async () => {
  const sessionId = 'finalize-session-2';
  const win = { winner: 'guild_beta', reason: 'guild_master_eliminated' };

  const gameState = makeGameState({
    status: 'in_progress',
    pluginState: { pendingVictory: null, winCondition: null },
  });

  const io = makeFakeIo();
  const fakeSync = makeFakeSyncMediaRoomState();
  const noRoomProvider = {
    calls: [],
    getRoom(sid) {
      this.calls.push({ method: 'getRoom', sessionId: sid });
      return null;
    },
  };
  const fakeAI = makeFakeAIDirector(null);

  _setMediaServerProvider(() => noRoomProvider);
  _setSyncMediaRoomState(fakeSync);
  _setAIDirectorForTest(fakeAI);

  try {
    finalizeWin(gameState, win, io, sessionId);

    // game:over still emits
    assert.equal(io.eventsFor('game:over').length, 1);

    // mediaServer probed but no syncMediaRoomState call
    assert.equal(noRoomProvider.calls.length, 1);
    assert.equal(fakeSync.calls.length, 0, 'syncMediaRoomState should be skipped when room is null');

    // state still mutated
    assert.equal(gameState.status, 'finished');
    assert.equal(gameState.pluginState.winCondition, win);

    // AIDirector still invoked, but game:ai_message must NOT emit when AI returns null
    await flushMicrotasks(4);
    assert.equal(fakeAI.calls.length, 1, 'fwOnGameEnd should still be invoked');
    assert.equal(
      io.eventsFor('game:ai_message').length,
      0,
      'game:ai_message must not emit when AI returns null',
    );
  } finally {
    _setMediaServerProvider(null);
    _setSyncMediaRoomState(null);
    _setAIDirectorForTest(null);
  }
});
