'use strict';

import { getSessionSnapshot } from '../../../services/locationService.js';

// Active reveal 의 주기적 위치 재방송 인터벌 핸들 (`${sessionId}:${viewerId}` → handle).
// 클라이언트 GPS 스트림이 emulator/실기기 드물게 갱신될 때도 추적 마커가
// 따라가도록 서버가 마지막으로 알려진 좌표를 주기적으로 다시 emit 한다.
const revealStreamHandles = new Map();
const REVEAL_REBROADCAST_INTERVAL_MS = 2500;
const REVEAL_REBROADCAST_SAFETY_BUFFER_MS = 5000;

function clearRevealStream(sessionId, viewerUserId) {
  const key = `${sessionId}:${viewerUserId}`;
  const handle = revealStreamHandles.get(key);
  if (!handle) return;
  clearInterval(handle.intervalId);
  clearTimeout(handle.safetyTimeoutId);
  revealStreamHandles.delete(key);
}

export function startRevealStream({
  io,
  sessionId,
  viewerUserId,
  targetUserId,
  revealUntil,
  readState,
}) {
  clearRevealStream(sessionId, viewerUserId);

  const key = `${sessionId}:${viewerUserId}`;
  const totalDurationMs = Math.max(
    0,
    revealUntil - Date.now() + REVEAL_REBROADCAST_SAFETY_BUFFER_MS,
  );
  if (totalDurationMs === 0) return;

  const intervalId = setInterval(async () => {
    try {
      const fresh = await readState();
      const viewer = fresh?.pluginState?.playerStates?.[viewerUserId];
      const stillTracking =
        viewer
        && viewer.trackedTargetUserId === targetUserId
        && Number(viewer.revealUntil ?? 0) > Date.now();

      if (!stillTracking) {
        clearRevealStream(sessionId, viewerUserId);
        return;
      }

      const snap = await getSessionSnapshot(sessionId, [targetUserId]);
      const loc = snap[targetUserId];
      if (!loc) return;

      io.to(`user:${viewerUserId}`).emit('location:changed', {
        userId: targetUserId,
        sessionId,
        ...loc,
        visibility: 'revealed',
      });
    } catch (err) {
      console.error('[FW] reveal periodic broadcast failed:', err.message);
    }
  }, REVEAL_REBROADCAST_INTERVAL_MS);

  const safetyTimeoutId = setTimeout(() => {
    clearRevealStream(sessionId, viewerUserId);
  }, totalDurationMs);

  revealStreamHandles.set(key, { intervalId, safetyTimeoutId });
}
