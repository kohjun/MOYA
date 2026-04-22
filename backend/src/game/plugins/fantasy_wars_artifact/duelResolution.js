'use strict';

import { consumeShield, isExecutionArmed } from './skills.js';

export function clearDuelState(player) {
  if (!player) {
    return;
  }
  player.inDuel = false;
  player.duelExpiresAt = null;
}

export function resolveCombatBetweenPlayers({
  winner,
  loser,
  reason,
  now = Date.now(),
}) {
  if (!winner || !loser) {
    return {
      verdict: {
        winner: winner?.userId ?? null,
        loser: loser?.userId ?? null,
        reason,
      },
      effects: {},
      eliminated: false,
    };
  }

  clearDuelState(winner);
  clearDuelState(loser);

  const effects = {};
  let eliminated = false;

  if (isExecutionArmed(winner, now)) {
    winner.executionArmedUntil = null;
    effects.executionTriggered = true;

    if (consumeShield(loser, now)) {
      effects.shieldAbsorbed = true;
    } else {
      loser.remainingLives = 0;
      eliminated = true;
    }
  } else if (consumeShield(loser, now)) {
    effects.shieldAbsorbed = true;
  } else {
    const currentLives = loser.remainingLives ?? (loser.job === 'warrior' ? 2 : 1);
    const nextLives = Math.max(0, currentLives - 1);
    loser.remainingLives = nextLives;
    if (loser.job === 'warrior') {
      effects.warriorHp = nextLives;
    }
    eliminated = nextLives <= 0;
  }

  if (!eliminated) {
    loser.hp = 100;
    loser.isAlive = true;
  }

  return {
    verdict: {
      winner: winner.userId,
      loser: loser.userId,
      reason,
      effects,
    },
    effects,
    eliminated,
  };
}
