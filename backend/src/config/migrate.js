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
  `ALTER TABLE users ADD COLUMN IF NOT EXISTS current_session_id UUID REFERENCES sessions(id) ON DELETE SET NULL`,

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

  // ─── sessions 모듈 컬럼 추가 ─────────────────────────────────────
  `ALTER TABLE sessions ADD COLUMN IF NOT EXISTS active_modules TEXT[] DEFAULT '{}'`,
  `ALTER TABLE sessions ADD COLUMN IF NOT EXISTS module_configs JSONB DEFAULT '{}'::jsonb`,

  // ─── 플레이어 역할 테이블 ─────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS player_roles (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id  UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role        VARCHAR(50) NOT NULL,
    team        VARCHAR(50),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(session_id, user_id)
  )`,

  // ─── 게임 라운드 테이블 ───────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS game_rounds (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id   UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    round_number INTEGER NOT NULL,
    phase        VARCHAR(30) NOT NULL DEFAULT 'waiting',
    started_at   TIMESTAMPTZ,
    ended_at     TIMESTAMPTZ,
    config       JSONB NOT NULL DEFAULT '{}'::jsonb
  )`,

  // ─── 미션 테이블 ──────────────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS missions (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id   UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    title        VARCHAR(100) NOT NULL,
    description  TEXT,
    location     GEOGRAPHY(POINT, 4326),
    radius_m     FLOAT,
    qr_code      VARCHAR(200),
    reward_item  VARCHAR(100),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )`,

  // ─── 플레이어 미션 완료 테이블 ───────────────────────────────────
  `CREATE TABLE IF NOT EXISTS player_missions (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    mission_id   UUID NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(mission_id, user_id)
  )`,

  // ─── Amongus 킬 로그 ─────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS kill_logs (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id   UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  killer_id    UUID NOT NULL REFERENCES users(id),
  victim_id    UUID NOT NULL REFERENCES users(id),
  zone         VARCHAR(100),
  method       VARCHAR(20) DEFAULT 'proximity',
  killed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
)`,
  `CREATE INDEX IF NOT EXISTS idx_kill_logs_session ON kill_logs(session_id)`,

  // ─── 투표 세션 ───────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS vote_sessions (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id    UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  caller_id     UUID NOT NULL REFERENCES users(id),
  body_id       UUID REFERENCES users(id),
  reason        VARCHAR(20) NOT NULL,
  phase         VARCHAR(20) NOT NULL DEFAULT 'discussion',
  ejected_id    UUID REFERENCES users(id),
  was_impostor  BOOLEAN,
  started_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at      TIMESTAMPTZ
)`,

  // ─── 투표 내역 ───────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS votes (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  vote_session_id UUID NOT NULL REFERENCES vote_sessions(id) ON DELETE CASCADE,
  voter_id        UUID NOT NULL REFERENCES users(id),
  target_id       VARCHAR(50) NOT NULL,
  is_pre_vote     BOOLEAN NOT NULL DEFAULT FALSE,
  voted_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(vote_session_id, voter_id)
)`,

  // ─── sessions 게임 설정 컬럼 추가 ────────────────────────
  `ALTER TABLE sessions ADD COLUMN IF NOT EXISTS game_type VARCHAR(50) DEFAULT 'among_us'`,
  `ALTER TABLE sessions ADD COLUMN IF NOT EXISTS max_members INTEGER DEFAULT 50`,
  `ALTER TABLE sessions ADD COLUMN IF NOT EXISTS kill_cooldown INTEGER DEFAULT 30`,
  `ALTER TABLE sessions ADD COLUMN IF NOT EXISTS discussion_time INTEGER DEFAULT 90`,
  `ALTER TABLE sessions ADD COLUMN IF NOT EXISTS vote_time INTEGER DEFAULT 30`,
  `ALTER TABLE sessions ADD COLUMN IF NOT EXISTS mission_per_crew INTEGER DEFAULT 3`,
  `ALTER TABLE sessions ADD COLUMN IF NOT EXISTS impostor_count INTEGER DEFAULT 1`,

  // ─── session_members 게임 상태 컬럼 추가 ─────────────────
  `ALTER TABLE session_members ADD COLUMN IF NOT EXISTS is_alive BOOLEAN NOT NULL DEFAULT TRUE`,
  `ALTER TABLE session_members ADD COLUMN IF NOT EXISTS game_role VARCHAR(20)`,
  `ALTER TABLE session_members ADD COLUMN IF NOT EXISTS game_team VARCHAR(20)`,
  `ALTER TABLE session_members ADD COLUMN IF NOT EXISTS currency INTEGER NOT NULL DEFAULT 0`,
  `ALTER TABLE session_members ADD COLUMN IF NOT EXISTS zone VARCHAR(100)`,
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
