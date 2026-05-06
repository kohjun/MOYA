import { GoogleGenerativeAI, TaskType } from '@google/generative-ai';
import { createClient } from '@supabase/supabase-js';

import { getParentChunk } from './knowledgeBase/index.js';

// Lazy init — module load 시점에 env 가 비어 있어도 import 단계 throw 를 막는다.
// 운영 런타임에서는 dotenv.config() (server.js) 후 첫 retrieve() 호출 시점에 client 가 만들어진다.
// 테스트 런타임에서 retrieve() 를 호출하지 않는 한 supabase 연결이 생성되지 않는다.
let _genAI = null;
let _supabase = null;

function getGenAI() {
  if (!_genAI) {
    _genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
  }
  return _genAI;
}

function getSupabase() {
  if (!_supabase) {
    _supabase = createClient(
      process.env.SUPABASE_URL,
      process.env.SUPABASE_SERVICE_KEY,
    );
  }
  return _supabase;
}

const EMBED_MODEL = 'gemini-embedding-001';
const TABLE_NAME = 'game_rules';
const TOP_K = 5;
// 한국어 단문 질의는 gemini-embedding-001 cosine 이 0.5~0.6 대로 떨어지는 케이스가 흔해
// 0.65 였을 때 hit-rate 가 너무 낮았다. 0.5 로 완화 + RPC 의 role/phase 'all' 폴백과
// 결합해 일반적인 게임 룰 질문이 안전하게 매칭되도록 조정.
const MIN_SIMILARITY = 0.5;
// embedKnowledge.js 와 동일 차원으로 호출해야 retrieval 가능 (스키마 vector(768)).
const EMBED_DIM = 768;

function isGeminiCredentialError(error) {
  const message = `${error?.message ?? ''}`;
  return (
    message.includes('API key was reported as leaked') ||
    message.includes('403 Forbidden') ||
    message.includes('API_KEY_INVALID') ||
    message.includes('PERMISSION_DENIED')
  );
}

async function embedQuery(text) {
  const embedModel = getGenAI().getGenerativeModel({ model: EMBED_MODEL });
  // 질의 측은 RETRIEVAL_QUERY taskType 으로 호출 — 문서 측은 RETRIEVAL_DOCUMENT.
  // 둘을 다르게 주는 것이 Gemini embedding 의 retrieval 정확도를 높이는 권장 패턴.
  const result = await embedModel.embedContent({
    content: { parts: [{ text }] },
    taskType: TaskType.RETRIEVAL_QUERY,
    outputDimensionality: EMBED_DIM,
  });
  return result.embedding.values;
}

async function searchChildren(embedding, gameType, role, phase) {
  const { data, error } = await getSupabase().rpc('match_game_rules', {
    query_embedding: embedding,
    match_threshold: MIN_SIMILARITY,
    match_count: TOP_K,
    p_game_type: gameType,
    p_role: role,
    p_phase: phase,
  });

  if (error) {
    console.error('[ragRetriever] search error:', error.message);
    return [];
  }

  return data || [];
}

async function fetchParents(childChunks) {
  const parentIds = [
    ...new Set(childChunks.map((chunk) => chunk.parent_id).filter(Boolean)),
  ];

  if (!parentIds.length) return childChunks;

  const { data, error } = await getSupabase()
    .from(TABLE_NAME)
    .select('chunk_id, title, content')
    .in('chunk_id', parentIds);

  if (error || !data?.length) {
    return parentIds
      .map((id) => getParentChunk(id))
      .filter(Boolean)
      .map((chunk) => ({
        chunk_id: chunk.chunkId,
        title: chunk.title,
        content: chunk.content,
      }));
  }

  return data;
}

function buildContext(parentDocs) {
  if (!parentDocs?.length) return '';
  return parentDocs
    .map((doc, index) => `[관련 규칙 ${index + 1}: ${doc.title}]\n${doc.content}`)
    .join('\n\n---\n\n');
}

async function retrieve(question, gameType, role = 'all', phase = 'all') {
  try {
    if (!process.env.GEMINI_API_KEY) {
      return { context: '', sources: [], found: false };
    }

    const embedding = await embedQuery(question);
    const children = await searchChildren(embedding, gameType, role, phase);
    if (!children.length) {
      return { context: '', sources: [], found: false };
    }

    const parents = await fetchParents(children);
    return {
      context: buildContext(parents),
      sources: parents.map((parent) => parent.title),
      found: true,
    };
  } catch (error) {
    if (isGeminiCredentialError(error)) {
      console.warn('[ragRetriever] Gemini embedding unavailable:', error.message);
    } else {
      console.error('[ragRetriever] error:', error.message);
    }

    return { context: '', sources: [], found: false };
  }
}

export { retrieve, embedQuery };
