import test from 'node:test';
import assert from 'node:assert/strict';

import {
  clearDuelState,
  resolveCombatBetweenPlayers,
} from '../../src/game/plugins/fantasy_wars_artifact/duelResolution.js';
import { makePlayer } from '../../testing/fantasy_wars/helpers.js';

test('clearDuelState clears transient duel flags', () => {
  const player = makePlayer({
    inDuel: true,
    duelExpiresAt: 99_999,
  });

  clearDuelState(player);

  assert.equal(player.inDuel, false);
  assert.equal(player.duelExpiresAt, null);
});

test('rogue execution is absorbed by a shield instead of eliminating the target', () => {
  const now = 1000;
  const winner = makePlayer({
    userId: 'rogue-1',
    job: 'rogue',
    executionArmedUntil: now + 5000,
    inDuel: true,
    duelExpiresAt: now + 5000,
  });
  const loser = makePlayer({
    userId: 'priest-1',
    job: 'priest',
    remainingLives: 1,
    shields: [{ from: 'priest-ally', grantedAt: 10, expiresAt: null }],
    inDuel: true,
    duelExpiresAt: now + 5000,
  });

  const result = resolveCombatBetweenPlayers({
    winner,
    loser,
    reason: 'minigame',
    now,
  });

  assert.equal(result.eliminated, false);
  assert.equal(result.effects.executionTriggered, true);
  assert.equal(result.effects.shieldAbsorbed, true);
  assert.equal(loser.remainingLives, 1);
  assert.equal(loser.shields.length, 0);
  assert.equal(winner.executionArmedUntil, null);
  assert.equal(winner.inDuel, false);
  assert.equal(loser.inDuel, false);
});

test('rogue execution eliminates unshielded target regardless of remaining lives', () => {
  const now = 2000;
  const winner = makePlayer({
    userId: 'rogue-1',
    job: 'rogue',
    executionArmedUntil: now + 5000,
  });
  const loser = makePlayer({
    userId: 'warrior-1',
    job: 'warrior',
    remainingLives: 2,
  });

  const result = resolveCombatBetweenPlayers({
    winner,
    loser,
    reason: 'minigame',
    now,
  });

  assert.equal(result.eliminated, true);
  assert.equal(result.effects.executionTriggered, true);
  assert.equal(loser.remainingLives, 0);
});

test('warrior loses one life on defeat before elimination', () => {
  const loser = makePlayer({
    userId: 'warrior-1',
    job: 'warrior',
    remainingLives: 2,
    hp: 45,
    isAlive: true,
    inDuel: true,
  });

  const result = resolveCombatBetweenPlayers({
    winner: makePlayer({ userId: 'mage-1', job: 'mage', inDuel: true }),
    loser,
    reason: 'minigame',
    now: 3000,
  });

  assert.equal(result.eliminated, false);
  assert.equal(result.effects.warriorHp, 1);
  assert.equal(loser.remainingLives, 1);
  assert.equal(loser.hp, 100);
  assert.equal(loser.isAlive, true);
});

test('non-warrior without shield is eliminated on defeat', () => {
  const loser = makePlayer({
    userId: 'priest-1',
    job: 'priest',
    remainingLives: 1,
    hp: 35,
  });

  const result = resolveCombatBetweenPlayers({
    winner: makePlayer({ userId: 'ranger-1', job: 'ranger' }),
    loser,
    reason: 'minigame',
    now: 4000,
  });

  assert.equal(result.eliminated, true);
  assert.deepEqual(result.effects, {});
  assert.equal(loser.remainingLives, 0);
});
