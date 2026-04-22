// src/services/geofenceService.js
import { query } from '../config/database.js';
import { redisClient } from '../config/redis.js';

// ── CRUD ─────────────────────────────────────────────────────────────────────

export async function createGeofence(sessionId, createdBy, {
  name, centerLat, centerLng, radiusM,
  notifyEnter = true, notifyExit = true,
}) {
  const result = await query(
    `INSERT INTO geofences
       (session_id, created_by, name, center, radius_m, notify_enter, notify_exit)
     VALUES ($1, $2, $3, ST_MakePoint($4, $5)::geography, $6, $7, $8)
     RETURNING id, name, radius_m, notify_enter, notify_exit,
       ST_Y(center::geometry) AS lat,
       ST_X(center::geometry) AS lng,
       created_at`,
    [sessionId, createdBy, name, centerLng, centerLat, radiusM, notifyEnter, notifyExit]
  );
  return result.rows[0];
}

export async function getGeofences(sessionId) {
  const result = await query(
    `SELECT id, session_id, created_by, name, radius_m,
       notify_enter, notify_exit,
       ST_Y(center::geometry) AS lat,
       ST_X(center::geometry) AS lng,
       created_at
     FROM geofences
     WHERE session_id = $1
     ORDER BY created_at ASC`,
    [sessionId]
  );
  return result.rows;
}

export async function deleteGeofence(geofenceId, userId) {
  const result = await query(
    `DELETE FROM geofences WHERE id = $1 AND created_by = $2`,
    [geofenceId, userId]
  );
  if (result.rowCount === 0) throw new Error('NOT_FOUND_OR_NOT_CREATOR');
}

// ── 진입/이탈 감지 ─────────────────────────────────────────────────────────────
// 이전 위치의 지오펜스 상태를 Redis에 저장하여 경계 교차 감지

function _haversine(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * 사용자의 새 위치가 지오펜스를 진입/이탈했는지 확인
 * @returns {{ entered: Geofence[], exited: Geofence[] }}
 */
export async function checkGeofences(userId, sessionId, lat, lng) {
  const fences = await getGeofences(sessionId);
  if (fences.length === 0) return { entered: [], exited: [] };

  // Redis에서 이전 상태 조회 (어떤 펜스 안에 있었는지)
  const stateKey = `geofence:state:${sessionId}:${userId}`;
  const prevRaw  = await redisClient.get(stateKey);
  const prevInside = new Set(prevRaw ? JSON.parse(prevRaw) : []);

  // 현재 위치 기준 각 펜스 안인지 계산
  const nowInside = new Set();
  for (const fence of fences) {
    const dist = _haversine(lat, lng, Number(fence.lat), Number(fence.lng));
    if (dist <= Number(fence.radius_m)) {
      nowInside.add(fence.id);
    }
  }

  const entered = fences.filter(
    (f) => nowInside.has(f.id) && !prevInside.has(f.id) && f.notify_enter
  );
  const exited = fences.filter(
    (f) => !nowInside.has(f.id) && prevInside.has(f.id) && f.notify_exit
  );

  // 상태 업데이트 (1시간 TTL)
  await redisClient.set(stateKey, JSON.stringify([...nowInside]), { EX: 3600 });

  return { entered, exited };
}
