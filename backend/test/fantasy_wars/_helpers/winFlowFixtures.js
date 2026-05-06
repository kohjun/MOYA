// Shared fixtures for winFlow / lifecycle tests.

import { defaultConfig } from '../../../src/game/plugins/fantasy_wars_artifact/schema.js';
import { makeControlPoint } from '../../../testing/fantasy_wars/helpers.js';

// 3-alpha-of-5 majority fixture: alpha 길드가 controlPointCount/2 + 1 = 3 점령 → leader.
// service.test.js의 territory-win 픽스처와 동일 패턴.
// `now` 값을 받아 holdStartedAt / holdUntil 를 결정 (mock Date 환경 호환).
export function makeMajorityPluginState(now) {
  return {
    eliminatedPlayerIds: [],
    guilds: {
      guild_alpha: { guildId: 'guild_alpha', guildMasterId: 'alpha-master', score: 10 },
      guild_beta: { guildId: 'guild_beta', guildMasterId: 'beta-master', score: 5 },
      guild_gamma: { guildId: 'guild_gamma', guildMasterId: 'gamma-master', score: 3 },
    },
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
      holdStartedAt: now,
      holdUntil: now + 20_000,
    },
    _config: defaultConfig,
  };
}

// No-win fixture: 5 미점령 controlPoint + 3 길드 마스터 모두 생존.
// evaluateWinCondition이 null을 반환해야 한다 (majority leader 없음, master_elim 미충족).
export function makeNoWinPluginState() {
  return {
    eliminatedPlayerIds: [],
    guilds: {
      guild_alpha: { guildId: 'guild_alpha', guildMasterId: 'alpha-master', score: 0 },
      guild_beta: { guildId: 'guild_beta', guildMasterId: 'beta-master', score: 0 },
      guild_gamma: { guildId: 'guild_gamma', guildMasterId: 'gamma-master', score: 0 },
    },
    controlPoints: [
      makeControlPoint({ id: 'cp-1' }),
      makeControlPoint({ id: 'cp-2' }),
      makeControlPoint({ id: 'cp-3' }),
      makeControlPoint({ id: 'cp-4' }),
      makeControlPoint({ id: 'cp-5' }),
    ],
    pendingVictory: null,
    _config: defaultConfig,
  };
}
