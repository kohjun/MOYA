import test from 'node:test';
import assert from 'node:assert/strict';

import { duelService } from '../../src/game/duel/DuelService.js';

// ─────────────────────────────────────────────────────────────────────────────
// Race condition 회귀 테스트.
// 패턴: onResolve를 manual deferred Promise로 만들어 _finalizeVerdict의
//       await 지점에서 _resolve를 멈춰두고, 그 사이에 disconnect / external
//       invalidate 를 트리거. fw:duel:result 와 fw:duel:invalidated 가 동시
//       emit 되는지 확인.
// ─────────────────────────────────────────────────────────────────────────────

function makeFakeTransport() {
  const events = [];
  return {
    events,
    sendToUser(userId, event, payload) {
      events.push({ kind: 'user', userId, event, payload });
    },
    sendToSession(sessionId, event, payload) {
      events.push({ kind: 'session', sessionId, event, payload });
    },
  };
}

function countEvent(events, eventName) {
  return events.filter((e) => e.event === eventName).length;
}

function flushMicrotasks() {
  return new Promise((resolve) => setImmediate(resolve));
}

// 어떤 minigame type이 픽되더라도 동작하는 통합 submission 페이로드.
const STUFFED_SUBMISSION = {
  reactionMs: 500,
  tapCount: 10,
  durationMs: 5000,
  hits: [],
  chamber: 1,
  hitCount: 0,
  rounds: [
    { bid: 30, applyMultiplier: false },
    { bid: 30, applyMultiplier: false },
    { bid: 30, applyMultiplier: false },
  ],
};

function cleanupAfterTest(duelId, ...userIds) {
  if (duelService.getDuel(duelId)) {
    duelService.invalidate(duelId, 'test_cleanup');
  }
  for (const userId of userIds) {
    const lingering = duelService.getDuelForUser(userId);
    if (lingering) {
      duelService.invalidate(lingering.duelId, 'test_cleanup_lingering');
    }
  }
}

test('T1: _resolve 중 disconnect 트리거 → invalidated가 중복 emit되지 않아야 함', async () => {
  const transport = makeFakeTransport();

  let releaseOnResolve;
  const onResolveDeferred = new Promise((resolve) => {
    releaseOnResolve = resolve;
  });
  const onResolve = async () => {
    await onResolveDeferred;
    return null;
  };

  const challengerId = 'race-t1-challenger';
  const targetId = 'race-t1-target';
  const sessionId = 'race-t1-session';

  const challenge = duelService.challenge({
    challengerId,
    targetId,
    sessionId,
    transport,
    onResolve,
  });
  assert.equal(challenge.ok, true);

  const accepted = duelService.accept({
    duelId: challenge.duelId,
    userId: targetId,
  });
  assert.equal(accepted.ok, true);

  // 첫 submit: _resolve 트리거 안 함 (length === 1).
  await duelService.submit({
    duelId: challenge.duelId,
    userId: challengerId,
    result: STUFFED_SUBMISSION,
  });

  // 두 번째 submit: _resolve 트리거. await 하지 않고 race 시점을 만든다.
  const p2Promise = duelService.submit({
    duelId: challenge.duelId,
    userId: targetId,
    result: STUFFED_SUBMISSION,
  });

  // microtask flush — _resolve 의 await chain 이 onResolveDeferred 까지 도달.
  await flushMicrotasks();
  await flushMicrotasks();

  // 이 시점:
  //   _resolve → _finalizeVerdict → await onResolve(...) → await onResolveDeferred (pending)
  //   record.status === 'in_game' 그대로
  //   _gameTimer 는 _resolve 진입 직후 clearTimeout 처리
  // 가드 미적용 시: handleDisconnect → _invalidate 가 진입해 invalidated emit + _close
  // 가드 적용 시: _terminating === true 라 _invalidate 가 early return.
  duelService.handleDisconnect(challengerId);

  // onResolve 의 deferred 를 풀어 _resolve 가 emit + _close 까지 진행하게 함.
  releaseOnResolve(null);
  await p2Promise;

  const events = transport.events;
  const resultCount = countEvent(events, 'fw:duel:result');
  const invalidatedCount = countEvent(events, 'fw:duel:invalidated');

  assert.equal(
    invalidatedCount,
    0,
    `expected 0 invalidated emits, got ${invalidatedCount} — race condition exposed: handleDisconnect 가 _resolve 진행 중에 _invalidate 를 트리거.`,
  );
  assert.ok(
    resultCount >= 1,
    `expected at least 1 fw:duel:result emit after _resolve completion, got ${resultCount}`,
  );

  cleanupAfterTest(challenge.duelId, challengerId, targetId);
});

