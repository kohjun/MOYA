'use strict';

// Color Chaser 플러그인 설정 + 무지개 색 팔레트.
// Phase 1+2 범위: 색 배정 / 원형 링크 / 카드 표시.
// Phase 3 이후에 tagRangeMeters, missionDurationSec, phase 전환 시간 등 추가.

export const COLOR_PALETTE = [
  { id: 'red',    label: '빨강', hex: '#EF4444' },
  { id: 'orange', label: '주황', hex: '#F97316' },
  { id: 'yellow', label: '노랑', hex: '#EAB308' },
  { id: 'green',  label: '초록', hex: '#22C55E' },
  { id: 'blue',   label: '파랑', hex: '#3B82F6' },
  { id: 'indigo', label: '남색', hex: '#6366F1' },
  { id: 'violet', label: '보라', hex: '#A855F7' },
  { id: 'pink',   label: '분홍', hex: '#EC4899' },
];

export const configSchema = {
  // Phase 3: 처치
  tagRangeMeters: { type: 'number', default: 5, min: 2, max: 20 },
  selfKillOnWrongTag: { type: 'boolean', default: true },
  // Phase 4 (재설계): 거점은 일정 주기마다 1개씩 활성화. 첫 미션 성공자만 힌트 획득.
  controlPointCount: { type: 'number', default: 8, min: 2, max: 20 }, // 게임 동안 풀에서 무작위 활성화
  controlPointRadiusMeters: { type: 'number', default: 15, min: 5, max: 50 },
  missionTimeoutSec: { type: 'number', default: 15, min: 5, max: 60 },
  cpActivationIntervalSec: { type: 'number', default: 90, min: 30, max: 600 }, // 거점 활성화 주기
  cpLifespanSec: { type: 'number', default: 60, min: 20, max: 300 },           // 활성 거점 유지 시간
  // Phase 6: 승리 조건
  timeLimitSec: { type: 'number', default: 1200, min: 300, max: 3600 },
  // GPS 검증
  locationFreshnessMs: { type: 'number', default: 45000, min: 5000, max: 300000 },
  locationAccuracyMaxMeters: { type: 'number', default: 50, min: 5, max: 500 },
};

export const defaultConfig = {
  tagRangeMeters: 5,
  selfKillOnWrongTag: true,
  controlPointCount: 8,
  controlPointRadiusMeters: 15,
  missionTimeoutSec: 15,
  cpActivationIntervalSec: 90,
  cpLifespanSec: 60,
  timeLimitSec: 1200,
  locationFreshnessMs: 45000,
  locationAccuracyMaxMeters: 50,
};

// 타이핑 미션 단어 풀 (한국어, 짧고 입력 편함).
export const MISSION_WORDS = [
  '무지개', '체이서', '추격전', '거점', '비밀',
  '신호', '단서', '발견', '근접', '꼬리',
  '색깔', '경계', '잠복', '관찰', '지점',
];

// 신체정보 attribute 정의. 클라이언트는 이 스키마를 그대로 폼으로 렌더한다.
// 모든 옵션은 string id. label 은 UI 표시용 한글.
export const BODY_ATTRIBUTES = {
  gender: {
    label: '성별',
    options: [
      { id: 'male', label: '남' },
      { id: 'female', label: '여' },
    ],
  },
  heightRange: {
    label: '키',
    options: [
      { id: 'lt160', label: '160cm 미만' },
      { id: '160_170', label: '160~170cm' },
      { id: '170_180', label: '170~180cm' },
      { id: 'gte180', label: '180cm 이상' },
    ],
  },
  hairLength: {
    label: '머리 길이',
    options: [
      { id: 'short', label: '짧음' },
      { id: 'medium', label: '중간' },
      { id: 'long', label: '긺' },
    ],
  },
  glasses: {
    label: '안경',
    options: [
      { id: 'yes', label: '착용' },
      { id: 'no', label: '미착용' },
    ],
  },
  topColor: {
    label: '상의 색',
    options: [
      { id: 'black', label: '검정' },
      { id: 'white', label: '흰색' },
      { id: 'gray', label: '회색' },
      { id: 'red', label: '빨강 계열' },
      { id: 'blue', label: '파랑 계열' },
      { id: 'green', label: '초록 계열' },
      { id: 'other', label: '기타' },
    ],
  },
  bottomColor: {
    label: '하의 색',
    options: [
      { id: 'black', label: '검정' },
      { id: 'jean', label: '청바지' },
      { id: 'gray', label: '회색' },
      { id: 'beige', label: '베이지' },
      { id: 'other', label: '기타' },
    ],
  },
  shoeType: {
    label: '신발',
    options: [
      { id: 'sneakers', label: '운동화' },
      { id: 'dress', label: '구두' },
      { id: 'sandals', label: '샌들' },
      { id: 'boots', label: '부츠' },
      { id: 'other', label: '기타' },
    ],
  },
};

export const BODY_ATTRIBUTE_KEYS = Object.keys(BODY_ATTRIBUTES);

// 입력값 검증: 정의된 attribute 키 + 옵션 id 만 허용.
// 알 수 없는 키/값은 무시하고 정상값만 추출.
export function sanitizeBodyProfile(profile) {
  if (!profile || typeof profile !== 'object') return {};
  const result = {};
  for (const [key, def] of Object.entries(BODY_ATTRIBUTES)) {
    const raw = profile[key];
    if (typeof raw !== 'string') continue;
    if (def.options.some((opt) => opt.id === raw)) {
      result[key] = raw;
    }
  }
  return result;
}

// 인원 수에 맞춰 색 팔레트를 잘라서 사용한다.
// 4명 → 4색, 5명 → 5색, ..., 8명 → 8색.
export function pickColorsForPlayers(playerCount) {
  const count = Math.max(2, Math.min(playerCount, COLOR_PALETTE.length));
  return COLOR_PALETTE.slice(0, count);
}
