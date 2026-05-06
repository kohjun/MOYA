import test from 'node:test';
import assert from 'node:assert/strict';

import {
  generateMinigameParams,
  buildPublicMinigameParams,
  judgeMinigame,
} from '../../src/game/duel/minigames/index.js';

function scoreHand(cards) {
  let total = cards.reduce((sum, card) => sum + card, 0);
  let aces = cards.filter((card) => card === 11).length;
  while (total > 21 && aces > 0) {
    total -= 10;
    aces -= 1;
  }
  return total > 21 ? 0 : total;
}

function findBlackjackWinner(params, participants) {
  const bestByUser = {};

  participants.forEach((userId) => {
    const baseHand = params.handsByUser[userId];
    const drawPile = params.drawPilesByUser[userId];
    let bestScore = -1;
    let bestHitCount = 0;

    for (let hitCount = 0; hitCount <= drawPile.length; hitCount += 1) {
      const score = scoreHand([...baseHand, ...drawPile.slice(0, hitCount)]);
      if (score > bestScore) {
        bestScore = score;
        bestHitCount = hitCount;
      }
    }

    bestByUser[userId] = { bestScore, bestHitCount };
  });

  const [left, right] = participants;
  if (bestByUser[left].bestScore === bestByUser[right].bestScore) {
    return null;
  }

  return bestByUser[left].bestScore > bestByUser[right].bestScore
    ? { winner: left, loser: right, picks: bestByUser }
    : { winner: right, loser: left, picks: bestByUser };
}

test('precision minigame uses shared target list for judging', () => {
  const params = generateMinigameParams('precision', 'seed-precision');
  assert.equal(params.shots, 3);
  assert.equal(params.targets.length, 3);

  const submissions = {
    alpha: {
      hits: params.targets.map((target) => ({ x: target.x, y: target.y })),
    },
    beta: {
      hits: params.targets.map((target) => ({
        x: Math.min(1, target.x + 0.08),
        y: Math.min(1, target.y + 0.08),
      })),
    },
  };

  const verdict = judgeMinigame('precision', 'seed-precision', submissions, params);
  assert.equal(verdict.winner, 'alpha');
  assert.equal(verdict.reason, 'better_precision');
});

test('speed blackjack exposes only the participant hand and draw pile', () => {
  const participants = ['user-1', 'user-2'];
  const params = generateMinigameParams('speed_blackjack', 'seed-blackjack', participants);

  const publicParams = buildPublicMinigameParams('speed_blackjack', params, 'user-1');
  assert.deepEqual(publicParams.hand, params.handsByUser['user-1']);
  assert.deepEqual(publicParams.drawPile, params.drawPilesByUser['user-1']);
  assert.equal(publicParams.hand.length, 2);
  assert.ok(publicParams.drawPile.length > 0);
});

test('speed blackjack verdict is computed from server-side hands and hit counts', () => {
  const participants = ['user-1', 'user-2'];
  const params = generateMinigameParams('speed_blackjack', 'seed-blackjack-score', participants);
  const expected = findBlackjackWinner(params, participants);

  assert.ok(expected, 'expected a non-draw blackjack seed for this test');

  const submissions = {
    'user-1': { hitCount: expected.picks['user-1'].bestHitCount },
    'user-2': { hitCount: expected.picks['user-2'].bestHitCount },
  };

  const verdict = judgeMinigame(
    'speed_blackjack',
    'seed-blackjack-score',
    submissions,
    params,
  );

  assert.equal(verdict.winner, expected.winner);
  assert.equal(verdict.loser, expected.loser);
  assert.equal(verdict.reason, 'higher_hand');
});

test('council bidding rolls per-player multiplier from the 1.0–2.0 ladder', () => {
  const participants = ['user-1', 'user-2'];
  const params = generateMinigameParams('council_bidding', 'seed-council', participants);
  assert.equal(params.rounds, 3);
  assert.equal(params.tokenPool, 100);
  assert.deepEqual(params.multiplierLadder, [1.0, 1.2, 1.4, 1.6, 1.8, 2.0]);
  assert.ok(params.multipliersByUser['user-1']);
  assert.ok(params.multipliersByUser['user-2']);
  for (const m of Object.values(params.multipliersByUser)) {
    assert.ok([1.0, 1.2, 1.4, 1.6, 1.8, 2.0].includes(m));
  }
});

test('council bidding public params expose only the requesting player\'s multiplier', () => {
  const participants = ['user-1', 'user-2'];
  const params = generateMinigameParams('council_bidding', 'seed-council-public', participants);
  const publicForP1 = buildPublicMinigameParams('council_bidding', params, 'user-1');
  assert.equal(publicForP1.myMultiplier, params.multipliersByUser['user-1']);
  assert.ok(!('multipliersByUser' in publicForP1));
});

