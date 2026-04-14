// src/game/MissionSystem.js
import { redisClient } from '../config/redis.js';

const MISSION_TTL = 60 * 60 * 24; // 24시간

function missionKey(sessionId, userId) {
  return `missions:${sessionId}:${userId}`;
}

function progressKey(sessionId) {
  return `mission_progress:${sessionId}`;
}

/**
 * 크루원/임포스터에게 미션 배정 후 Redis에 저장
 * session.playable_area 가 있으면 폴리곤 내부 랜덤 좌표를 각 미션에 할당합니다.
 * @param {object} session  { id, mission_per_crew, playable_area? }
 * @param {Array}  members  [{ user_id, game_role }]
 */
export async function assignMissions(session, members) {
  const sessionId      = session.id;
  const perCrew        = session.mission_per_crew ?? 3;
  const polygon        = session.playable_area ?? null; // [{lat, lng}, ...]
  const missionPool    = generateMissionPool(perCrew * members.length);

  let poolIndex  = 0;
  let crewTotal  = 0;

  for (const member of members) {
    const isImpostor = member.game_role === 'impostor';
    const count      = isImpostor ? perCrew : perCrew;
    const assigned   = [];

    for (let i = 0; i < count; i++) {
      const template = missionPool[poolIndex % missionPool.length];
      const coord    = polygon ? randomPointInPolygon(polygon) : null;

      assigned.push({
        id:          `${sessionId}_m${poolIndex}`,
        title:       isImpostor ? `[가짜] ${template.title}` : template.title,
        description: template.description,
        fake:        isImpostor,
        done:        false,
        lat:         coord?.lat ?? null,
        lng:         coord?.lng ?? null,
      });
      poolIndex++;
    }

    await redisClient.set(
      missionKey(sessionId, member.user_id),
      JSON.stringify(assigned),
      { EX: MISSION_TTL }
    );

    if (!isImpostor) crewTotal += count;
  }

  await redisClient.set(
    progressKey(sessionId),
    JSON.stringify({ completed: 0, total: crewTotal }),
    { EX: MISSION_TTL }
  );
}

/**
 * 특정 플레이어의 미션 목록 조회
 * @param {string} sessionId
 * @param {string} userId
 * @returns {Array|null}
 */
export async function getMissions(sessionId, userId) {
  const data = await redisClient.get(missionKey(sessionId, userId));
  return data ? JSON.parse(data) : null;
}

/**
 * 미션 완료 처리
 * @param {string} sessionId
 * @param {string} userId
 * @param {string} missionId
 * @returns {{ missions: Array, progress: object, allDone: boolean }}
 */
export async function completeMission(sessionId, userId, missionId) {
  const key      = missionKey(sessionId, userId);
  const data     = await redisClient.get(key);
  if (!data) throw new Error('미션 데이터를 찾을 수 없습니다.');

  const missions = JSON.parse(data);
  const mission  = missions.find(m => m.id === missionId);
  if (!mission)       throw new Error('해당 미션을 찾을 수 없습니다.');
  if (mission.fake)   throw new Error('가짜 미션은 완료할 수 없습니다.');
  if (mission.done)   return { missions, progress: await getProgress(sessionId), allDone: false };

  mission.done = true;
  await redisClient.set(key, JSON.stringify(missions), { EX: MISSION_TTL });

  // 전체 진행도 갱신
  const progData  = await redisClient.get(progressKey(sessionId));
  const progress  = progData ? JSON.parse(progData) : { completed: 0, total: 0 };
  progress.completed += 1;
  await redisClient.set(progressKey(sessionId), JSON.stringify(progress), { EX: MISSION_TTL });

  const allDone = progress.total > 0 && progress.completed >= progress.total;
  return { missions, progress, allDone };
}

/**
 * 전체 미션 완료율 반환
 * @param {string} sessionId
 * @returns {{ completed: number, total: number, percent: number }}
 */
export async function getProgressBar(sessionId) {
  const data     = await redisClient.get(progressKey(sessionId));
  const progress = data ? JSON.parse(data) : { completed: 0, total: 0 };
  const percent  = progress.total > 0
    ? Math.floor((progress.completed / progress.total) * 100)
    : 0;
  return { ...progress, percent };
}