test('T2: _resolve 중 external invalidate → invalidated가 중복 emit되지 않아야 함', async () => {
  const transport = makeFakeTransport();

  let releaseOnResolve;
  const onResolveDeferred = new Promise((resolve) => {
    releaseOnResolve = resolve;
  });
  const onResolve = async () => {
    await onResolveDeferred;
    return null;
  };

  const challengerId = 'race-t2-challenger';
  const targetId = 'race-t2-target';
  const sessionId = 'race-t2-session';

  const challenge = duelService.challenge({
    challengerId,
    targetId,
    sessionId,
    transport,
    onResolve,
  });
  assert.equal(challenge.ok, true);

  const accepted = duelService.accept({
    duelId: challenge.duelId,
    userId: targetId,
  });
  assert.equal(accepted.ok, true);

  await duelService.submit({
    duelId: challenge.duelId,
    userId: challengerId,
    result: STUFFED_SUBMISSION,
  });

  const p2Promise = duelService.submit({
    duelId: challenge.duelId,
    userId: targetId,
    result: STUFFED_SUBMISSION,
  });

  await flushMicrotasks();
  await flushMicrotasks();

  // _resolve 가 await onResolve 에서 멈춰 있는 동안 외부 invalidate 호출.
  duelService.invalidate(challenge.duelId, 'external_test_trigger');

  releaseOnResolve(null);
  await p2Promise;

  const events = transport.events;
  const resultCount = countEvent(events, 'fw:duel:result');
  const invalidatedCount = countEvent(events, 'fw:duel:invalidated');

  assert.equal(
    invalidatedCount,
    0,
    `expected 0 invalidated emits, got ${invalidatedCount} — race condition exposed: external invalidate 가 _resolve 진행 중에 통과.`,
  );
  assert.ok(
    resultCount >= 1,
    `expected at least 1 fw:duel:result emit, got ${resultCount}`,
  );

  cleanupAfterTest(challenge.duelId, challengerId, targetId);
});

test('T3: _invalidate 재진입은 한 번만 emit/onInvalidate 되어야 함', async () => {
  const transport = makeFakeTransport();

  let onInvalidateCalls = 0;
  const onInvalidate = () => {
    onInvalidateCalls += 1;
  };

  const challengerId = 'race-t3-challenger';
  const targetId = 'race-t3-target';
  const sessionId = 'race-t3-session';

  const challenge = duelService.challenge({
    challengerId,
    targetId,
    sessionId,
    transport,
    onInvalidate,
  });
  assert.equal(challenge.ok, true);

  // 같은 duelId 에 두 번 invalidate.
  duelService.invalidate(challenge.duelId, 'first');
  duelService.invalidate(challenge.duelId, 'second');

  // onInvalidate 는 fire-and-forget 으로 microtask 에 스케줄됨.
  await flushMicrotasks();

  const events = transport.events;
  const invalidatedCount = countEvent(events, 'fw:duel:invalidated');

  // 첫 호출: challenger + target 양쪽에 invalidated emit (2개).
  // 두 번째 호출: activeDuels.get(duelId) 가 undefined 라 early return — emit 없음.
  assert.equal(
    invalidatedCount,
    2,
    `expected 2 invalidated emits (1 invalidate × challenger+target), got ${invalidatedCount}`,
  );
  assert.equal(
    onInvalidateCalls,
    1,
    `expected 1 onInvalidate call, got ${onInvalidateCalls}`,
  );

  cleanupAfterTest(challenge.duelId, challengerId, targetId);
});
