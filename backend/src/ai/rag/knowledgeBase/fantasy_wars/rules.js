// src/ai/rag/knowledgeBase/fantasy_wars/rules.js
//
// 판타지 워즈: 성유물 쟁탈전 — 게임 규칙 지식 베이스

export default [

  // ══════════════════════════════════════════════
  //  부모: 게임 개요
  // ══════════════════════════════════════════════
  {
    chunkId:  'fw_parent_overview',
    gameType: 'fantasy_wars',
    role:     'all',
    phase:    'all',
    category: 'rule',
    isParent: true,
    parentId: null,
    title:    '판타지 워즈 게임 개요',
    content:  `판타지 워즈: 성유물 쟁탈전은 3개 길드(전사/마법사/도적)가 실제 공간에서 거점을 점령하고 성유물을 쟁탈하는 실시간 위치기반 게임입니다.

[승리 조건]
- 성유물을 먼저 획득하거나
- 제한 시간 종료 시 가장 많은 거점을 보유한 길드

[게임 구조]
1. 각 길드에 3명 이상 배정, 직업 비밀 배정
2. 지도 위 5개 거점 중심으로 이동 및 점령 경쟁
3. 거점 반경 20m 이내 진입 → 점령 게이지 상승
4. 100% 달성 시 해당 길드 소유로 전환
5. 성유물 거점(중앙)은 최소 3개 거점 보유 길드만 도전 가능

[직업별 역할]
- 전사(warrior): 근접 전투 강화, HP 2 (1회 더 버팀)
- 마법사(wizard): 원거리 스킬, 광역 봉쇄 가능
- 사제(priest): 아군 보호막 부여, 부활 스킬
- 도적(rogue): 기습 처형 스킬, 은신 이동`,
  },

  {
    chunkId:  'fw_overview_win',
    gameType: 'fantasy_wars',
    role:     'all',
    phase:    'all',
    category: 'rule',
    isParent: false,
    parentId: 'fw_parent_overview',
    title:    '판타지 워즈 승리 조건',
    content:  '성유물 거점을 점령하면 즉시 승리. 제한 시간 종료 시 거점 수 비교. 동점이면 추가 전투.',
  },
  {
    chunkId:  'fw_overview_structure',
    gameType: 'fantasy_wars',
    role:     'all',
    phase:    'all',
    category: 'rule',
    isParent: false,
    parentId: 'fw_parent_overview',
    title:    '거점 점령 방법',
    content:  '거점 반경 20m 이내에 머물면 점령 게이지 상승. 여러 길드 동시 진입 시 게이지 정지. 단독 점거 시 100% → 소유권 획득.',
  },

  // ══════════════════════════════════════════════
  //  부모: 직업 가이드
  // ══════════════════════════════════════════════
  {
    chunkId:  'fw_parent_jobs',
    gameType: 'fantasy_wars',
    role:     'all',
    phase:    'all',
    category: 'job',
    isParent: true,
    parentId: null,
    title:    '직업 스킬 전체 가이드',
    content:  `[전사 warrior]
HP가 2입니다. 첫 번째 대결에서 패배해도 HP 1로 생존하며, 두 번째 패배 시 탈락합니다.
공격적으로 거점을 막아서는 역할에 적합합니다.

[마법사 wizard]
봉쇄(blockade) 스킬: 특정 거점을 30초간 상대 길드가 점령 불가 상태로 만듭니다.
광역 효과로 아군 거점 방어에 유용합니다.

[사제 priest]
보호막(shield) 스킬: 아군 1명에게 부여, 다음 대결 패배를 1회 무효화합니다.
부활(revive) 스킬: 탈락한 아군을 복귀시킵니다 (쿨다운 있음).

[도적 rogue]
처형(execution) 스킬: 대결 승리 시 상대를 즉시 탈락(체력 무시). 단, 보호막이 있으면 흡수됩니다.
은신 이동으로 상대방 지도에 위치가 표시되지 않습니다(일시적).`,
  },

  {
    chunkId:  'fw_job_warrior',
    gameType: 'fantasy_wars',
    role:     'all',
    phase:    'all',
    category: 'job',
    isParent: false,
    parentId: 'fw_parent_jobs',
    title:    '전사 직업 특성',
    content:  '전사는 HP 2. 대결 첫 패배 후 HP 1 상태로 계속 플레이. 두 번째 패배 시 탈락. 전선 돌파에 최적.',
  },
  {
    chunkId:  'fw_job_priest',
    gameType: 'fantasy_wars',
    role:     'all',
    phase:    'all',
    category: 'job',
    isParent: false,
    parentId: 'fw_parent_jobs',
    title:    '사제 직업 특성',
    content:  '사제는 아군에게 보호막 부여 가능. 보호막이 있으면 다음 대결 패배를 1회 무효화. 도적 처형도 보호막으로 막힘.',
  },
  {
    chunkId:  'fw_job_rogue',
    gameType: 'fantasy_wars',
    role:     'all',
    phase:    'all',
    category: 'job',
    isParent: false,
    parentId: 'fw_parent_jobs',
    title:    '도적 직업 특성',
    content:  '도적은 대결 승리 시 처형 스킬로 상대를 즉시 탈락 가능. 보호막이 있는 대상은 처형 무효. 은신 이동 중 지도에 위치 미표시.',
  },
  {
    chunkId:  'fw_job_wizard',
    gameType: 'fantasy_wars',
    role:     'all',
    phase:    'all',
    category: 'job',
    isParent: false,
    parentId: 'fw_parent_jobs',
    title:    '마법사 직업 특성',
    content:  '마법사는 봉쇄 스킬로 특정 거점을 30초간 잠금. 잠긴 거점은 어떤 길드도 점령 게이지를 올릴 수 없음.',
  },

  // ══════════════════════════════════════════════
  //  부모: 대결 (Duel) 시스템
  // ══════════════════════════════════════════════
  {
    chunkId:  'fw_parent_duel',
    gameType: 'fantasy_wars',
    role:     'all',
    phase:    'all',
    category: 'duel',
    isParent: true,
    parentId: null,
    title:    '1대1 대결 시스템',
    content:  `플레이어 두 명이 근접하면 대결을 신청할 수 있습니다.

[대결 흐름]
1. 도전장 발송 (15초 내 수락/거절)
2. 수락 시 미니게임 시작 (30초 제한)
3. 서버가 seed 기반으로 결과 판정
4. 패자는 탈락 또는 HP 감소

[미니게임 종류]
- 반응속도: 신호가 뜨면 화면을 누르는 속도 대결
- 연타: 5초 동안 더 많이 탭하는 사람이 승리
- 정밀타격: 움직이는 표적에 최대한 가깝게 탭
- 러시안룰렛: 6개 중 탄환 위치를 서버가 결정, 탄환 챔버를 선택한 사람이 패배
- 스피드블랙잭: 21에 가깝게 패를 구성 (초과 시 0점)

[무승부 처리]
- 러시안룰렛에서 둘 다 살아남으면 재대결 없이 무승부 처리
- 무승부 시 양측 모두 탈락/HP 변화 없음`,
  },

  {
    chunkId:  'fw_duel_minigames',
    gameType: 'fantasy_wars',
    role:     'all',
    phase:    'all',
    category: 'duel',
    isParent: false,
    parentId: 'fw_parent_duel',
    title:    '대결 미니게임 규칙 요약',
    content:  '반응속도: 빠른 사람 승리. 연타: 더 많이 탭한 사람. 정밀타격: 오차가 작은 사람. 러시안룰렛: 탄환 챔버 선택, 서버 판정. 스피드블랙잭: 21 이하 중 높은 점수.',
  },
  {
    chunkId:  'fw_duel_effects',
    gameType: 'fantasy_wars',
    role:     'all',
    phase:    'all',
    category: 'duel',
    isParent: false,
    parentId: 'fw_parent_duel',
    title:    '대결 결과 특수 효과',
    content:  '전사 HP 2 → 첫 패배 시 HP 1 잔존. 사제 보호막 → 패배 1회 무효. 도적 처형 발동 시 상대 즉시 탈락 (보호막으로 차단 가능).',
  },
];
