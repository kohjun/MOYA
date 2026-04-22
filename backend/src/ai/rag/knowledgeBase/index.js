// src/ai/rag/knowledgeBase/index.js
//
// 전체 게임 지식 베이스 진입점
// 새 게임 추가 시 여기에 import만 추가하면 됩니다.

import commonChunks   from './among_us/common.js';
import crewChunks     from './among_us/crew.js';
import impostorChunks from './among_us/impostor.js';
import itemsChunks    from './among_us/items.js';
import faqChunks      from './among_us/faq.js';
import fwRulesChunks  from './fantasy_wars/rules.js';

const amongUsChunks = [
  ...commonChunks,
  ...crewChunks,
  ...impostorChunks,
  ...itemsChunks,
  ...faqChunks,
];

const fantasyWarsChunks = [
  ...fwRulesChunks,
];

export const ALL_CHUNKS = [
  ...amongUsChunks,
  ...fantasyWarsChunks,
];

// 임베딩할 텍스트 생성 (자식 청크만)
export function getEmbeddableChunks() {
  return ALL_CHUNKS
    .filter(c => !c.isParent)
    .map(c => ({
      ...c,
      embedText: `[${c.title}]\n${c.content}`,
    }));
}

// 게임 타입별 청크 조회
export function getChunksByGame(gameType) {
  return ALL_CHUNKS.filter(c => c.gameType === gameType);
}

// chunk_id로 부모 문서 조회 (로컬 fallback용)
export function getParentChunk(parentId) {
  return ALL_CHUNKS.find(c => c.chunkId === parentId && c.isParent) || null;
}
