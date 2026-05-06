'use strict';

import {
  calcReviveChance,
  scheduleDungeonRevive,
  cancelDungeonTimer,
  applyReviveSuccess,
  DUNGEON_REVIVE_INTERVAL_MS,
} from './revive.js';
import { defaultConfig } from './schema.js';
import { runExclusive } from './mutex.js';

function cfg(ps) {
  return ps._config ?? defaultConfig;
}

export async function handleDungeonEnter({ dungeonId = 'dungeon_main' }, ctx) {
  const { userId, sessionId, gameState, saveState, readState, io } = ctx;
  const ps = gameState.pluginState ?? {};
  const player = (ps.playerStates ?? {})[userId];

  if (!player) {
    return { error: 'PLAYER_NOT_FOUND' };
  }

  if (player.isAlive) {
    return { error: 'PLAYER_NOT_DEAD' };
  }

  if (player.dungeonEnteredAt) {
    return { error: 'ALREADY_IN_DUNGEON' };
  }

  const dungeon = (ps.dungeons ?? []).find((item) => item.id === dungeonId);
  if (!dungeon || dungeon.status !== 'open') {
    return { error: 'DUNGEON_CLOSED' };
  }

  const now = Date.now();
  player.dungeonEnteredAt = now;
  player.reviveReady      = false;
  player.nextReviveAt     = now + DUNGEON_REVIVE_INTERVAL_MS;
  await saveState(gameState);

  const timerKey = `${sessionId}:${userId}`;
  scheduleReviveReady(timerKey, userId, sessionId, readState, saveState, io);

  return true;
}

// Cooldown 만료 시 player.reviveReady = true 로 설정하고 클라이언트에 알린다.
// 자동 부활 판정은 더 이상 하지 않는다 — 사용자가 'fw:revive' 로 직접 시도해야 한다.
function scheduleReviveReady(timerKey, userId, sessionId, readState, saveState, io) {
  scheduleDungeonRevive(timerKey, () => runExclusive(`fw:session:${sessionId}`, async () => {
    const fresh = await readState();
    if (!fresh) {
      return;
    }

    const ps = fresh.pluginState ?? {};
    const player = ps.playerStates?.[userId];
    if (!player || player.isAlive || !player.dungeonEnteredAt) {
      cancelDungeonTimer(timerKey);
      return;
    }

    player.reviveReady  = true;
    player.nextReviveAt = null;
    await saveState(fresh);

    io.to(`session:${sessionId}`).emit('fw:revive_ready', {
      targetUserId: userId,
    });
  }));
}

export async function handleReviveAttempt(_payload, ctx) {
  const { userId, sessionId, gameState, saveState, readState, io } = ctx;
  const ps = gameState.pluginState ?? {};
  const config = cfg(ps);
  const player = (ps.playerStates ?? {})[userId];

  if (!player) {
    return { error: 'PLAYER_NOT_FOUND' };
  }
  if (player.isAlive) {
    return { error: 'PLAYER_NOT_DEAD' };
  }
  if (!player.dungeonEnteredAt) {
    return { error: 'NOT_IN_DUNGEON' };
  }
  if (!player.reviveReady) {
    return { error: 'REVIVE_COOLDOWN' };
  }

  const chance = calcReviveChance(
    player.reviveAttempts,
    config.reviveBaseChance ?? 0.3,
    config.reviveStepChance ?? 0.1,
    config.reviveMaxChance ?? 0.8,
  );
  player.reviveAttempts += 1;
  player.reviveReady     = false;

  const timerKey = `${sessionId}:${userId}`;

  if (Math.random() < chance) {
    applyReviveSuccess(player, gameState);
    await saveState(gameState);
    cancelDungeonTimer(timerKey);
    io.to(`session:${sessionId}`).emit('fw:player_revived', {
      targetUserId: userId,
      revivedBy: 'dungeon',
    });
    return true;
  }

  const now = Date.now();
  player.nextReviveAt = now + DUNGEON_REVIVE_INTERVAL_MS;
  await saveState(gameState);

  io.to(`session:${sessionId}`).emit('fw:revive_failed', {
    targetUserId: userId,
    attemptedBy: 'dungeon',
    nextAttemptAt: player.nextReviveAt,
    nextChance: calcReviveChance(
      player.reviveAttempts,
      config.reviveBaseChance ?? 0.3,
      config.reviveStepChance ?? 0.1,
      config.reviveMaxChance ?? 0.8,
    ),
  });

  scheduleReviveReady(timerKey, userId, sessionId, readState, saveState, io);
  return true;
}
