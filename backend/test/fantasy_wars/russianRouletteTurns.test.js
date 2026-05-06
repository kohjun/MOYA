import test from 'node:test';
import assert from 'node:assert/strict';

import {
  generateParams,
  buildPublic,
  processAction,
} from '../../src/game/duel/minigames/russianRoulette.js';

function setup({ seed = 'rr-seed-fixed', participants = ['p1', 'p2'] } = {}) {
  const params = generateParams(seed, participants);
  return { params, participants };
}

test('generateParams seeds bullet within [1..6] and grants first turn to participant[0]', () => {
  const { params } = setup({ seed: 'seed-A', participants: ['alice', 'bob'] });
  assert.equal(params.chamberCount, 6);
  assert.ok(Number.isInteger(params.bulletChamber));
  assert.ok(params.bulletChamber >= 1 && params.bulletChamber <= 6);
  assert.equal(params.state.currentTurn, 'alice');
  assert.equal(params.state.settled, false);
  assert.deepEqual(params.state.chambersFired, []);
  assert.deepEqual(params.state.history, []);
});

test('buildPublic strips bulletChamber but exposes turn state', () => {
  const { params } = setup();
  const pub = buildPublic(params);
  assert.equal(pub.bulletChamber, undefined);
  assert.equal(pub.chamberCount, 6);
  assert.deepEqual(pub.state.chambersFired, []);
  assert.equal(pub.state.currentTurn, 'p1');
  assert.equal(pub.state.settled, false);
});

test('non-actor turn is rejected', () => {
  const { params, participants } = setup();
  const r = processAction({
    params,
    actorId: 'p2',
    action: { chamber: 1, target: 'self' },
    participants,
  });
  assert.equal(r.ok, false);
  assert.equal(r.error, 'NOT_YOUR_TURN');
});

test('invalid chamber / target / used chamber are rejected', () => {
  const { params, participants } = setup();
  const out = processAction({
    params,
    actorId: 'p1',
    action: { chamber: 0, target: 'self' },
    participants,
  });
  assert.equal(out.ok, false);
  assert.equal(out.error, 'INVALID_CHAMBER');

  const bad = processAction({
    params,
    actorId: 'p1',
    action: { chamber: 1, target: 'wat' },
    participants,
  });
  assert.equal(bad.ok, false);
  assert.equal(bad.error, 'INVALID_TARGET');

  // 1 발 쏜 후 같은 chamber 재사용 거부.
  const after = processAction({
    params,
    actorId: 'p1',
    action: { chamber: 1, target: 'opponent' },
    participants,
  });
  assert.equal(after.ok, true);
  if (!after.terminal) {
    const dup = processAction({
      params: after.params,
      actorId: after.params.state.currentTurn,
      action: { chamber: 1, target: 'self' },
      participants,
    });
    assert.equal(dup.ok, false);
    assert.equal(dup.error, 'CHAMBER_USED');
  }
});

test('self miss keeps turn with same actor (classic rule)', () => {
  const { params, participants } = setup();
  // bulletChamber 와 다른 chamber 를 골라 self miss 강제.
  const safe = params.bulletChamber === 1 ? 2 : 1;
  const r = processAction({
    params,
    actorId: 'p1',
    action: { chamber: safe, target: 'self' },
    participants,
  });
  assert.equal(r.ok, true);
  assert.equal(r.terminal, false);
  assert.equal(r.params.state.currentTurn, 'p1');
  assert.equal(r.params.state.history.length, 1);
  assert.equal(r.params.state.history[0].actor, 'p1');
  assert.equal(r.params.state.history[0].target, 'p1');
  assert.equal(r.params.state.history[0].hit, false);
});

test('opponent miss passes turn to opponent (classic rule)', () => {
  const { params, participants } = setup();
  const safe = params.bulletChamber === 1 ? 2 : 1;
  const r = processAction({
    params,
    actorId: 'p1',
    action: { chamber: safe, target: 'opponent' },
    participants,
  });
  assert.equal(r.ok, true);
  assert.equal(r.terminal, false);
  assert.equal(r.params.state.currentTurn, 'p2');
});

test('bullet hit on opponent → opponent loses, actor wins', () => {
  const { params, participants } = setup();
  const r = processAction({
    params,
    actorId: 'p1',
    action: { chamber: params.bulletChamber, target: 'opponent' },
    participants,
  });
  assert.equal(r.ok, true);
  assert.equal(r.terminal, true);
  assert.equal(r.verdict.winner, 'p1');
  assert.equal(r.verdict.loser, 'p2');
  assert.equal(r.verdict.reason, 'bullet_hit');
  assert.equal(r.params.state.settled, true);
});

test('bullet hit on self → self loses, opponent wins', () => {
  const { params, participants } = setup();
  const r = processAction({
    params,
    actorId: 'p1',
    action: { chamber: params.bulletChamber, target: 'self' },
    participants,
  });
  assert.equal(r.ok, true);
  assert.equal(r.terminal, true);
  assert.equal(r.verdict.winner, 'p2');
  assert.equal(r.verdict.loser, 'p1');
  assert.equal(r.verdict.reason, 'bullet_hit');
});

test('post-settled action is rejected', () => {
  const { params, participants } = setup();
  const fst = processAction({
    params,
    actorId: 'p1',
    action: { chamber: params.bulletChamber, target: 'opponent' },
    participants,
  });
  assert.equal(fst.terminal, true);
  const dup = processAction({
    params: fst.params,
    actorId: 'p1',
    action: { chamber: 1, target: 'self' },
    participants,
  });
  assert.equal(dup.ok, false);
  assert.equal(dup.error, 'GAME_SETTLED');
});

test('multi-turn sequence: self miss → retry → opponent miss → turn passes', () => {
  const { params, participants } = setup();
  const safeChambers = [];
  for (let c = 1; c <= 6; c += 1) {
    if (c !== params.bulletChamber) safeChambers.push(c);
  }
  assert.ok(safeChambers.length >= 3);

  // 1) p1: self miss → turn stays p1
  let cur = processAction({
    params,
    actorId: 'p1',
    action: { chamber: safeChambers[0], target: 'self' },
    participants,
  });
  assert.equal(cur.params.state.currentTurn, 'p1');

  // 2) p1: opponent miss → turn passes to p2
  cur = processAction({
    params: cur.params,
    actorId: 'p1',
    action: { chamber: safeChambers[1], target: 'opponent' },
    participants,
  });
  assert.equal(cur.params.state.currentTurn, 'p2');

  // 3) p2: self miss → turn stays p2
  cur = processAction({
    params: cur.params,
    actorId: 'p2',
    action: { chamber: safeChambers[2], target: 'self' },
    participants,
  });
  assert.equal(cur.params.state.currentTurn, 'p2');
  assert.equal(cur.params.state.history.length, 3);
  assert.deepEqual(cur.params.state.chambersFired.sort(), safeChambers.slice(0, 3).sort());
});
