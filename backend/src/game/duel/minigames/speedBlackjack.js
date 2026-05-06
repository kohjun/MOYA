'use strict';

import { sr, clampInt } from './shared.js';

const BLACKJACK_DRAW_LIMIT = 8;
const BLACKJACK_TARGET_SCORE = 21;
const BLACKJACK_TIMEOUT_SEC = 15;

function buildBlackjackDeck(seed) {
  const deck = [];
  for (let value = 1; value <= 13; value += 1) {
    const cardValue = value === 1 ? 11 : Math.min(value, 10);
    for (let suit = 0; suit < 4; suit += 1) {
      deck.push(cardValue);
    }
  }

  for (let index = deck.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(sr(seed, index + 100) * (index + 1));
    [deck[index], deck[swapIndex]] = [deck[swapIndex], deck[index]];
  }

  return deck;
}

function buildBlackjackState(seed, participants) {
  const deck = buildBlackjackDeck(seed);
  const handsByUser = {};
  const drawPilesByUser = {};
  let cursor = 0;

  participants.forEach((userId) => {
    handsByUser[userId] = [deck[cursor], deck[cursor + 1]];
    cursor += 2;
  });

  participants.forEach((userId) => {
    drawPilesByUser[userId] = deck.slice(cursor, cursor + BLACKJACK_DRAW_LIMIT);
    cursor += BLACKJACK_DRAW_LIMIT;
  });

  return { handsByUser, drawPilesByUser };
}

function scoreBlackjackHand(cards) {
  let total = cards.reduce((sum, card) => sum + card, 0);
  let aces = cards.filter((card) => card === 11).length;

  while (total > BLACKJACK_TARGET_SCORE && aces > 0) {
    total -= 10;
    aces -= 1;
  }

  return total > BLACKJACK_TARGET_SCORE ? 0 : total;
}

function scoreBlackjackSubmission(userId, submission, params) {
  const baseHand = Array.isArray(params?.handsByUser?.[userId])
    ? params.handsByUser[userId]
    : [];
  const drawPile = Array.isArray(params?.drawPilesByUser?.[userId])
    ? params.drawPilesByUser[userId]
    : [];
  const hitCount = clampInt(submission?.hitCount, 0, drawPile.length, 0);
  const cards = [...baseHand, ...drawPile.slice(0, hitCount)];
  return scoreBlackjackHand(cards);
}

export function generateParams(seed, participants) {
  const { handsByUser, drawPilesByUser } = buildBlackjackState(seed, participants);
  return {
    targetScore: BLACKJACK_TARGET_SCORE,
    timeoutSec: BLACKJACK_TIMEOUT_SEC,
    handsByUser,
    drawPilesByUser,
  };
}

export function buildPublic(params, participantId) {
  return {
    targetScore: params?.targetScore ?? BLACKJACK_TARGET_SCORE,
    timeoutSec: params?.timeoutSec ?? BLACKJACK_TIMEOUT_SEC,
    hand: Array.isArray(params?.handsByUser?.[participantId])
      ? params.handsByUser[participantId]
      : [],
    drawPile: Array.isArray(params?.drawPilesByUser?.[participantId])
      ? params.drawPilesByUser[participantId]
      : [],
  };
}

export function judge({ p1, p2, s1, s2, params }) {
  const sc1 = scoreBlackjackSubmission(p1, s1, params);
  const sc2 = scoreBlackjackSubmission(p2, s2, params);
  if (sc1 === sc2) {
    return { winner: null, loser: null, reason: 'draw' };
  }

  return sc1 > sc2
    ? { winner: p1, loser: p2, reason: 'higher_hand' }
    : { winner: p2, loser: p1, reason: 'higher_hand' };
}
