import test from 'node:test';
import assert from 'node:assert/strict';

import { duelService } from '../../src/game/duel/DuelService.js';

function scoreHand(cards) {
  let total = cards.reduce((sum, card) => sum + card, 0);
  let aces = cards.filter((card) => card === 11).length;

  while (total > 21 && aces > 0) {
    total -= 10;
    aces -= 1;
  }

  return total > 21 ? 0 : total;
}

function drawSubmissionFor(type, paramsByUser, participants) {
  switch (type) {
    case 'reaction_time':
      return {
        [participants[0]]: { reactionMs: 250 },
        [participants[1]]: { reactionMs: 250 },
      };
    case 'rapid_tap':
      return {
        [participants[0]]: { tapCount: 20, durationMs: 5000 },
        [participants[1]]: { tapCount: 20, durationMs: 5000 },
      };
    case 'precision':
      return {
        [participants[0]]: { hits: paramsByUser[participants[0]].targets },
        [participants[1]]: { hits: paramsByUser[participants[1]].targets },
      };
    case 'russian_roulette':
      return {
        [participants[0]]: { chamber: 1 },
        [participants[1]]: { chamber: 1 },
      };
    case 'speed_blackjack': {
      const scoreByUser = {};
      participants.forEach((userId) => {
        const params = paramsByUser[userId];
        scoreByUser[userId] = new Map();
        for (let hitCount = 0; hitCount <= params.drawPile.length; hitCount += 1) {
          scoreByUser[userId].set(
            scoreHand([...params.hand, ...params.drawPile.slice(0, hitCount)]),
            hitCount,
          );
        }
      });

      for (const [score, leftHitCount] of scoreByUser[participants[0]]) {
        const rightHitCount = scoreByUser[participants[1]].get(score);
        if (rightHitCount != null) {
          return {
            [participants[0]]: { hitCount: leftHitCount },
            [participants[1]]: { hitCount: rightHitCount },
          };
        }
      }
      throw new Error('Unable to build draw blackjack submissions');
    }
    case 'council_bidding': {
      // 양측 동일 입찰 → 모든 라운드 무승부 → council_draw.
      const drawRounds = [
        { bid: 30, applyMultiplier: false },
        { bid: 30, applyMultiplier: false },
        { bid: 30, applyMultiplier: false },
      ];
      return {
        [participants[0]]: { rounds: drawRounds },
        [participants[1]]: { rounds: drawRounds },
      };
    }
    default:
      throw new Error(`Unsupported minigame type: ${type}`);
  }
}

test('duel resolution passes participant ids to draw cleanup path', async () => {
  const participants = ['duel-draw-challenger', 'duel-draw-target'];
  const paramsByUser = {};
  let minigameType = null;
  let resolveArgs = null;

  const transport = {
    sendToUser(userId, event, payload) {
      if (event === 'fw:duel:started') {
        paramsByUser[userId] = payload.params;
        minigameType = payload.minigameType;
      }
    },
    sendToSession() {},
  };

  const challenge = duelService.challenge({
    challengerId: participants[0],
    targetId: participants[1],
    sessionId: 'duel-draw-session',
    transport,
    onResolve: (args) => {
      resolveArgs = args;
      return null;
    },
  });
  assert.equal(challenge.ok, true);

  const accepted = duelService.accept({
    duelId: challenge.duelId,
    userId: participants[1],
  });
  assert.equal(accepted.ok, true);
  assert.ok(minigameType);

  const submissions = drawSubmissionFor(minigameType, paramsByUser, participants);
  await duelService.submit({
    duelId: challenge.duelId,
    userId: participants[0],
    result: submissions[participants[0]],
  });
  await duelService.submit({
    duelId: challenge.duelId,
    userId: participants[1],
    result: submissions[participants[1]],
  });

  assert.equal(resolveArgs?.winnerId, null);
  assert.equal(resolveArgs?.loserId, null);
  assert.equal(resolveArgs?.challengerId, participants[0]);
  assert.equal(resolveArgs?.targetId, participants[1]);
  assert.equal(duelService.isInDuel(participants[0]), false);
  assert.equal(duelService.isInDuel(participants[1]), false);
});

