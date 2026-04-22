import { redisClient } from '../../config/redis.js';
import * as sessionService from '../../services/sessionService.js';
import { EVENTS } from '../socketProtocol.js';
import { normalizeGameState, saveGameState } from '../socketRuntime.js';

const EARTH_RADIUS_METERS = 6371000;

const toRadians = (deg) => (deg * Math.PI) / 180;

const haversineDistanceMeters = (a, b) => {
  const dLat = toRadians(b.lat - a.lat);
  const dLng = toRadians(b.lng - a.lng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRadians(a.lat)) * Math.cos(toRadians(b.lat)) *
    Math.sin(dLng / 2) ** 2;
  return EARTH_RADIUS_METERS * 2 * Math.atan2(Math.sqrt(s), Math.sqrt(1 - s));
};

const resolveLocation = async (sessionId, uid) => {
  const prox = await redisClient.get(`prox:${sessionId}:${uid}`);
  if (prox) return JSON.parse(prox);
  const main = await redisClient.get(`location:${sessionId}:${uid}`);
  if (main) return JSON.parse(main);
  const hash = await redisClient.hGetAll(`session:${sessionId}:user:${uid}:state`);
  if (hash && hash.lat && hash.lng) {
    return { lat: parseFloat(hash.lat), lng: parseFloat(hash.lng) };
  }
  return null;
};

export const registerProximityHandlers = ({ io, socket, mediaServer, userId }) => {
  socket.on(EVENTS.ACTION_INTERACT, async ({ sessionId: sid, actionType, targetUserId }) => {
    const sessionId = sid || socket.currentSessionId;
    if (!sessionId || !actionType) {
      return socket.emit(EVENTS.MODULE_ERROR, { code: 'MISSING_FIELDS' });
    }

    try {
      const session = await sessionService.getSession(sessionId);
      if (!session) {
        return socket.emit(EVENTS.MODULE_ERROR, { code: 'SESSION_NOT_FOUND' });
      }

      const activeModules = session.active_modules || [];

      if (actionType !== 'PROXIMITY_KILL') return;

      if (!activeModules.includes('PROXIMITY_ACTION')) {
        return socket.emit(EVENTS.MODULE_ERROR, { code: 'MODULE_NOT_ACTIVE' });
      }
      if (!targetUserId) {
        return socket.emit(EVENTS.MODULE_ERROR, { code: 'MISSING_FIELDS' });
      }

      const [actorLoc, targetLoc] = await Promise.all([
        resolveLocation(sessionId, userId),
        resolveLocation(sessionId, targetUserId),
      ]);

      if (!actorLoc || !targetLoc) {
        return socket.emit(EVENTS.ACTION_RESULT, {
          actionType, sessionId, status: 'failed', reason: 'LOCATION_UNAVAILABLE',
        });
      }

      const distance = haversineDistanceMeters(actorLoc, targetLoc);
      if (distance > 15) {
        return socket.emit(EVENTS.ACTION_RESULT, {
          actionType, sessionId, status: 'failed', reason: 'TOO_FAR',
        });
      }

      // 타겟 기준 2초 락 — 동시 타격 방어
      const lockKey = `target_lock:${sessionId}:${targetUserId}`;
      const locked = await redisClient.set(lockKey, '1', { NX: true, EX: 2 });
      if (!locked) return;

      // Tag 모듈 활성 시: 킬 대신 태그 전달
      if (activeModules.includes('tag')) {
        await redisClient.set(`tag:${sessionId}:tagger`, userId, { EX: 86400 });

        socket.emit(EVENTS.ACTION_RESULT, {
          actionType, sessionId, targetUserId, status: 'success',
        });

        io.to(`session:${sessionId}`).emit(EVENTS.TAG_TRANSFERRED, {
          newTaggerId:      userId,
          previousTaggerId: targetUserId,
          sessionId,
          timestamp:        Date.now(),
        });
        return;
      }

      // 일반 킬 처리
      await redisClient.set(`eliminated:${sessionId}:${targetUserId}`, '1', { EX: 86400 });

      socket.emit(EVENTS.ACTION_RESULT, {
        actionType, sessionId, targetUserId, status: 'success',
      });

      io.to(`user:${targetUserId}`).emit('proximity:killed', {
        killedBy: userId,
        nickname: socket.user.nickname,
        sessionId,
      });

      io.to(`session:${sessionId}`).emit(EVENTS.PLAYER_ELIMINATED, {
        userId:    targetUserId,
        killedBy:  userId,
        nickname:  socket.user.nickname,
        sessionId,
        timestamp: Date.now(),
      });

      const gameRaw = await redisClient.get(`game:${sessionId}`);
      if (!gameRaw) return;

      const gameState = normalizeGameState(JSON.parse(gameRaw));
      if (gameState.status !== 'in_progress') return;

      gameState.alivePlayerIds = gameState.alivePlayerIds.filter((id) => id !== targetUserId);
      mediaServer?.getRoom(sessionId)?.setAlivePeers(gameState.alivePlayerIds);

      if (gameState.alivePlayerIds.length === 1) {
        gameState.status = 'finished';
        gameState.finishedAt = Date.now();
        await saveGameState(sessionId, gameState);
        io.to(`session:${sessionId}`).emit(EVENTS.GAME_OVER, {
          winnerId:  gameState.alivePlayerIds[0],
          sessionId,
          timestamp: Date.now(),
        });
      } else {
        await saveGameState(sessionId, gameState);
        io.to(`session:${sessionId}`).emit(EVENTS.GAME_STATE_UPDATE, {
          sessionId,
          status:         gameState.status,
          aliveCount:     gameState.alivePlayerIds.length,
          alivePlayerIds: gameState.alivePlayerIds,
        });
      }
    } catch (err) {
      console.error('[WS] action:interact error:', err);
      socket.emit(EVENTS.MODULE_ERROR, { code: 'INTERNAL_ERROR' });
    }
  });
};
