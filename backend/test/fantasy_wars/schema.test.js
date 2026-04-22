import test from 'node:test';
import assert from 'node:assert/strict';

import {
  configSchema,
  defaultConfig,
  JOB_PRIORITY,
} from '../../src/game/plugins/fantasy_wars_artifact/schema.js';

test('Fantasy Wars defaults match approved ruleset', () => {
  assert.equal(configSchema.captureDurationSec.default, 30);
  assert.equal(configSchema.reviveBaseChance.default, 0.3);
  assert.equal(defaultConfig.captureDurationSec, 30);
  assert.equal(defaultConfig.reviveBaseChance, 0.3);
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
