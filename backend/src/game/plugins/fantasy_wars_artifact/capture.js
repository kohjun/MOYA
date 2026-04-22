'use strict';

const captureTimers = new Map();

export function captureValidator(cp, player, options = {}) {
  if (!player?.isAlive) {
    return { ok: false, error: 'PLAYER_DEAD' };
  }
  if (!cp) {
    return { ok: false, error: 'CP_NOT_FOUND' };
  }
  if (!cp.location) {
    return { ok: false, error: 'CP_LOCATION_UNSET' };
  }
  if (cp.capturedBy === player.guildId) {
    return { ok: false, error: 'ALREADY_OWNED' };
  }

  const now = options.now ?? Date.now();
  if (cp.blockadedBy && cp.blockadedBy !== player.guildId) {
    if (!cp.blockadeExpiresAt || cp.blockadeExpiresAt > now) {
      return { ok: false, error: 'BLOCKADED' };
    }
  }

  if (options.hasFreshLocation === false) {
    return { ok: false, error: 'LOCATION_UNAVAILABLE' };
  }
  if (options.requesterInZone === false) {
    return { ok: false, error: 'NOT_IN_CAPTURE_ZONE' };
  }
  if ((options.enemyInZoneCount ?? 0) > 0) {
    return { ok: false, error: 'ENEMY_IN_ZONE' };
  }
  if ((options.friendlyInZoneCount ?? 0) < 2) {
    return { ok: false, error: 'NOT_ENOUGH_TEAMMATES_IN_ZONE' };
  }

  return { ok: true };
}

export function captureHoldValidator(cp, options = {}) {
  if (!cp?.capturingGuild) {
    return { ok: false, error: 'CAPTURE_NOT_ACTIVE' };
  }
  if (!cp.location) {
    return { ok: false, error: 'CP_LOCATION_UNSET' };
  }
  if ((options.enemyInZoneCount ?? 0) > 0) {
    return { ok: false, error: 'ENEMY_IN_ZONE' };
  }
  if ((options.friendlyInZoneCount ?? 0) < 2) {
    return { ok: false, error: 'NOT_ENOUGH_TEAMMATES_IN_ZONE' };
  }

  return { ok: true };
}

export function pruneCaptureIntents(intentMap, validUserIds, now, windowMs) {
  const validSet = new Set(validUserIds);
  const next = {};

  Object.entries(intentMap ?? {}).forEach(([userId, ts]) => {
    if (!validSet.has(userId)) {
      return;
    }
    if (typeof ts !== 'number') {
      return;
    }
    if ((now - ts) > windowMs) {
      return;
    }
    next[userId] = ts;
  });

  return next;
}

export function isCaptureReady(intentMap, requiredUserIds) {
  if (!Array.isArray(requiredUserIds) || requiredUserIds.length < 2) {
    return false;
  }

  return requiredUserIds.every((userId) => typeof intentMap?.[userId] === 'number');
}

export function scheduleCaptureComplete(key, delayMs, callback) {
  cancelCaptureTimer(key);
  const id = setTimeout(() => {
    captureTimers.delete(key);
    callback();
  }, delayMs);
  captureTimers.set(key, id);
}

export function cancelCaptureTimer(key) {
  const id = captureTimers.get(key);
  if (id !== undefined) {
    clearTimeout(id);
    captureTimers.delete(key);
  }
}

export function hasCaptureTimer(key) {
  return captureTimers.has(key);
}