/**
 * 세션 미션 데이터 전체 삭제
 * @param {string} sessionId
 */
export async function clearSession(sessionId) {
  const pattern = `missions:${sessionId}:*`;
  const keys    = await redisClient.keys(pattern);
  if (keys.length > 0) await redisClient.del(keys);
  await redisClient.del(progressKey(sessionId));
}

// ─── 내부 헬퍼 ──────────────────────────────────────────────────────────────

/**
 * Ray-Casting 알고리즘으로 점이 폴리곤 내부에 있는지 판별
 * @param {{ lat: number, lng: number }} point
 * @param {Array<{ lat: number, lng: number }>} polygon  최소 3개 꼭짓점
 * @returns {boolean}
 */
export function pointInPolygon(point, polygon) {
  const { lat: y, lng: x } = point;
  const n = polygon.length;
  let inside = false;

  for (let i = 0, j = n - 1; i < n; j = i++) {
    const xi = polygon[i].lng, yi = polygon[i].lat;
    const xj = polygon[j].lng, yj = polygon[j].lat;

    const intersect =
      yi > y !== yj > y &&
      x < ((xj - xi) * (y - yi)) / (yj - yi) + xi;

    if (intersect) inside = !inside;
  }

  return inside;
}

/**
 * 폴리곤 내부의 랜덤 좌표 생성 (바운딩 박스 + 거절 샘플링)
 * @param {Array<{ lat: number, lng: number }>} polygon
 * @param {number} [maxRetries=60]
 * @returns {{ lat: number, lng: number }}
 */
export function randomPointInPolygon(polygon, maxRetries = 60) {
  // 바운딩 박스 계산
  const lats = polygon.map((p) => p.lat);
  const lngs = polygon.map((p) => p.lng);
  const minLat = Math.min(...lats), maxLat = Math.max(...lats);
  const minLng = Math.min(...lngs), maxLng = Math.max(...lngs);

  for (let i = 0; i < maxRetries; i++) {
    const candidate = {
      lat: minLat + Math.random() * (maxLat - minLat),
      lng: minLng + Math.random() * (maxLng - minLng),
    };
    if (pointInPolygon(candidate, polygon)) return candidate;
  }

  // 거절 샘플링 실패 시 폴리곤 무게 중심으로 폴백
  const centroid = {
    lat: lats.reduce((a, b) => a + b, 0) / lats.length,
    lng: lngs.reduce((a, b) => a + b, 0) / lngs.length,
  };
  return centroid;
}

async function getProgress(sessionId) {
  const data = await redisClient.get(progressKey(sessionId));
  return data ? JSON.parse(data) : { completed: 0, total: 0 };
}

function generateMissionPool(count) {
  const templates = [
    { title: '전선 수리',       description: '제어실의 끊어진 전선을 올바르게 연결하세요.' },
    { title: '데이터 업로드',   description: '수집된 데이터를 메인 서버에 업로드하세요.' },
    { title: '산소 필터 청소',  description: '산소 공급 장치의 필터를 교체하세요.' },
    { title: '연료 주입',       description: '엔진 연료 탱크를 가득 채우세요.' },
    { title: '보안 카메라 점검',description: '각 구역의 보안 카메라 작동 여부를 확인하세요.' },
    { title: '의료 스캔',       description: '의무실 스캐너에 올라가 신체 검사를 받으세요.' },
    { title: '전원 라우팅',     description: '전기실에서 전력 공급 경로를 재설정하세요.' },
    { title: '소행성 격추',     description: '외부 포대를 조작해 소행성을 제거하세요.' },
    { title: '쓰레기 배출',     description: '쓰레기 저장소를 비우세요.' },
    { title: '엔진 정렬',       description: '좌·우 엔진의 정렬 상태를 점검하세요.' },
  ];

  const pool = [];
  for (let i = 0; i < count; i++) {
    pool.push(templates[i % templates.length]);
  }
  return pool;
}
