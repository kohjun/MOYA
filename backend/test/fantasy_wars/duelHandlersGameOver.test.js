import test from 'node:test';
import assert from 'node:assert/strict';

import {
  onDuelResolve,
  _setReadGameStateForTest,
  _setSaveGameStateForTest,
  _setMediaServerProviderForTest,
  _setSyncMediaRoomStateForTest,
  _setAIDirectorForTest,
} from '../../src/websocket/handlers/duelHandlers.js';
import { EVENTS } from '../../src/websocket/socketProtocol.js';
import { defaultConfig } from '../../src/game/plugins/fantasy_wars_artifact/schema.js';
import { makeGameState } from '../../testing/fantasy_wars/helpers.js';
import { makeFakeIo } from './_helpers/fakeIo.js';
import { makeFakeGameStateStore } from './_helpers/fakeGameStateStore.js';
import {
  makeFakeMediaServer,
  makeFakeSyncMediaRoomState,
} from './_helpers/fakeMediaServer.js';
import { flushMicrotasks } from './_helpers/deferred.js';

// Fake AIDirector exposing all 3 methods used by onDuelResolve.
function makeFakeDuelAIDirector(messages = {}) {
  const calls = { fwOnGameEnd: [], fwOnDuelResult: [], fwOnDuelDraw: [] };
  return {
    calls,
    fwOnGameEnd: async (room, winner, reason) => {
      calls.fwOnGameEnd.push({ room, winner, reason });
      return messages.fwOnGameEnd ?? null;
    },
    fwOnDuelResult: async (room, winner, loser, minigameType, executionTriggered) => {
      calls.fwOnDuelResult.push({ room, winner, loser, minigameType, executionTriggered });
      return messages.fwOnDuelResult ?? null;
    },
    fwOnDuelDraw: async (room, minigameType) => {
      calls.fwOnDuelDraw.push({ room, minigameType });
      return messages.fwOnDuelDraw ?? null;
    },
  };
}

// 3 길드 fixture. gamma-master는 사전 탈락 상태. duel에서 beta-master가 죽으면
// alive guildMaster가 alpha 단독 → guild_master_eliminated win.
function makeMasterElimFixture() {
  return {
    eliminatedPlayerIds: ['gamma-master'],
    guilds: {
      guild_alpha: { guildId: 'guild_alpha', guildMasterId: 'alpha-master', score: 0 },
      guild_beta: { guildId: 'guild_beta', guildMasterId: 'beta-master', score: 0 },
      guild_gamma: { guildId: 'guild_gamma', guildMasterId: 'gamma-master', score: 0 },
    },
    controlPoints: [],
    // duel 종료가 finalizeWin 통합되기 전 발생할 수 있는 stale pendingVictory.
    // onDuelResolve가 game-over 시 null로 정리해야 한다.
    pendingVictory: {
      winner: 'guild_alpha',
      reason: 'control_point_majority',
      holdStartedAt: 0,
      holdUntil: 999_999_999,
    },
    playerStates: {
      'alpha-master': {
        userId: 'alpha-master',
        guildId: 'guild_alpha',
        job: 'priest',
        isAlive: true,
        hp: 100,
        remainingLives: 1,
        shields: [],
        inDuel: true,
        duelExpiresAt: null,
        captureZone: null,
        executionArmedUntil: null,
        nickname: 'Alpha Master',
      },
      'beta-master': {
        userId: 'beta-master',
        guildId: 'guild_beta',
        job: 'priest',
        isAlive: true,
        hp: 100,
        remainingLives: 1,
        shields: [],
        inDuel: true,
        duelExpiresAt: null,
        captureZone: null,
        executionArmedUntil: null,
        nickname: 'Beta Master',
      },
    },
    _config: defaultConfig,
  };
}

