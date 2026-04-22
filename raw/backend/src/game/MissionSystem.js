// src/game/MissionSystem.js
import { redisClient } from '../config/redis.js';

const MISSION_TTL = 60 * 60 * 24; // 24 hours

// `title` is the template category shared with the client mapping logic.
const MISSION_TEMPLATES = [
  {
    title: '코인 수집',
    displayTitle: '코인 수집',
    description: '맵에 생성된 코인 3개를 수집하세요.',
    type: 'COIN_COLLECT',
  },
  {
    title: '동물 포획',
    displayTitle: '동물 포획',
    description: '움직이는 동물을 1마리 포획하세요.',
    type: 'CAPTURE_ANIMAL',
  },
  {
    title: '미니게임',
    displayTitle: '전선 수리',
    description: '끊어진 전선을 순서대로 연결하세요.',
    type: 'MINIGAME',
    minigameId: 'wire_fix',
  },
  {
    title: '미니게임',
    displayTitle: '카드 긁기',
    description: '카드를 끝까지 밀어 인증을 완료하세요.',
    type: 'MINIGAME',
    minigameId: 'card_swipe',
  },
];

function missionKey(sessionId, userId) {
  return `missions:${sessionId}:${userId}`;
}

function progressKey(sessionId) {
  return `mission_progress:${sessionId}`;
}

/**
 * 승무원/임포스터에게 미션을 배정해 Redis에 저장합니다.
 * session.playable_area 가 있으면 코인/동물 미션에 사용할 좌표도 함께 배정합니다.
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
    const count      = perCrew;
    const assigned   = [];

    for (let i = 0; i < count; i++) {
      const template = missionPool[poolIndex % missionPool.length];
      const type     = template.type;
      const needsCoord = type !== 'MINIGAME';
      const coord = needsCoord && polygon ? randomPointInPolygon(polygon) : null;

      assigned.push({
        id: `${sessionId}_m${poolIndex}`,
        title: isImpostor
          ? `[가짜] ${template.displayTitle ?? template.title}`
          : (template.displayTitle ?? template.title),
        templateTitle: template.title,
        description: template.description,
        type,
        minigameId: template.minigameId ?? null,
        fake: isImpostor,
        done: false,
        lat: coord?.lat ?? null,
        lng: coord?.lng ?? null,
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
 * - 크루 미션: 전체 진행도 반영
 * - 임포스터 가짜 미션: 개인 완료 상태만 저장하고 전체 진행도는 유지
 * @param {string} sessionId
 * @param {string} userId
 * @param {string} missionId
 * @returns {{ missions: Array, progress: object, allDone: boolean, fakeCompletion?: boolean }}
 */
export async function completeMission(sessionId, userId, missionId) {
  const key      = missionKey(sessionId, userId);
  const data     = await redisClient.get(key);
  if (!data) throw new Error('미션 데이터를 찾을 수 없습니다.');

  const missions = JSON.parse(data);
  const mission  = missions.find((m) => m.id === missionId);
  if (!mission) throw new Error('해당 미션을 찾을 수 없습니다.');

  if (mission.done) {
    return {
      missions,
      progress: await getProgress(sessionId),
      allDone: false,
      fakeCompletion: mission.fake === true,
    };
  }

  mission.done = true;
  await redisClient.set(key, JSON.stringify(missions), { EX: MISSION_TTL });

  if (mission.fake) {
    return {
      missions,
      progress: await getProgress(sessionId),
      allDone: false,
      fakeCompletion: true,
    };
  }

  const progData  = await redisClient.get(progressKey(sessionId));
  const progress  = progData ? JSON.parse(progData) : { completed: 0, total: 0 };
  progress.completed += 1;
  await redisClient.set(progressKey(sessionId), JSON.stringify(progress), { EX: MISSION_TTL });

  const allDone = progress.total > 0 && progress.completed >= progress.total;
  return { missions, progress, allDone, fakeCompletion: false };
}

/**
 * 전체 미션 완료도 반환
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
 * 세션 미션 데이터를 전체 삭제
 * @param {string} sessionId
 */
export async function clearSession(sessionId) {
  const pattern = `missions:${sessionId}:*`;
  const keys    = await redisClient.keys(pattern);
  if (keys.length > 0) await redisClient.del(keys);
  await redisClient.del(progressKey(sessionId));
}

/**
 * Ray-casting 알고리즘으로 점이 폴리곤 내부에 있는지 판별
 * @param {{ lat: number, lng: number }} point
 * @param {Array<{ lat: number, lng: number }>} polygon
 * @returns {boolean}
 */
export function pointInPolygon(point, polygon) {
  const { lat: y, lng: x } = point;
  const n = polygon.length;
  let inside = false;

  for (let i = 0, j = n - 1; i < n; j = i++) {
    const xi = polygon[i].lng;
    const yi = polygon[i].lat;
    const xj = polygon[j].lng;
    const yj = polygon[j].lat;

    const intersect =
      yi > y !== yj > y &&
      x < ((xj - xi) * (y - yi)) / (yj - yi) + xi;

    if (intersect) inside = !inside;
  }

  return inside;
}

/**
 * 폴리곤 내부의 랜덤 좌표 생성 (bounding box + rejection sampling)
 * @param {Array<{ lat: number, lng: number }>} polygon
 * @param {number} [maxRetries=60]
 * @returns {{ lat: number, lng: number }}
 */
export function randomPointInPolygon(polygon, maxRetries = 60) {
  const lats = polygon.map((p) => p.lat);
  const lngs = polygon.map((p) => p.lng);
  const minLat = Math.min(...lats);
  const maxLat = Math.max(...lats);
  const minLng = Math.min(...lngs);
  const maxLng = Math.max(...lngs);

  for (let i = 0; i < maxRetries; i++) {
    const candidate = {
      lat: minLat + Math.random() * (maxLat - minLat),
      lng: minLng + Math.random() * (maxLng - minLng),
    };
    if (pointInPolygon(candidate, polygon)) return candidate;
  }

  return {
    lat: lats.reduce((a, b) => a + b, 0) / lats.length,
    lng: lngs.reduce((a, b) => a + b, 0) / lngs.length,
  };
}

async function getProgress(sessionId) {
  const data = await redisClient.get(progressKey(sessionId));
  return data ? JSON.parse(data) : { completed: 0, total: 0 };
}

function generateMissionPool(count) {
  const pool = [];
  while (pool.length < count) {
    pool.push(...MISSION_TEMPLATES.map((template) => ({ ...template })));
  }
  return shuffleMissionPool(pool).slice(0, count);
}

function shuffleMissionPool(pool) {
  const cloned = [...pool];
  for (let i = cloned.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [cloned[i], cloned[j]] = [cloned[j], cloned[i]];
  }
  return cloned;
}
