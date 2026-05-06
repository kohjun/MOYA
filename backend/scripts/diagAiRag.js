// scripts/diagAiRag.js
//
// AI Director RAG 진단:
//   1. 필요한 env 변수 존재 확인
//   2. Supabase game_rules 테이블 row 수 + game_type / phase / role distinct 값
//   3. retrieve() 4가지 시나리오 비교 (game_type 일치 vs 불일치, phase 'all' vs 'early')
//   4. 최종 진단 요약
//
// 실행: node scripts/diagAiRag.js
// (.env 의 GEMINI_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_KEY 사용)

import dotenv from 'dotenv';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.resolve(__dirname, '../.env') });

import { createClient } from '@supabase/supabase-js';
import { retrieve } from '../src/ai/rag/ragRetriever.js';

function badge(ok) {
  return ok ? '✅' : '❌';
}

function maskKey(value, leadKeep = 6, tailKeep = 4) {
  if (!value) return '<unset>';
  if (value.length <= leadKeep + tailKeep) return value;
  return `${value.slice(0, leadKeep)}…${value.slice(-tailKeep)}`;
}

async function checkEnv() {
  console.log('━━━ 1. ENV 변수 ━━━');
  const required = ['GEMINI_API_KEY', 'SUPABASE_URL', 'SUPABASE_SERVICE_KEY'];
  let allOk = true;
  for (const key of required) {
    const v = process.env[key];
    const ok = Boolean(v && v.length > 0);
    console.log(`  ${badge(ok)} ${key}: ${ok ? maskKey(v) : '(누락)'}`);
    if (!ok) allOk = false;
  }
  return allOk;
}

async function checkSupabase() {
  console.log('\n━━━ 2. Supabase game_rules 테이블 ━━━');
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_KEY) {
    console.log('  ❌ Supabase env 누락 — 건너뜀');
    return null;
  }
  const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_KEY,
  );

  // total count
  let count = null;
  let countErr = null;
  try {
    const res = await supabase
      .from('game_rules')
      .select('*', { count: 'exact', head: true });
    count = res.count;
    countErr = res.error;
  } catch (e) {
    countErr = e;
  }
  if (countErr) {
    console.log(`  ❌ count error: ${countErr.message ?? countErr}`);
    if (countErr.cause) console.log(`     cause: ${countErr.cause.message ?? countErr.cause}`);
    if (countErr.code) console.log(`     code: ${countErr.code}`);
    // Probe the URL reachability with a plain fetch.
    try {
      const url = process.env.SUPABASE_URL.replace(/\/$/, '') + '/rest/v1/';
      const probe = await fetch(url, {
        method: 'GET',
        headers: {
          apikey: process.env.SUPABASE_SERVICE_KEY,
          Authorization: `Bearer ${process.env.SUPABASE_SERVICE_KEY}`,
        },
      });
      console.log(`  🔎 raw probe ${url} → ${probe.status} ${probe.statusText}`);
    } catch (e) {
      console.log(`  🔎 raw probe failed: ${e.message}`);
      if (e.cause) console.log(`      cause: ${e.cause.message ?? e.cause}`);
    }
    return null;
  }
  console.log(`  📊 total rows: ${count}`);
  if (count === 0) {
    console.log('  ⚠️  데이터 없음 — `node src/ai/rag/embedKnowledge.js` 실행 필요');
    return { count: 0 };
  }

  // distinct game_type / phase / role
  const { data: sample, error: sErr } = await supabase
    .from('game_rules')
    .select('game_type, role, phase, is_parent')
    .limit(500);
  if (sErr) {
    console.log(`  ❌ sample error: ${sErr.message}`);
    return { count };
  }
  const types = [...new Set(sample.map((r) => r.game_type))];
  const roles = [...new Set(sample.map((r) => r.role))];
  const phases = [...new Set(sample.map((r) => r.phase))];
  const parents = sample.filter((r) => r.is_parent).length;
  const children = sample.filter((r) => !r.is_parent).length;

  console.log(`  📋 game_type 종류: ${JSON.stringify(types)}`);
  console.log(`  📋 role 종류: ${JSON.stringify(roles)}`);
  console.log(`  📋 phase 종류: ${JSON.stringify(phases)}`);
  console.log(`  📋 parents=${parents}, children(임베딩 대상)=${children}`);
  return { count, types, roles, phases };
}

async function probeRetrieve(label, question, gameType, role, phase) {
  console.log(`\n  ▶ "${label}"`);
  console.log(`    args: question="${question}", gameType="${gameType}", role="${role}", phase="${phase}"`);
  const start = Date.now();
  const result = await retrieve(question, gameType, role, phase);
  const ms = Date.now() - start;
  console.log(`    found=${result.found}, sources=${JSON.stringify(result.sources)}, contextLen=${result.context?.length ?? 0}, ${ms}ms`);
  if (result.found) {
    console.log(`    [context preview] ${result.context.slice(0, 200).replace(/\n/g, ' ')}…`);
  }
  return result;
}

