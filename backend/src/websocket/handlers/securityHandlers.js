// src/websocket/handlers/securityHandlers.js
//
// Anti-cheat / 보안 이벤트 수집 핸들러.
// 클라이언트에서 감지한 위협(예: mock GPS)을 서버에 보고하면 로그를 남긴다.

import { EVENTS } from '../socketProtocol.js';
import { redisClient } from '../../config/redis.js';

const REPORT_TTL_SECONDS = 60 * 60 * 24;

export const registerSecurityHandlers = ({ socket, userId }) => {
  socket.on(EVENTS.ACTION_INTERACT, async (payload = {}) => {
    const { sessionId: sid, actionType } = payload;
    const sessionId = sid || socket.currentSessionId;

    if (actionType !== 'CHEAT_DETECTED') {
      return;
    }

    const record = {
      userId,
      sessionId: sessionId ?? null,
      reason: payload?.reason ?? 'unknown',
      details: payload?.details ?? null,
      reportedAt: Date.now(),
    };

    console.warn('[Security] cheat report:', record);

    if (sessionId) {
      try {
        await redisClient.lPush(
          `security:cheat:${sessionId}`,
          JSON.stringify(record),
        );
        await redisClient.expire(
          `security:cheat:${sessionId}`,
          REPORT_TTL_SECONDS,
        );
      } catch (err) {
        console.error('[Security] failed to persist cheat report:', err.message);
      }
    }
  });
};
