// src/websocket/index.js
//
// Socket.IO 서버 부트스트랩 및 도메인 핸들러 등록 허브.
// 실제 이벤트 처리는 handlers/ 하위 모듈에 위임한다.
//   - sessionHandlers      : session:join/leave, location:update, status:update, sos, voice:speaking, disconnect
//   - proximityHandlers    : action:interact (PROXIMITY_KILL)
//   - gameHandlers         : game:start/kill/emergency/report/vote/mission_complete/sabotage/request_state
//   - aiHandlers           : game:ai_ask
//   - roundVoteHandlers    : round:start, vote:open, vote:cast
//   - meetingBusHandlers   : VoteSystem EventBus → Socket.IO 중계 (io 단위 1회 등록)

import { Server } from 'socket.io';
import { createAdapter } from '@socket.io/redis-streams-adapter';
import { verifySocketToken } from '../middleware/auth.js';
import { redisClient } from '../config/redis.js';
import { getMediaServer } from '../media/MediaServer.js';
import { registerMediaSignalingHandlers } from './mediaSignaling.js';
import { EVENTS } from './socketProtocol.js';
export { EVENTS } from './socketProtocol.js';
import { syncMediaRoomState } from './socketRuntime.js';
import { registerSessionHandlers } from './handlers/sessionHandlers.js';
import { registerProximityHandlers } from './handlers/proximityHandlers.js';
import { registerGameHandlers } from './handlers/gameHandlers.js';
import { registerAiHandlers } from './handlers/aiHandlers.js';
import { registerRoundVoteHandlers } from './handlers/roundVoteHandlers.js';
import { registerMeetingBusHandlers } from './handlers/meetingBusHandlers.js';

let _io = null;
export const getIo = () => _io;

export const createSocketServer = (
  httpServer,
  { mediaServer = getMediaServer() } = {},
) => {
  _io = new Server(httpServer, {
    cors: {
      origin: process.env.ALLOWED_ORIGINS?.split(',') || '*',
      credentials: true,
    },
    pingTimeout: 60000,
    pingInterval: 25000,
    transports: ['websocket', 'polling'],
  });
  const io = _io;

  // Redis Streams Adapter (OOM 방지를 위한 maxLen 10000)
  io.adapter(createAdapter(redisClient, { maxLen: 10000 }));

  // 전역 인증 미들웨어
  io.use(async (socket, next) => {
    try {
      const token =
        socket.handshake.auth?.token ||
        socket.handshake.query?.token;

      const user = verifySocketToken(token);
      socket.user = user;
      next();
    } catch (err) {
      next(new Error('AUTH_FAILED'));
    }
  });

  // 소켓 연결 핸들러
  io.on('connection', (socket) => {
    const userId = socket.user.id;
    console.log(`[WS] Connected: ${socket.user.nickname} (${userId})`);

    socket.join(`user:${userId}`);

    const leaveSession = async (sessionIdToLeave = socket.currentSessionId) => {
      if (!sessionIdToLeave) return;

      socket.leave(`session:${sessionIdToLeave}`);
      mediaServer?.removePeer(sessionIdToLeave, userId);

      if (socket.currentSessionId === sessionIdToLeave) {
        socket.currentSessionId = null;
      }
    };

    if (mediaServer) {
      registerMediaSignalingHandlers({
        socket,
        mediaServer,
        events: EVENTS,
        syncRoomState: syncMediaRoomState,
      });
    }

    registerSessionHandlers({ io, socket, mediaServer, userId, leaveSession });
    registerProximityHandlers({ io, socket, mediaServer, userId });
    registerGameHandlers({ io, socket, mediaServer, userId });
    registerAiHandlers({ socket, userId });
    registerRoundVoteHandlers({ io, socket, userId });
  });

  // VoteSystem EventBus → Socket.IO 중계 (io 인스턴스 단위 1회)
  registerMeetingBusHandlers({ io, mediaServer });

  return io;
};
