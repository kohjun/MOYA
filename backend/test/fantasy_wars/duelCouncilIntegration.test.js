import test from 'node:test';
import assert from 'node:assert/strict';

import { duelService } from '../../src/game/duel/DuelService.js';

// pickMinigame 이 무작위(1/6) 이므로 council_bidding 매칭까지 retry.
function setupCouncilDuel({ challengerPrefix, targetPrefix, sessionPrefix, maxAttempts = 80 }) {
  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    const challengerId = `${challengerPrefix}-${attempt}`;
    const targetId = `${targetPrefix}-${attempt}`;
    const sessionId = `${sessionPrefix}-${attempt}`;

    const events = [];
    const observed = {
      paramsByUser: {},
      minigameType: null,
      resultPayload: null,
      resolveArgs: null,
    };

    const transport = {
      sendToUser(userId, event, payload) {
        events.push({ userId, event, payload });
        if (event === 'fw:duel:started') {
          observed.paramsByUser[userId] = payload.params;
          observed.minigameType = payload.minigameType;
        }
        if (event === 'fw:duel:result') {
          observed.resultPayload = payload;
        }
      },
      sendToSession(_sessionId, event, payload) {
        events.push({ sessionId: _sessionId, event, payload });
        if (event === 'fw:duel:result') {
          observed.resultPayload = payload;
        }
      },
    };

    const challenge = duelService.challenge({
      challengerId,
      targetId,
      sessionId,
      transport,
      onResolve: (args) => {
        observed.resolveArgs = args;
        return null;
      },
    });
    if (!challenge.ok) throw new Error(`challenge failed: ${challenge.error}`);

    const accepted = duelService.accept({ duelId: challenge.duelId, userId: targetId });
    if (!accepted.ok) throw new Error(`accept failed: ${accepted.error}`);

    if (observed.minigameType === 'council_bidding') {
      return {
        duelId: challenge.duelId,
        challengerId,
        targetId,
        observed,
      };
    }

    // 다른 미니게임이면 invalidate 로 정리 후 재시도.
    duelService.invalidate(challenge.duelId, 'test_setup_retry');
  }
  throw new Error('Could not match council_bidding within attempts');
}

test('council bidding integration: per-player myMultiplier exposure', async () => {
  const ctx = setupCouncilDuel({
    challengerPrefix: 'cb-int-c1',
    targetPrefix: 'cb-int-t1',
    sessionPrefix: 'cb-int-s1',
  });

  const cParams = ctx.observed.paramsByUser[ctx.challengerId];
  const tParams = ctx.observed.paramsByUser[ctx.targetId];

  assert.equal(typeof cParams.myMultiplier, 'number');
  assert.equal(typeof tParams.myMultiplier, 'number');
  assert.ok([1.0, 1.2, 1.4, 1.6, 1.8, 2.0].includes(cParams.myMultiplier));
  assert.ok([1.0, 1.2, 1.4, 1.6, 1.8, 2.0].includes(tParams.myMultiplier));

  // 상대 multiplier 가 노출되면 안 됨.
  assert.equal(cParams.multipliersByUser, undefined);
  assert.equal(tParams.multipliersByUser, undefined);

  // 공통 메타.
  assert.equal(cParams.rounds, 3);
  assert.equal(cParams.tokenPool, 100);
  assert.deepEqual(cParams.multiplierLadder, [1.0, 1.2, 1.4, 1.6, 1.8, 2.0]);

  // Cleanup: 양측 동일 입찰 → council_draw 로 resolve.
  const drawRounds = [
    { bid: 30, applyMultiplier: false },
    { bid: 30, applyMultiplier: false },
    { bid: 30, applyMultiplier: false },
  ];
  await duelService.submit({
    duelId: ctx.duelId,
    userId: ctx.challengerId,
    result: { rounds: drawRounds },
  });
  await duelService.submit({
    duelId: ctx.duelId,
    userId: ctx.targetId,
    result: { rounds: drawRounds },
  });

  assert.ok(ctx.observed.resultPayload, 'expected fw:duel:result to be sent');
  assert.equal(ctx.observed.resultPayload.minigameType, 'council_bidding');
});

test('council bidding integration: BO3 with majority winner', async () => {
  const ctx = setupCouncilDuel({
    challengerPrefix: 'cb-int-c2',
    targetPrefix: 'cb-int-t2',
    sessionPrefix: 'cb-int-s2',
  });

  // challenger 가 R1, R2 모두 우위 → 2 승 선취 종료.
  await duelService.submit({
    duelId: ctx.duelId,
    userId: ctx.challengerId,
    result: {
      rounds: [
        { bid: 50, applyMultiplier: false },
        { bid: 30, applyMultiplier: false },
        { bid: 20, applyMultiplier: false },
      ],
    },
  });
  await duelService.submit({
    duelId: ctx.duelId,
    userId: ctx.targetId,
    result: {
      rounds: [
        { bid: 30, applyMultiplier: false },
        { bid: 20, applyMultiplier: false },
        { bid: 50, applyMultiplier: false },
      ],
    },
  });

  const verdict = ctx.observed.resultPayload.verdict;
  assert.equal(verdict.winner, ctx.challengerId);
  assert.equal(verdict.loser, ctx.targetId);
  assert.equal(verdict.reason, 'council_majority');
  // BO3 조기 종료: 2 승 도달 시 R3 미평가.
  assert.equal(verdict.roundResults.length, 2);
});

test('council bidding integration: 100 토큰 초과 입찰은 비례 스케일링', async () => {
  const ctx = setupCouncilDuel({
    challengerPrefix: 'cb-int-c3',
    targetPrefix: 'cb-int-t3',
    sessionPrefix: 'cb-int-s3',
  });

  // challenger 가 합 200 → 절반 스케일 → R1 50 vs 30 (challenger), R2 25 vs 30 (target), R3 25 vs 30 (target).
  await duelService.submit({
    duelId: ctx.duelId,
    userId: ctx.challengerId,
    result: {
      rounds: [
        { bid: 100, applyMultiplier: false },
        { bid: 50, applyMultiplier: false },
        { bid: 50, applyMultiplier: false },
      ],
    },
  });
  await duelService.submit({
    duelId: ctx.duelId,
    userId: ctx.targetId,
    result: {
      rounds: [
        { bid: 30, applyMultiplier: false },
        { bid: 30, applyMultiplier: false },
        { bid: 30, applyMultiplier: false },
      ],
    },
  });

  const verdict = ctx.observed.resultPayload.verdict;
  // target 이 R2/R3 두 라운드 승리 → 2승 선취 → BO3 종료.
  assert.equal(verdict.winner, ctx.targetId);
  assert.equal(verdict.reason, 'council_majority');
});
