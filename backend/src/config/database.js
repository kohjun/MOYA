// src/config/database.js
import pg from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const { Pool } = pg;

const pool = new Pool({
  host:     process.env.DB_HOST,
  port:     Number(process.env.DB_PORT),
  database: process.env.DB_NAME,
  user:     process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 20,                    // 최대 연결 수
  idleTimeoutMillis: 30000,   // 유휴 연결 타임아웃
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
