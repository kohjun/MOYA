import { redisClient } from '../../config/redis.js';
import * as locationService from '../../services/locationService.js';
import * as sessionService from '../../services/sessionService.js';
import { sendSosAlert, sendGeofenceAlert } from '../../services/fcmService.js';
import { checkGeofences } from '../../services/geofenceService.js';
import { EVENTS } from '../socketProtocol.js';
import { ensureMediaRoomForSocket } from '../socketRuntime.js';

export const registerSessionHandlers = ({ io, socket, mediaServer, userId, leaveSession }) => {
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

      if (socket.currentSessionId && socket.currentSessionId !== sessionId) {
        await leaveSession(socket.currentSessionId);
      }

      const roomName = `session:${sessionId}`;
      socket.join(roomName);
      socket.currentSessionId = sessionId;

      const memberIds = members.map((m) => m.user_id);
      const snapshot = await locationService.getSessionSnapshot(sessionId, memberIds);
      const joinedMember = members.find((m) => m.user_id === userId);

      socket.emit(EVENTS.SESSION_SNAPSHOT, {
        sessionId,
        members,
        locations: snapshot,
      });

      socket.to(roomName).emit(EVENTS.MEMBER_JOINED, {
        userId,
        nickname: socket.user.nickname,
        teamId: joinedMember?.team_id ?? null,
        role: joinedMember?.role ?? 'member',
        timestamp: Date.now(),
      });

      socket.emit(EVENTS.SESSION_JOINED, { sessionId, memberCount: members.length });

      await ensureMediaRoomForSocket({ socket, mediaServer, sessionId });
    } catch (err) {
      console.error('[WS] join error:', err);
      socket.emit(EVENTS.ERROR, { code: 'JOIN_FAILED' });
    }
  });

  socket.on(EVENTS.LEAVE_SESSION, async ({ sessionId: sid } = {}) => {
    const sessionId = sid || socket.currentSessionId;
    if (!sessionId) return;

    await leaveSession(sessionId);

    socket.to(`session:${sessionId}`).emit(EVENTS.MEMBER_LEFT, {
      userId,
      nickname: socket.user.nickname,
      reason: 'leave',
      timestamp: Date.now(),
    });
  });

  socket.on(EVENTS.LOCATION_UPDATE, async (payload) => {
    const sessionId = socket.currentSessionId || payload.sessionId;
    if (!sessionId) return;

    const { lat, lng, accuracy, altitude, speed, heading, source, battery, status } = payload;

    if (typeof lat !== 'number' || typeof lng !== 'number') return;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return;

    try {
      const saved = await locationService.saveLocation(userId, sessionId, {
        lat, lng, accuracy, altitude, speed, heading,
        source: source || 'gps',
        battery,
        status: status || 'moving',
      });

      await redisClient.set(
        `prox:${sessionId}:${userId}`,
        JSON.stringify({ lat, lng }),
        { EX: 300 },
      );

      const broadcastData = {
        userId,
        sessionId,
        nickname: socket.user.nickname,
        ...saved,
      };

      socket.to(`session:${sessionId}`).emit(EVENTS.LOCATION_CHANGED, broadcastData);

      // 지오펜스 DB 과부하 방지: 5초 throttle
      const geoThrottleKey = `throttle:geo:${sessionId}:${userId}`;
      const canCheckGeo = await redisClient.set(geoThrottleKey, '1', { NX: true, EX: 5 });

      if (canCheckGeo) {
        checkGeofences(userId, sessionId, lat, lng)
          .then(({ entered, exited }) => {
            if (entered.length > 0) {
              sendGeofenceAlert({
                sessionId, userId,
                nickname: socket.user.nickname,
                geofences: entered,
                eventType: 'enter',
              }).catch((e) => console.error('[WS] FCM geofence enter error:', e));
            }
            if (exited.length > 0) {
              sendGeofenceAlert({
                sessionId, userId,
                nickname: socket.user.nickname,
                geofences: exited,
                eventType: 'exit',
              }).catch((e) => console.error('[WS] FCM geofence exit error:', e));
            }
          })
          .catch((e) => console.error('[WS] checkGeofences error:', e));
      }
    } catch (err) {
      console.error('[WS] location update error:', err);
    }
  });

  socket.on(EVENTS.STATUS_UPDATE, async ({ sessionId: sid, status, battery }) => {
    const sessionId = sid || socket.currentSessionId;
    if (!sessionId) return;
    const validStatuses = ['moving', 'stopped', 'sos', 'idle'];
    if (!validStatuses.includes(status)) return;
    io.to(`session:${sessionId}`).emit(EVENTS.STATUS_CHANGED, {
      userId, nickname: socket.user.nickname, status, battery, timestamp: Date.now(),
    });
  });

  socket.on(EVENTS.SOS_TRIGGER, async ({ sessionId: sid, message, lat, lng }) => {
    const sessionId = sid || socket.currentSessionId;
    if (!sessionId) return;
    io.to(`session:${sessionId}`).emit(EVENTS.SOS_ALERT, {
      userId, nickname: socket.user.nickname,
      message: message || '긴급 상황 발생!',
      location: lat && lng ? { lat, lng } : null,
      timestamp: Date.now(),
    });
    sendSosAlert({
      sessionId, triggeredByUserId: userId, nickname: socket.user.nickname,
      location: lat && lng ? { lat, lng } : null, sosMessage: message || '긴급 상황 발생!',
    }).catch((err) => console.error('[WS] FCM SOS error:', err));
  });

  socket.on(EVENTS.VOICE_SPEAKING, ({ sessionId: sid, isSpeaking }) => {
    const sessionId = sid || socket.currentSessionId;
    if (!sessionId) return;
    socket.to(`session:${sessionId}`).emit(EVENTS.VOICE_SPEAKING, {
      userId,
      isSpeaking: !!isSpeaking,
    });
  });

  socket.on('disconnect', async (reason) => {
    console.log(`[WS] Disconnected: ${socket.user.nickname} - ${reason}`);
    const sessionId = socket.currentSessionId;
    if (sessionId) {
      socket.to(`session:${sessionId}`).emit(EVENTS.MEMBER_LEFT, {
        userId, nickname: socket.user.nickname, reason, timestamp: Date.now(),
      });
      await leaveSession(sessionId);
    }
  });
};