test('onDuelResolve game-over path: cleanup + emit order + voice resync', async () => {
  const sessionId = 'duel-go-1';
  const initialGs = makeGameState({
    status: 'in_progress',
    finishedAt: null,
    alivePlayerIds: ['alpha-master', 'beta-master'],
    pluginState: makeMasterElimFixture(),
  });

  const store = makeFakeGameStateStore(initialGs);
  const io = makeFakeIo();
  const fakeMediaServer = makeFakeMediaServer();
  const fakeSync = makeFakeSyncMediaRoomState();
  const fakeAI = makeFakeDuelAIDirector({ fwOnGameEnd: 'Alpha guild master prevails' });

  _setReadGameStateForTest(async (sid) => {
    assert.equal(sid, sessionId);
    return store.readState();
  });
  _setSaveGameStateForTest(async (sid, gs) => {
    assert.equal(sid, sessionId);
    return store.saveState(gs);
  });
  _setMediaServerProviderForTest(() => fakeMediaServer);
  _setSyncMediaRoomStateForTest(fakeSync);
  _setAIDirectorForTest(fakeAI);

  try {
    const result = await onDuelResolve({
      duelId: 'duel-1',
      challengerId: 'alpha-master',
      targetId: 'beta-master',
      winnerId: 'alpha-master',
      loserId: 'beta-master',
      sessionId,
      reason: 'reaction_time_winner',
      minigameType: 'reaction_time',
    }, { io });

    // resolution returned (not null)
    assert.ok(result, 'onDuelResolve should return resolution object on win path');
    assert.equal(result.eliminated, true);

    // emit order 검증: GAME_STATE_UPDATE (×3 — session + 2 user) → FW_DUEL_LOG → fw:player_eliminated → game:over
    const events = io.events;
    const eventNames = events.map((e) => e.event);

    const stateUpdateCount = events.filter((e) => e.event === EVENTS.GAME_STATE_UPDATE).length;
    assert.equal(
      stateUpdateCount,
      3,
      'expected 3 GAME_STATE_UPDATE emits (session + winner private + loser private)',
    );

    // 첫 GAME_STATE_UPDATE는 session-broadcast
    assert.equal(events[0].event, EVENTS.GAME_STATE_UPDATE);
    assert.equal(events[0].room, `session:${sessionId}`);

    // FW_DUEL_LOG는 GAME_STATE_UPDATE 그룹 직후
    const duelLogIndex = eventNames.indexOf(EVENTS.FW_DUEL_LOG);
    assert.equal(duelLogIndex, 3, 'FW_DUEL_LOG should follow the 3 GAME_STATE_UPDATE emits');
    assert.equal(events[duelLogIndex].room, `session:${sessionId}`);

    // fw:player_eliminated 다음
    const elimIndex = eventNames.indexOf('fw:player_eliminated');
    assert.equal(elimIndex, 4);
    assert.deepEqual(events[elimIndex].payload, {
      userId: 'beta-master',
      killedBy: 'alpha-master',
      method: 'duel',
      duelReason: 'reaction_time_winner',
    });

    // game:over 그 다음
    const overIndex = eventNames.indexOf('game:over');
    assert.equal(overIndex, 5);
    assert.equal(events[overIndex].room, `session:${sessionId}`);
    assert.deepEqual(events[overIndex].payload, {
      winner: 'guild_alpha',
      reason: 'guild_master_eliminated',
    });

    // store 영구화 검증
    const final = store.snapshot();
    assert.equal(final.status, 'finished');
    assert.ok(typeof final.finishedAt === 'number');
    assert.equal(final.pluginState.winCondition.winner, 'guild_alpha');
    assert.equal(final.pluginState.winCondition.reason, 'guild_master_eliminated');
    assert.equal(final.pluginState.pendingVictory, null, 'stale pendingVictory must be cleared');
    assert.ok(
      final.pluginState.eliminatedPlayerIds.includes('beta-master'),
      'loser should be added to eliminatedPlayerIds',
    );
    assert.ok(
      !final.alivePlayerIds.includes('beta-master'),
      'loser should be removed from alivePlayerIds',
    );

    // voice resync 호출
    assert.equal(fakeMediaServer.calls.length, 1);
    assert.equal(fakeMediaServer.calls[0].method, 'getRoom');
    assert.equal(fakeMediaServer.calls[0].sessionId, sessionId);
    assert.equal(fakeSync.calls.length, 1);
    assert.equal(fakeSync.calls[0].sessionId, sessionId);

    // AI fwOnGameEnd 호출 + game:ai_message emit (fire-and-forget)
    await flushMicrotasks(4);
    assert.equal(fakeAI.calls.fwOnGameEnd.length, 1);
    assert.equal(fakeAI.calls.fwOnGameEnd[0].winner, 'guild_alpha');
    assert.equal(fakeAI.calls.fwOnGameEnd[0].reason, 'guild_master_eliminated');
    assert.equal(fakeAI.calls.fwOnGameEnd[0].room.roomId, sessionId);
    assert.equal(fakeAI.calls.fwOnDuelResult.length, 0, 'duel-result AI must not fire on game-over branch');

    const aiEvents = io.eventsFor('game:ai_message');
    assert.equal(aiEvents.length, 1);
    assert.equal(aiEvents[0].room, `session:${sessionId}`);
    assert.deepEqual(aiEvents[0].payload, {
      type: 'announcement',
      message: 'Alpha guild master prevails',
    });
  } finally {
    _setReadGameStateForTest(null);
    _setSaveGameStateForTest(null);
    _setMediaServerProviderForTest(null);
    _setSyncMediaRoomStateForTest(null);
    _setAIDirectorForTest(null);
  }
});

