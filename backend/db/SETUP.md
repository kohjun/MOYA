# Supabase RAG 셋업 가이드

기존 Supabase 프로젝트가 사라져 (`ENOTFOUND kqasmgovxrmzrskwoboa.supabase.co`) RAG 가
작동하지 않던 상태. 새 프로젝트를 띄우고 데이터 적재까지 5단계로 처리한다.

---

## 1. 새 Supabase 프로젝트 생성

1. https://supabase.com/dashboard → **New project**
2. region: 서버와 가까운 곳 (예: ap-northeast-2 Seoul)
3. password 메모해두고 생성. 셋업 완료까지 1~2분 대기

## 2. 스키마 + RPC 적재

1. 프로젝트 대시보드 → **SQL Editor** 진입
2. `backend/db/schema.sql` 내용 통째로 복사 → 붙여넣기 → Run
3. 출력에 `Success. No rows returned` 또는 별다른 에러 없으면 OK
4. **Database → Tables** 에 `game_rules` 가 보이고, **Database → Functions** 에
   `match_game_rules` 가 보이는지 확인

## 3. .env 갱신

1. 프로젝트 대시보드 → **Project Settings → API**
2. 다음 두 값 복사:
   - `Project URL` → `SUPABASE_URL`
   - `service_role` key → `SUPABASE_SERVICE_KEY` (anon key 가 아님 주의)
3. `backend/.env` 파일에서 두 변수 갱신

## 4. 지식 베이스 임베딩 적재

```bash
cd backend
node src/ai/rag/embedKnowledge.js
```

처음 적재라면 args 없이 실행 (모든 game_type 처리). 약 1~2분 소요.

### 부분 적재 (특정 게임만)

```bash
# fantasy_wars_artifact 의 chunks 만 UPSERT
node src/ai/rag/embedKnowledge.js --game fantasy_wars_artifact

# 청크 제거/이름변경 반영하려면 해당 game 의 기존 row 삭제 후 재삽입
node src/ai/rag/embedKnowledge.js --game fantasy_wars_artifact --force
```

기본은 `UPSERT` 라 변경된 chunk_id 만 비용 발생, 빈 테이블 윈도우 없음.

## 5. 검증

```bash
node scripts/diagAiRag.js
```

기대 출력:
- `total rows: <0 보다 큰 값>`
- `game_type 종류: ["fantasy_wars_artifact"]` (혹은 추가된 게임 포함)
- `A) 런타임 실제 값 found=true`
- 진단 요약: `✅ RAG 정상 동작`

found=false 가 보이면 — RPC threshold/필터 mismatch. 진단 스크립트의 시나리오 B/C/D
결과를 보고 원인 파악.

---

## 운영 배포 시나리오

### 게임 룰만 바뀐 경우
```bash
node src/ai/rag/embedKnowledge.js --game <game_id>
```
- UPSERT 라 zero-downtime
- 변경된 chunk 만 Gemini API 호출 (chunk_id 기준 conflict)

### 게임 청크가 삭제되거나 이름이 바뀐 경우
```bash
node src/ai/rag/embedKnowledge.js --game <game_id> --force
```
- 해당 game_type 의 row 만 DELETE 후 INSERT
- 다른 게임은 영향 없음

### 새 게임 추가
1. `src/ai/rag/knowledgeBase/<게임id>/rules.js` 작성 (chunks 에 `gameType: '<게임id>'`)
2. `knowledgeBase/index.js` 의 `ALL_CHUNKS` spread 에 추가
3. `node src/ai/rag/embedKnowledge.js --game <게임id>`
4. 스키마/RPC: 변경 없음 (game_type 컬럼이 자동으로 격리)

---

## 트러블슈팅

### `count error: TypeError: fetch failed` / `ENOTFOUND`
→ `SUPABASE_URL` 이 잘못되었거나 프로젝트가 삭제됨. 1단계부터 재실행.

### `match_game_rules does not exist`
→ 스키마 SQL 이 적재되지 않음. 2단계 SQL Editor 에서 다시 실행.

### `0 rows in game_rules`
→ embedKnowledge.js 가 실행되지 않았거나 실패. 4단계 재실행 + stderr 확인.

### `retrieve found=false 인데 데이터는 있음`
→ similarity threshold 가 너무 빡셈. `ragRetriever.js` 의 `MIN_SIMILARITY` 값 확인
   (현재 0.5 로 완화되어 있음).
→ 또는 game_type / role / phase 가 실제 KB 와 다름. 진단 스크립트의 시나리오 A vs C
   결과 비교로 어떤 mismatch 인지 파악.
