// src/ai/rag/embedKnowledge.js
//
// 지식 베이스 → Supabase game_rules 테이블 임베딩 적재.
//
// 사용:
//   node src/ai/rag/embedKnowledge.js
//     → 모든 게임 chunks 를 UPSERT (변경된 chunk 만 비용 발생, 삭제된 row 는 유지)
//   node src/ai/rag/embedKnowledge.js --game fantasy_wars_artifact
//     → 해당 game_type 만 UPSERT
//   node src/ai/rag/embedKnowledge.js --game fantasy_wars_artifact --force
//     → 해당 game_type 의 기존 row 모두 DELETE 후 재삽입 (chunk 제거/이름변경 반영용)
//
// 임베딩 모델: gemini-embedding-001 (768 차원).
// 룰이 바뀐 게임만 부분 적재할 수 있어 배포 시 비용/시간 절약 + zero downtime.

import dotenv from 'dotenv';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.resolve(__dirname, '../../../.env') });

import { GoogleGenerativeAI, TaskType } from '@google/generative-ai';
import { createClient } from '@supabase/supabase-js';
import { ALL_CHUNKS, getEmbeddableChunks } from './knowledgeBase/index.js';

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY,
);

const EMBED_MODEL = 'gemini-embedding-001';
const TABLE_NAME = 'game_rules';
const RATE_LIMIT_MS = 200;
// gemini-embedding-001 의 default 출력은 3072 dim. 우리 스키마는 vector(768) 이므로
// 명시적으로 outputDimensionality 를 넘겨 차원 일치시킴. ragRetriever.js 의 query 측
// 임베딩과 항상 같은 차원으로 호출해야 retrieval 가능.
const EMBED_DIM = 768;

function parseArgs(argv) {
  const args = { game: null, force: false };
  for (let i = 2; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--game' && argv[i + 1]) {
      args.game = argv[i + 1];
      i += 1;
    } else if (a === '--force') {
      args.force = true;
    }
  }
  return args;
}

async function embedText(text) {
  const model = genAI.getGenerativeModel({ model: EMBED_MODEL });
  // outputDimensionality 와 taskType 을 명시: 문서 임베딩은 RETRIEVAL_DOCUMENT 가
  // 권장 (retrieval 품질 ↑). query 측은 ragRetriever.js 가 RETRIEVAL_QUERY 사용.
  const result = await model.embedContent({
    content: { parts: [{ text }] },
    taskType: TaskType.RETRIEVAL_DOCUMENT,
    outputDimensionality: EMBED_DIM,
  });
  return result.embedding.values;
}

function rowFromChunk(chunk, embedding = null) {
  return {
    chunk_id: chunk.chunkId,
    game_type: chunk.gameType,
    role: chunk.role,
    phase: chunk.phase,
    category: chunk.category,
    title: chunk.title,
    content: chunk.content,
    is_parent: !!chunk.isParent,
    parent_id: chunk.parentId ?? null,
    embedding,
  };
}

async function processGame(gameType, force) {
  const allForGame = ALL_CHUNKS.filter((c) => c.gameType === gameType);
  if (!allForGame.length) {
    console.log(`  ⚠️  [${gameType}] chunks 0개 — KB 에 등록 안 된 game_type. 스킵.`);
    return;
  }

  const parents = allForGame.filter((c) => c.isParent);
  const children = getEmbeddableChunks().filter((c) => c.gameType === gameType);
  console.log(`\n📦 [${gameType}] parents=${parents.length}, children=${children.length}`);

  if (force) {
    const { error: delErr } = await supabase
      .from(TABLE_NAME)
      .delete()
      .eq('game_type', gameType);
    if (delErr) {
      console.error(`  ❌ delete 실패: ${delErr.message}`);
      return;
    }
    console.log(`  🧹 [${gameType}] 기존 row 삭제 완료 (--force)`);
  }

  // 부모 문서 UPSERT (embedding 없음)
  console.log(`  1️⃣  부모 UPSERT: ${parents.length}개`);
  for (const chunk of parents) {
    const { error } = await supabase
      .from(TABLE_NAME)
      .upsert(rowFromChunk(chunk, null), { onConflict: 'chunk_id' });
    if (error) console.error(`    ❌ ${chunk.chunkId}: ${error.message}`);
    else console.log(`    ✅ ${chunk.chunkId}`);
  }

  // 자식 청크 임베딩 후 UPSERT
  console.log(`  2️⃣  자식 임베딩 + UPSERT: ${children.length}개`);
  let success = 0;
  for (const chunk of children) {
    try {
      const embedding = await embedText(chunk.embedText);
      const { error } = await supabase
        .from(TABLE_NAME)
        .upsert(rowFromChunk(chunk, embedding), { onConflict: 'chunk_id' });
      if (error) {
        console.error(`    ❌ ${chunk.chunkId}: ${error.message}`);
      } else {
        console.log(`    ✅ ${chunk.chunkId}`);
        success += 1;
      }
      await new Promise((r) => setTimeout(r, RATE_LIMIT_MS));
    } catch (e) {
      console.error(`    ❌ ${chunk.chunkId} 임베딩 실패: ${e.message}`);
    }
  }
  console.log(`  ✅ [${gameType}] ${success}/${children.length} 자식 청크 적재 완료`);
}

async function main() {
  const { game, force } = parseArgs(process.argv);
  console.log('📚 지식 베이스 임베딩 시작');
  console.log(`   모델: ${EMBED_MODEL} (768 dim)`);
  console.log(`   대상: ${game ? `--game ${game}` : '모든 게임'}`);
  console.log(`   모드: ${force ? '--force (DELETE + INSERT)' : 'UPSERT (default)'}`);

  const allTypes = [...new Set(ALL_CHUNKS.map((c) => c.gameType))];
  const targets = game ? [game] : allTypes;
  console.log(`   처리할 game_type: ${JSON.stringify(targets)}`);

  for (const gt of targets) {
    await processGame(gt, force);
  }

  console.log('\n✅ 적재 완료');
}

main().catch((err) => {
  console.error('❌ 실패:', err);
  process.exit(1);
});
