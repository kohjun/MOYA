'use strict';

// Fantasy Wars Artifact plugin config and role defaults.

export const configSchema = {
  teamCount: { type: 'number', default: 3, min: 2, max: 4 },
  controlPointCount: { type: 'number', default: 5, min: 3, max: 9 },
  captureDurationSec: { type: 'number', default: 30, min: 15, max: 300 },
  // 0 = hold 없이 다수 점령 도달 즉시 게임 종료. UX 요구 ("3개 점령했는데 게임이
  // 안 끝남") 에 맞춰 hold delay 를 끈 기본값. 운영 단계에서 다시 늘리려면
  // 0..120s 범위 안에서 host 설정 가능.
  controlPointHoldDurationSec: { type: 'number', default: 0, min: 0, max: 120 },
  captureRadiusMeters: { type: 'number', default: 30, min: 5, max: 200 },
  captureReadyWindowMs: { type: 'number', default: 5000, min: 1000, max: 15000 },
  duelRangeMeters: { type: 'number', default: 20, min: 1, max: 100 },
  bleEvidenceFreshnessMs: { type: 'number', default: 12000, min: 2000, max: 60000 },
  // [DEV DEFAULT] Local/emulator-friendly default. Production should override this via
  // host lobby config (allowGpsFallbackWithoutBle: false) — see README 운영 전환 체크리스트.
  // resolveDuelConfig / normalizeFantasyWarsDuelSettings 가 host config 우선 적용한다.
  allowGpsFallbackWithoutBle: { type: 'boolean', default: true },
  locationFreshnessMs: { type: 'number', default: 45000, min: 5000, max: 300000 },
  locationAccuracyMaxMeters: { type: 'number', default: 50, min: 5, max: 500 },
  reviveBaseChance: { type: 'number', default: 0.3, min: 0.1, max: 1.0 },
  reviveStepChance: { type: 'number', default: 0.1, min: 0.0, max: 0.5 },
  reviveMaxChance: { type: 'number', default: 0.8, min: 0.3, max: 1.0 },
  controlPoints: { type: 'array', default: [] },
  skillCooldowns: {
    type: 'object',
    default: {
      priest: 600,
      mage: 600,
      ranger: 300,
      rogue: 600,
    },
  },
  winByMajority: { type: 'boolean', default: false },
  winByMasterElim: { type: 'boolean', default: true },
};

export const defaultConfig = {
  teamCount: 3,
  controlPointCount: 5,
  captureDurationSec: 30,
  controlPointHoldDurationSec: 0,
  captureRadiusMeters: 30,
  captureReadyWindowMs: 5000,
  duelRangeMeters: 20,
  bleEvidenceFreshnessMs: 12000,
  // [DEV DEFAULT] Local/emulator-friendly default. Production should override via host lobby config
  // — see README 운영 전환 체크리스트.
  allowGpsFallbackWithoutBle: true,
  locationFreshnessMs: 45000,
  locationAccuracyMaxMeters: 50,
  reviveBaseChance: 0.3,
  reviveStepChance: 0.1,
  reviveMaxChance: 0.8,
  controlPoints: [],
  skillCooldowns: {
    priest: 600,
    mage: 600,
    ranger: 300,
    rogue: 600,
  },
  winByMajority: false,
  winByMasterElim: true,
};

export function resolveDuelConfig(config = {}) {
  return {
    duelRangeMeters: config.duelRangeMeters ?? defaultConfig.duelRangeMeters,
    bleEvidenceFreshnessMs:
      config.bleEvidenceFreshnessMs ?? defaultConfig.bleEvidenceFreshnessMs,
    allowGpsFallbackWithoutBle:
      config.allowGpsFallbackWithoutBle ?? defaultConfig.allowGpsFallbackWithoutBle,
    locationFreshnessMs:
      config.locationFreshnessMs ?? defaultConfig.locationFreshnessMs,
    locationAccuracyMaxMeters:
      config.locationAccuracyMaxMeters ?? defaultConfig.locationAccuracyMaxMeters,
  };
}

export const GUILD_IDS = ['guild_alpha', 'guild_beta', 'guild_gamma', 'guild_delta'];

// Guild master is a status flag, not a separate job.
export const JOB_PRIORITY = [
  'warrior',
  'priest',
  'mage',
  'ranger',
  'rogue',
  'warrior',
  'ranger',
  'priest',
  'mage',
  'rogue',
];
