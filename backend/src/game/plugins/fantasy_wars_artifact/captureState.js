'use strict';

export function findControlPointById(ps, controlPointId) {
  return (ps.controlPoints ?? []).find((point) => point.id === controlPointId) ?? null;
}

export function clearCaptureIntents(ps, controlPointId) {
  if (ps.captureIntents) {
    delete ps.captureIntents[controlPointId];
  }
}

export function clearCaptureZoneForControlPoint(ps, controlPointId, guildId = null) {
  Object.values(ps.playerStates ?? {}).forEach((player) => {
    if (player.captureZone !== controlPointId) {
      return;
    }
    if (guildId && player.guildId !== guildId) {
      return;
    }
    player.captureZone = null;
  });
}

export function resetCaptureState(ps, cp, controlPointId, guildId = null) {
  if (cp) {
    cp.capturingGuild = null;
    cp.captureProgress = 0;
    cp.captureStartedAt = null;
    cp.captureParticipantUserIds = [];
    cp.readyCount = 0;
    cp.requiredCount = 0;
  }

  clearCaptureZoneForControlPoint(ps, controlPointId, guildId);
  clearCaptureIntents(ps, controlPointId);
}

export function cancelCaptureForPlayer(ps, userId) {
  const player = ps.playerStates?.[userId];
  if (!player?.captureZone) {
    return null;
  }

  const controlPointId = player.captureZone;
  const cp = findControlPointById(ps, controlPointId);
  if (cp?.capturingGuild === player.guildId) {
    resetCaptureState(ps, cp, controlPointId, player.guildId);
    return {
      controlPointId,
      guildId: player.guildId,
      cancelledActiveCapture: true,
    };
  }

  player.captureZone = null;
  return {
    controlPointId,
    guildId: player.guildId,
    cancelledActiveCapture: false,
  };
}
