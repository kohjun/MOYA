'use strict';

import { defaultConfig, resolveDuelConfig } from './schema.js';
import { calcReviveChance } from './revive.js';
import { activeShields } from './skills.js';

export function getPublicState(gameState) {
  const ps = gameState.pluginState ?? {};
  const guilds = ps.guilds ?? {};
  const config = ps._config ?? defaultConfig;
  const captureDurationSec = Math.max(1, config.captureDurationSec ?? 30);
  const captureDurationMs = captureDurationSec * 1000;
  const now = Date.now();

  const guildSummary = {};
  Object.values(guilds).forEach((guild) => {
    guildSummary[guild.guildId] = {
      guildId: guild.guildId,
      displayName: guild.displayName,
      color: guild.color ?? null,
      memberIds: guild.memberIds,
      guildMasterId: guild.guildMasterId,
      score: guild.score ?? 0,
    };
  });

  const controlPoints = (ps.controlPoints ?? []).map((cp) => ({
    id: cp.id,
    displayName: cp.displayName,
    capturedBy: cp.capturedBy,
    captureProgress: cp.capturingGuild && cp.captureStartedAt
      ? Math.min(
        99,
        Math.max(
          cp.captureProgress ?? 0,
          Math.floor(((now - cp.captureStartedAt) / captureDurationMs) * 100),
        ),
      )
      : (cp.captureProgress ?? 0),
    capturingGuild: cp.capturingGuild,
    captureStartedAt: cp.captureStartedAt,
    captureDurationSec,
    readyCount: cp.readyCount ?? Object.keys(ps.captureIntents?.[cp.id] ?? {}).length,
    requiredCount: cp.requiredCount ?? 0,
    location: cp.location,
    blockadedBy: cp.blockadedBy,
    blockadeExpiresAt: cp.blockadeExpiresAt,
  }));

  const dungeons = (ps.dungeons ?? []).map((dungeon) => ({
    id: dungeon.id,
    displayName: dungeon.displayName,
    status: dungeon.status,
    artifact: {
      id: dungeon.artifact?.id,
      heldBy: dungeon.artifact?.heldBy,
    },
  }));

  const playableArea = Array.isArray(ps.playableArea) ? ps.playableArea : [];
  const spawnZones = (ps.spawnZones ?? []).map((zone) => ({
    teamId: zone.teamId,
    displayName: zone.displayName,
    color: zone.color ?? null,
    polygonPoints: Array.isArray(zone.polygonPoints) ? zone.polygonPoints : [],
  }));
  const duelConfig = resolveDuelConfig(config);

  return {
    status: gameState.status,
    startedAt: gameState.startedAt,
    finishedAt: gameState.finishedAt,
    duelRangeMeters: duelConfig.duelRangeMeters,
    bleEvidenceFreshnessMs: duelConfig.bleEvidenceFreshnessMs,
    allowGpsFallbackWithoutBle: duelConfig.allowGpsFallbackWithoutBle,
    aliveCount: gameState.alivePlayerIds.length,
    alivePlayerIds: gameState.alivePlayerIds,
    eliminatedPlayerIds: ps.eliminatedPlayerIds ?? [],
    guilds: guildSummary,
    controlPoints,
    dungeons,
    playableArea,
    spawnZones,
    winCondition: ps.winCondition ?? null,
  };
}

export function getPrivateState(gameState, userId) {
  const ps = gameState.pluginState ?? {};
  const player = (ps.playerStates ?? {})[userId];
  const config = ps._config ?? defaultConfig;
  if (!player) {
    return { guildId: 'unknown', job: 'warrior', isGuildMaster: false };
  }

  const dungeonEntered = Boolean(player.dungeonEnteredAt);
  const nextReviveChance = !player.isAlive && dungeonEntered
    ? calcReviveChance(
      player.reviveAttempts ?? 0,
      config.reviveBaseChance ?? 0.3,
      config.reviveStepChance ?? 0.1,
      config.reviveMaxChance ?? 0.8,
    )
    : null;

  return {
    guildId: player.guildId,
    job: player.job,
    isGuildMaster: player.isGuildMaster,
    isAlive: player.isAlive,
    hp: player.hp,
    remainingLives: player.remainingLives ?? 1,
    reviveAttempts: player.reviveAttempts,
    skillUsedAt: player.skillUsedAt ?? {},
    captureZone: player.captureZone,
    inDuel: player.inDuel ?? false,
    duelExpiresAt: player.duelExpiresAt ?? null,
    shields: activeShields(player),
    buffedUntil: player.buffedUntil ?? null,
    revealUntil: player.revealUntil ?? null,
    trackedTargetUserId: player.trackedTargetUserId ?? null,
    executionArmedUntil: player.executionArmedUntil ?? null,
    dungeonEntered,
    dungeonEnteredAt: player.dungeonEnteredAt ?? null,
    nextReviveAt: player.nextReviveAt ?? null,
    reviveReady: Boolean(player.reviveReady),
    nextReviveChance,
  };
}
