import test from 'node:test';
import assert from 'node:assert/strict';

import {
  validateSkill,
  applySkillEffect,
  activeShields,
  consumeShield,
  isExecutionArmed,
} from '../../src/game/plugins/fantasy_wars_artifact/skills.js';
import { makeControlPoint, makePlayer } from '../../testing/fantasy_wars/helpers.js';

test('validateSkill enforces job-to-skill mapping', () => {
  assert.deepEqual(validateSkill('priest', 'shield'), {
    ok: true,
    effect: 'shield',
  });
  assert.deepEqual(validateSkill('priest', 'reveal'), {
    ok: false,
    error: 'WRONG_SKILL',
  });
  assert.deepEqual(validateSkill('warrior', 'shield'), {
    ok: false,
    error: 'NO_ACTIVE_SKILL',
  });
});

test('shield skill only applies to allies who are not currently in a duel', () => {
  const player = makePlayer({ userId: 'priest-1', job: 'priest' });
  const ally = makePlayer({ userId: 'ally-1', guildId: player.guildId });
  const enemy = makePlayer({ userId: 'enemy-1', guildId: 'guild_beta' });

  const success = applySkillEffect('shield', {
    player,
    targetPlayer: ally,
    now: 1000,
  });
  assert.deepEqual(success, {
    type: 'shield',
    targetUserId: 'ally-1',
    shieldCount: 1,
  });
  assert.equal(ally.shields.length, 1);

  assert.deepEqual(
    applySkillEffect('shield', { player, targetPlayer: enemy, now: 1000 }),
    { type: 'shield', error: 'TARGET_NOT_ALLY' },
  );
  assert.deepEqual(
    applySkillEffect('shield', {
      player,
      targetPlayer: makePlayer({
        userId: 'ally-2',
        guildId: player.guildId,
        inDuel: true,
        duelExpiresAt: 2000,
      }),
      now: 1000,
    }),
    { type: 'shield', error: 'TARGET_IN_DUEL' },
  );
});

test('blockade, reveal, and execution effects update state as expected', () => {
  const mage = makePlayer({ userId: 'mage-1', job: 'mage' });
  const ranger = makePlayer({ userId: 'ranger-1', job: 'ranger' });
  const rogue = makePlayer({ userId: 'rogue-1', job: 'rogue' });
  const enemy = makePlayer({ userId: 'enemy-1', guildId: 'guild_beta' });
  const cp = makeControlPoint({ id: 'cp-7' });

  assert.deepEqual(
    applySkillEffect('blockade', { player: mage, cp, now: 5000 }),
    { type: 'blockade', cpId: 'cp-7', expiresAt: 65_000 },
  );
  assert.equal(cp.blockadedBy, mage.guildId);

  assert.deepEqual(
    applySkillEffect('reveal', { player: ranger, targetPlayer: enemy, now: 5000 }),
    { type: 'reveal', targetUserId: 'enemy-1', revealUntil: 65_000 },
  );
  assert.equal(ranger.trackedTargetUserId, 'enemy-1');
  assert.deepEqual(
    applySkillEffect('reveal', {
      player: ranger,
      targetPlayer: makePlayer({ userId: 'ally-1', guildId: ranger.guildId }),
      now: 5000,
    }),
    { type: 'reveal', error: 'TARGET_NOT_ENEMY' },
  );

  assert.deepEqual(
    applySkillEffect('execution', { player: rogue, now: 5000 }),
    { type: 'execution', armedUntil: 65_000 },
  );
  assert.equal(isExecutionArmed(rogue, 6000), true);
  assert.equal(isExecutionArmed(rogue, 66_000), false);
});

test('blockade on a CP that is being captured applies blockade AND signals capture disrupt', () => {
  const mage = makePlayer({ userId: 'mage-2', job: 'mage', guildId: 'guild_alpha' });
  // 진행 중 점령: capturingGuild 가 적 길드.
  const cp = makeControlPoint({
    id: 'cp-9',
    capturingGuild: 'guild_beta',
    captureStartedAt: 1000,
    captureProgress: 40,
    requiredCount: 2,
    readyCount: 2,
  });

  const result = applySkillEffect('blockade', { player: mage, cp, now: 5000 });
  assert.deepEqual(result, {
    type: 'blockade',
    cpId: 'cp-9',
    expiresAt: 65_000,
    disrupted: true,
    interruptedGuild: 'guild_beta',
  });

  // 봉쇄는 정상 적용된다 (지속시간 60s).
  assert.equal(cp.blockadedBy, mage.guildId);
  assert.equal(cp.blockadeExpiresAt, 65_000);
  // capture state 클린업은 핸들러가 책임 — applySkillEffect 자체는 capture 필드를
  // 건드리지 않고 disrupted 플래그로 핸들러에 위임한다.
  assert.equal(cp.capturingGuild, 'guild_beta');
});

test('blockade on idle CP still applies normally (regression)', () => {
  const mage = makePlayer({ userId: 'mage-3', job: 'mage', guildId: 'guild_alpha' });
  const cp = makeControlPoint({ id: 'cp-10' });

  const result = applySkillEffect('blockade', { player: mage, cp, now: 7000 });
  assert.equal(result.type, 'blockade');
  assert.equal(result.disrupted, undefined);
  assert.equal(result.expiresAt, 67_000);
  assert.equal(cp.blockadedBy, mage.guildId);
});

test('shield helpers report and consume active shields', () => {
  const player = makePlayer({
    shields: [
      { from: 'expired', grantedAt: 1, expiresAt: 10 },
      { from: 'active-1', grantedAt: 2, expiresAt: 200 },
      { from: 'active-2', grantedAt: 3, expiresAt: null },
    ],
  });

  assert.equal(activeShields(player, 100).length, 2);
  assert.equal(consumeShield(player, 100), true);
  assert.deepEqual(
    player.shields.map((shield) => shield.from),
    ['expired', 'active-2'],
  );
  assert.equal(consumeShield(player, 100), true);
  assert.equal(consumeShield(player, 100), false);
});
