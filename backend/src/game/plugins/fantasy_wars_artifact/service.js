'use strict';

import { getPublicState, getPrivateState } from './stateViews.js';
import { handleDungeonEnter, handleReviveAttempt } from './reviveHandlers.js';
import { handleUseSkill } from './skillHandlers.js';
import {
  handleCaptureStart,
  handleCaptureCancel,
  handleCaptureDisrupt,
} from './captureHandlers.js';
import {
  resolveCombatBetweenPlayers,
  eliminatePlayer,
} from './duelResolution.js';
import { checkWinCondition as evaluateWinCondition } from './winConditions.js';

export { getPublicState, getPrivateState };

export function checkWinCondition(gameState, config = {}) {
  return evaluateWinCondition(gameState, config);
}

export async function handleEvent(eventName, payload, ctx) {
  switch (eventName) {
    case 'capture_start':
      return handleCaptureStart(payload, ctx);
    case 'capture_cancel':
      return handleCaptureCancel(payload, ctx);
    case 'capture_disrupt':
      return handleCaptureDisrupt(payload, ctx);
    case 'use_skill':
      return handleUseSkill(payload, ctx);
    case 'attack':
      return { error: 'ATTACK_DISABLED_USE_DUEL' };
    case 'revive':
      return handleReviveAttempt(payload, ctx);
    case 'dungeon_enter':
      return handleDungeonEnter(payload, ctx);
    default:
      return false;
  }
}

export function resolveDuelOutcome(gameState, { winnerId, loserId, reason }) {
  const ps = gameState.pluginState ?? {};
  const winner = ps.playerStates?.[winnerId];
  const loser = ps.playerStates?.[loserId];

  if (!winner || !loser) {
    return {
      verdict: { winner: winnerId, loser: loserId, reason },
      effects: {},
      eliminated: false,
    };
  }

  const resolution = resolveCombatBetweenPlayers({ winner, loser, reason });
  const { eliminated } = resolution;
  if (eliminated) {
    eliminatePlayer(loser, gameState);
  }

  return resolution;
}
