// src/routes/sessions.js
import { z } from 'zod';
import { authenticate } from '../middleware/auth.js';
import * as sessionService from '../services/sessionService.js';
import * as locationService from '../services/locationService.js';

const createSessionSchema = z.object({
  name: z.string().max(100).optional(),
});

export default async function sessionRoutes(fastify) {
  // 모든 세션 라우트는 인증 필요
  fastify.addHook('preHandler', authenticate);

  // ── POST /sessions ───────────────────────────────────────────────────────
  // 세션 생성 (호스트가 됨)
  fastify.post('/', async (request, reply) => {
    const parsed = createSessionSchema.safeParse(request.body || {});
    if (!parsed.success) {
      return reply.code(400).send({ error: 'VALIDATION_ERROR' });
    }

    const session = await sessionService.createSession(request.user.id, parsed.data);
    return reply.code(201).send({ session });
  });

  // ── POST /sessions/join ──────────────────────────────────────────────────
  // 초대 코드로 세션 참가
  fastify.post('/join', async (request, reply) => {
    const { code } = request.body || {};
    if (!code || typeof code !== 'string') {
      return reply.code(400).send({ error: 'MISSING_SESSION_CODE' });
    }

    try {
      const session = await sessionService.joinSession(request.user.id, code);
      return reply.send({ session });
    } catch (err) {
      const errorMap = {
        SESSION_NOT_FOUND: 404,
        SESSION_ENDED:     410,
        SESSION_EXPIRED:   410,
        ALREADY_IN_SESSION: 409,
      };
      return reply.code(errorMap[err.message] || 500).send({ error: err.message });
    }
  });

  // ── GET /sessions ────────────────────────────────────────────────────────
  // 내가 참가 중인 세션 목록
  fastify.get('/', async (request, reply) => {
    const sessions = await sessionService.getMySessions(request.user.id);
    return reply.send({ sessions });
  });

  // ── GET /sessions/:sessionId ─────────────────────────────────────────────
  // 세션 상세 (멤버 목록 + 각 멤버 최신 위치)
  fastify.get('/:sessionId', async (request, reply) => {
    const { sessionId } = request.params;

    const members = await sessionService.getSessionMembers(sessionId);

    // 현재 유저가 이 세션 멤버인지 확인
    const isMember = members.some((m) => m.user_id === request.user.id);
    if (!isMember) {
      return reply.code(403).send({ error: 'NOT_A_MEMBER' });
    }

    return reply.send({ members });
  });

  // ── DELETE /sessions/:sessionId ──────────────────────────────────────────
  // 세션 종료 (호스트만)
  fastify.delete('/:sessionId', async (request, reply) => {
    try {
      await sessionService.endSession(request.user.id, request.params.sessionId);
      return reply.send({ message: 'Session ended' });
    } catch (err) {
      if (err.message === 'SESSION_NOT_FOUND_OR_NOT_HOST') {
        return reply.code(403).send({ error: err.message });
      }
      throw err;
    }
  });

  // ── POST /sessions/:sessionId/leave ─────────────────────────────────────
  // 세션 나가기
  fastify.post('/:sessionId/leave', async (request, reply) => {
    await sessionService.leaveSession(request.user.id, request.params.sessionId);
    return reply.send({ message: 'Left session' });
  });

  // ── GET /sessions/:sessionId/track/:userId ───────────────────────────────
  // 특정 멤버 이동 경로 히스토리 조회
  fastify.get('/:sessionId/track/:userId', async (request, reply) => {
    const { sessionId, userId } = request.params;
    const { from, to, limit } = request.query;

    // 세션 멤버인지 확인
    const members = await sessionService.getSessionMembers(sessionId);
    const isMember = members.some((m) => m.user_id === request.user.id);
    if (!isMember) {
      return reply.code(403).send({ error: 'NOT_A_MEMBER' });
    }

    const track = await locationService.getTrackHistory(userId, sessionId, {
      from,
      to,
      limit: limit ? Math.min(Number(limit), 1000) : 500,
    });

    return reply.send({ track });
  });

  // ── GET /sessions/:sessionId/distance ────────────────────────────────────
  // 두 사용자 간 현재 거리
  fastify.get('/:sessionId/distance', async (request, reply) => {
    const { sessionId } = request.params;
    const { userId1, userId2 } = request.query;

    if (!userId1 || !userId2) {
      return reply.code(400).send({ error: 'MISSING_USER_IDS' });
    }

    const distance = await locationService.getDistanceBetweenUsers(
      sessionId, userId1, userId2
    );

    return reply.send({
      distance,
      unit: 'meters',
      available: distance !== null,
    });
  });

  // ── PATCH /sessions/:sessionId/sharing ───────────────────────────────────
  // 내 위치 공유 ON/OFF
  fastify.patch('/:sessionId/sharing', async (request, reply) => {
    const { enabled } = request.body || {};
    if (typeof enabled !== 'boolean') {
      return reply.code(400).send({ error: 'MISSING_ENABLED_FIELD' });
    }

    await locationService.toggleSharing(request.user.id, request.params.sessionId, enabled);
    return reply.send({ sharing_enabled: enabled });
  });
}