test('council bidding judges BO3 with multiplier applied at chosen round', () => {
  // 강제로 multiplier 고정해서 결정적 테스트.
  const params = {
    rounds: 3,
    tokenPool: 100,
    multiplierLadder: [1.0, 1.2, 1.4, 1.6, 1.8, 2.0],
    multipliersByUser: { 'user-1': 1.6, 'user-2': 1.2 },
  };

  // R1: u1 40 vs u2 30 → u1 win
  // R2: u1 34 ×1.6 = 54.4 vs u2 50 → u1 win (먼저 2승 → 종료)
  const submissions = {
    'user-1': {
      rounds: [
        { bid: 40, applyMultiplier: false },
        { bid: 34, applyMultiplier: true },
        { bid: 26, applyMultiplier: false },
      ],
    },
    'user-2': {
      rounds: [
        { bid: 30, applyMultiplier: false },
        { bid: 50, applyMultiplier: false },
        { bid: 20, applyMultiplier: true },
      ],
    },
  };

  const verdict = judgeMinigame('council_bidding', 'seed-x', submissions, params);
  assert.equal(verdict.winner, 'user-1');
  assert.equal(verdict.loser, 'user-2');
  assert.equal(verdict.reason, 'council_majority');
  // 2승 도달 즉시 종료 → R3 는 평가하지 않음.
  assert.equal(verdict.roundResults.length, 2);
});

test('council bidding rejects 2nd multiplier toggle (only first counts)', () => {
  const params = {
    rounds: 3,
    tokenPool: 100,
    multipliersByUser: { 'user-1': 2.0, 'user-2': 1.0 },
  };
  const submissions = {
    // u1 가 모든 라운드에 multiplier 적용 시도 → 첫 라운드만 적용되어야.
    'user-1': {
      rounds: [
        { bid: 40, applyMultiplier: true },  // 적용 → 80
        { bid: 30, applyMultiplier: true },  // 무시 → 30
        { bid: 30, applyMultiplier: true },  // 무시 → 30
      ],
    },
    'user-2': {
      rounds: [
        { bid: 60, applyMultiplier: false },
        { bid: 25, applyMultiplier: false },
        { bid: 15, applyMultiplier: false },
      ],
    },
  };
  // R1: 80 vs 60 → u1 / R2: 30 vs 25 → u1 / 종료
  const verdict = judgeMinigame('council_bidding', 'seed', submissions, params);
  assert.equal(verdict.winner, 'user-1');
  assert.equal(verdict.roundResults[1].effective['user-1'], 30);
  assert.equal(verdict.roundResults[1].effective['user-2'], 25);
});

test('council bidding scales bids when total exceeds token pool', () => {
  const params = {
    rounds: 3,
    tokenPool: 100,
    multipliersByUser: { 'user-1': 1.0, 'user-2': 1.0 },
  };
  // u1 합 200 → 절반으로 스케일.
  const submissions = {
    'user-1': {
      rounds: [
        { bid: 100, applyMultiplier: false },
        { bid: 50, applyMultiplier: false },
        { bid: 50, applyMultiplier: false },
      ],
    },
    'user-2': {
      rounds: [
        { bid: 30, applyMultiplier: false },
        { bid: 30, applyMultiplier: false },
        { bid: 30, applyMultiplier: false },
      ],
    },
  };
  const verdict = judgeMinigame('council_bidding', 'seed', submissions, params);
  // 스케일 후 u1: [50, 25, 25] vs u2: [30, 30, 30]
  // R1: 50 > 30 (u1) / R2: 25 < 30 (u2) / R3: 25 < 30 (u2) → u2 2승.
  assert.equal(verdict.winner, 'user-2');
  assert.equal(verdict.reason, 'council_majority');
});

test('council bidding ends in draw when round wins are equal', () => {
  const params = {
    rounds: 3,
    tokenPool: 100,
    multipliersByUser: { 'user-1': 1.0, 'user-2': 1.0 },
  };
  // R1: u1 win / R2: u2 win / R3: 동률 → 1-1 with draw → 무승부.
  const submissions = {
    'user-1': {
      rounds: [
        { bid: 50, applyMultiplier: false },
        { bid: 20, applyMultiplier: false },
        { bid: 30, applyMultiplier: false },
      ],
    },
    'user-2': {
      rounds: [
        { bid: 30, applyMultiplier: false },
        { bid: 40, applyMultiplier: false },
        { bid: 30, applyMultiplier: false },
      ],
    },
  };
  const verdict = judgeMinigame('council_bidding', 'seed', submissions, params);
  assert.equal(verdict.winner, null);
  assert.equal(verdict.loser, null);
  assert.equal(verdict.reason, 'council_draw');
});