async function checkRetrieve(supabaseInfo) {
  console.log('\n━━━ 3. retrieve() 시나리오 비교 ━━━');
  if (!supabaseInfo || supabaseInfo.count === 0) {
    console.log('  ⏭ Supabase 비어 있음 — 스킵');
    return;
  }

  const q = '점령은 어떻게 하나요?';

  // 시나리오 A: 런타임이 실제로 보내는 값 (gameType=fantasy_wars_artifact, phase=early)
  const a = await probeRetrieve(
    'A) 런타임 실제 값',
    q,
    'fantasy_wars_artifact',
    'all',
    'early',
  );

  // 시나리오 B: gameType 만 KB 표기로 맞춤 (fantasy_wars)
  const b = await probeRetrieve(
    'B) gameType 만 KB 값으로',
    q,
    'fantasy_wars',
    'all',
    'early',
  );

  // 시나리오 C: phase 도 'all' 로 (KB 가 모두 phase=all 이므로)
  const c = await probeRetrieve(
    'C) gameType+phase 모두 KB 값으로',
    q,
    'fantasy_wars',
    'all',
    'all',
  );

  // 시나리오 D: 다른 질문 (음성 검증, 옛 KB 값으로 일부러 호출 → 0건이 정답)
  const d = await probeRetrieve(
    'D) 옛 game_type 으로 결투 질문 (음성)',
    '결투에서 마법사는 뭘 할 수 있어?',
    'fantasy_wars',
    'all',
    'all',
  );

  // 시나리오 E: role 분화 검증 — mage 로 마법사 질문 → mage chunk + 'all' chunk 둘 다 hit 해야
  const e = await probeRetrieve(
    'E) 직업별 분화 검증 (role=mage)',
    '봉쇄 마법은 어떻게 작동해?',
    'fantasy_wars_artifact',
    'mage',
    'mid',
  );

  // 시나리오 F: 직업 미상 (role=all) 일반 질문 → 'all' chunk 만 매칭
  const f = await probeRetrieve(
    'F) role=all 로 봉쇄 질문',
    '봉쇄 마법은 어떻게 작동해?',
    'fantasy_wars_artifact',
    'all',
    'mid',
  );

  return { a, b, c, d, e, f };
}

async function summarize(envOk, supabaseInfo, retrieveResults) {
  console.log('\n━━━ 4. 진단 요약 ━━━');
  if (!envOk) {
    console.log('  ❌ env 변수 누락 — .env 파일 확인 필요');
    return;
  }
  if (!supabaseInfo || supabaseInfo.count === 0) {
    console.log('  ❌ Supabase 데이터 없음 — `node src/ai/rag/embedKnowledge.js` 실행 필요');
    return;
  }

  const r = retrieveResults ?? {};
  console.log(`  A (런타임 실제 값)            found=${r.a?.found}, sources=${r.a?.sources?.length ?? 0}`);
  console.log(`  B (옛 gameType, phase=early)  found=${r.b?.found}  ← 0건이 정답 (음성 검증)`);
  console.log(`  C (옛 gameType, phase=all)    found=${r.c?.found}  ← 0건이 정답 (음성 검증)`);
  console.log(`  D (옛 gameType, 결투 질문)    found=${r.d?.found}  ← 0건이 정답 (음성 검증)`);
  console.log(`  E (role=mage 봉쇄 질문)       found=${r.e?.found}, sources=${r.e?.sources?.length ?? 0}`);
  console.log(`  F (role=all 봉쇄 질문)        found=${r.f?.found}, sources=${r.f?.sources?.length ?? 0}`);

  // 직업별 분화 효과: E (role=mage) 는 F (role=all) 보다 같거나 더 많은 source 를 받아야 함.
  // RPC 가 (role=p_role OR role='all') 폴백을 하므로 E ⊇ F.
  const eCount = r.e?.sources?.length ?? 0;
  const fCount = r.f?.sources?.length ?? 0;
  const roleSplitOk = r.e?.found && eCount >= fCount;

  // B/C/D 는 의도적 음성 검증 — found=false 가 정답.
  const negativesOk = !r.b?.found && !r.c?.found && !r.d?.found;

  if (r.a?.found && negativesOk && roleSplitOk) {
    console.log('  ✅ RAG 정상. game_type 격리 OK, 직업별 분화 OK (E ≥ F sources).');
  } else if (r.a?.found && negativesOk) {
    console.log('  ⚠️  기본 검색은 OK 인데 직업별 분화 효과 약함 (E sources < F).');
    console.log('     원인 후보: KB 에 mage 전용 chunk 가 없거나 query 가 mage chunk 와 유사도 낮음.');
  } else if (r.a?.found && !negativesOk) {
    console.log('  ⚠️  음성 검증이 실패 (옛 game_type 으로도 hit). game_type 격리에 구멍 있음.');
  } else if (!r.a?.found) {
    console.log('  ❌ 런타임 실제 값으로 retrieve 0건. KB 적재 / RPC 정의 / threshold 점검 필요.');
  }
}

async function main() {
  const envOk = await checkEnv();
  const supabaseInfo = envOk ? await checkSupabase() : null;
  const retrieveResults = envOk && supabaseInfo?.count > 0
    ? await checkRetrieve(supabaseInfo)
    : null;
  await summarize(envOk, supabaseInfo, retrieveResults);
}

main().catch((err) => {
  console.error('\n❌ 진단 스크립트 실패:', err);
  process.exit(1);
});
