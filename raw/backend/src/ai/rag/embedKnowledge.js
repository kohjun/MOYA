// src/ai/rag/embedKnowledge.js
//
// 실행: node src/ai/rag/embedKnowledge.js
// 규칙이 바뀌거나 새 게임 추가 시에만 실행합니다.
// 임베딩 모델: gemini-embedding-001 (768차원, Gemini)

import dotenv from 'dotenv';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.resolve(__dirname, '../../../.env') });

import { GoogleGenerativeAI }             from '@google/generative-ai';
import { createClient }                   from '@supabase/supabase-js';
import { getEmbeddableChunks, ALL_CHUNKS } from './knowledgeBase/index.js';

const genAI    = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);

const EMBED_MODEL = 'gemini-embedding-001';
const TABLE_NAME  = 'game_rules';

async function embedText(text) {
  const model  = genAI.getGenerativeModel({ model: EMBED_MODEL });
  const result = await model.embedContent(text);
  return result.embedding.values;
}

async function main() {
  console.log('📚 지식 베이스 임베딩 시작...');
  console.log(`   모델: ${EMBED_MODEL} (768차원)`);
  console.log(`   전체 청크: ${ALL_CHUNKS.length}개`);

  const embeddable = getEmbeddableChunks();
  console.log(`   임베딩 대상 (자식 청크): ${embeddable.length}개`);

  // 기존 데이터 삭제 후 재삽입
  await supabase.from(TABLE_NAME).delete().neq('chunk_id', '');

  // 부모 문서 먼저 삽입 (embedding 없이)
  const parents = ALL_CHUNKS.filter(c => c.isParent);
  console.log(`\n1️⃣  부모 문서 삽입: ${parents.length}개`);

  for (const chunk of parents) {
    const { error } = await supabase.from(TABLE_NAME).insert({
      chunk_id:  chunk.chunkId,
      game_type: chunk.gameType,
      role:      chunk.role,
      phase:     chunk.phase,
      category:  chunk.category,
      title:     chunk.title,
      content:   chunk.content,
      is_parent: true,
      parent_id: null,
      embedding:  null,
    });
    if (error) console.error(`  ❌ ${chunk.chunkId}:`, error.message);
    else       console.log(`  ✅ ${chunk.chunkId}`);
  }

  // 자식 청크 임베딩 후 삽입
  console.log(`\n2️⃣  자식 청크 임베딩: ${embeddable.length}개`);

  let success = 0;
  for (const chunk of embeddable) {
    try {
      const embedding = await embedText(chunk.embedText);

      const { error } = await supabase.from(TABLE_NAME).insert({
        chunk_id:  chunk.chunkId,
        game_type: chunk.gameType,
        role:      chunk.role,
        phase:     chunk.phase,
        category:  chunk.category,
        title:     chunk.title,
        content:   chunk.content,
        is_parent: false,
        parent_id: chunk.parentId,
        embedding,
      });

      if (error) console.error(`  ❌ ${chunk.chunkId}:`, error.message);
      else { console.log(`  ✅ ${chunk.chunkId}`); success++; }

      await new Promise(r => setTimeout(r, 200)); // rate limit 대응

    } catch (e) {
      console.error(`  ❌ ${chunk.chunkId} 임베딩 실패:`, e.message);
    }
  }

  console.log(`\n✅ 완료: ${success}/${embeddable.length}개 임베딩 저장`);
}

main().catch(console.error);