test('onDuelResolve non-game-over path: emits duel result, no game:over, no voice resync', async () => {
  const sessionId = 'duel-no-go-1';

  // 모두 살아있고 controlPoint 점령 없음 → checkWinCondition === null.
  const initialGs = makeGameState({
    status: 'in_progress',
    finishedAt: null,
    alivePlayerIds: ['alpha-master', 'beta-master', 'gamma-master'],
    pluginState: {
      eliminatedPlayerIds: [],
      guilds: {
        guild_alpha: { guildId: 'guild_alpha', guildMasterId: 'alpha-master', score: 0 },
        guild_beta: { guildId: 'guild_beta', guildMasterId: 'beta-master', score: 0 },
        guild_gamma: { guildId: 'guild_gamma', guildMasterId: 'gamma-master', score: 0 },
      },
      controlPoints: [],
      pendingVictory: null,
      playerStates: {
        'alpha-master': {
          userId: 'alpha-master', guildId: 'guild_alpha', job: 'warrior',
          isAlive: true, hp: 100, remainingLives: 2, shields: [], inDuel: true,
          duelExpiresAt: null, captureZone: null, executionArmedUntil: null,
          nickname: 'Alpha Master',
        },
        'beta-master': {
          userId: 'beta-master', guildId: 'guild_beta', job: 'warrior',
          isAlive: true, hp: 100, remainingLives: 2, shields: [], inDuel: true,
          duelExpiresAt: null, captureZone: null, executionArmedUntil: null,
          nickname: 'Beta Master',
        },
        'gamma-master': {
          userId: 'gamma-master', guildId: 'guild_gamma', job: 'priest',
          isAlive: true, hp: 100, remainingLives: 1, shields: [], inDuel: false,
          duelExpiresAt: null, captureZone: null, executionArmedUntil: null,
          nickname: 'Gamma Master',
        },
      },
      _config: defaultConfig,
    },
  });

  const store = makeFakeGameStateStore(initialGs);
  const io = makeFakeIo();
  const fakeMediaServer = makeFakeMediaServer();
  const fakeSync = makeFakeSyncMediaRoomState();
  const fakeAI = makeFakeDuelAIDirector({ fwOnDuelResult: 'Alpha bested Beta' });

  _setReadGameStateForTest(async () => store.readState());
  _setSaveGameStateForTest(async (_sid, gs) => store.saveState(gs));
  _setMediaServerProviderForTest(() => fakeMediaServer);
  _setSyncMediaRoomStateForTest(fakeSync);
  _setAIDirectorForTest(fakeAI);

  try {
    await onDuelResolve({
      duelId: 'duel-2',
      challengerId: 'alpha-master',
      targetId: 'beta-master',
      winnerId: 'alpha-master',
      loserId: 'beta-master',
      sessionId,
      reason: 'reaction_time_winner',
      minigameType: 'reaction_time',
    }, { io });

    // game:over는 발생하지 않아야 함 (warrior 2 lives → 첫 패배는 비제거)
    assert.equal(io.eventsFor('game:over').length, 0);

    // voice resync 미호출
    assert.equal(fakeMediaServer.calls.length, 0);
    assert.equal(fakeSync.calls.length, 0);

    // status는 in_progress 유지
    const final = store.snapshot();
    assert.equal(final.status, 'in_progress');
    assert.equal(final.pluginState.winCondition ?? null, null);

    // AI fwOnDuelResult 호출 + game:ai_message emit
    await flushMicrotasks(4);
    assert.equal(fakeAI.calls.fwOnDuelResult.length, 1);
    assert.equal(fakeAI.calls.fwOnGameEnd.length, 0, 'fwOnGameEnd must not fire on non-game-over branch');

    const aiEvents = io.eventsFor('game:ai_message');
    assert.equal(aiEvents.length, 1);
    assert.deepEqual(aiEvents[0].payload, {
      type: 'announcement',
      message: 'Alpha bested Beta',
    });
  } finally {
    _setReadGameStateForTest(null);
    _setSaveGameStateForTest(null);
    _setMediaServerProviderForTest(null);
    _setSyncMediaRoomStateForTest(null);
    _setAIDirectorForTest(null);
  }
});
