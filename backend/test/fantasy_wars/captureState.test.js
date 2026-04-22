import test from 'node:test';
import assert from 'node:assert/strict';

import {
  resetCaptureState,
  cancelCaptureForPlayer,
} from '../../src/game/plugins/fantasy_wars_artifact/captureState.js';
import {
  makeControlPoint,
  makeGameState,
  makePlayer,
} from '../../testing/fantasy_wars/helpers.js';

test('resetCaptureState clears capture progress, intents, and player zones', () => {
  const cp = makeControlPoint({
    id: 'cp-1',
    capturingGuild: 'guild_alpha',
    captureProgress: 0.6,
    captureStartedAt: 123,
    captureParticipantUserIds: ['user-1', 'user-2'],
    readyCount: 2,
    requiredCount: 2,
  });
  const ps = {
    controlPoints: [cp],
    captureIntents: {
      'cp-1': { 'user-1': 1, 'user-2': 2 },
    },
    playerStates: {
      'user-1': makePlayer({ userId: 'user-1', guildId: 'guild_alpha', captureZone: 'cp-1' }),
      'user-2': makePlayer({ userId: 'user-2', guildId: 'guild_alpha', captureZone: 'cp-1' }),
      'enemy-1': makePlayer({ userId: 'enemy-1', guildId: 'guild_beta', captureZone: 'cp-1' }),
    },
  };

  resetCaptureState(ps, cp, 'cp-1', 'guild_alpha');

  assert.equal(cp.capturingGuild, null);
  assert.equal(cp.captureProgress, 0);
  assert.equal(cp.captureStartedAt, null);
  assert.deepEqual(cp.captureParticipantUserIds, []);
  assert.equal(cp.readyCount, 0);
  assert.equal(cp.requiredCount, 0);
  assert.equal(ps.captureIntents['cp-1'], undefined);
  assert.equal(ps.playerStates['user-1'].captureZone, null);
  assert.equal(ps.playerStates['user-2'].captureZone, null);
  assert.equal(ps.playerStates['enemy-1'].captureZone, 'cp-1');
});

test('cancelCaptureForPlayer resets active guild capture or only clears local zone', () => {
  const cp = makeControlPoint({
    id: 'cp-1',
    capturingGuild: 'guild_alpha',
    readyCount: 2,
    requiredCount: 2,
  });
  const gameState = makeGameState({
    pluginState: {
      controlPoints: [cp],
      captureIntents: { 'cp-1': { 'user-1': 1, 'user-2': 2 } },
      playerStates: {
        'user-1': makePlayer({ userId: 'user-1', guildId: 'guild_alpha', captureZone: 'cp-1' }),
        'user-2': makePlayer({ userId: 'user-2', guildId: 'guild_alpha', captureZone: 'cp-1' }),
        'user-3': makePlayer({ userId: 'user-3', guildId: 'guild_beta', captureZone: 'cp-2' }),
      },
    },
  });

  const activeCancel = cancelCaptureForPlayer(gameState.pluginState, 'user-1');
  assert.deepEqual(activeCancel, {
    controlPointId: 'cp-1',
    guildId: 'guild_alpha',
    cancelledActiveCapture: true,
  });
  assert.equal(cp.capturingGuild, null);
  assert.equal(gameState.pluginState.playerStates['user-2'].captureZone, null);

  const passiveCancel = cancelCaptureForPlayer(gameState.pluginState, 'user-3');
  assert.deepEqual(passiveCancel, {
    controlPointId: 'cp-2',
    guildId: 'guild_beta',
    cancelledActiveCapture: false,
  });
  assert.equal(gameState.pluginState.playerStates['user-3'].captureZone, null);
});
