// src/ai/rag/ragRetriever.js

import { GoogleGenerativeAI } from '@google/generative-ai';
import { createClient }       from '@supabase/supabase-js';
import { getParentChunk }     from './knowledgeBase/index.js';

const genAI    = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

// gemini-embedding-001: 768차원 출력
const EMBED_MODEL    = 'gemini-embedding-001';
const TABLE_NAME     = 'game_rules';
const TOP_K          = 5;
const MIN_SIMILARITY = 0.65;

async function embedQuery(text) {
  const embedModel = genAI.getGenerativeModel({ model: EMBED_MODEL });
  const result     = await embedModel.embedContent(text);
  return result.embedding.values;
}

async function searchChildren(embedding, gameType, role, phase) {
  const { data, error } = await supabase.rpc('match_game_rules', {
    query_embedding: embedding,
    match_threshold: MIN_SIMILARITY,
    match_count:     TOP_K,
    p_game_type:     gameType,
    p_role:          role,
    p_phase:         phase,
  });
  if (error) { console.error('[ragRetriever] 검색 오류:', error.message); return []; }
  return data || [];
}

async function fetchParents(childChunks) {
  const parentIds = [...new Set(childChunks.map(c => c.parent_id).filter(Boolean))];
  if (!parentIds.length) return childChunks;

  const { data, error } = await supabase
    .from(TABLE_NAME)
    .select('chunk_id, title, content')
    .in('chunk_id', parentIds);

  if (error || !data?.length) {
    return parentIds
      .map(id => getParentChunk(id))
      .filter(Boolean)
      .map(c => ({ chunk_id: c.chunkId, title: c.title, content: c.content }));
  }
  return data;
}

function buildContext(parentDocs) {
  if (!parentDocs?.length) return '';
  return parentDocs
    .map((doc, i) => `[관련 규칙 ${i + 1}: ${doc.title}]\n${doc.content}`)
    .join('\n\n---\n\n');
}

async function retrieve(question, gameType, role = 'all', phase = 'all') {
  try {
    const embedding = await embedQuery(question);
    const children  = await searchChildren(embedding, gameType, role, phase);
    if (!children.length) return { context: '', sources: [], found: false };

    const parents = await fetchParents(children);
    return {
      context: buildContext(parents),
      sources: parents.map(p => p.title),
      found:   true,
    };
  } catch (e) {
    console.error('[ragRetriever] 오류:', e.message);
    return { context: '', sources: [], found: false };
  }
}

export { retrieve, embedQuery };
