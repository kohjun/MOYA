// src/services/authService.js
import bcrypt from 'bcrypt';
import crypto from 'crypto';
import { query, withTransaction } from '../config/database.js';
import { setCache, getCache, delCache } from '../config/redis.js';
import dotenv from 'dotenv';

dotenv.config();

const SALT_ROUNDS = 12;
const REFRESH_TTL_DAYS = 7;

// ─────────────────────────────────────────────────────────────────────────────
// 사용자 등록
// ─────────────────────────────────────────────────────────────────────────────
export const register = async ({ email, password, nickname }) => {
  // 이메일 중복 확인
  const existing = await query(
    'SELECT id FROM users WHERE email = $1',
    [email]
  );
  if (existing.rows.length > 0) {
    throw new Error('EMAIL_ALREADY_EXISTS');
  }

  const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

  const { rows } = await query(
    `INSERT INTO users (email, nickname, password_hash)
     VALUES ($1, $2, $3)
     RETURNING id, email, nickname, created_at`,
    [email, nickname, passwordHash]
  );

  return rows[0];
};

// ─────────────────────────────────────────────────────────────────────────────
// 로그인
// ─────────────────────────────────────────────────────────────────────────────
export const login = async ({ email, password }) => {
  const { rows } = await query(
    'SELECT id, email, nickname, password_hash, avatar_url FROM users WHERE email = $1',
    [email]
  );

  if (rows.length === 0) {
    throw new Error('INVALID_CREDENTIALS');
  }

  const user = rows[0];
  const isValid = await bcrypt.compare(password, user.password_hash);
  if (!isValid) {
    throw new Error('INVALID_CREDENTIALS');
  }

  // password_hash 제거 후 반환
  delete user.password_hash;
  return user;
};

// ─────────────────────────────────────────────────────────────────────────────
// Refresh Token 발급 및 저장
// refresh token은 단방향 해시로 DB에 저장 (노출 시 피해 최소화)
// ─────────────────────────────────────────────────────────────────────────────
export const createRefreshToken = async (userId) => {
  // 랜덤 토큰 생성 (64바이트 → 128자 hex)
  const rawToken = crypto.randomBytes(64).toString('hex');
  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');

  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + REFRESH_TTL_DAYS);

  await query(
    `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
     VALUES ($1, $2, $3)`,
    [userId, tokenHash, expiresAt]
  );

  return rawToken; // 클라이언트에게 raw 토큰 전달 (DB에는 해시만 저장)
};

// ─────────────────────────────────────────────────────────────────────────────
// Refresh Token 검증 및 회전 (Token Rotation)
// 한 번 사용한 토큰은 즉시 폐기 → 새 토큰 발급
// ─────────────────────────────────────────────────────────────────────────────
export const rotateRefreshToken = async (rawToken) => {
  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');

  const { rows } = await query(
    `SELECT rt.id, rt.user_id, rt.expires_at, rt.revoked,
            u.email, u.nickname, u.avatar_url
     FROM refresh_tokens rt
     JOIN users u ON u.id = rt.user_id
     WHERE rt.token_hash = $1`,
    [tokenHash]
  );

  if (rows.length === 0) throw new Error('INVALID_REFRESH_TOKEN');

  const token = rows[0];

  // 이미 사용된 토큰이면 → 계정 탈취 가능성 → 모든 토큰 폐기
  if (token.revoked) {
    await query(
      'UPDATE refresh_tokens SET revoked = TRUE WHERE user_id = $1',
      [token.user_id]
    );
    throw new Error('REFRESH_TOKEN_REUSE_DETECTED');
  }

  if (new Date(token.expires_at) < new Date()) {
    throw new Error('REFRESH_TOKEN_EXPIRED');
  }

  // 트랜잭션: 기존 토큰 폐기 + 새 토큰 발급
  const newRawToken = await withTransaction(async (client) => {
    // 기존 토큰 폐기
    await client.query(
      'UPDATE refresh_tokens SET revoked = TRUE WHERE id = $1',
      [token.id]
    );
    // 새 토큰 생성
    const newRaw = crypto.randomBytes(64).toString('hex');
    const newHash = crypto.createHash('sha256').update(newRaw).digest('hex');
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + REFRESH_TTL_DAYS);

    await client.query(
      `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
       VALUES ($1, $2, $3)`,
      [token.user_id, newHash, expiresAt]
    );
    return newRaw;
  });

  return {
    user: {
      id: token.user_id,
      email: token.email,
      nickname: token.nickname,
      avatar_url: token.avatar_url,
    },
    newRefreshToken: newRawToken,
  };
};

// ─────────────────────────────────────────────────────────────────────────────
// 로그아웃 (refresh token 폐기)
// ─────────────────────────────────────────────────────────────────────────────
export const logout = async (rawToken) => {
  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
  await query(
    'UPDATE refresh_tokens SET revoked = TRUE WHERE token_hash = $1',
    [tokenHash]
  );
};

// ─────────────────────────────────────────────────────────────────────────────
// 사용자 정보 조회 (캐시 우선)
// ─────────────────────────────────────────────────────────────────────────────
export const getUserById = async (userId) => {
  const cacheKey = `user:${userId}`;
  const cached = await getCache(cacheKey);
  if (cached) return cached;

  const { rows } = await query(
    'SELECT id, email, nickname, avatar_url, created_at FROM users WHERE id = $1',
    [userId]
  );
  if (rows.length === 0) return null;

  await setCache(cacheKey, rows[0], 300); // 5분 캐시
  return rows[0];
};
