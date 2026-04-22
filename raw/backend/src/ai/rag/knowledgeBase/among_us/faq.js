// src/ai/rag/knowledgeBase/among_us/faq.js

export default [
  {
    chunkId:   'parent_faq_general',
    gameType:  'among_us', role: 'all', phase: 'all',
    category:  'faq', isParent: true, parentId: null,
    title:     '자주 묻는 질문 모음',
    content:   `Q. 임포스터가 몇 명인지 알 수 있나요?
A. 게임 시작 시 공개되지 않습니다. 6명 이하면 1명, 7명 이상이면 2명이 기본값입니다.
   임포스터가 추방되면 AI 해설에서 알려줍니다.

Q. 언제 긴급 버튼을 써야 하나요?
A. 수상한 행동을 목격했을 때. 단 게임당 1회이므로 확실한 상황에서 사용하세요.
   미션 진행도 75% 이상이면 임포스터가 급해지니 특히 조심하세요.

Q. 구역은 어떻게 인식되나요?
A. 앱이 자동으로 구역 입장을 감지합니다. QR 미션은 입장 후 직접 스캔해야 합니다.

Q. 회의 중에도 킬이 가능한가요?
A. 아닙니다. 회의(meeting) 페이즈에서는 킬이 비활성화됩니다.`,
  },
  {
    chunkId:   'child_faq_impostor_count',
    gameType:  'among_us', role: 'all', phase: 'all',
    category:  'faq', isParent: false, parentId: 'parent_faq_general',
    title:     '임포스터 몇 명인가요',
    content:   '게임 시작 시 공개 안 됨. 6명 이하 1명, 7명 이상 2명이 기본. 추방 시 AI가 알려줌.',
  },
  {
    chunkId:   'child_faq_emergency_timing',
    gameType:  'among_us', role: 'all', phase: 'playing',
    category:  'faq', isParent: false, parentId: 'parent_faq_general',
    title:     '긴급 버튼 언제 써요',
    content:   '수상한 행동 목격 시. 게임당 1회이므로 신중하게. 미션 75% 이상일 때 특히 유용.',
  },
  {
    chunkId:   'child_faq_meeting_kill',
    gameType:  'among_us', role: 'all', phase: 'meeting',
    category:  'faq', isParent: false, parentId: 'parent_faq_general',
    title:     '회의 중 킬 가능한가요',
    content:   '불가. 회의(meeting) 페이즈에서는 킬 버튼이 비활성화됩니다.',
  },
];