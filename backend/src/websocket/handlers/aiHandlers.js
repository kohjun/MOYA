import { redisClient } from '../../config/redis.js';
import * as AIDirector from '../../ai/AIDirector.js';
import { EVENTS } from '../socketProtocol.js';
import { readGameState } from '../socketRuntime.js';

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

    const aiLimitKey = `throttle:ai:${sessionId}:${userId}`;
    const canAsk = await redisClient.set(aiLimitKey, '1', { NX: true, EX: 5 });
    if (!canAsk) {
      return respond({
        ok: false,
        error: 'AI 마스터가 답변을 준비 중입니다. 잠시 후 다시 질문해주세요.',
      });
    }

    try {
      const gameState = await readGameState(sessionId);
      if (!gameState) return respond({ ok: false, error: '게임이 시작되지 않았습니다.' });

      const ps = gameState.pluginState ?? {};
      const playerState = ps.playerStates?.[userId] ?? {};

      const roomLike = {
        roomId:         sessionId,
        gameType:       gameState.gameType,
        status:         gameState.status,
        alivePlayerIds: gameState.alivePlayerIds ?? [],
        pluginState:    ps,
      };

      const playerLike = {
        userId,
        nickname: socket.user.nickname,
        team:     playerState.guildId ?? null,
        roleId:   playerState.job ?? null,
        isAlive:  playerState.isAlive ?? (gameState.alivePlayerIds ?? []).includes(userId),
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
