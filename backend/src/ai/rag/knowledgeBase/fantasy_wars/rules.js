// src/ai/rag/knowledgeBase/fantasy_wars/rules.js
//
// 판타지 워즈: 성유물 쟁탈전 — 게임 규칙 지식 베이스

export default [

  // ══════════════════════════════════════════════
  //  부모: 게임 개요
  // ══════════════════════════════════════════════
  {
    chunkId:  'fw_parent_overview',
    gameType: 'fantasy_wars_artifact',
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
- 마법사(mage): 봉쇄 마법으로 거점 60초 잠금
- 사제(priest): 아군 보호막 부여, 부활 보조
- 도적(rogue): 처형 스킬로 즉시 탈락 (보호막 흡수)
- 레인저(ranger): 적 위치 60초 정찰`,
  },

  {
    chunkId:  'fw_overview_win',
    gameType: 'fantasy_wars_artifact',
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
    gameType: 'fantasy_wars_artifact',
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
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'job',
    isParent: true,
    parentId: null,
    title:    '직업 스킬 전체 가이드',
    content:  `[전사 warrior]
HP 2. 첫 번째 결투에서 패배해도 HP 1 로 생존, 두 번째 패배 시 탈락. 전선 돌파에 강함.

[마법사 mage]
봉쇄(blockade) 스킬: 단일 거점을 60초간 잠금. 잠긴 거점은 어느 길드도 점령 불가.
점령 진행 중 거점에 봉쇄가 걸리면 봉쇄 적용 + 점령 강제 종료.

[사제 priest]
보호막(shield) 스킬: 아군 1명에게 부여, 다음 결투 패배 1회 무효 (도적 처형도 흡수).
결투 중 아군에는 부여 불가. 보호막은 영구 (다음 패배까지).

[도적 rogue]
처형(execution) 스킬: 60초 무장 윈도우. 무장 중 결투 승리 시 상대 즉시 탈락 (HP 무시).
보호막 보유 상대는 무효, 보호막 1 소비 후 일반 결투 결과 적용.

[레인저 ranger]
정찰(reveal) 스킬: 적군 1명 선택 → 60초간 자기 지도에 그 적의 GPS 위치 실시간 노출.
2.5초 간격 streaming, 같은 길드 아군에는 사용 불가.`,
  },

  {
    chunkId:  'fw_job_warrior',
    gameType: 'fantasy_wars_artifact',
    role:     'warrior',
    phase:    'all',
    category: 'job',
    isParent: false,
    parentId: 'fw_parent_jobs',
    title:    '전사 직업 특성',
    content:  '전사(warrior)는 HP 2. 결투 첫 패배 후 HP 1 상태로 계속 플레이. 두 번째 패배 시 탈락. 전선 돌파에 최적. 다른 직업과 달리 보호막 없이도 한 번 더 버틴다.',
  },
  {
    chunkId:  'fw_job_priest',
    gameType: 'fantasy_wars_artifact',
    role:     'priest',
    phase:    'all',
    category: 'job',
    isParent: false,
    parentId: 'fw_parent_jobs',
    title:    '사제 직업 특성',
    content:  '사제(priest)는 아군에게 보호막(shield) 부여. 보호막이 있으면 다음 결투 패배 1회 무효 (도적 처형도 보호막이 흡수). 결투 중인 아군에는 부여 불가. 보호막은 영구 (소비될 때까지).',
  },
  {
    chunkId:  'fw_job_rogue',
    gameType: 'fantasy_wars_artifact',
    role:     'rogue',
    phase:    'all',
    category: 'job',
    isParent: false,
    parentId: 'fw_parent_jobs',
    title:    '도적 직업 특성',
    content:  '도적(rogue)은 처형(execution) 스킬로 60초 무장 윈도우 발동. 무장 중 결투 승리 시 상대 즉시 탈락 (HP 무시). 보호막 보유 상대는 처형 무효, 보호막 1 소비 후 일반 결투 결과.',
  },
  {
    chunkId:  'fw_job_mage',
    gameType: 'fantasy_wars_artifact',
    role:     'mage',
    phase:    'all',
    category: 'job',
    isParent: false,
    parentId: 'fw_parent_jobs',
    title:    '마법사 직업 특성',
    content:  '마법사(mage)는 봉쇄(blockade) 스킬로 단일 거점을 60초 잠금. 잠긴 거점은 어느 길드도 점령 시작/진행 불가. 점령 진행 중 거점에 봉쇄가 걸리면 봉쇄 적용 + 점령 강제 종료.',
  },
  {
    chunkId:  'fw_job_ranger',
    gameType: 'fantasy_wars_artifact',
    role:     'ranger',
    phase:    'all',
    category: 'job',
    isParent: false,
    parentId: 'fw_parent_jobs',
    title:    '레인저 직업 특성',
    content:  '레인저(ranger)는 정찰(reveal) 스킬로 적군 1명을 60초간 자기 지도에 노출. 2.5초 간격으로 마지막 GPS 위치가 streaming. 같은 길드 아군에는 사용 불가 (TARGET_NOT_ENEMY). 적군 위치 추적/타격 조정에 핵심.',
  },

  // ══════════════════════════════════════════════
  //  부모: 대결 (Duel) 시스템
  // ══════════════════════════════════════════════
  {
    chunkId:  'fw_parent_duel',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'duel',
    isParent: true,
    parentId: null,
    title:    '1대1 대결 시스템',
    content:  `플레이어 두 명이 근접하면 대결을 신청할 수 있습니다.

[대결 흐름]
1. 도전장 발송 (15초 내 수락/거절)
2. 수락 시 미니게임 시작 (30초 제한, 러시안 룰렛은 턴제라 별도 timeout 적용)
3. 서버가 seed 기반으로 결과 판정 또는 액션 동기화
4. 패자는 탈락 또는 HP 감소

[미니게임 종류]
- 반응속도: 신호가 뜨면 화면을 누르는 속도 대결
- 연타: 5초 동안 더 많이 탭하는 사람이 승리
- 정밀타격: 움직이는 표적에 최대한 가깝게 탭
- 러시안룰렛: 턴제 동기화. 6 약실 중 1발 실탄, 양 플레이어가 번갈아 chamber+target 액션. self miss → 같은 턴 / opp miss → 턴 넘김 / hit → 그 약실 향한 target 패배 (무승부 없음)
- 스피드블랙잭: 21에 가깝게 패를 구성 (초과 시 0점)
- 평의회 입찰: 3 라운드 BO3 토큰 입찰

[무승부 처리]
- 동률(반응속도/연타 등)이 가능한 미니게임에서 양측 동등 시 무승부 — 양쪽 모두 탈락/HP 변화 없음
- 러시안 룰렛은 턴제로 항상 누군가 명중하므로 무승부 없음`,
  },

  {
    chunkId:  'fw_duel_minigames',
    gameType: 'fantasy_wars_artifact',
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
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'duel',
    isParent: false,
    parentId: 'fw_parent_duel',
    title:    '대결 결과 특수 효과',
    content:  '전사 HP 2 → 첫 패배 시 HP 1 잔존. 사제 보호막 → 패배 1회 무효. 도적 처형 발동 시 상대 즉시 탈락 (보호막으로 차단 가능).',
  },
  {
    chunkId:  'fw_duel_russian_roulette_turn',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'duel',
    isParent: false,
    parentId: 'fw_parent_duel',
    title:    '러시안 룰렛 턴제 룰',
    content:  `러시안 룰렛은 양 플레이어가 서버 동기화 상태에서 번갈아 진행하는 턴제 미니게임입니다.

[규칙]
- 6 약실 중 1 발이 실탄 (서버가 seed 로 결정, 클라이언트에는 비공개)
- 액션: { chamber: 1..6, target: 'self' | 'opponent' }
- self miss → 같은 플레이어 턴 유지 (재시도 가능)
- opponent miss → 턴이 상대에게 넘어감
- 누군가 hit (실탄 챔버 선택) → 그 약실을 향한 target 이 패배

[동기화]
- 서버가 양 클라에 fw:duel:state broadcast (chambersFired/currentTurn/history)
- 클라가 NOT_YOUR_TURN / CHAMBER_USED 같은 잘못된 액션 보내면 서버가 거부`,
  },

  // ══════════════════════════════════════════════
  //  부모: 거점 점령 메커닉
  // ══════════════════════════════════════════════
  {
    chunkId:  'fw_parent_capture',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'capture',
    isParent: true,
    parentId: null,
    title:    '거점 점령 메커닉',
    content:  `[점령 영역]
- 각 거점 중심 반경 30m 가 점령 영역 (host config 로 5~200m 변경 가능)
- 영역 안에 진입한 플레이어는 captureZone 에 등록
- 영역 이탈 시 자동 해제

[점령 진행]
1. 점령 버튼 클릭 시 5초 ready window 안에 같은 길드 멤버가 모두 영역 안이어야 시작
2. 시작 후 30초 게이지 (host config 로 15~300s)
3. 도중 영역 이탈하거나 봉쇄 마법이 걸리면 점령 취소
4. 100% 도달 시 capturedBy 가 자기 길드로 전환, 점수 +10

[방해 액션]
- 적 길드의 점령은 자동으로 차단되지 않음 — 적이 명시적으로 "점령 방해" 버튼을 눌러야 진행이 끊김
- 방해는 별도 fw:capture_disrupt 이벤트, 결투 중인 플레이어는 방해 불가

[승리 조건]
- 한 길드가 3 거점을 점령하면 즉시 게임 종료 (controlPointHoldDurationSec=0 기본값)
- 운영 시 host 가 hold delay 를 늘리면 그 시간 동안 hold 유지해야 승리`,
  },
  {
    chunkId:  'fw_capture_radius',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'capture',
    isParent: false,
    parentId: 'fw_parent_capture',
    title:    '점령 영역 반경',
    content:  '거점 중심 반경 30m 가 기본 captureRadiusMeters. 호스트 설정으로 5m~200m 까지 조정 가능. 영역 안에 GPS fresh 신호로 들어가야 점령 의향이 등록됨.',
  },
  {
    chunkId:  'fw_capture_duration',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'capture',
    isParent: false,
    parentId: 'fw_parent_capture',
    title:    '점령 게이지 30초',
    content:  '점령은 시작 후 30초 (captureDurationSec) 동안 같은 길드 멤버가 영역에 머물러야 완료. 도중 이탈/봉쇄 발동 시 게이지 0 으로 리셋. 적군이 영역 안에 있어도 점령 시작 자체는 가능 — 적이 방해 액션을 따로 발동해야 끊김.',
  },
  {
    chunkId:  'fw_capture_disrupt',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'capture',
    isParent: false,
    parentId: 'fw_parent_capture',
    title:    '점령 방해 액션',
    content:  '적 길드 점령이 진행 중일 때 같은 영역 안의 적군은 "점령 방해" 버튼을 누를 수 있다. 방해 시 fw:capture_cancelled (reason="disrupted") 가 broadcast 되며 진행 중 게이지가 0 으로 리셋. 결투 중인 플레이어는 방해 액션 불가.',
  },
  {
    chunkId:  'fw_capture_threshold',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'late',
    category: 'capture',
    isParent: false,
    parentId: 'fw_parent_capture',
    title:    '3거점 점령 즉시 승리',
    content:  '5개 거점 중 한 길드가 3개를 점령하면 controlPointHoldDurationSec=0 기본값에서 즉시 게임 종료 (control_point_majority 사유). 호스트가 hold delay 를 0 보다 크게 두면 그 시간 동안 다수 점령을 유지해야 승리 — 적이 거점 하나 빼앗으면 hold 가 풀림.',
  },
  {
    chunkId:  'fw_capture_blockaded',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'capture',
    isParent: false,
    parentId: 'fw_parent_capture',
    title:    '봉쇄된 거점은 점령 불가',
    content:  '거점에 마법사 봉쇄가 걸려있는 동안 (blockadeExpiresAt > now) 어느 길드도 점령 시작 / 진행 불가. 봉쇄 만료 후에 다시 점령 가능. 봉쇄가 점령 진행 중 거점에 걸리면 진행 중 점령은 강제 종료된다.',
  },

  // ══════════════════════════════════════════════
  //  부모: 스킬 상호작용
  // ══════════════════════════════════════════════
  {
    chunkId:  'fw_parent_skill_interaction',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'skill',
    isParent: true,
    parentId: null,
    title:    '직업 스킬 상호작용 디테일',
    content:  `[봉쇄 (마법사)]
- 단일 거점 대상, 60초 지속
- 점령 진행 중 거점에 걸면 봉쇄 적용 + 점령 강제 종료 (양수)
- 봉쇄 동안 어느 길드도 점령 불가

[보호막 (사제)]
- 아군 1명에게 부여, 영구 (다음 패배까지)
- 결투 패배 1회 무효 — 처형 스킬도 보호막이 흡수
- 결투 중인 아군에는 부여 불가 (TARGET_IN_DUEL)

[처형 (도적)]
- 발동 후 60초 무장 윈도우
- 무장 중 결투 승리 → 상대 즉시 탈락 (HP 무시)
- 보호막 보유 상대는 무효, 보호막 1개 소비 후 일반 결투 결과 적용

[정찰 (레인저)]
- 적군 1명 선택 → 60초간 자기 지도에 위치 노출
- 매 2.5초 간격으로 마지막 GPS 위치를 실시간 broadcast`,
  },
  {
    chunkId:  'fw_skill_blockade',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'skill',
    isParent: false,
    parentId: 'fw_parent_skill_interaction',
    title:    '마법사 봉쇄 스킬 상세',
    content:  '봉쇄(blockade)는 마법사가 대상 거점에 60초 잠금을 거는 스킬. 잠긴 거점은 어느 길드도 점령 불가. 점령 진행 중 거점에 봉쇄가 걸리면 봉쇄가 적용되면서 진행 중 점령은 강제 종료되고 fw:capture_cancelled (reason="blockaded") broadcast.',
  },
  {
    chunkId:  'fw_skill_shield_absorb',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'skill',
    isParent: false,
    parentId: 'fw_parent_skill_interaction',
    title:    '사제 보호막 흡수 규칙',
    content:  '보호막은 아군에게 부여되며 다음 결투 패배 1회를 무효화. 도적 처형이 발동돼도 보호막이 있으면 흡수되어 즉시 탈락은 일어나지 않음. 보호막 1개 소비 후 결투 결과는 일반 처리. 결투 중인 아군에는 부여 불가.',
  },
  {
    chunkId:  'fw_skill_execution',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'skill',
    isParent: false,
    parentId: 'fw_parent_skill_interaction',
    title:    '도적 처형 무장 윈도우',
    content:  '처형(execution) 스킬은 발동 후 60초 무장 윈도우 동안만 효과. 그 안에 결투에서 승리하면 상대를 HP 무시하고 즉시 탈락시킴. 보호막 보유 상대는 처형 차단, 보호막 1 소비.',
  },
  {
    chunkId:  'fw_skill_reveal',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'skill',
    isParent: false,
    parentId: 'fw_parent_skill_interaction',
    title:    '레인저 정찰 스킬',
    content:  '정찰(reveal)은 적군 1명을 선택해 60초간 자기 지도에 그 적의 GPS 위치를 실시간 노출. 같은 길드 아군에는 사용 불가 (TARGET_NOT_ENEMY). 적이 GPS 갱신 빈도와 무관하게 2.5초 간격으로 마지막 위치가 streaming.',
  },

  // ══════════════════════════════════════════════
  //  부모: 결투 거리 / BLE 근접
  // ══════════════════════════════════════════════
  {
    chunkId:  'fw_parent_proximity',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'duel',
    isParent: true,
    parentId: null,
    title:    '결투 근접 / BLE 증거',
    content:  `[기본 결투 거리]
- 두 플레이어 사이 거리 20m 이내일 때 결투 신청 가능 (duelRangeMeters)
- 호스트 설정으로 1~100m 변경 가능

[BLE 증거 우선]
- 결투 신청 시 mutual BLE proximity 증거가 12초 이내 (bleEvidenceFreshnessMs) 면 사실상 한 자리에 같이 있는 것으로 간주
- BLE 증거가 신선하면 GPS 거리 검증을 완화

[GPS 폴백]
- BLE 미확인 + 호스트 config allowGpsFallbackWithoutBle=true 일 때 GPS 거리만으로 결투 허용 (기본값, 에뮬레이터/QA용)
- 운영 단계에서는 false 로 둬 BLE 강제`,
  },
  {
    chunkId:  'fw_proximity_duel_range',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'duel',
    isParent: false,
    parentId: 'fw_parent_proximity',
    title:    '결투 신청 거리 20m',
    content:  '결투 신청은 두 플레이어가 서로 20m 이내 (duelRangeMeters 기본값) 일 때만 가능. 거리 초과 시 PROXIMITY_TOO_FAR 에러. 호스트가 1~100m 사이로 조정 가능.',
  },
  {
    chunkId:  'fw_proximity_ble_freshness',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'duel',
    isParent: false,
    parentId: 'fw_parent_proximity',
    title:    'BLE 신선도 12초',
    content:  '서로의 BLE 신호 증거가 12초 (bleEvidenceFreshnessMs 기본값) 이내면 mutual proximity 로 인정. BLE 가 mutual 이면 GPS 거리 검증을 우회. BLE 가 신선하지 않을 때만 GPS 검증으로 폴백.',
  },

  // ══════════════════════════════════════════════
  //  부모: 던전 / 부활
  // ══════════════════════════════════════════════
  {
    chunkId:  'fw_parent_dungeon_revive',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'revive',
    isParent: true,
    parentId: null,
    title:    '던전 입장 + 부활 메커닉',
    content:  `[던전 입장]
- 결투 패배 또는 처형으로 탈락한 플레이어는 길드별 던전 위치로 이동 가능
- 던전에 입장하면 부활 시도 가능 상태로 전환

[부활 시도]
- 첫 시도 성공 확률 reviveBaseChance = 30%
- 시도 실패 시마다 reviveStepChance = +10% 누적 (다음 시도)
- 최대 reviveMaxChance = 80% 까지 상승
- 시도 사이 쿨다운: nextReviveAt 만료 후만 재시도 가능

[마스터 부활]
- 길드 마스터가 탈락하면 그 길드는 master_eliminated 사유로 패배 위험
- 마스터를 던전에서 부활시키면 길드가 게임에 복귀
- 모든 길드 마스터가 탈락하면 점수 비교 (last_standing_by_score) 로 승자 판정`,
  },
  {
    chunkId:  'fw_revive_chance_curve',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'all',
    category: 'revive',
    isParent: false,
    parentId: 'fw_parent_dungeon_revive',
    title:    '부활 확률 곡선',
    content:  '부활 확률은 첫 시도 30%, 실패할 때마다 +10% 누적, 최대 80%. 즉 1회 30%, 2회 40%, 3회 50%, ..., 6회 이후 80% 고정. reviveAttempts 가 누적되어 자동 계산.',
  },
  {
    chunkId:  'fw_revive_master_elim',
    gameType: 'fantasy_wars_artifact',
    role:     'all',
    phase:    'late',
    category: 'revive',
    isParent: false,
    parentId: 'fw_parent_dungeon_revive',
    title:    '길드 마스터 탈락 패배 조건',
    content:  '길드 마스터가 탈락한 채 게임이 종료되면 그 길드는 guild_master_eliminated 사유로 패배. 마스터를 던전에서 부활시키지 않으면 길드 자체가 사실상 무력화. 모든 길드 마스터 동시 탈락 시 점수가 가장 높은 길드가 last_standing_by_score 로 승리.',
  },
];
