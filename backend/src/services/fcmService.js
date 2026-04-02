// src/services/fcmService.js
//
// ════════════════════════════════════════════════════════════════
// Firebase Admin SDK를 사용한 FCM 발송 서비스
//
// [초기 설정 가이드]
// 1. Firebase 콘솔 → 프로젝트 설정 → 서비스 계정
// 2. "새 비공개 키 생성" 클릭 → JSON 파일 다운로드
// 3. 파일명을 serviceAccountKey.json으로 변경
// 4. backend/ 폴더에 복사
// 5. .gitignore에 serviceAccountKey.json 추가 (필수!)
// 6. .env에 GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json 추가
// ════════════════════════════════════════════════════════════════

import admin from 'firebase-admin';
import { createRequire } from 'module';
import { query } from '../config/database.js';

let initialized = false;

// ── Firebase Admin 초기화 ─────────────────────────────────────────────────────
function initializeFirebase() {
  if (initialized) return;

  try {
    // 방법 1: GOOGLE_APPLICATION_CREDENTIALS 환경변수 (권장)
    // .env: GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json
    if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      admin.initializeApp({
        credential: admin.credential.applicationDefault(),
      });
      initialized = true;
      console.log('[FCM] Firebase Admin initialized via GOOGLE_APPLICATION_CREDENTIALS');
      return;
    }

    // 방법 2: 파일 직접 로드 (fallback)
    const require = createRequire(import.meta.url);
    try {
      const serviceAccount = require('../../serviceAccountKey.json');
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
      initialized = true;
      console.log('[FCM] Firebase Admin initialized via serviceAccountKey.json');
    } catch {
      console.warn('[FCM] serviceAccountKey.json not found — FCM disabled');
      console.warn('[FCM] Firebase 콘솔에서 서비스 계정 키를 다운로드하세요');
    }
  } catch (err) {
    console.error('[FCM] Firebase Admin init failed:', err.message);
  }
}

initializeFirebase();

// ── FCM 토큰 DB 저장/조회 ─────────────────────────────────────────────────────

/**
 * 사용자의 FCM 토큰을 DB에 저장
 */
export async function saveFcmToken(userId, fcmToken) {
  await query(
    `UPDATE users SET fcm_token = $1, updated_at = NOW() WHERE id = $2`,
    [fcmToken, userId]
  );
}

/**
 * 세션 멤버들의 FCM 토큰 조회 (본인 제외)
 */
async function getSessionMemberTokens(sessionId, excludeUserId = null) {
  const result = await query(
    `SELECT u.id, u.fcm_token
     FROM session_members sm
     JOIN users u ON u.id = sm.user_id
     WHERE sm.session_id = $1
       AND sm.left_at IS NULL
       AND u.fcm_token IS NOT NULL
       ${excludeUserId ? 'AND u.id != $2' : ''}`,
    excludeUserId ? [sessionId, excludeUserId] : [sessionId]
  );
  return result.rows;
}

// ── Silent Push: 백그라운드 위치 요청 ────────────────────────────────────────
/**
 * 백그라운드 상태인 멤버들에게 위치 업데이트 요청
 * 알림 없이 데이터만 전달하는 Silent Push
 *
 * @param {string} sessionId
 * @param {string} requestedBy - 요청자 userId (본인 제외)
 */
export async function requestBackgroundLocations(sessionId, requestedBy) {
  if (!initialized) return;

  const members = await getSessionMemberTokens(sessionId, requestedBy);
  if (members.length === 0) return;

  const tokens = members.map((m) => m.fcm_token).filter(Boolean);
  if (tokens.length === 0) return;

  // Silent Push: notification 없음, data만 있음
  const message = {
    data: {
      type: 'location_request',
      session_id: sessionId,
    },
    android: {
      priority: 'high',           // 백그라운드 앱 깨우기
      ttl: 30000,                  // 30초 내 전달 안 되면 버림
    },
    tokens,
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    _cleanupInvalidTokens(members, response);
    console.log(`[FCM] Location request sent: ${response.successCount}/${tokens.length}`);
  } catch (err) {
    console.error('[FCM] sendEachForMulticast error:', err.message);
  }
}

