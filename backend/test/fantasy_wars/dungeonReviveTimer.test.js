import test from 'node:test';
import assert from 'node:assert/strict';

import { handleDungeonEnter } from '../../src/game/plugins/fantasy_wars_artifact/reviveHandlers.js';
import { DUNGEON_REVIVE_INTERVAL_MS } from '../../src/game/plugins/fantasy_wars_artifact/revive.js';
import { makeGameState, makePlayer } from '../../testing/fantasy_wars/helpers.js';
import { buildHandlerCtx } from './_helpers/testCtx.js';
import { flushMicrotasks } from './_helpers/deferred.js';

test('handleDungeonEnter schedules revive ready that fires after DUNGEON_REVIVE_INTERVAL_MS', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });

  const userId = 'dungeon-enter-user';
  const sessionId = 'dungeon-enter-session';

  const initial = makeGameState({
    alivePlayerIds: [],
    pluginState: {
      eliminatedPlayerIds: [userId],
      dungeons: [
        {
          id: 'dungeon_main',
          displayName: 'Main Dungeon',
          status: 'open',
        },
      ],
      playerStates: {
        [userId]: makePlayer({
          userId,
          isAlive: false,
          dungeonEnteredAt: null,
          reviveReady: false,
          nextReviveAt: null,
          reviveAttempts: 0,
        }),
      },
    },
  });

  const { ctx, io, store } = buildHandlerCtx({
    userId,
    sessionId,
    gameState: initial,
  });

  const enterStartMs = Date.now();
  const result = await handleDungeonEnter({ dungeonId: 'dungeon_main' }, ctx);

  assert.equal(result, true);

  const afterEnter = store.snapshot();
  const playerAfterEnter = afterEnter.pluginState.playerStates[userId];
  assert.ok(
    playerAfterEnter.dungeonEnteredAt >= enterStartMs,
    'expected dungeonEnteredAt to be set to a recent timestamp',
  );
  assert.equal(
    playerAfterEnter.nextReviveAt,
    playerAfterEnter.dungeonEnteredAt + DUNGEON_REVIVE_INTERVAL_MS,
    'nextReviveAt should be dungeonEnteredAt + DUNGEON_REVIVE_INTERVAL_MS',
  );
  assert.equal(playerAfterEnter.reviveReady, false);
  assert.equal(
    io.eventsFor('fw:revive_ready').length,
    0,
    'fw:revive_ready should not fire before the timer elapses',
  );

  // Advance the mock clock past the dungeon revive interval.
  t.mock.timers.tick(DUNGEON_REVIVE_INTERVAL_MS);

  // Allow runExclusive's microtask chain (readState → mutate → saveState → emit) to settle.
  await flushMicrotasks(8);

  const readyEvents = io.eventsFor('fw:revive_ready');
  assert.equal(readyEvents.length, 1, 'expected exactly one fw:revive_ready emit');
  assert.equal(readyEvents[0].room, `session:${sessionId}`);
  assert.equal(readyEvents[0].payload.targetUserId, userId);

  const final = store.snapshot();
  const finalPlayer = final.pluginState.playerStates[userId];
  assert.equal(finalPlayer.reviveReady, true);
  assert.equal(finalPlayer.nextReviveAt, null);
  assert.equal(
    finalPlayer.dungeonEnteredAt,
    playerAfterEnter.dungeonEnteredAt,
    'dungeonEnteredAt should be preserved after revive_ready fires',
  );
});
