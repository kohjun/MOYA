'use strict';

// 세션별 사용자 직업 선호 저장소.
// 로비에서 받은 선택만 보관하며, startSession 시점에 소비/삭제된다.
// in-memory: 서버 재시작이나 다중 인스턴스로 확장되면 Redis 로 옮긴다.

const sessionJobSelections = new Map();

const VALID_JOBS = new Set(['warrior', 'priest', 'mage', 'ranger', 'rogue']);

export function isValidJob(job) {
  return typeof job === 'string' && VALID_JOBS.has(job);
}

export function setJobPreference(sessionId, userId, job) {
  if (!sessionId || !userId || !isValidJob(job)) {
    return false;
  }

  let bucket = sessionJobSelections.get(sessionId);
  if (!bucket) {
    bucket = new Map();
    sessionJobSelections.set(sessionId, bucket);
  }

  bucket.set(userId, job);
  return true;
}

export function clearJobPreference(sessionId, userId) {
  const bucket = sessionJobSelections.get(sessionId);
  if (!bucket) return;
  bucket.delete(userId);
  if (bucket.size === 0) {
    sessionJobSelections.delete(sessionId);
  }
}

export function getJobPreferences(sessionId) {
  const bucket = sessionJobSelections.get(sessionId);
  if (!bucket) {
    return new Map();
  }
  return new Map(bucket);
}

export function consumeJobPreferences(sessionId) {
  const bucket = sessionJobSelections.get(sessionId);
  sessionJobSelections.delete(sessionId);
  return bucket ?? new Map();
}
