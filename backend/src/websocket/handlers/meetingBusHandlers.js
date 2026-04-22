import { redisClient } from '../../config/redis.js';
import EventBus from '../../game/EventBus.js';
import * as AIDirector from '../../ai/AIDirector.js';
import { EVENTS } from '../socketProtocol.js';
import { normalizeGameState, saveGameState } from '../socketRuntime.js';

/**
 * VoteSystem이 EventBus로 내보내는 회의/투표 흐름 이벤트를 Socket.IO 방 전체에
 * 중계한다. 소켓 단위가 아니라 io 인스턴스 단위로 1회만 등록한다.
 */
export const registerMeetingBusHandlers = ({ io, mediaServer }) => {
  EventBus.on('meeting_started', async ({ session, voteSession }) => {
    io.to(`session:${session.id}`).emit(EVENTS.GAME_MEETING_STARTED, {
      callerId:       voteSession.callerId,
      bodyId:         voteSession.bodyId,
      reason:         voteSession.reason,
      discussionTime: voteSession.discussionTime,
    });

    const mediaRoom = mediaServer?.getRoom(session.id);
    if (mediaRoom) {
      mediaRoom.setAlivePeers(
        (session.aliveMembers ?? []).map((member) => member.user_id ?? member.userId),
      );
      mediaRoom.startEmergencyMeeting();
    }

    try {
      const caller = { nickname: voteSession.callerId };
      const body   = voteSession.bodyId ? { nickname: voteSession.bodyId, zone: '' } : null;
      const msg = await AIDirector.onMeeting(session, caller, voteSession.reason, body);
      if (msg) {
        io.to(`session:${session.id}`).emit(EVENTS.GAME_AI_MESSAGE, {
          type: 'announcement',
          message: msg,
        });
      }
    } catch (e) {
      console.error('[AI] 회의 안내 실패:', e.message);
    }
  });

  EventBus.on('meeting_tick', ({ session, phase, remaining, earlyEnd }) => {
    io.to(`session:${session.id}`).emit(EVENTS.GAME_MEETING_TICK, { phase, remaining, earlyEnd });
  });

  EventBus.on('voting_started', ({ session, voteSession }) => {
    io.to(`session:${session.id}`).emit(EVENTS.GAME_VOTING_STARTED, { voteTime: voteSession.voteTime });
  });

  EventBus.on('pre_vote_submitted', ({ sessionId, count, totalPlayers }) => {
    io.to(`session:${sessionId}`).emit(EVENTS.GAME_PRE_VOTE_SUBMITTED, { totalPreVotes: count, totalPlayers });
  });

  EventBus.on('vote_submitted', ({ sessionId, count, totalPlayers }) => {
    io.to(`session:${sessionId}`).emit(EVENTS.GAME_VOTE_SUBMITTED, { totalVotes: count, totalPlayers });
  });

  EventBus.on('vote_result', async ({ session, result, ejected, ejectedMember }) => {
    let nextResult = { ...result };
    const ejectedPayload = ejected
      ? { userId: ejected, nickname: ejectedMember?.nickname ?? ejected }
      : null;

    try {
      const gameRaw = await redisClient.get(`game:${session.id}`);
      if (gameRaw) {
        const gameState = normalizeGameState(JSON.parse(gameRaw));
        if (ejected) {
          const wasImpostor = gameState.impostors.includes(ejected);
          nextResult = { ...nextResult, wasImpostor };
          if (gameState.alivePlayerIds.includes(ejected)) {
            gameState.alivePlayerIds = gameState.alivePlayerIds.filter((id) => id !== ejected);
          }
          const aliveImpostors = gameState.impostors.filter((id) => gameState.alivePlayerIds.includes(id));
          const aliveCrew = gameState.alivePlayerIds.filter((id) => !gameState.impostors.includes(id));

          let gameOverPayload = null;
          if (aliveImpostors.length === 0) {
            gameState.status = 'finished';
            gameState.finishedAt = Date.now();
            gameOverPayload = { winner: 'crew', reason: 'impostors_ejected' };
          } else if (aliveImpostors.length >= aliveCrew.length) {
            gameState.status = 'finished';
            gameState.finishedAt = Date.now();
            gameOverPayload = { winner: 'impostor', reason: 'outnumbered' };
          }

          await saveGameState(session.id, gameState);
          mediaServer?.getRoom(session.id)?.setAlivePeers(gameState.alivePlayerIds);
          mediaServer?.getRoom(session.id)?.startEmergencyMeeting();
          io.to(`session:${session.id}`).emit(EVENTS.GAME_STATE_UPDATE, {
            sessionId: session.id, status: gameState.status,
            aliveCount: gameState.alivePlayerIds.length, alivePlayerIds: gameState.alivePlayerIds,
          });
          if (gameOverPayload != null) {
            io.to(`session:${session.id}`).emit(EVENTS.GAME_OVER, gameOverPayload);
          }
        }
      }
    } catch (e) {
      console.error('[WS] vote_result sync error:', e);
    }

    io.to(`session:${session.id}`).emit(EVENTS.GAME_VOTE_RESULT, { ...nextResult, ejected: ejectedPayload });

    try {
      const msg = await AIDirector.onVoteResult(session, nextResult, ejectedPayload);
      if (msg) {
        io.to(`session:${session.id}`).emit(EVENTS.GAME_AI_MESSAGE, {
          type: 'vote_result',
          message: msg,
        });
      }
    } catch (e) {
      console.error('[AI] 투표 결과 해설 실패:', e.message);
    }
  });

  EventBus.on('meeting_ended', ({ session }) => {
    mediaServer?.getRoom(session.id)?.muteAll();
    io.to(`session:${session.id}`).emit(EVENTS.GAME_MEETING_ENDED, { message: '게임으로 돌아갑니다.' });
  });
};
