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
  // 적군이 zone 안에 있어도 점령 시작 자체는 막지 않는다. 적은 capture_disrupt
  // 이벤트를 명시적으로 보내야만 진행을 끊을 수 있다.
  // 점령 최소 인원: 1명. SOLO / 소규모 세션에서도 단독 점령 가능.
  if ((options.friendlyInZoneCount ?? 0) < 1) {
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
  // 점령 진행 중에 적군이 zone 으로 들어와도 자동 취소하지 않는다.
  // 방해는 capture_disrupt 이벤트로만 이루어진다.
  // 점령 최소 인원: 1명. SOLO / 소규모 세션에서도 단독 점령 가능.
  if ((options.friendlyInZoneCount ?? 0) < 1) {
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
  // 1인 점령 허용. captureIntent 가 비어 있는 호출만 차단.
  if (!Array.isArray(requiredUserIds) || requiredUserIds.length < 1) {
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
