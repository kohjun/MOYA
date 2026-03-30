// src/websocket/index.js
import { Server } from 'socket.io';
import { verifySocketToken } from '../middleware/auth.js';
import { redisClient, subClient } from '../config/redis.js';
import * as locationService from '../services/locationService.js';
import * as sessionService from '../services/sessionService.js';

// ─────────────────────────────────────────────────────────────────────────────
// Socket.IO 이벤트 상수 (클라이언트와 공유하는 프로토콜)
// ─────────────────────────────────────────────────────────────────────────────
export const EVENTS = {
  // Client → Server
  JOIN_SESSION:      'session:join',
  LEAVE_SESSION:     'session:leave',
  LOCATION_UPDATE:   'location:update',
  STATUS_UPDATE:     'status:update',
  SOS_TRIGGER:       'sos:trigger',

  // Server → Client
  SESSION_JOINED:    'session:joined',
  MEMBER_JOINED:     'member:joined',
  MEMBER_LEFT:       'member:left',
  LOCATION_CHANGED:  'location:changed',    // 다른 멤버 위치 수신
  STATUS_CHANGED:    'status:changed',
  SOS_ALERT:         'sos:alert',
  SESSION_SNAPSHOT:  'session:snapshot',    // 첫 연결 시 전체 상태
  ERROR:             'error',
};

