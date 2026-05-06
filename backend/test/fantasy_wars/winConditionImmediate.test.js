import test from 'node:test';
import assert from 'node:assert/strict';

import {
  checkWinCondition,
  syncPendingMajorityVictory,
} from '../../src/game/plugins/fantasy_wars_artifact/winConditions.js';
import { defaultConfig } from '../../src/game/plugins/fantasy_wars_artifact/schema.js';
import { makeGameState, makeControlPoint } from '../../testing/fantasy_wars/helpers.js';

function makeStateWith3Captured() {
  return makeGameState({
    status: 'in_progress',
    finishedAt: null,
    alivePlayerIds: ['alpha-master', 'beta-master', 'gamma-master'],
    pluginState: {
      eliminatedPlayerIds: [],
      guilds: {
        guild_alpha: { guildId: 'guild_alpha', guildMasterId: 'alpha-master', score: 30 },
        guild_beta: { guildId: 'guild_beta', guildMasterId: 'beta-master', score: 10 },
        guild_gamma: { guildId: 'guild_gamma', guildMasterId: 'gamma-master', score: 5 },
      },
      controlPoints: [
        makeControlPoint({ id: 'cp-1', capturedBy: 'guild_alpha' }),
        makeControlPoint({ id: 'cp-2', capturedBy: 'guild_alpha' }),
        makeControlPoint({ id: 'cp-3', capturedBy: 'guild_alpha' }),
        makeControlPoint({ id: 'cp-4', capturedBy: 'guild_beta' }),
        makeControlPoint({ id: 'cp-5' }),
      ],
      pendingVictory: null,
      _config: defaultConfig,
    },
  });
}

test('defaultConfig.controlPointHoldDurationSec is 0 (UX: 3 caps → 즉시 종료)', () => {
  assert.equal(defaultConfig.controlPointHoldDurationSec, 0);
});

test('hold=0 → checkWinCondition returns immediate win on majority threshold', () => {
  const state = makeStateWith3Captured();
  const win = checkWinCondition(state, defaultConfig);
  assert.ok(win, 'win object expected');
  assert.equal(win.winner, 'guild_alpha');
  assert.equal(win.reason, 'control_point_majority');
  assert.equal(win.threshold, 3); // floor(5/2)+1
});

test('hold=0 → syncPendingMajorityVictory clears pendingVictory (no hold needed)', () => {
  const state = makeStateWith3Captured();
  const pending = syncPendingMajorityVictory(state, defaultConfig);
  assert.equal(pending, null);
  assert.equal(state.pluginState.pendingVictory, null);
});

test('hold>0 (legacy override) still uses pendingVictory + holdUntil path', () => {
  const state = makeStateWith3Captured();
  const cfg = { ...defaultConfig, controlPointHoldDurationSec: 20 };
  // 실시계 기준 미래 시점으로 holdUntil 을 두어야 checkWinCondition (Date.now() 비교)
  // 이 hold 미만 분기를 탄다.
  const baseNow = Date.now();
  const pending = syncPendingMajorityVictory(state, cfg, baseNow);
  assert.ok(pending);
  assert.equal(pending.winner, 'guild_alpha');
  assert.equal(pending.holdUntil, baseNow + 20_000);

  const winBefore = checkWinCondition(state, cfg);
  assert.equal(winBefore, null, 'no win during hold');
});
