// src/ai/rag/knowledgeBase/among_us/impostor.js

export default [

  // ══════════════════════════════════════════════
  //  부모: 킬 시스템 전체
  // ══════════════════════════════════════════════
  {
    chunkId:   'parent_impostor_kill',
    gameType:  'among_us',
    role:      'impostor',
    phase:     'playing',
    category:  'rule',
    isParent:  true,
    parentId:  null,
    title:     '임포스터 킬 시스템',
    content:   `[킬 방법]
1. 크루원에게 충분히 가까이 접근합니다
   - UWB 기기(아이폰 11+): 1.5미터 이내
   - BLE 기기(그 외): 3미터 이내
2. 앱 킬 버튼이 빨간색으로 활성화됩니다
3. 킬 버튼을 누르면 서버에서 거리를 재검증합니다
4. 킬 확정 후 30초 쿨다운이 시작됩니다

[킬 후 행동]
- 즉시 현장을 벗어나세요
- 다른 구역에서 미션하는 척 알리바이를 만드세요
- 시체 근처에 오래 있으면 의심받습니다

[주의사항]
- 방탄조끼를 가진 크루원은 첫 킬이 1회 무효화됩니다
- 증인이 있으면 킬 후 바로 회의가 소집될 수 있습니다`,
  },
  {
    chunkId:   'child_impostor_kill_method',
    gameType:  'among_us',
    role:      'impostor',
    phase:     'playing',
    category:  'rule',
    isParent:  false,
    parentId:  'parent_impostor_kill',
    title:     '킬 방법',
    content:   '1.5m(UWB) 또는 3m(BLE) 이내 접근 → 킬 버튼 빨간색 활성화 → 탭 → 30초 쿨다운.',
  },
  {
    chunkId:   'child_impostor_kill_timing',
    gameType:  'among_us',
    role:      'impostor',
    phase:     'playing',
    category:  'strategy',
    isParent:  false,
    parentId:  'parent_impostor_kill',
    title:     '킬 타이밍',
    content:   '혼자 있는 크루원, 외진 구역, 회의 직후(경계심 낮을 때)가 좋은 타이밍입니다.',
  },

  // ══════════════════════════════════════════════
  //  부모: 임포스터 전략
  // ══════════════════════════════════════════════
  {
    chunkId:   'parent_impostor_strategy',
    gameType:  'among_us',
    role:      'impostor',
    phase:     'all',
    category:  'strategy',
    isParent:  true,
    parentId:  null,
    title:     '임포스터 생존 및 위장 전략',
    content:   `[위장 전략]
- 앱에 가짜 미션 2개가 표시됩니다. 미션하는 척 크루원의 신뢰를 얻으세요
- 미션 구역에 있었다는 알리바이로 활용하세요
- 크루원들과 함께 이동하면서 기회를 노리세요

[회의 전략]
- 너무 조용히 있으면 의심받습니다. 적당히 발언하세요
- 다른 사람에게 의심을 돌리세요
- 확실한 증거가 없는 상황에서 다른 크루원을 적극 의심하세요
- 동률이 나오도록 투표를 유도하면 아무도 추방되지 않습니다

[다수 임포스터일 때]
- 서로 의심하는 척 연기하세요
- 같은 구역에서 동시에 킬하지 마세요 (둘 다 의심받음)

[주의]
- 탐지기 아이템을 가진 크루원이 있을 수 있습니다
- 변장 아이템을 미리 사면 탐지기를 피할 수 있습니다`,
  },
  {
    chunkId:   'child_impostor_fake_mission',
    gameType:  'among_us',
    role:      'impostor',
    phase:     'playing',
    category:  'strategy',
    isParent:  false,
    parentId:  'parent_impostor_strategy',
    title:     '가짜 미션 수행',
    content:   '앱에 가짜 미션 2개 표시됨. 실제로는 완료 안 되지만 미션하는 척 알리바이 만들기 가능.',
  },
  {
    chunkId:   'child_impostor_vote',
    gameType:  'among_us',
    role:      'impostor',
    phase:     'meeting',
    category:  'strategy',
    isParent:  false,
    parentId:  'parent_impostor_strategy',
    title:     '회의 투표 전략',
    content:   '적당히 발언, 다른 사람 의심 유도, 동률 유도(아무도 추방 안 됨). 너무 조용하면 의심.',
  },
];