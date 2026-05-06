-- MOYA RAG schema for Supabase (Postgres + pgvector)
--
-- 신규 Supabase 프로젝트에서 SQL Editor 에 통째로 붙여넣어 한 번 실행한다.
-- 이후 backend/scripts/diagAiRag.js 로 검증, embedKnowledge.js 로 데이터 적재.

------------------------------------------------------------
-- 1. pgvector extension
------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS vector;

------------------------------------------------------------
-- 2. game_rules table
------------------------------------------------------------
-- chunk_id: 지식 베이스의 unique id (parent / child 모두)
-- is_parent: true 면 embedding 없이 본문만 보관, 검색 결과의 parent fetch 시 사용.
--   false (child) 만 embedding 컬럼이 채워져 vector 검색 대상.
-- embedding: gemini-embedding-001 출력 768 dim 벡터.
CREATE TABLE IF NOT EXISTS game_rules (
  chunk_id   text PRIMARY KEY,
  game_type  text NOT NULL,
  role       text NOT NULL DEFAULT 'all',
  phase      text NOT NULL DEFAULT 'all',
  category   text,
  title      text NOT NULL,
  content    text NOT NULL,
  is_parent  boolean NOT NULL DEFAULT false,
  parent_id  text,
  embedding  vector(768)
);

-- 검색 가속: cosine 거리 IVFFlat 인덱스 (수백~수천 청크면 lists=100 충분)
CREATE INDEX IF NOT EXISTS idx_game_rules_embedding
  ON game_rules
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

-- 필터 가속용 보조 인덱스
CREATE INDEX IF NOT EXISTS idx_game_rules_game_type ON game_rules (game_type);
CREATE INDEX IF NOT EXISTS idx_game_rules_role ON game_rules (role);
CREATE INDEX IF NOT EXISTS idx_game_rules_phase ON game_rules (phase);

------------------------------------------------------------
-- 3. match_game_rules RPC
------------------------------------------------------------
-- ragRetriever.js 가 호출하는 RPC.
-- 핵심: role / phase 는 query 인자값과 'all' 모두 매칭되도록 OR 처리.
--   - 런타임이 role='warrior', phase='early' 로 호출하면 그 값 + 'all' 행 모두 후보
--   - KB 가 모두 phase='all' 이어도 hit 가능
-- 단 game_type 은 strict 매칭 (다른 게임 모드 룰 누출 방지).
CREATE OR REPLACE FUNCTION match_game_rules(
  query_embedding vector(768),
  match_threshold float,
  match_count int,
  p_game_type text,
  p_role text,
  p_phase text
)
RETURNS TABLE (
  chunk_id   text,
  parent_id  text,
  title      text,
  content    text,
  similarity float
)
LANGUAGE sql STABLE
AS $$
  SELECT
    gr.chunk_id,
    gr.parent_id,
    gr.title,
    gr.content,
    1 - (gr.embedding <=> query_embedding) AS similarity
  FROM game_rules gr
  WHERE
    gr.is_parent = false
    AND gr.embedding IS NOT NULL
    AND gr.game_type = p_game_type
    AND (gr.role = p_role OR gr.role = 'all')
    AND (gr.phase = p_phase OR gr.phase = 'all')
    AND 1 - (gr.embedding <=> query_embedding) > match_threshold
  ORDER BY gr.embedding <=> query_embedding ASC
  LIMIT match_count;
$$;

------------------------------------------------------------
-- 4. 권한
------------------------------------------------------------
-- service_role 만 INSERT/UPSERT 한다 (embedKnowledge.js 가 SUPABASE_SERVICE_KEY 로 접근).
-- anon 에는 권한 부여 안 함 — 백엔드만 거쳐서 사용.
GRANT SELECT, INSERT, UPDATE, DELETE ON game_rules TO service_role;
GRANT EXECUTE ON FUNCTION match_game_rules(vector, float, int, text, text, text) TO service_role;
