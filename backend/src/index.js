// src/index.js
import Fastify from 'fastify';
import fastifyCors from '@fastify/cors';
import fastifyCookie from '@fastify/cookie';
import { createServer } from 'http';
import dotenv from 'dotenv';

import { connectRedis } from './config/redis.js';
import { query as dbQuery } from './config/database.js';
import { createSocketServer } from './websocket/index.js';
import authRoutes from './routes/auth.js';
import sessionRoutes from './routes/sessions.js';

dotenv.config();

// ─────────────────────────────────────────────────────────────────────────────
// Fastify 앱 초기화
// ─────────────────────────────────────────────────────────────────────────────
const fastify = Fastify({
  logger: {
    level: process.env.NODE_ENV === 'production' ? 'warn' : 'info',
  },
});

// ─── 플러그인 등록 ─────────────────────────────────────────────────────────
await fastify.register(fastifyCors, {
  origin: process.env.ALLOWED_ORIGINS?.split(',') || true,
  credentials: true,
});

await fastify.register(fastifyCookie);

// ─── 라우트 등록 ───────────────────────────────────────────────────────────
fastify.register(authRoutes,    { prefix: '/auth' });
fastify.register(sessionRoutes, { prefix: '/sessions' });

// ─── 헬스체크 ─────────────────────────────────────────────────────────────
fastify.get('/health', async () => {
  try {
    await dbQuery('SELECT 1');
    return { status: 'ok', db: 'connected', timestamp: new Date().toISOString() };
  } catch {
    return { status: 'error', db: 'disconnected' };
  }
});

// ─── 에러 핸들러 ───────────────────────────────────────────────────────────
fastify.setErrorHandler((error, request, reply) => {
  fastify.log.error(error);
  reply.code(500).send({
    error: 'INTERNAL_SERVER_ERROR',
    message: process.env.NODE_ENV === 'development' ? error.message : undefined,
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 서버 시작
// ─────────────────────────────────────────────────────────────────────────────
const start = async () => {
  try {
    // Redis 연결
    await connectRedis();

    // DB 연결 테스트
    await dbQuery('SELECT NOW()');
    console.log('[DB] PostgreSQL connected');

    // HTTP 서버 생성 (Socket.IO와 공유)
    const httpServer = createServer(fastify.server);

    // Socket.IO 서버 붙이기
    const io = createSocketServer(httpServer);

    // Fastify 초기화 (라우트 등록 완료)
    await fastify.ready();

    const PORT = Number(process.env.PORT) || 3000;
    const HOST = '0.0.0.0';

    httpServer.listen(PORT, HOST, () => {
      console.log(`
╔══════════════════════════════════════════╗
║   🗺️  Location Sharing Server Started     ║
║   REST API : http://${HOST}:${PORT}       ║
║   WebSocket: ws://${HOST}:${PORT}         ║
║   Env      : ${process.env.NODE_ENV}                ║
╚══════════════════════════════════════════╝
      `);
    });

    // Graceful shutdown
    const shutdown = async (signal) => {
      console.log(`\n[${signal}] Shutting down...`);
      io.close();
      httpServer.close(async () => {
        await fastify.close();
        process.exit(0);
      });
    };

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT',  () => shutdown('SIGINT'));

  } catch (err) {
    console.error('Failed to start server:', err);
    process.exit(1);
  }
};

start();
