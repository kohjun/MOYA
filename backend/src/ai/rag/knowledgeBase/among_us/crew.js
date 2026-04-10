// src/ai/rag/knowledgeBase/among_us/crew.js

export default [

  // ══════════════════════════════════════════════
  //  부모: 미션 전체 가이드
  // ══════════════════════════════════════════════
  {
    chunkId:   'parent_crew_mission',
    gameType:  'among_us',
    role:      'crew',
    phase:     'playing',
    category:  'rule',
    isParent:  true,
    parentId:  null,
    title:     '크루원 미션 완전 가이드',
    content:   `크루원은 3종류의 미션을 수행합니다.

[QR 스캔 미션]
지정된 구역으로 이동해서 QR 코드를 스캔합니다.
예: 카페테리아 배식구, 엔진실 제어판
방법: 구역 입장 → QR 버튼 탭 → 카메라로 스캔

[미니게임 미션]
앱 화면에서 미니게임을 완료합니다.
예: 배선 연결(30초), 슬라이더 맞추기(20초), 버튼 순서 기억하기
방법: 구역 입장 → 미션 버튼 탭 → 게임 완료

[STAY 미션]
지정된 구역에서 정해진 시간 동안 머뭅니다.
예: 의료실 60초, 통신실 45초
주의: 구역을 벗어나면 타이머가 멈추고, 돌아오면 이어서 진행됩니다.

[전략]
- 현재 있는 구역의 미션부터 완료하세요
- 혼자 외진 곳에서 미션하는 건 위험합니다
- STAY 미션 중에는 신뢰할 수 있는 사람 옆에서 하세요
- 임포스터는 1.5~3미터 이내에서만 킬할 수 있습니다`,
  },
  {
    chunkId:   'child_crew_qr',
    gameType:  'among_us',
    role:      'crew',
    phase:     'playing',
    category:  'rule',
    isParent:  false,
    parentId:  'parent_crew_mission',
    title:     'QR 스캔 미션 방법',
    content:   '지정 구역 이동 → 앱에서 QR 버튼 탭 → 카메라로 스캔 → 완료.',
  },
  {
    chunkId:   'child_crew_minigame',
    gameType:  'among_us',
    role:      'crew',
    phase:     'playing',
    category:  'rule',
    isParent:  false,
    parentId:  'parent_crew_mission',
    title:     '미니게임 미션 방법',
    content:   '구역 입장 → 미션 탭 → 배선 연결/슬라이더/버튼 순서 등 게임 완료.',
  },
  {
    chunkId:   'child_crew_stay',
    gameType:  'among_us',
    role:      'crew',
    phase:     'playing',
    category:  'rule',
    isParent:  false,
    parentId:  'parent_crew_mission',
    title:     'STAY 미션 방법',
    content:   '구역에서 지정 시간 체류. 이탈 시 타이머 일시정지, 복귀 시 이어서 진행.',
  },

  // ══════════════════════════════════════════════
  //  부모: 크루원 생존 전략
  // ══════════════════════════════════════════════
  {
    chunkId:   'parent_crew_strategy',
    gameType:  'among_us',
    role:      'crew',
    phase:     'playing',
    category:  'strategy',
    isParent:  true,
    parentId:  null,
    title:     '크루원 생존 및 임포스터 탐지 전략',
    content:   `[생존 전략]
- 혼자 있을 때 임포스터에게 킬 당할 위험이 높습니다
- 다른 크루원과 2~3명씩 함께 이동하세요
- 수상한 사람이 따라오면 사람이 많은 구역으로 이동하세요
- STAY 미션이나 긴 QR 미션은 신뢰할 수 있는 사람 옆에서 하세요

[임포스터 탐지]
- 수상한 점을 기억해두세요: 어디서 무엇을 했는지 알리바이가 없는 사람
- 시체 근처에서 혼자 있던 사람
- 미션 구역에 있었다고 했는데 미션 진행도가 안 늘어난 경우
- 다른 사람을 지나치게 의심하거나 화제를 돌리는 사람

[회의 전략]
- 어디서 무엇을 했는지 구체적으로 말하세요
- 수상한 사람에게 "어디 있었어요?"라고 물어보세요
- 확신이 없을 때는 SKIP이 더 안전할 수 있습니다
- 잘못된 추방은 크루원에게 불리합니다`,
  },
  {
    chunkId:   'child_crew_alone',
    gameType:  'among_us',
    role:      'crew',
    phase:     'playing',
    category:  'strategy',
    isParent:  false,
    parentId:  'parent_crew_strategy',
    title:     '혼자 있을 때 위험한가요',
    content:   '혼자 있을 때 킬 위험 높음. 다른 크루원과 함께 이동하고 외진 곳 미션은 피하세요.',
  },
  {
    chunkId:   'child_crew_suspect',
    gameType:  'among_us',
    role:      'crew',
    phase:     'meeting',
    category:  'strategy',
    isParent:  false,
    parentId:  'parent_crew_strategy',
    title:     '임포스터 의심하는 방법',
    content:   '알리바이 없는 사람, 시체 근처 혼자 있던 사람, 미션 안 하면서 있던 척하는 사람을 의심하세요.',
  },
  {
    chunkId:   'child_crew_skip',
    gameType:  'among_us',
    role:      'crew',
    phase:     'meeting',
    category:  'strategy',
    isParent:  false,
    parentId:  'parent_crew_strategy',
    title:     '언제 SKIP 투표를 하나요',
    content:   '확실한 증거 없을 때, 여러 명이 의심스러울 때 SKIP. 잘못된 추방은 크루원에게 불리합니다.',
  },
];