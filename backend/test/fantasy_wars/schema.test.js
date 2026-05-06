import test from 'node:test';
import assert from 'node:assert/strict';

import {
  configSchema,
  defaultConfig,
  JOB_PRIORITY,
  resolveDuelConfig,
} from '../../src/game/plugins/fantasy_wars_artifact/schema.js';

test('Fantasy Wars defaults match approved ruleset (dev defaults)', () => {
  // [DEV DEFAULT] allowGpsFallbackWithoutBle 가 true 인 것은 에뮬레이터/QA 임시값.
  // 운영 전환 시 README 의 운영 전환 체크리스트 참조하여 false 로 override 한다.
  assert.equal(configSchema.captureDurationSec.default, 30);
  // [W4] hold delay 0 = 다수 점령 도달 즉시 게임 종료. UX 요구 ("3개 점령했는데 게임이
  // 안 끝남") 에 맞춘 기본값. host config 에서 override 가능.
  assert.equal(configSchema.controlPointHoldDurationSec.default, 0);
  assert.equal(configSchema.reviveBaseChance.default, 0.3);
  assert.equal(configSchema.reviveMaxChance.default, 0.8);
  assert.equal(configSchema.bleEvidenceFreshnessMs.default, 12000);
  assert.equal(configSchema.allowGpsFallbackWithoutBle.default, true);
  assert.equal(defaultConfig.captureDurationSec, 30);
  assert.equal(defaultConfig.controlPointHoldDurationSec, 0);
  assert.equal(defaultConfig.reviveBaseChance, 0.3);
  assert.equal(defaultConfig.reviveMaxChance, 0.8);
  assert.equal(defaultConfig.bleEvidenceFreshnessMs, 12000);
  assert.equal(defaultConfig.allowGpsFallbackWithoutBle, true);
  assert.deepEqual(defaultConfig.skillCooldowns, {
    priest: 600,
    mage: 600,
    ranger: 300,
    rogue: 600,
  });
});

test('Fantasy Wars job rotation uses only approved jobs', () => {
  const allowedJobs = new Set(['warrior', 'priest', 'mage', 'ranger', 'rogue']);
  const legacyJobs = new Set(['guild_master', 'archer', 'healer', 'scout']);

  assert.ok(JOB_PRIORITY.length > 0);
  JOB_PRIORITY.forEach((job) => {
    assert.ok(allowedJobs.has(job));
    assert.equal(legacyJobs.has(job), false);
  });
});

test('resolveDuelConfig keeps realtime duel defaults aligned (dev defaults)', () => {
  // [DEV DEFAULT] allowGpsFallbackWithoutBle: true 는 에뮬레이터 결투 테스트용 임시값.
  assert.deepEqual(resolveDuelConfig(), {
    duelRangeMeters: 20,
    bleEvidenceFreshnessMs: 12000,
    allowGpsFallbackWithoutBle: true,
    locationFreshnessMs: 45000,
    locationAccuracyMaxMeters: 50,
  });

  assert.deepEqual(resolveDuelConfig({
    duelRangeMeters: 14,
    bleEvidenceFreshnessMs: 8000,
    allowGpsFallbackWithoutBle: true,
    locationFreshnessMs: 12000,
    locationAccuracyMaxMeters: 30,
  }), {
    duelRangeMeters: 14,
    bleEvidenceFreshnessMs: 8000,
    allowGpsFallbackWithoutBle: true,
    locationFreshnessMs: 12000,
    locationAccuracyMaxMeters: 30,
  });
});

test('resolveDuelConfig honors production override (allowGpsFallbackWithoutBle=false)', () => {
  // 운영 전환 시 host config 에 false 를 명시하면 dev default 를 덮어쓰고 false 가 적용되어야 한다.
  const result = resolveDuelConfig({ allowGpsFallbackWithoutBle: false });
  assert.equal(result.allowGpsFallbackWithoutBle, false);
  // 다른 default 는 유지.
  assert.equal(result.duelRangeMeters, 20);
  assert.equal(result.bleEvidenceFreshnessMs, 12000);
  assert.equal(result.locationFreshnessMs, 45000);
  assert.equal(result.locationAccuracyMaxMeters, 50);
});
