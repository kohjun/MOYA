import { redisClient } from '../../config/redis.js';
import * as AIDirector from '../../ai/AIDirector.js';
import { EVENTS } from '../socketProtocol.js';
import { normalizeGameState } from '../socketRuntime.js';

export const registerAiHandlers = ({ socket, userId }) => {
  socket.on(EVENTS.GAME_AI_ASK, async ({ sessionId: sid, question }, cb) => {
    const sessionId = sid || socket.currentSessionId;
    const respond = typeof cb === 'function' ? cb : () => {};

    if (!question || question.trim().length === 0) {
      return respond({ ok: false, error: '질문을 입력해주세요.' });
    }
    if (question.length > 200) {
      return respond({ ok: false, error: '질문이 너무 깁니다. (최대 200자)' });
    }

    // AI 쿨타임 쓰로틀링 — 도배/요금 방어 (5초)
    const aiLimitKey = `throttle:ai:${sessionId}:${userId}`;
    const canAsk = await redisClient.set(aiLimitKey, '1', { NX: true, EX: 5 });
    if (!canAsk) {
      return respond({
        ok: false,
        error: 'AI 마스터가 답변을 준비 중입니다. 잠시 후 다시 질문해주세요.',
      });
    }

    try {
      const gameRaw = await redisClient.get(`game:${sessionId}`);
      if (!gameRaw) return respond({ ok: false, error: '게임이 시작되지 않았습니다.' });

      const gameState  = normalizeGameState(JSON.parse(gameRaw));
      const isImpostor = gameState.impostors.includes(userId);

      const roomLike = {
        roomId:         sessionId,
        gameType:       'among_us',
        status:         gameState.status,
        killLog:        gameState.killLog || [],
        alivePlayerIds: gameState.alivePlayerIds || [],
        players:        new Map(
          (gameState.alivePlayerIds || []).map((id) => [id, {
            userId: id,
            isAlive: true,
            team: gameState.impostors.includes(id) ? 'impostor' : 'crew',
          }]),
        ),
      };

      const playerLike = {
        userId,
        nickname:  socket.user.nickname,
        team:      isImpostor ? 'impostor' : 'crew',
        roleId:    isImpostor ? 'impostor' : 'crew',
        isAlive:   gameState.alivePlayerIds.includes(userId),
        tasks:     [],
      };

      respond({ ok: true });

      const {
        answer,
        sources,
        isError = false,
        errorCode = null,
      } = await AIDirector.ask(roomLike, playerLike, question);

      socket.emit(EVENTS.GAME_AI_REPLY, { question, answer, sources, isError, errorCode });
    } catch (err) {
      console.error('[WS] game:ai_ask error:', err);
      socket.emit(EVENTS.GAME_AI_REPLY, {
        question,
        answer: '죄송해요, 잠시 후 다시 물어봐주세요! 🙏',
        sources: [],
        isError: true,
        errorCode: 'AI_UNAVAILABLE',
      });
    }
  });
};