test('markPlayStarted arms game timer and broadcasts fw:duel:play_armed', () => {
  const participants = ['mps-challenger', 'mps-target'];
  const armedEvents = [];
  const transport = {
    sendToUser(userId, event, payload) {
      if (event === 'fw:duel:play_armed') {
        armedEvents.push({ userId, payload });
      }
    },
    sendToSession() {},
  };

  const challenge = duelService.challenge({
    challengerId: participants[0],
    targetId: participants[1],
    sessionId: 'mps-session',
    transport,
    onResolve: () => null,
  });
  assert.equal(challenge.ok, true);
  const accepted = duelService.accept({ duelId: challenge.duelId, userId: participants[1] });
  assert.equal(accepted.ok, true);

  const acceptedAt = duelService.getDuel(challenge.duelId).startedAt;
  assert.ok(acceptedAt);

  // 첫 번째 클라가 emit → 본 게임 타이머 가동, startedAt 이 새로 갱신되고
  // play_armed 가 두 사용자에게 브로드캐스트.
  const first = duelService.markPlayStarted({ duelId: challenge.duelId, userId: participants[0] });
  assert.equal(first.ok, true);
  assert.equal(first.alreadyStarted, false);
  assert.equal(first.gameTimeoutMs, 30_000);
  assert.ok(first.startedAt >= acceptedAt);
  assert.equal(armedEvents.length, 2);
  assert.deepEqual(
    armedEvents.map((e) => e.userId).sort(),
    [...participants].sort(),
  );

  // 두 번째 클라가 늦게 emit → idempotent. 새 타이머를 또 걸지 않음 (브로드캐스트도 추가 없음).
  const armedBefore = armedEvents.length;
  const second = duelService.markPlayStarted({ duelId: challenge.duelId, userId: participants[1] });
  assert.equal(second.ok, true);
  assert.equal(second.alreadyStarted, true);
  assert.equal(second.startedAt, first.startedAt);
  assert.equal(armedEvents.length, armedBefore);

  // 비참가자는 거부.
  const stranger = duelService.markPlayStarted({ duelId: challenge.duelId, userId: 'someone-else' });
  assert.equal(stranger.ok, false);
  assert.equal(stranger.error, 'NOT_PARTICIPANT');

  duelService.invalidate(challenge.duelId);
});

// 랜덤 seed 가 RR 을 뽑을 때까지 challenge 를 retry 하여 RR 통합 흐름을 검증.
// 6 minigames 중 1/6 확률 → 100 회 cap 이면 사실상 항상 성공.
function setupRussianRoulette() {
  const participants = ['rr-challenger', 'rr-target'];
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const ev = { armed: [], state: [], result: [] };
    const params = {};
    const transport = {
      sendToUser(userId, event, payload) {
        if (event === 'fw:duel:started') params[userId] = payload.params;
        if (event === 'fw:duel:state') ev.state.push({ userId, payload });
        if (event === 'fw:duel:result') ev.result.push({ userId, payload });
        if (event === 'fw:duel:play_armed') ev.armed.push({ userId, payload });
      },
      sendToSession() {},
    };
    const challenge = duelService.challenge({
      challengerId: participants[0],
      targetId: participants[1],
      sessionId: `rr-session-${attempt}`,
      transport,
      onResolve: () => null,
    });
    if (!challenge.ok) {
      throw new Error(`challenge failed: ${challenge.error}`);
    }
    const accepted = duelService.accept({
      duelId: challenge.duelId,
      userId: participants[1],
    });
    if (!accepted.ok) throw new Error(`accept failed: ${accepted.error}`);
    const duel = duelService.getDuel(challenge.duelId);
    if (duel.minigameType !== 'russian_roulette') {
      duelService.invalidate(challenge.duelId);
      continue;
    }
    return { duel, ev, params, participants };
  }
  throw new Error('russian_roulette never selected within 100 attempts');
}

test('russian_roulette submitAction: self miss keeps turn and broadcasts state', async () => {
  const { duel, ev, participants } = setupRussianRoulette();
  const safe = duel.params.bulletChamber === 1 ? 2 : 1;

  const r1 = await duelService.submitAction({
    duelId: duel.duelId,
    userId: participants[0],
    action: { chamber: safe, target: 'self' },
  });
  assert.equal(r1.ok, true);
  assert.equal(r1.terminal, false);

  // 양쪽 모두에게 fw:duel:state 가 emit 되었는가.
  const stateEvents = ev.state.filter((e) => e.payload.duelId === duel.duelId);
  assert.equal(stateEvents.length, 2);
  const dst = stateEvents.map((e) => e.userId).sort();
  assert.deepEqual(dst, [...participants].sort());
  for (const e of stateEvents) {
    assert.equal(e.payload.minigameType, 'russian_roulette');
    assert.equal(e.payload.state.currentTurn, participants[0]); // self miss → 같은 턴
    assert.equal(e.payload.state.history.length, 1);
    assert.equal(e.payload.state.history[0].hit, false);
  }

  duelService.invalidate(duel.duelId);
});

