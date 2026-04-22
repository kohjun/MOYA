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
  assert.deepEqual(
    captureValidator(cp, makePlayer(), {
      hasFreshLocation: true,
      requesterInZone: true,
      enemyInZoneCount: 1,
      friendlyInZoneCount: 2,
    }),
    { ok: false, error: 'ENEMY_IN_ZONE' },
  );
  assert.deepEqual(
    captureValidator(cp, makePlayer(), {
      hasFreshLocation: true,
      requesterInZone: true,
      enemyInZoneCount: 0,
      friendlyInZoneCount: 1,
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
  assert.deepEqual(
    captureHoldValidator(cp, {
      enemyInZoneCount: 1,
      friendlyInZoneCount: 2,
    }),
    { ok: false, error: 'ENEMY_IN_ZONE' },
  );
  assert.deepEqual(
    captureHoldValidator(cp, {
      enemyInZoneCount: 0,
      friendlyInZoneCount: 1,
    }),
    { ok: false, error: 'NOT_ENOUGH_TEAMMATES_IN_ZONE' },
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
  assert.equal(isCaptureReady(intents, ['user-1']), false);
});
