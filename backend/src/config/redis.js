// src/config/redis.js
import { createClient } from 'redis';
import dotenv from 'dotenv';

dotenv.config();

// 일반 명령용 클라이언트
const redisClient = createClient({
  socket: {
    host: process.env.REDIS_HOST || 'localhost',
    port: Number(process.env.REDIS_PORT) || 6379,
  },
  password: process.env.REDIS_PASSWORD || undefined,
});

redisClient.on('error', (err) => console.error('[Redis] Client error:', err));

export const connectRedis = async () => {
  await redisClient.connect();
  console.log('[Redis] Connected');
};

/**
 * 키-값 저장 (TTL 초 단위)
 */
export const setCache = (key, value, ttlSeconds) =>
  redisClient.set(key, JSON.stringify(value), { EX: ttlSeconds });

/**
 * 키-값 조회
 */
export const getCache = async (key) => {
  const data = await redisClient.get(key);
  return data ? JSON.parse(data) : null;
};

/**
 * 키 삭제
 */
export const delCache = (key) => redisClient.del(key);

/**
 * 특정 패턴의 키 모두 삭제
 * @example await delPattern('session:abc123:*')
 */
export const delPattern = async (pattern) => {
  const keys = await redisClient.keys(pattern);
  if (keys.length > 0) await redisClient.del(keys);
};

export { redisClient };
