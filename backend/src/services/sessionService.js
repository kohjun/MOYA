// src/websocket/index.js
import { Server } from 'socket.io';
import { createAdapter } from '@socket.io/redis-streams-adapter';
import { verifySocketToken } from '../middleware/auth.js';
import { redisClient } from '../config/redis.js'; // subClient는 더 이상 필요 없음
import * as locationService from '../services/locationService.js';
import * as sessionService from '../services/sessionService.js';
import { sendSosAlert, sendGeofenceAlert } from '../services/fcmService.js';
import { checkGeofences } from '../services/geofenceService.js';

// ─────────────────────────────────────────────────────────────────────────────
// Socket.IO 이벤트 상수 (클라이언트와 공유하는 프로토콜)
// ─────────────────────────────────────────────────────────────────────────────
export const EVENTS = {
  JOIN_SESSION:      'session:join',
  LEAVE_SESSION:     'session:leave',
  LOCATION_UPDATE:   'location:update',
  STATUS_UPDATE:     'status:update',
  SOS_TRIGGER:       'sos:trigger',

  SESSION_JOINED:    'session:joined',
  MEMBER_JOINED:     'member:joined',
  MEMBER_LEFT:       'member:left',
  LOCATION_CHANGED:  'location:changed',
  STATUS_CHANGED:    'status:changed',
  SOS_ALERT:         'sos:alert',
  SESSION_SNAPSHOT:  'session:snapshot',
  KICKED:            'kicked',
  ROLE_CHANGED:      'role_changed',
  ERROR:             'error',
};

let _io = null;
export const getIo = () => _io;

// ─────────────────────────────────────────────────────────────────────────────
// Socket.IO 서버 초기화
// ─────────────────────────────────────────────────────────────────────────────
export const createSocketServer = (httpServer) => {
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

  // ── Redis Streams Adapter 장착 (클러스터링 및 스케일아웃) ────────────────
  // 이제 io.to('room').emit()을 사용하면 여러 대의 Node.js 서버에 접속한
  // 모든 유저들에게 자동으로 메시지가 분산 전달됩니다. 수동 Publish 불필요.
  io.adapter(createAdapter(redisClient));

  // ── 전역 인증 미들웨어 ─────────────────────────────────────────────────
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

  // ── 소켓 연결 핸들러 ─────────────────────────────────────────────────
  io.on('connection', (socket) => {
    const userId = socket.user.id;
    console.log(`[WS] Connected: ${socket.user.nickname} (${userId})`);

    socket.join(`user:${userId}`);

    // ── session:join ──────────────────────────────────────────────────
    socket.on(EVENTS.JOIN_SESSION, async ({ sessionId }) => {
      if (!sessionId) {
        return socket.emit(EVENTS.ERROR, { code: 'MISSING_SESSION_ID' });
      }

      try {
        const members = await sessionService.getSessionMembers(sessionId);
        const isMember = members.some((m) => m.user_id === userId);
        if (!isMember) {
          return socket.emit(EVENTS.ERROR, { code: 'NOT_A_MEMBER' });
        }

        const roomName = `session:${sessionId}`;
        socket.join(roomName);
        socket.currentSessionId = sessionId;

        // DB 스냅샷 대신, Redis에 저장된 최신 상태(State Layer)를 불러오는 로직으로 
        // 향후 고도화할 수 있습니다. 현재는 기존 DB 스냅샷 유지.
        const memberIds = members.map((m) => m.user_id);
        const snapshot = await locationService.getSessionSnapshot(sessionId, memberIds);

        socket.emit(EVENTS.SESSION_SNAPSHOT, {
          sessionId,
          members,
          locations: snapshot,
        });

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
    socket.on(EVENTS.LOCATION_UPDATE, async (payload) => {
      const sessionId = socket.currentSessionId || payload.sessionId;
      if (!sessionId) return;

      const { lat, lng, accuracy, altitude, speed, heading, source, battery, status } = payload;

      if (typeof lat !== 'number' || typeof lng !== 'number') return;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return;

      try {
        // 1. (선택적) DB 저장. 실시간성이 더 중요하다면 이 과정은 Kafka 등으로 넘기고 
        // 비동기로 빼는 것이 이상적입니다.
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

        // 2. Realtime Layer: Redis Adapter가 알아서 다른 서버 클라이언트로 중계해줌
        socket.to(`session:${sessionId}`).emit(EVENTS.LOCATION_CHANGED, broadcastData);

        // 3. State Layer: 최신 유저 상태를 Redis Hash에 저장 (DB 부하 제로)
        const stateKey = `session:${sessionId}:user:${userId}:state`;
        await redisClient.hSet(stateKey, {
          lat: lat.toString(),
          lng: lng.toString(),
          status: status || 'moving',
          lastActivity: Date.now().toString()
        });
        // 2시간 뒤 자동 만료 처리
        await redisClient.expire(stateKey, 7200);

        // 4. 지오펜스 감지 (기존 유지)
        checkGeofences(userId, sessionId, lat, lng)
          .then(({ entered, exited }) => {
            if (entered.length > 0) {
              sendGeofenceAlert({
                sessionId, userId,
                nickname: socket.user.nickname,
                geofences: entered,
                eventType: 'enter',
              }).catch((e) => console.error('[WS] FCM enter err:', e));
            }
            if (exited.length > 0) {
              sendGeofenceAlert({
                sessionId, userId,
                nickname: socket.user.nickname,
                geofences: exited,
                eventType: 'exit',
              }).catch((e) => console.error('[WS] FCM exit err:', e));
            }
          })
          .catch((e) => console.error('[WS] checkGeofences error:', e));

      } catch (err) {
        console.error('[WS] location update error:', err);
      }
    });

    // ── status:update ─────────────────────────────────────────────────
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

      // Realtime Layer
      io.to(`session:${sessionId}`).emit(EVENTS.STATUS_CHANGED, payload);

      // State Layer 업데이트
      const stateKey = `session:${sessionId}:user:${userId}:state`;
      await redisClient.hSet(stateKey, {
        status: status,
        battery: battery ? battery.toString() : "0",
        lastActivity: Date.now().toString()
      });
      await redisClient.expire(stateKey, 7200);
    });

    // ── sos:trigger ───────────────────────────────────────────────────
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

      io.to(`session:${sessionId}`).emit(EVENTS.SOS_ALERT, sosPayload);

      sendSosAlert({
        sessionId,
        triggeredByUserId: userId,
        nickname: socket.user.nickname,
        location: lat && lng ? { lat, lng } : null,
        sosMessage: message || '긴급 상황 발생!',
      }).catch((err) => console.error('[WS] FCM SOS error:', err));
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