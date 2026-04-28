// src/ai/rag/knowledgeBase/index.js
//
// 전체 게임 지식 베이스 진입점

import fwRulesChunks from './fantasy_wars/rules.js';

export const ALL_CHUNKS = [
  ...fwRulesChunks,
];

export function getEmbeddableChunks() {
  return ALL_CHUNKS
    .filter(c => !c.isParent)
    .map(c => ({
      ...c,
      embedText: `[${c.title}]\n${c.content}`,
    }));
}

export function getChunksByGame(gameType) {
  return ALL_CHUNKS.filter(c => c.gameType === gameType);
}

export function getParentChunk(parentId) {
  return ALL_CHUNKS.find(c => c.chunkId === parentId && c.isParent) || null;
}
