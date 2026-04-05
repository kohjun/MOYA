// src/config/migrate.js
// 실행: node src/config/migrate.js
import { query } from './database.js';
import dotenv from 'dotenv';

dotenv.config();

const migrations = [
  // ─── PostGIS 확장 활성화 ─────────────────────────────────────────
  `CREATE EXTENSION IF NOT EXISTS "uuid-ossp"`,
  `CREATE EXTENSION IF NOT EXISTS postgis`,

  // ─── 사용자 테이블 ────────────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS users (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email         VARCHAR(255) UNIQUE NOT NULL,
    nickname      VARCHAR(50)  NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    avatar_url    VARCHAR(500),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
  )`,

  // ─── users 테이블에 fcm_token 및 current_session_id 컬럼 추가 ──────────────
  `ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token VARCHAR(500)`,
  `ALTER TABLE users ADD COLUMN IF NOT EXISTS current_session_id UUID REFERENCES sessions(id) ON DELETE SET NULL`,

  // ─── Refresh Token 저장소 ─────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS refresh_tokens (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked    BOOLEAN NOT NULL DEFAULT FALSE
  )`,
  `CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user
    ON refresh_tokens(user_id)`,

  // ─── 세션 테이블 ─────────────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS sessions (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    host_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_code VARCHAR(8) UNIQUE NOT NULL,
    name         VARCHAR(100),
    status       VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at   TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '24 hours',
    ended_at     TIMESTAMPTZ
  )`,
  `CREATE INDEX IF NOT EXISTS idx_sessions_code ON sessions(session_code)`,
  `CREATE INDEX IF NOT EXISTS idx_sessions_host  ON sessions(host_user_id)`,

  // ─── 세션 참가자 테이블 ───────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS session_members (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id        UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    left_at           TIMESTAMPTZ,
    sharing_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE(session_id, user_id)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_members_session ON session_members(session_id)`,
  `CREATE INDEX IF NOT EXISTS idx_members_user    ON session_members(user_id)`,

  // ─── 위치 트랙 테이블 (PostGIS) ──────────────────────────────────
  `CREATE TABLE IF NOT EXISTS location_tracks (
    id          BIGSERIAL PRIMARY KEY,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id  UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    point       GEOGRAPHY(POINT, 4326) NOT NULL,
    accuracy    FLOAT,
    altitude    FLOAT,
    speed       FLOAT,
    heading     FLOAT,
    source      VARCHAR(10) NOT NULL DEFAULT 'gps',
    battery     SMALLINT,
    status      VARCHAR(20) NOT NULL DEFAULT 'moving',
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )`,

  `CREATE INDEX IF NOT EXISTS idx_tracks_geom
    ON location_tracks USING GIST(point)`,
  `CREATE INDEX IF NOT EXISTS idx_tracks_user_time
    ON location_tracks(user_id, recorded_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_tracks_session_time
    ON location_tracks(session_id, recorded_at DESC)`,

  // ─── 지오펜스 테이블 ─────────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS geofences (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id   UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    created_by   UUID NOT NULL REFERENCES users(id),
    name         VARCHAR(100) NOT NULL,
    center       GEOGRAPHY(POINT, 4326) NOT NULL,
    radius_m     FLOAT NOT NULL DEFAULT 100,
    notify_enter BOOLEAN NOT NULL DEFAULT TRUE,
    notify_exit  BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )`,
  `CREATE INDEX IF NOT EXISTS idx_geofences_session ON geofences(session_id)`,

  // ─── session_members 역할 컬럼 추가 ─────────────────────────────
  `ALTER TABLE session_members ADD COLUMN IF NOT EXISTS role VARCHAR(20) NOT NULL DEFAULT 'member'`,
];

(async () => {
  console.log('Running migrations...');
  for (const sql of migrations) {
    try {
      await query(sql);
      const preview = sql.trim().split('\n')[0].substring(0, 60);
      console.log(`[Success] ${preview}`);
    } catch (err) {
      console.error(`[Error] Migration failed: ${err.message}`);
      console.error('SQL:', sql);
      process.exit(1);
    }
  }
  console.log('All migrations completed');
  process.exit(0);
})();