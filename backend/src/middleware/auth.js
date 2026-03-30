// src/middleware/auth.js
import dotenv from 'dotenv';
import jwt from 'jsonwebtoken';

dotenv.config();

/**
 * Fastify preHandler: Authorization 헤더에서 Bearer 토큰 검증
 * 
 * 성공 시: request.user = { id, email, nickname } 주입
 * 실패 시: 401 응답
 */
export const authenticate = async (request, reply) => {
  const authHeader = request.headers.authorization;

  if (!authHeader?.startsWith('Bearer ')) {
    return reply.code(401).send({ error: 'MISSING_TOKEN' });
  }

  const token = authHeader.slice(7);

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    request.user = decoded;
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return reply.code(401).send({ error: 'TOKEN_EXPIRED' });
    }
    return reply.code(401).send({ error: 'INVALID_TOKEN' });
  }
};

/**
 * Access Token 발급 헬퍼
 */
export const signAccessToken = (user) => {
  return jwt.sign(
    { id: user.id, email: user.email, nickname: user.nickname },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '15m' }
  );
};

/**
 * WebSocket 연결 시 토큰 검증 (쿼리 파라미터 방식)
 * ws://host?token=xxx
 */
export const verifySocketToken = (token) => {
  if (!token) throw new Error('MISSING_TOKEN');
  return jwt.verify(token, process.env.JWT_SECRET);
};
