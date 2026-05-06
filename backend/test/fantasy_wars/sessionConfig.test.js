import test from 'node:test';
import assert from 'node:assert/strict';

import { normalizeFantasyWarsDuelSettings } from '../../src/game/plugins/fantasy_wars_artifact/sessionConfig.js';

test('normalizeFantasyWarsDuelSettings falls back to plugin defaults (dev default)', () => {
  // [DEV DEFAULT] allowGpsFallbackWithoutBle: true 는 에뮬레이터/QA 친화 기본값.
  // 운영 전환 시 host config 또는 env 로 false override 되어야 한다 (아래 production override 테스트 참조).
  const config = normalizeFantasyWarsDuelSettings();

  assert.deepEqual(config, {
    duelRangeMeters: 20,
    bleEvidenceFreshnessMs: 12000,
    allowGpsFallbackWithoutBle: true,
    locationFreshnessMs: 45000,
  });
});

test('normalizeFantasyWarsDuelSettings honors production override (allowGpsFallbackWithoutBle=false)', () => {
  // 운영 전환 시 host 가 lobby config 에 false 를 명시하면 dev default 를 무시하고 false 가 적용되어야 한다.
  const config = normalizeFantasyWarsDuelSettings({
    allowGpsFallbackWithoutBle: false,
  });

  assert.equal(config.allowGpsFallbackWithoutBle, false);
  // 다른 default 는 유지.
  assert.equal(config.duelRangeMeters, 20);
  assert.equal(config.bleEvidenceFreshnessMs, 12000);
  assert.equal(config.locationFreshnessMs, 45000);
});

test('normalizeFantasyWarsDuelSettings clamps invalid numeric values', () => {
  const config = normalizeFantasyWarsDuelSettings({
    duelRangeMeters: 999,
    bleEvidenceFreshnessMs: 1000,
    locationFreshnessMs: '600000',
  });

  assert.equal(config.duelRangeMeters, 100);
  assert.equal(config.bleEvidenceFreshnessMs, 2000);
  assert.equal(config.locationFreshnessMs, 300000);
});

test('normalizeFantasyWarsDuelSettings keeps explicit host choices', () => {
  const config = normalizeFantasyWarsDuelSettings({
    allowGpsFallbackWithoutBle: true,
    bleEvidenceFreshnessMs: 8000,
  });

  assert.equal(config.allowGpsFallbackWithoutBle, true);
  assert.equal(config.bleEvidenceFreshnessMs, 8000);
});