// ─────────────────────────────────────────────────────────────────────────────
// Socket.IO 서버 초기화
// ─────────────────────────────────────────────────────────────────────────────
export const createSocketServer = (httpServer) => {
  const io = new Server(httpServer, {
    cors: {
      origin: process.env.ALLOWED_ORIGINS?.split(',') || '*',
      credentials: true,
    },
    // 연결 안정성 설정
    pingTimeout: 60000,
    pingInterval: 25000,
    transports: ['websocket', 'polling'],
  });

  // ── 전역 인증 미들웨어 ─────────────────────────────────────────────────
  // 모든 소켓 연결 전에 JWT 검증
  io.use(async (socket, next) => {
    try {
      const token =
        socket.handshake.auth?.token ||          // { auth: { token } }
        socket.handshake.query?.token;            // ?token=xxx (Fallback)

      const user = verifySocketToken(token);
      socket.user = user;  // socket.user.id, socket.user.nickname 사용 가능
      next();
    } catch (err) {
      next(new Error('AUTH_FAILED'));
    }
  });

  // ── Redis Pub/Sub 구독 설정 ────────────────────────────────────────────
  // 다른 서버 인스턴스에서 발행한 위치 이벤트를 받아 해당 Room으로 전달
  subClient.subscribe('location:*', (message, channel) => {
    // channel 형식: location:{sessionId}:{userId}
    const parts = channel.split(':');
    const sessionId = parts[1];
    const senderId  = parts[2];

    const data = JSON.parse(message);

    // 송신자 제외하고 같은 세션 Room에 브로드캐스트
    io.to(`session:${sessionId}`)
      .except(`user:${senderId}`)
      .emit(EVENTS.LOCATION_CHANGED, data);
  });

  subClient.subscribe('session:event:*', (message, channel) => {
    const sessionId = channel.split(':')[2];
    const event = JSON.parse(message);
    io.to(`session:${sessionId}`).emit(event.type, event.payload);
  });

  // ── 소켓 연결 핸들러 ─────────────────────────────────────────────────
  io.on('connection', (socket) => {
    const userId = socket.user.id;
    console.log(`[WS] Connected: ${socket.user.nickname} (${userId})`);

    // 사용자 전용 룸 (개인 알림용)
    socket.join(`user:${userId}`);

    // ── session:join ──────────────────────────────────────────────────
    socket.on(EVENTS.JOIN_SESSION, async ({ sessionId }) => {
      if (!sessionId) {
        return socket.emit(EVENTS.ERROR, { code: 'MISSING_SESSION_ID' });
      }

      try {
        // 멤버 목록 확인 (세션에 속해 있는지)
        const members = await sessionService.getSessionMembers(sessionId);
        const isMember = members.some((m) => m.user_id === userId);
        if (!isMember) {
          return socket.emit(EVENTS.ERROR, { code: 'NOT_A_MEMBER' });
        }

        const roomName = `session:${sessionId}`;
        socket.join(roomName);
        socket.currentSessionId = sessionId;

        // 현재 세션의 모든 멤버 위치 스냅샷 전송 (초기 동기화)
        const memberIds = members.map((m) => m.user_id);
        const snapshot = await locationService.getSessionSnapshot(sessionId, memberIds);

        socket.emit(EVENTS.SESSION_SNAPSHOT, {
          sessionId,
          members,
          locations: snapshot,
        });

        // 다른 멤버에게 입장 알림
        socket.to(roomName).emit(EVENTS.MEMBER_JOINED, {
          userId,
          nickname: socket.user.nickname,
          timestamp: Date.now(),
        });

        socket.emit(EVENTS.SESSION_JOINED, { sessionId, memberCount: members.length });

      } catch (err) {
        console.error('[WS] join error:', err);
        socket.emit(EVENTS.ERROR, { code: 'JOIN_FAILED' });
      }
    });

    // ── location:update ───────────────────────────────────────────────
    // 클라이언트 GPS 위치 수신 → 저장 → 같은 세션 멤버에게 브로드캐스트
    socket.on(EVENTS.LOCATION_UPDATE, async (payload) => {
      const sessionId = socket.currentSessionId || payload.sessionId;
      if (!sessionId) return;

      const { lat, lng, accuracy, altitude, speed, heading, source, battery, status } = payload;

      // 기본 유효성 검사
      if (typeof lat !== 'number' || typeof lng !== 'number') return;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return;

      try {
        const saved = await locationService.saveLocation(userId, sessionId, {
          lat, lng, accuracy, altitude, speed, heading,
          source: source || 'gps',
          battery,
          status: status || 'moving',
        });

        const broadcastData = {
          userId,
          sessionId,
          nickname: socket.user.nickname,
          ...saved,
        };

        // Redis Pub/Sub으로 발행 (수평 확장 대응)
        await redisClient.publish(
          `location:${sessionId}:${userId}`,
          JSON.stringify(broadcastData)
        );

        // 같은 서버 인스턴스 내 즉시 브로드캐스트 (레이턴시 최소화)
        socket.to(`session:${sessionId}`).emit(EVENTS.LOCATION_CHANGED, broadcastData);

      } catch (err) {
        console.error('[WS] location update error:', err);
      }
    });

    // ── status:update ─────────────────────────────────────────────────
    // 이동중 / 정지 / SOS 등 상태 변경
    socket.on(EVENTS.STATUS_UPDATE, async ({ sessionId: sid, status, battery }) => {
      const sessionId = sid || socket.currentSessionId;
      if (!sessionId) return;

      const validStatuses = ['moving', 'stopped', 'sos', 'idle'];
      if (!validStatuses.includes(status)) return;

      const payload = {
        userId,
        nickname: socket.user.nickname,
        status,
        battery,
        timestamp: Date.now(),
      };

      io.to(`session:${sessionId}`).emit(EVENTS.STATUS_CHANGED, payload);
    });

    // ── sos:trigger ───────────────────────────────────────────────────
    // 긴급 SOS 발송 → 세션 전체에 고우선순위 알림
    socket.on(EVENTS.SOS_TRIGGER, async ({ sessionId: sid, message, lat, lng }) => {
      const sessionId = sid || socket.currentSessionId;
      if (!sessionId) return;

      console.warn(`[SOS] User ${userId} triggered SOS in session ${sessionId}`);

      const sosPayload = {
        userId,
        nickname: socket.user.nickname,
        message: message || '긴급 상황 발생!',
        location: lat && lng ? { lat, lng } : null,
        timestamp: Date.now(),
      };

      // 세션 전체에 SOS 브로드캐스트 (본인 포함)
      io.to(`session:${sessionId}`).emit(EVENTS.SOS_ALERT, sosPayload);

      // TODO: Phase 2 - FCM 푸시 알림으로 백그라운드 멤버에게도 전달
    });

    // ── disconnect ────────────────────────────────────────────────────
    socket.on('disconnect', (reason) => {
      console.log(`[WS] Disconnected: ${socket.user.nickname} - ${reason}`);

      const sessionId = socket.currentSessionId;
      if (sessionId) {
        socket.to(`session:${sessionId}`).emit(EVENTS.MEMBER_LEFT, {
          userId,
          nickname: socket.user.nickname,
          reason,
          timestamp: Date.now(),
        });
      }
    });
  });

  return io;
};
