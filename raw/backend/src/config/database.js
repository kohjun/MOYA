// src/config/database.js
import pg from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const { Pool } = pg;

const pool = new Pool({
  // 환경 변수가 없으면 오른쪽의 기본값을 사용하고, 문자열로 변환 후 공백을 제거합니다.
  host:     (process.env.DB_HOST || 'localhost').trim(),
  port:     Number(process.env.DB_PORT || 5433),
  database: (process.env.DB_NAME || 'location_sharing').trim(),
  user:     (process.env.DB_USER || 'kohju').trim(),
  password: (process.env.DB_PASSWORD || 'postgres').trim(),
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// 연결 테스트
pool.on('error', (err) => {
  console.error('[DB] Unexpected error on idle client:', err);
  process.exit(-1);
});

/**
 * 쿼리 헬퍼: 자동으로 클라이언트 반환
 */
export const query = (text, params) => pool.query(text, params);

/**
 * 트랜잭션 헬퍼
 * @example
 * await withTransaction(async (client) => {
 *   await client.query('INSERT INTO ...')
 *   await client.query('UPDATE ...')
 * })
 */
export const withTransaction = async (callback) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
};

export default pool;
