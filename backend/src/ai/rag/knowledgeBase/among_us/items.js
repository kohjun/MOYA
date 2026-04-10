// src/ai/rag/knowledgeBase/among_us/items.js

export default [
  {
    chunkId:   'parent_items_all',
    gameType:  'among_us',
    role:      'all',
    phase:     'all',
    category:  'item',
    isParent:  true,
    parentId:  null,
    title:     '아이템 전체 목록',
    content:   `앱 하단 상점 아이콘을 탭해서 아이템을 구매할 수 있습니다.

[공용 아이템]
연막탄 (80코인): 5초 동안 내 위치 정보 숨김. 킬 직후 도주에 유용.

[크루원 전용]
지도 (120코인): 30초 동안 모든 생존자 위치 표시. 단, 연막탄 사용자는 표시 안 됨.
방탄조끼 (150코인): 다음 킬 시도 1회 무효화. 조건 발동형으로 계속 유지됨.
탐지기 (200코인): 30초 동안 5미터 이내 임포스터 감지. 단, 변장 사용자는 감지 안 됨.

[임포스터 전용]
변장 (180코인): 30초 동안 탐지기에 잡히지 않음.
방해전파 (160코인): 현재 구역의 모든 미션 30초 동안 진행 불가.

사용 방법: 앱 인벤토리 탭 → 아이템 선택 → 사용 버튼`,
  },
  {
    chunkId:   'child_item_smoke',
    gameType:  'among_us', role: 'all', phase: 'playing',
    category:  'item', isParent: false, parentId: 'parent_items_all',
    title:     '연막탄 사용법',
    content:   '80코인. 5초 위치 숨김. 공용. 인벤토리에서 사용.',
  },
  {
    chunkId:   'child_item_map',
    gameType:  'among_us', role: 'crew', phase: 'playing',
    category:  'item', isParent: false, parentId: 'parent_items_all',
    title:     '지도 사용법',
    content:   '120코인. 30초 전체 위치 공개. 크루원 전용. 연막탄 사용자는 표시 안 됨.',
  },
  {
    chunkId:   'child_item_vest',
    gameType:  'among_us', role: 'crew', phase: 'playing',
    category:  'item', isParent: false, parentId: 'parent_items_all',
    title:     '방탄조끼 사용법',
    content:   '150코인. 킬 1회 무효화. 크루원 전용. 발동 후 자동 소모.',
  },
  {
    chunkId:   'child_item_detector',
    gameType:  'among_us', role: 'crew', phase: 'playing',
    category:  'item', isParent: false, parentId: 'parent_items_all',
    title:     '탐지기 사용법',
    content:   '200코인. 30초간 5m 이내 임포스터 감지. 변장 중인 임포스터는 감지 안 됨.',
  },
  {
    chunkId:   'child_item_disguise',
    gameType:  'among_us', role: 'impostor', phase: 'playing',
    category:  'item', isParent: false, parentId: 'parent_items_all',
    title:     '변장 사용법',
    content:   '180코인. 30초간 탐지기 회피. 임포스터 전용.',
  },
  {
    chunkId:   'child_item_jammer',
    gameType:  'among_us', role: 'impostor', phase: 'playing',
    category:  'item', isParent: false, parentId: 'parent_items_all',
    title:     '방해전파 사용법',
    content:   '160코인. 현재 구역 미션 30초 불가. 임포스터 전용. 방해할 구역에서 직접 사용.',
  },
];