import test from 'node:test';
import assert from 'node:assert/strict';

import {
  captureValidator,
  captureHoldValidator,
  pruneCaptureIntents,
  isCaptureReady,
} from '../../src/game/plugins/fantasy_wars_artifact/capture.js';
import { makeControlPoint, makePlayer } from '../../testing/fantasy_wars/helpers.js';

test('captureValidator accepts a valid coordinated capture attempt', () => {
  const cp = makeControlPoint();
  const player = makePlayer();

  const result = captureValidator(cp, player, {
    hasFreshLocation: true,
    requesterInZone: true,
    enemyInZoneCount: 0,
    friendlyInZoneCount: 2,
  });

  assert.deepEqual(result, { ok: true });
});

test('captureValidator rejects invalid capture attempts', () => {
  const cp = makeControlPoint();
  const deadPlayer = makePlayer({ isAlive: false });

  assert.deepEqual(captureValidator(cp, deadPlayer), {
    ok: false,
    error: 'PLAYER_DEAD',
  });
  assert.deepEqual(captureValidator(null, makePlayer()), {
    ok: false,
    error: 'CP_NOT_FOUND',
  });
  assert.deepEqual(
    captureValidator(
      makeControlPoint({ blockadedBy: 'guild_beta', blockadeExpiresAt: Date.now() + 5000 }),
      makePlayer(),
    ),
    { ok: false, error: 'BLOCKADED' },
  );
  assert.deepEqual(
    captureValidator(cp, makePlayer(), {
      hasFreshLocation: false,
      requesterInZone: true,
      enemyInZoneCount: 0,
      friendlyInZoneCount: 2,
    }),
    { ok: false, error: 'LOCATION_UNAVAILABLE' },
  );
  assert.deepEqual(
    captureValidator(cp, makePlayer(), {
      hasFreshLocation: true,
      requesterInZone: false,
      enemyInZoneCount: 0,
      friendlyInZoneCount: 2,
    }),
    { ok: false, error: 'NOT_IN_CAPTURE_ZONE' },
  );
  // 적이 zone 안에 있어도 점령 시작은 허용한다 (방해는 capture_disrupt 전용).
  assert.deepEqual(
    captureValidator(cp, makePlayer(), {
      hasFreshLocation: true,
      requesterInZone: true,
      enemyInZoneCount: 1,
      friendlyInZoneCount: 2,
    }),
    { ok: true },
  );
  // friendlyInZoneCount: 1 은 SOLO 점령 허용 정책상 ok 가 되어야 한다.
  assert.deepEqual(
    captureValidator(cp, makePlayer(), {
      hasFreshLocation: true,
      requesterInZone: true,
      enemyInZoneCount: 0,
      friendlyInZoneCount: 1,
    }),
    { ok: true },
  );
  // 0 명일 때만 NOT_ENOUGH_TEAMMATES_IN_ZONE.
  assert.deepEqual(
    captureValidator(cp, makePlayer(), {
      hasFreshLocation: true,
      requesterInZone: true,
      enemyInZoneCount: 0,
      friendlyInZoneCount: 0,
    }),
    { ok: false, error: 'NOT_ENOUGH_TEAMMATES_IN_ZONE' },
  );
});

test('captureHoldValidator enforces active hold requirements', () => {
  assert.deepEqual(captureHoldValidator(makeControlPoint()), {
    ok: false,
    error: 'CAPTURE_NOT_ACTIVE',
  });

  const cp = makeControlPoint({ capturingGuild: 'guild_alpha' });
  // 적이 zone 안에 들어와도 hold 는 자동 취소되지 않는다 (disrupt 가 별도 경로).
  assert.deepEqual(
    captureHoldValidator(cp, {
      enemyInZoneCount: 1,
      friendlyInZoneCount: 2,
    }),
    { ok: true },
  );
  assert.deepEqual(
    captureHoldValidator(cp, {
      enemyInZoneCount: 0,
      friendlyInZoneCount: 0,
    }),
    { ok: false, error: 'NOT_ENOUGH_TEAMMATES_IN_ZONE' },
  );
  assert.deepEqual(
    captureHoldValidator(cp, {
      enemyInZoneCount: 0,
      friendlyInZoneCount: 1,
    }),
    { ok: true },
  );
  assert.deepEqual(
    captureHoldValidator(cp, {
      enemyInZoneCount: 0,
      friendlyInZoneCount: 2,
    }),
    { ok: true },
  );
});

test('capture intent helpers keep only valid and ready intents', () => {
  const now = 100_000;
  const intents = pruneCaptureIntents(
    {
      'user-1': now - 1000,
      'user-2': now - 3000,
      stale: now - 10_000,
      invalid: 'recent',
    },
    ['user-1', 'user-2', 'user-3'],
    now,
    5000,
  );

  assert.deepEqual(intents, {
    'user-1': now - 1000,
    'user-2': now - 3000,
  });
  assert.equal(isCaptureReady(intents, ['user-1', 'user-2']), true);
  assert.equal(isCaptureReady(intents, ['user-1', 'user-3']), false);
  // 1인 점령 허용 정책: 단일 사용자 intent 도 ready 로 인정.
  assert.equal(isCaptureReady(intents, ['user-1']), true);
  // 빈 배열은 ready 가 아님.
  assert.equal(isCaptureReady(intents, []), false);
});
