// src/routes/games.js — game catalog endpoints
import { GamePluginRegistry } from '../game/index.js';

export default async function gameRoutes(fastify) {
  fastify.get('/', async (_req, reply) => {
    return reply.send({ games: GamePluginRegistry.list() });
  });

  fastify.get('/:gameType', async (req, reply) => {
    try {
      const plugin = GamePluginRegistry.get(req.params.gameType);
      const { gameType, displayName, configSchema, defaultConfig, capabilities } = plugin;
      return reply.send({ game: { gameType, displayName, configSchema, defaultConfig, capabilities } });
    } catch {
      return reply.status(404).send({ error: 'GAME_NOT_FOUND' });
    }
  });
}
