// src/ai/rag/knowledgeBase/among_us/common.js
//
// 어몽어스 공통 규칙 — 크루원/임포스터 모두에게 적용
// 부모 문서(is_parent: true)와 자식 청크(is_parent: false)로 구성됩니다.
// 검색은 자식 청크로 하고, AI에게는 부모 문서 전체를 전달합니다.

export default [

  // ══════════════════════════════════════════════
  //  부모 문서: 게임 목표 & 기본 구조
  // ══════════════════════════════════════════════
  {
    chunkId:   'parent_common_overview',
    gameType:  'among_us',
    role:      'all',
    phase:     'all',
    category:  'rule',
    isParent:  true,
    parentId:  null,
    title:     '게임 목표와 기본 구조',
    content:   `이 게임은 크루원팀과 임포스터팀이 대결하는 소셜 디덕션 게임입니다.
실제 공간에서 스마트폰 앱과 함께 플레이합니다.

[크루원 승리 조건]
- 모든 미션을 완료한다 (미션 진행 바 100%)
- 투표로 임포스터 전원을 추방한다

[임포스터 승리 조건]
- 살아있는 임포스터 수가 살아있는 크루원 수 이상이 된다

[게임 진행 순서]
1. 방장이 게임 시작 → 역할 비밀 배정
2. 각자 구역을 돌며 미션 수행 (크루원) / 방해 (임포스터)
3. 시체 발견 또는 긴급 버튼 → 회의 소집
4. 토론 90초 → 투표 30초 → 추방 or SKIP
5. 승리 조건 달성 시 게임 종료`,
  },

  // 자식 청크들
  {
    chunkId:   'child_common_crew_win',
    gameType:  'among_us',
    role:      'all',
    phase:     'all',
    category:  'rule',
    isParent:  false,
    parentId:  'parent_common_overview',
    title:     '크루원 승리 조건',
    content:   '미션 진행 바 100% 달성 또는 투표로 임포스터 전원 추방 시 크루원 승리.',
  },
  {
    chunkId:   'child_common_impostor_win',
    gameType:  'among_us',
    role:      'all',
    phase:     'all',
    category:  'rule',
    isParent:  false,
    parentId:  'parent_common_overview',
    title:     '임포스터 승리 조건',
    content:   '살아있는 임포스터 수 >= 살아있는 크루원 수가 되면 임포스터 즉시 승리.',
  },

  // ══════════════════════════════════════════════
  //  부모 문서: 회의 규칙
  // ══════════════════════════════════════════════
  {
    chunkId:   'parent_common_meeting',
    gameType:  'among_us',
    role:      'all',
    phase:     'all',
    category:  'rule',
    isParent:  true,
    parentId:  null,
    title:     '회의 소집 및 투표 규칙',
    content:   `회의는 두 가지 방법으로 소집할 수 있습니다.

[시체 신고]
- 시체에서 5미터 이내에 있을 때 앱의 시체 신고 버튼이 활성화됩니다.
- 신고하면 즉시 전체 회의가 소집됩니다.

[긴급 버튼]
- 앱의 긴급 버튼을 누릅니다.
- 게임당 1인 1회만 사용 가능합니다.

[토론 단계] 90초
- 어디 있었는지, 무엇을 했는지 자유롭게 발언합니다.

[투표 단계] 30초
- 자기 자신에게는 투표할 수 없습니다.
- SKIP 투표도 가능합니다.
- 가장 많은 표를 받은 사람이 추방됩니다.
- 동률이면 아무도 추방되지 않습니다.
- 추방되면 역할이 공개됩니다.`,
  },

  {
    chunkId:   'child_common_report',
    gameType:  'among_us',
    role:      'all',
    phase:     'playing',
    category:  'rule',
    isParent:  false,
    parentId:  'parent_common_meeting',
    title:     '시체 신고 방법',
    content:   '시체에서 5미터 이내에서 앱 신고 버튼 탭 → 즉시 회의 소집.',
  },
  {
    chunkId:   'child_common_emergency',
    gameType:  'among_us',
    role:      'all',
    phase:     'playing',
    category:  'rule',
    isParent:  false,
    parentId:  'parent_common_meeting',
    title:     '긴급 버튼',
    content:   '앱 긴급 버튼 탭 → 회의 소집. 게임당 1인 1회만 사용 가능.',
  },
  {
    chunkId:   'child_common_vote',
    gameType:  'among_us',
    role:      'all',
    phase:     'meeting',
    category:  'rule',
    isParent:  false,
    parentId:  'parent_common_meeting',
    title:     '투표 규칙',
    content:   '자기 투표 불가. SKIP 가능. 최다 득표자 추방. 동률 시 추방 없음. 추방 시 역할 공개.',
  },

  // ══════════════════════════════════════════════
  //  부모 문서: 거리 측정
  // ══════════════════════════════════════════════
  {
    chunkId:   'parent_common_proximity',
    gameType:  'among_us',
    role:      'all',
    phase:     'all',
    category:  'rule',
    isParent:  true,
    parentId:  null,
    title:     'UWB/BLE 거리 측정',
    content:   `앱이 기기에 따라 자동으로 측정 방식을 선택합니다.

[UWB 방식] 아이폰 11 이상
- 약 10cm 오차의 정밀 측정
- 킬 가능 거리: 1.5미터 이내

[BLE 방식] 그 외 기기
- 1~3미터 오차의 추정 측정
- 킬 가능 거리: 3미터 이내

앱에서 킬 버튼이 빨간색으로 활성화되면 충분히 가까운 것입니다.
일정 시간(UWB 3초, BLE 8초) 이상 갱신이 없으면 거리 정보가 무효 처리됩니다.`,
  },
  {
    chunkId:   'child_common_uwb',
    gameType:  'among_us',
    role:      'all',
    phase:     'all',
    category:  'rule',
    isParent:  false,
    parentId:  'parent_common_proximity',
    title:     'UWB vs BLE 킬 범위',
    content:   'UWB(아이폰 11+): 1.5m 이내. BLE(그 외): 3m 이내. 킬 버튼 빨간색 = 범위 안.',
  },

  // ══════════════════════════════════════════════
  //  부모 문서: 사망 후 행동
  // ══════════════════════════════════════════════
  {
    chunkId:   'parent_common_dead',
    gameType:  'among_us',
    role:      'all',
    phase:     'all',
    category:  'faq',
    isParent:  true,
    parentId:  null,
    title:     '사망 후 행동',
    content:   `사망하면 앱이 유령 모드로 전환됩니다.

- 미션 수행 불가
- 투표 참여 불가
- 게임 결과가 나올 때까지 조용히 지켜봅니다
- 임포스터가 누구인지 다른 플레이어에게 알려주면 안 됩니다 (게임 공정성)
- 자신이 죽었다는 사실도 함구하는 것이 매너입니다`,
  },
  {
    chunkId:   'child_common_dead',
    gameType:  'among_us',
    role:      'all',
    phase:     'all',
    category:  'faq',
    isParent:  false,
    parentId:  'parent_common_dead',
    title:     '죽으면 어떻게 되나요',
    content:   '유령 모드로 전환. 미션/투표 불가. 임포스터 정보 누설 금지. 게임 종료까지 대기.',
  },

  // ══════════════════════════════════════════════
  //  부모 문서: 코인 시스템
  // ══════════════════════════════════════════════
  {
    chunkId:   'parent_common_currency',
    gameType:  'among_us',
    role:      'all',
    phase:     'all',
    category:  'faq',
    isParent:  true,
    parentId:  null,
    title:     '코인 획득 방법',
    content:   `코인은 상점에서 아이템을 구매하는 데 사용됩니다.

[획득 경로]
- 미션 완료 (easy): 10코인
- 미션 완료 (medium): 15코인
- 미션 완료 (hard): 20코인
- 게임 승리: 50코인
- 게임 참여 (패배): 10코인
- 무고한 사람 지지 투표: 회당 15코인
- 임포스터 첫 정확한 지목: 50코인 보너스

[조건부 아이템 보상]
- 임포스터 첫 킬: 연막탄 1개
- 미션 3연속 완료: 지도 1개`,
  },
  {
    chunkId:   'child_common_currency',
    gameType:  'among_us',
    role:      'all',
    phase:     'all',
    category:  'faq',
    isParent:  false,
    parentId:  'parent_common_currency',
    title:     '코인 어떻게 버나요',
    content:   '미션 완료 10~20코인. 게임 승리 50코인. 패배 10코인. 상점에서 아이템 구매 가능.',
  },
];