import test from 'node:test';
import assert from 'node:assert/strict';

import { defaultConfig } from '../../src/game/plugins/fantasy_wars_artifact/schema.js';
import { getPublicState } from '../../src/game/plugins/fantasy_wars_artifact/service.js';
import { checkWinCondition } from '../../src/game/plugins/fantasy_wars_artifact/winConditions.js';
import { makeControlPoint, makeGameState } from '../../testing/fantasy_wars/helpers.js';

function makeGuilds() {
  return {
    guild_alpha: {
      guildId: 'guild_alpha',
      guildMasterId: 'alpha-master',
      score: 10,
    },
    guild_beta: {
      guildId: 'guild_beta',
      guildMasterId: 'beta-master',
      score: 5,
    },
    guild_gamma: {
      guildId: 'guild_gamma',
      guildMasterId: 'gamma-master',
      score: 3,
    },
  };
}

// hold delay 가 켜진(legacy) config 를 명시 — 기본값은 [W4] 로 0 으로 바뀌어
// 즉시 종료라 이 케이스를 더 이상 default 로 검증할 수 없다.
const holdEnabledConfig = { ...defaultConfig, controlPointHoldDurationSec: 20 };

test('checkWinCondition waits for the control point hold duration before territory win', () => {
  const gameState = makeGameState({
    pluginState: {
      guilds: makeGuilds(),
      controlPoints: [
        makeControlPoint({ id: 'cp-1', capturedBy: 'guild_alpha' }),
        makeControlPoint({ id: 'cp-2', capturedBy: 'guild_alpha' }),
        makeControlPoint({ id: 'cp-3', capturedBy: 'guild_alpha' }),
        makeControlPoint({ id: 'cp-4', capturedBy: 'guild_beta' }),
        makeControlPoint({ id: 'cp-5' }),
      ],
      pendingVictory: {
        winner: 'guild_alpha',
        reason: 'control_point_majority',
        holdStartedAt: Date.now() - 5_000,
        holdUntil: Date.now() + 10_000,
      },
    },
  });

  assert.equal(checkWinCondition(gameState, holdEnabledConfig), null);
});

test('checkWinCondition grants territory win after the hold timer expires', () => {
  const now = Date.now();
  const gameState = makeGameState({
    pluginState: {
      guilds: makeGuilds(),
      controlPoints: [
        makeControlPoint({ id: 'cp-1', capturedBy: 'guild_alpha' }),
        makeControlPoint({ id: 'cp-2', capturedBy: 'guild_alpha' }),
        makeControlPoint({ id: 'cp-3', capturedBy: 'guild_alpha' }),
        makeControlPoint({ id: 'cp-4', capturedBy: 'guild_beta' }),
        makeControlPoint({ id: 'cp-5' }),
      ],
      pendingVictory: {
        winner: 'guild_alpha',
        reason: 'control_point_majority',
        holdStartedAt: now - 25_000,
        holdUntil: now - 5_000,
      },
    },
  });

  const verdict = checkWinCondition(gameState, holdEnabledConfig);
  assert.equal(verdict?.winner, 'guild_alpha');
  assert.equal(verdict?.reason, 'control_point_majority');
});

test('checkWinCondition still allows immediate guild master elimination wins', () => {
  const gameState = makeGameState({
    pluginState: {
      guilds: makeGuilds(),
      controlPoints: [
        makeControlPoint({ id: 'cp-1', capturedBy: 'guild_alpha' }),
        makeControlPoint({ id: 'cp-2', capturedBy: 'guild_beta' }),
      ],
      eliminatedPlayerIds: ['beta-master', 'gamma-master'],
      pendingVictory: {
        winner: 'guild_alpha',
        reason: 'control_point_majority',
        holdStartedAt: Date.now(),
        holdUntil: Date.now() + 20_000,
      },
    },
  });

  const verdict = checkWinCondition(gameState, defaultConfig);
  assert.equal(verdict?.winner, 'guild_alpha');
  assert.equal(verdict?.reason, 'guild_master_eliminated');
});

test('getPublicState exposes duel BLE rules to clients', () => {
  const gameState = makeGameState({
    pluginState: {
      guilds: makeGuilds(),
      controlPoints: [],
      dungeons: [],
      playableArea: [],
      spawnZones: [],
      _config: {
        ...defaultConfig,
        duelRangeMeters: 18,
        bleEvidenceFreshnessMs: 9000,
        allowGpsFallbackWithoutBle: false,
      },
    },
    alivePlayerIds: ['alpha-master'],
  });

  const publicState = getPublicState(gameState);
  assert.equal(publicState.duelRangeMeters, 18);
  assert.equal(publicState.bleEvidenceFreshnessMs, 9000);
  assert.equal(publicState.allowGpsFallbackWithoutBle, false);
});

// reconnect/late-join 클라가 점령 진행 중인 CP 의 정확한 진행 시간을 복원하려면
// public state 의 controlPoint 페이로드에 captureDurationSec 가 포함되어야 한다.
test('getPublicState includes captureDurationSec on control points', () => {
  const cp = makeControlPoint({
    id: 'cp-1',
    capturingGuild: 'guild_alpha',
    captureStartedAt: Date.now() - 5_000,
  });
  const gameState = makeGameState({
    pluginState: {
      guilds: makeGuilds(),
      controlPoints: [cp],
      dungeons: [],
      playableArea: [],
      spawnZones: [],
      _config: {
        ...defaultConfig,
        captureDurationSec: 60,
      },
    },
    alivePlayerIds: ['alpha-master'],
  });

  const publicState = getPublicState(gameState);
  assert.equal(publicState.controlPoints.length, 1);
  assert.equal(publicState.controlPoints[0].captureDurationSec, 60);
});