// ── SOS 고우선순위 알림 ───────────────────────────────────────────────────────
/**
 * SOS 발생 시 세션 전체 멤버에게 고우선순위 푸시 알림
 *
 * @param {string} sessionId
 * @param {string} triggeredByUserId - SOS 발생자 userId
 * @param {string} nickname - SOS 발생자 닉네임
 * @param {{ lat: number, lng: number } | null} location
 * @param {string} sosMessage
 */
export async function sendSosAlert({
  sessionId,
  triggeredByUserId,
  nickname,
  location,
  sosMessage = '긴급 상황 발생!',
}) {
  if (!initialized) return;

  // SOS 발생자 제외 (본인도 알림 받지 않음)
  const members = await getSessionMemberTokens(sessionId, triggeredByUserId);
  if (members.length === 0) return;

  const tokens = members.map((m) => m.fcm_token).filter(Boolean);
  if (tokens.length === 0) return;

  const message = {
    notification: {
      title: `🆘 ${nickname}님이 긴급 상황을 알렸습니다`,
      body: sosMessage,
    },
    data: {
      type: 'sos_alert',
      session_id: sessionId,
      triggered_by: triggeredByUserId,
      nickname,
      message: sosMessage,
      lat: location?.lat?.toString() ?? '',
      lng: location?.lng?.toString() ?? '',
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'sos_channel',
        priority: 'max',
        defaultSound: true,
        defaultVibrateTimings: true,
        // Android 화면이 꺼져 있어도 알림 표시
        visibility: 'public',
      },
      ttl: 300000, // 5분
    },
    tokens,
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    _cleanupInvalidTokens(members, response);
    console.log(`[FCM] SOS alert sent: ${response.successCount}/${tokens.length}`);
  } catch (err) {
    console.error('[FCM] SOS sendEachForMulticast error:', err.message);
  }
}

// ── 지오펜스 진입/이탈 알림 ───────────────────────────────────────────────────
/**
 * @param {string} sessionId
 * @param {string} userId       - 이동한 사용자
 * @param {string} nickname
 * @param {Array}  geofences    - 진입/이탈한 펜스 목록
 * @param {'enter'|'exit'} eventType
 */
export async function sendGeofenceAlert({ sessionId, userId, nickname, geofences, eventType }) {
  if (!initialized) return;

  // 이동한 본인에게도 알림 (자신의 폰에 표시)
  const members = await getSessionMemberTokens(sessionId, null);
  // 본인 토큰만 추출
  const selfTokens = members.filter((m) => m.id === userId).map((m) => m.fcm_token).filter(Boolean);
  if (selfTokens.length === 0) return;

  const fenceNames = geofences.map((f) => f.name).join(', ');
  const isEnter    = eventType === 'enter';

  const message = {
    notification: {
      title: isEnter ? `📍 ${fenceNames} 진입` : `📍 ${fenceNames} 이탈`,
      body:  isEnter
        ? `${nickname}님이 ${fenceNames} 구역에 들어왔습니다`
        : `${nickname}님이 ${fenceNames} 구역을 벗어났습니다`,
    },
    data: {
      type:       'geofence_alert',
      session_id: sessionId,
      event_type: eventType,
      fence_names: fenceNames,
      nickname,
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'default_channel',
      },
    },
    tokens: selfTokens,
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    _cleanupInvalidTokens(members.filter((m) => m.id === userId), response);
  } catch (err) {
    console.error('[FCM] geofence alert error:', err.message);
  }
}

// ── 무효 토큰 정리 ───────────────────────────────────────────────────────────
// 등록 해제된 기기의 FCM 토큰을 DB에서 삭제
async function _cleanupInvalidTokens(members, response) {
  const toDelete = [];

  response.responses.forEach((resp, idx) => {
    if (!resp.success) {
      const code = resp.error?.code;
      // 유효하지 않은 토큰만 삭제 (일시적 오류는 유지)
      if (
        code === 'messaging/invalid-registration-token' ||
        code === 'messaging/registration-token-not-registered'
      ) {
        toDelete.push(members[idx].id);
      }
    }
  });

  if (toDelete.length > 0) {
    await query(
      `UPDATE users SET fcm_token = NULL WHERE id = ANY($1::uuid[])`,
      [toDelete]
    );
    console.log(`[FCM] Removed ${toDelete.length} invalid tokens`);
  }
}
