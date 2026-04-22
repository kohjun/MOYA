import { redisClient } from '../../config/redis.js';
import * as sessionService from '../../services/sessionService.js';
import { EVENTS } from '../socketProtocol.js';
import { normalizeGameState, saveGameState } from '../socketRuntime.js';

export const registerRoundVoteHandlers = ({ io, socket, userId }) => {
  socket.on(EVENTS.ROUND_START, async ({ sessionId: sid } = {}) => {
    const sessionId = sid || socket.currentSessionId;
    if (!sessionId) return socket.emit(EVENTS.MODULE_ERROR, { code: 'MISSING_SESSION_ID' });

    try {
      const session = await sessionService.getSession(sessionId);
      if (!session) return socket.emit(EVENTS.MODULE_ERROR, { code: 'SESSION_NOT_FOUND' });
      if (session.host_user_id !== userId) return socket.emit(EVENTS.MODULE_ERROR, { code: 'PERMISSION_DENIED' });

      const gameRaw = await redisClient.get(`game:${sessionId}`);
      if (!gameRaw) return socket.emit(EVENTS.MODULE_ERROR, { code: 'GAME_NOT_STARTED' });

      const currentRaw = await redisClient.get(`round:${sessionId}:current`);
      const roundNumber = (parseInt(currentRaw ?? '0', 10) || 0) + 1;
      await redisClient.set(`round:${sessionId}:current`, String(roundNumber), { EX: 86400 });

      const roundState = { roundNumber, phase: 'discussing', startedAt: Date.now(), votes: {} };
      await redisClient.set(`round:${sessionId}:${roundNumber}`, JSON.stringify(roundState), { EX: 86400 });

      io.to(`session:${sessionId}`).emit(EVENTS.ROUND_START, { sessionId, ...roundState });
    } catch (err) {
      console.error('[WS] round:start error:', err);
      socket.emit(EVENTS.MODULE_ERROR, { code: 'INTERNAL_ERROR' });
    }
  });

  socket.on(EVENTS.VOTE_OPEN, async ({ sessionId: sid, prompt } = {}) => {
    const sessionId = sid || socket.currentSessionId;
    if (!sessionId) return socket.emit(EVENTS.MODULE_ERROR, { code: 'MISSING_SESSION_ID' });

    try {
      const session = await sessionService.getSession(sessionId);
      if (!session) return socket.emit(EVENTS.MODULE_ERROR, { code: 'SESSION_NOT_FOUND' });
      if (session.host_user_id !== userId) return socket.emit(EVENTS.MODULE_ERROR, { code: 'PERMISSION_DENIED' });

      const currentRaw = await redisClient.get(`round:${sessionId}:current`);
      if (!currentRaw) return socket.emit(EVENTS.MODULE_ERROR, { code: 'NO_ACTIVE_ROUND' });

      const roundNumber = parseInt(currentRaw, 10);
      const roundRaw = await redisClient.get(`round:${sessionId}:${roundNumber}`);
      if (!roundRaw) return socket.emit(EVENTS.MODULE_ERROR, { code: 'ROUND_NOT_FOUND' });

      const roundState = JSON.parse(roundRaw);
      roundState.phase = 'voting';
      await redisClient.set(`round:${sessionId}:${roundNumber}`, JSON.stringify(roundState), { EX: 86400 });

      io.to(`session:${sessionId}`).emit(EVENTS.VOTE_OPEN, { sessionId, roundNumber, prompt: prompt ?? '' });
    } catch (err) {
      console.error('[WS] vote:open error:', err);
      socket.emit(EVENTS.MODULE_ERROR, { code: 'INTERNAL_ERROR' });
    }
  });

  socket.on(EVENTS.VOTE_CAST, async ({ sessionId: sid, roundNumber, targetUserId } = {}) => {
    const sessionId = sid || socket.currentSessionId;
    if (!sessionId || roundNumber == null || !targetUserId) {
      return socket.emit(EVENTS.MODULE_ERROR, { code: 'MISSING_FIELDS' });
    }

    try {
      const roundRaw = await redisClient.get(`round:${sessionId}:${roundNumber}`);
      if (!roundRaw) return socket.emit(EVENTS.MODULE_ERROR, { code: 'ROUND_NOT_FOUND' });

      const roundState = JSON.parse(roundRaw);
      roundState.votes[userId] = targetUserId;
      await redisClient.set(`round:${sessionId}:${roundNumber}`, JSON.stringify(roundState), { EX: 86400 });

      const votedCount = Object.keys(roundState.votes).length;
      io.to(`session:${sessionId}`).emit(EVENTS.VOTE_CAST, { sessionId, roundNumber, votedCount });

      const gameRaw = await redisClient.get(`game:${sessionId}`);
      if (!gameRaw) return;

      const gameState = normalizeGameState(JSON.parse(gameRaw));
      if (votedCount < gameState.alivePlayerIds.length) return;

      const tally = {};
      for (const vote of Object.values(roundState.votes)) {
        tally[vote] = (tally[vote] ?? 0) + 1;
      }

      const eliminatedUserId = Object.entries(tally).reduce(
        (top, [id, count]) => (count > (tally[top] ?? 0) ? id : top),
        Object.keys(tally)[0],
      );

      await redisClient.set(`eliminated:${sessionId}:${eliminatedUserId}`, '1', { EX: 86400 });

      gameState.alivePlayerIds = gameState.alivePlayerIds.filter((id) => id !== eliminatedUserId);
      if (gameState.alivePlayerIds.length <= 1) {
        gameState.status = 'finished';
        gameState.finishedAt = Date.now();
      }
      await saveGameState(sessionId, gameState);

      io.to(`session:${sessionId}`).emit(EVENTS.VOTE_RESULT, {
        sessionId, roundNumber, eliminatedUserId, voteBreakdown: tally,
      });

      io.to(`session:${sessionId}`).emit(EVENTS.GAME_STATE_UPDATE, {
        sessionId, status: gameState.status,
        aliveCount: gameState.alivePlayerIds.length,
        alivePlayerIds: gameState.alivePlayerIds,
      });
    } catch (err) {
      console.error('[WS] vote:cast error:', err);
      socket.emit(EVENTS.MODULE_ERROR, { code: 'INTERNAL_ERROR' });
    }
  });
};