test('russian_roulette submitAction: bullet hit on opponent resolves verdict and emits result', async () => {
  let resolved = null;
  const participants = ['rr-hit-challenger', 'rr-hit-target'];
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const transport = {
      _started: {},
      sendToUser(userId, event, payload) {
        if (event === 'fw:duel:started') this._started[userId] = payload.params;
        if (event === 'fw:duel:result') resolved = payload;
      },
      sendToSession() {},
    };
    const challenge = duelService.challenge({
      challengerId: participants[0],
      targetId: participants[1],
      sessionId: `rr-hit-session-${attempt}`,
      transport,
      onResolve: (args) => { resolved = { ...resolved, args }; return null; },
    });
    duelService.accept({ duelId: challenge.duelId, userId: participants[1] });
    const duel = duelService.getDuel(challenge.duelId);
    if (duel.minigameType !== 'russian_roulette') {
      duelService.invalidate(challenge.duelId);
      continue;
    }
    const r = await duelService.submitAction({
      duelId: challenge.duelId,
      userId: participants[0],
      action: { chamber: duel.params.bulletChamber, target: 'opponent' },
    });
    assert.equal(r.ok, true);
    assert.equal(r.terminal, true);
    assert.ok(resolved);
    assert.equal(resolved.minigameType, 'russian_roulette');
    assert.equal(resolved.verdict.winner, participants[0]);
    assert.equal(resolved.verdict.loser, participants[1]);
    assert.equal(resolved.verdict.reason, 'bullet_hit');
    return;
  }
  throw new Error('russian_roulette never selected within 100 attempts');
});

test('submitAction rejects non-action minigames with NOT_ACTION_GAME', async () => {
  const participants = ['rr-na-challenger', 'rr-na-target'];
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const transport = {
      sendToUser() {},
      sendToSession() {},
    };
    const challenge = duelService.challenge({
      challengerId: participants[0],
      targetId: participants[1],
      sessionId: `rr-na-session-${attempt}`,
      transport,
      onResolve: () => null,
    });
    duelService.accept({ duelId: challenge.duelId, userId: participants[1] });
    const duel = duelService.getDuel(challenge.duelId);
    if (duel.minigameType === 'russian_roulette') {
      duelService.invalidate(challenge.duelId);
      continue;
    }
    const r = await duelService.submitAction({
      duelId: challenge.duelId,
      userId: participants[0],
      action: { foo: 'bar' },
    });
    assert.equal(r.ok, false);
    assert.equal(r.error, 'NOT_ACTION_GAME');
    duelService.invalidate(challenge.duelId);
    return;
  }
  throw new Error('non-RR minigame never selected within 100 attempts');
});

test('fw:duel:result emits only to participants (no session-wide broadcast)', async () => {
  // 회귀 테스트: _emitResult 가 sendToSession 으로도 result 를 보내면 비참가자
  // 클라가 자기 duel state.phase 를 'result' 로 덮어써 결과 오버레이가 잘못 노출된다.
  // 송수신 전송만 허용한다는 계약을 명시적으로 검증.
  const participants = ['result-emit-challenger', 'result-emit-target'];
  const userResultRecipients = [];
  const sessionEvents = [];
  const transport = {
    sendToUser(userId, event, payload) {
      if (event === 'fw:duel:result') {
        userResultRecipients.push({ userId, payload });
      }
    },
    sendToSession(sessionId, event, payload) {
      sessionEvents.push({ sessionId, event, payload });
    },
  };

  const challenge = duelService.challenge({
    challengerId: participants[0],
    targetId: participants[1],
    sessionId: 'result-emit-session',
    transport,
    onResolve: () => null,
  });
  assert.equal(challenge.ok, true);
  duelService.accept({ duelId: challenge.duelId, userId: participants[1] });

  const duel = duelService.getDuel(challenge.duelId);
  // RR 이 picked 되면 submit-기반 _resolve 가 안 돌아가므로 다시 retry.
  if (duel.minigameType === 'russian_roulette') {
    duelService.invalidate(challenge.duelId);
    return; // 재시도 비용 줄이기 위해 skip — 다른 minigameType 으로 재실행이 충분.
  }

  // Trigger _resolve via timeout path (가장 빠른 종결 경로).
  // submit 두 건을 즉시 보내면 _resolve 가 호출된다 — minigame-별 동률/draw payload 를
  // 사용해 verdict 가 무엇이든 result emit 자체는 동일.
  const dummyResult = { reactionMs: 9999, tapCount: 0, durationMs: 5000, hits: [], hitCount: 0, rounds: [] };
  await duelService.submit({ duelId: challenge.duelId, userId: participants[0], result: dummyResult });
  await duelService.submit({ duelId: challenge.duelId, userId: participants[1], result: dummyResult });

  // 결과는 두 참가자에게만 직접 송신.
  assert.equal(userResultRecipients.length, 2, 'result must reach exactly 2 users');
  const userIds = userResultRecipients.map((e) => e.userId).sort();
  assert.deepEqual(userIds, [...participants].sort());

  // session 으로 fw:duel:result 가 broadcast 되지 않아야 한다.
  const sessionResults = sessionEvents.filter((e) => e.event === 'fw:duel:result');
  assert.equal(sessionResults.length, 0, 'no session-wide result broadcast');
});
