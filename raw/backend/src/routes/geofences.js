// src/routes/geofences.js
import { z } from 'zod';
import { authenticate } from '../middleware/auth.js';
import * as sessionService from '../services/sessionService.js';
import * as geofenceService from '../services/geofenceService.js';

const createSchema = z.object({
  name:       z.string().min(1).max(100),
  centerLat:  z.number().min(-90).max(90),
  centerLng:  z.number().min(-180).max(180),
  radiusM:    z.number().min(10).max(50000),
  notifyEnter: z.boolean().optional(),
  notifyExit:  z.boolean().optional(),
});

export default async function geofenceRoutes(fastify) {
  fastify.addHook('preHandler', authenticate);

  // 멤버 여부 확인 헬퍼
  async function assertMember(sessionId, userId, reply) {
    const members = await sessionService.getSessionMembers(sessionId);
    if (!members.some((m) => m.user_id === userId)) {
      reply.code(403).send({ error: 'NOT_A_MEMBER' });
      return false;
    }
    return true;
  }

  // ── POST /sessions/:sessionId/geofences ──────────────────────────────────
  fastify.post('/:sessionId/geofences', async (request, reply) => {
    const { sessionId } = request.params;
    if (!(await assertMember(sessionId, request.user.id, reply))) return;

    const parsed = createSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.issues });
    }

    const geofence = await geofenceService.createGeofence(
      sessionId,
      request.user.id,
      parsed.data
    );
    return reply.code(201).send({ geofence });
  });

  // ── GET /sessions/:sessionId/geofences ───────────────────────────────────
  fastify.get('/:sessionId/geofences', async (request, reply) => {
    const { sessionId } = request.params;
    if (!(await assertMember(sessionId, request.user.id, reply))) return;

    const geofences = await geofenceService.getGeofences(sessionId);
    return reply.send({ geofences });
  });

  // ── DELETE /sessions/:sessionId/geofences/:id ────────────────────────────
  fastify.delete('/:sessionId/geofences/:id', async (request, reply) => {
    const { sessionId, id } = request.params;
    if (!(await assertMember(sessionId, request.user.id, reply))) return;

    try {
      await geofenceService.deleteGeofence(id, request.user.id);
      return reply.send({ message: 'Geofence deleted' });
    } catch (err) {
      if (err.message === 'NOT_FOUND_OR_NOT_CREATOR') {
        return reply.code(403).send({ error: err.message });
      }
      throw err;
    }
  });
}
