// src/services/locationService.js
import { query } from '../config/database.js';
import { setCache, getCache } from '../config/redis.js';

// ─────────────────────────────────────────────────────────────────────────────
// 위치 데이터 저장 (DB + Redis 캐시 동시)
// ─────────────────────────────────────────────────────────────────────────────
export const saveLocation = async (userId, sessionId, locationData) => {
  const {
    lat, lng,
    accuracy = null,
    altitude = null,
    speed = null,
    heading = null,
    source = 'gps',
    battery = null,
    status = 'moving',
  } = locationData;

  // PostGIS POINT 포맷: ST_MakePoint(경도, 위도) — 경도가 먼저!
  await query(
    `INSERT INTO location_tracks
       (user_id, session_id, point, accuracy, altitude, speed, heading, source, battery, status)
     VALUES
       ($1, $2, ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography,
        $5, $6, $7, $8, $9, $10, $11)`,
    [userId, sessionId, lng, lat, accuracy, altitude, speed, heading, source, battery, status]
  );

  // Redis에 최신 위치 캐시 (30분 TTL)
  const cachePayload = { lat, lng, accuracy, speed, heading, source, battery, status, ts: Date.now() };
  await setCache(`location:${sessionId}:${userId}`, cachePayload, 1800);

  return cachePayload;
};

// ─────────────────────────────────────────────────────────────────────────────
// 세션 내 특정 사용자의 이동 경로 조회
// ─────────────────────────────────────────────────────────────────────────────
export const getTrackHistory = async (userId, sessionId, options = {}) => {
  const {
    limit = 500,
    from = null,   // ISO 시간
    to = null,
  } = options;

  let paramIdx = 3;
  const params = [userId, sessionId];
  let timeFilter = '';

  if (from) {
    params.push(from);
    timeFilter += ` AND recorded_at >= $${paramIdx++}`;
  }
  if (to) {
    params.push(to);
    timeFilter += ` AND recorded_at <= $${paramIdx++}`;
  }
  params.push(limit);

  const { rows } = await query(
    `SELECT
       ST_Y(point::geometry) AS lat,
       ST_X(point::geometry) AS lng,
       accuracy, speed, heading, source, battery, status,
       recorded_at
     FROM location_tracks
     WHERE user_id = $1 AND session_id = $2 ${timeFilter}
     ORDER BY recorded_at ASC
     LIMIT $${paramIdx}`,
    params
  );

  return rows;
};

// ─────────────────────────────────────────────────────────────────────────────
// 두 사용자 사이의 실시간 거리 계산 (Redis 캐시 기반)
// ─────────────────────────────────────────────────────────────────────────────
export const getDistanceBetweenUsers = async (sessionId, userId1, userId2) => {
  const loc1 = await getCache(`location:${sessionId}:${userId1}`);
  const loc2 = await getCache(`location:${sessionId}:${userId2}`);

  if (!loc1 || !loc2) return null;

  // Haversine 공식 (서버 사이드 계산)
  const distance = haversineMeters(loc1.lat, loc1.lng, loc2.lat, loc2.lng);
  return Math.round(distance);
};

// ─────────────────────────────────────────────────────────────────────────────
// 세션 내 모든 멤버의 최신 위치 일괄 조회 (스냅샷)
// WebSocket 첫 연결 시 초기 상태 동기화용
// ─────────────────────────────────────────────────────────────────────────────
export const getSessionSnapshot = async (sessionId, memberUserIds) => {
  const snapshot = {};
  await Promise.all(
    memberUserIds.map(async (userId) => {
      const loc = await getCache(`location:${sessionId}:${userId}`);
      if (loc) snapshot[userId] = loc;
    })
  );
  return snapshot;
};

// ─────────────────────────────────────────────────────────────────────────────
// Haversine 거리 계산 (미터 단위)
// ─────────────────────────────────────────────────────────────────────────────
export const haversineMeters = (lat1, lng1, lat2, lng2) => {
  const R = 6371000;
  const toRad = (v) => (v * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
};

// ─────────────────────────────────────────────────────────────────────────────
// 위치 공유 ON/OFF 토글
// ─────────────────────────────────────────────────────────────────────────────
export const toggleSharing = async (userId, sessionId, enabled) => {
  await query(
    `UPDATE session_members
     SET sharing_enabled = $1
     WHERE user_id = $2 AND session_id = $3`,
    [enabled, userId, sessionId]
  );
};
