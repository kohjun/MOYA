# MOYA

MOYA는 위치 공유, 실시간 세션 관리, 음성 채널 제어, 역할 기반 게임 규칙을 결합한 모바일 멀티플레이 프로젝트입니다.
이 문서는 단순 소개용 README가 아니라, `graphify-out` 분석 결과를 바탕으로 앞으로의 리팩터링과 유지보수가 쉬워지도록 팀의 구조 기준을 정리한 운영 문서입니다.

## 프로젝트 성격

- Flutter 앱이 사용자 경험의 중심입니다.
- Backend는 REST API 서버이면서 동시에 Socket.IO + mediasoup 기반 실시간 게임 런타임입니다.
- PostgreSQL/PostGIS, Redis, FCM, Gemini가 보조 인프라로 연결됩니다.
- 핵심 사용자 흐름은 로그인 → 세션 참가 → 로비 → 게임 시작 → 역할 배정 → 미션/회의/투표 → 음성 채널 제어로 이어집니다.

## graphify-out 기준 현재 진단

`graphify-out`의 2026-04-19 분석 스냅샷 기준:

- 분석 파일 수: 99
- 노드 수: 1009
- 엣지 수: 1391
- 커뮤니티 수: 34
- 노드 분포: Flutter 749, Backend 260
- 핵심 허브: `game_main_screen.dart`, `game_provider.dart`, `socket_service.dart`, `Room.js`

이 분석이 말해주는 핵심은 명확합니다.

- 복잡도는 Flutter 게임 계층에 가장 많이 몰려 있습니다.
- 서버는 게임 조율과 미디어 상태 동기화가 핵심입니다.
- 리팩터링 우선순위는 새 기능 추가보다 “책임 분리”에 두는 편이 효과가 큽니다.

관련 문서:

- [프로젝트 전체 리포트](graphify-out/PROJECT_FULL_REPORT_KO.md)
- [리팩터링 실행 계획](graphify-out/REFACTOR_PLAN_KO.md)
- [인터랙티브 그래프](graphify-out/graph.html)
- [현재 로드맵](docs/refactor-roadmap.md)

## 소스 오브 트루스

- 실제 런타임 코드: `backend/`, `flutter/`
- 구조 분석용 입력 스냅샷: `raw/`
- 구조 분석 산출물: `graphify-out/`

주의:

- 기능 수정은 항상 `backend/`와 `flutter/`에 반영합니다.
- `raw/`와 `graphify-out/`은 분석과 문서화를 위한 산출물이지 운영 코드가 아닙니다.

## 디렉터리 구조

```text
.
├─ backend/
│  └─ src/
│     ├─ config/        # DB, Redis, migration
│     ├─ cron/          # 주기 작업
│     ├─ game/          # 역할, 미션, 투표, 시작 로직
│     ├─ media/         # mediasoup, Room, Peer
│     ├─ middleware/    # 인증 등 공통 미들웨어
│     ├─ routes/        # HTTP API
│     ├─ services/      # 세션, 인증, 알림 등 앱 서비스
│     ├─ websocket/     # Socket.IO 허브, 프로토콜, 핸들러
│     └─ server.js      # 백엔드 진입점
├─ flutter/
│  └─ lib/
│     ├─ core/          # router, 공통 서비스
│     └─ features/      # auth, lobby, game, map, session...
├─ docs/                # 리팩터링/설계 문서
├─ raw/                 # graphify 분석용 스냅샷
└─ graphify-out/        # graphify 결과물
```

## 핵심 런타임 흐름

1. 사용자가 Flutter 앱에서 세션에 참가합니다.
2. 호스트가 게임 시작을 요청합니다.
3. Backend의 `startGameService.js`가 역할 배정, 상태 초기화, 미션 할당을 수행합니다.
4. Socket.IO 이벤트가 Flutter로 전달됩니다.
5. `game_provider.dart`가 서버 이벤트를 앱 상태로 정규화합니다.
6. `game_main_screen.dart`와 하위 위젯이 이를 렌더링합니다.
7. 회의/투표/사망/사보타주 상태에 맞춰 mediasoup 음성 채널이 동기화됩니다.

즉 이 프로젝트는 “위치 공유 기능이 있는 앱”이 아니라, 위치와 음성을 포함한 하나의 실시간 게임 런타임입니다.

## 현재 구조에서 중요한 포인트

이미 일부 1차 분리는 진행되어 있습니다.

- `backend/src/websocket/index.js`는 등록 허브 역할로 축소되어 있고, 실제 이벤트 처리는 `handlers/` 하위 모듈로 나뉘어 있습니다.
- `flutter/lib/features/game/presentation/widgets/`에는 메인 게임 화면에서 분리된 프레젠테이션 위젯이 존재합니다.

하지만 여전히 아래 지점은 유지보수 병목 후보입니다.

- `flutter/lib/features/game/presentation/game_main_screen.dart`
- `flutter/lib/features/game/providers/game_provider.dart`
- `backend/src/media/Room.js`

새 기능을 추가할 때는 위 파일에 책임을 더 쌓는 대신, 먼저 “별도 파일로 분리할 수 있는가”를 검토해야 합니다.

## 설계 원칙

### 1. 한 파일은 한 가지 이유로만 변경되게 만든다

- 화면 조립
- 상태 번역
- 도메인 규칙
- 외부 시스템 연동

이 네 책임은 한 파일에 섞지 않습니다.

### 2. 도메인 이름을 우선한다

`graphify-out`에서 `get()`, `query()`, `build` 같은 일반 이름은 허브처럼 보이는 노이즈를 만들었습니다.
새 코드는 가능한 한 의도가 드러나는 이름을 사용합니다.

좋은 예:

- `fetchSessionMembers`
- `normalizeGameState`
- `emitMeetingStarted`
- `syncMediaRoomState`

피해야 할 예:

- `getData`
- `handleThing`
- `common`
- `utils`
- `index`만으로 의미를 대신하는 파일

### 3. 부작용은 경계에서만 실행한다

- Widget은 네트워크 호출과 게임 규칙 계산을 직접 하지 않습니다.
- Provider는 가능한 한 상태 조합과 번역에 집중합니다.
- Service는 외부 SDK와 연결만 담당하고 UI 구조를 알지 않습니다.
- Backend의 route/socket handler는 입출력 조율을 담당하고, 규칙은 도메인 서비스에 위임합니다.

### 4. 계약은 코드와 함께 관리한다

특히 Socket.IO 이벤트는 서버와 Flutter가 함께 의존하므로 다음을 지킵니다.

- 이벤트 이름은 중앙화된 상수 또는 명시적 계약 파일에서 관리합니다.
- payload 구조가 바뀌면 양쪽 소비 지점과 문서를 동시에 수정합니다.
- “일단 맞춰 보자”식의 암묵적 필드 추가를 피합니다.

### 5. 큰 리팩터링은 동작 보존부터 시작한다

- 먼저 헬퍼, 위젯, 핸들러, 계산기를 분리합니다.
- 그 다음 책임 경계를 정리합니다.
- 마지막으로 계약과 테스트를 보강합니다.

한 번에 구조와 동작을 모두 크게 바꾸는 방식은 지양합니다.

## 계층별 책임 규칙

| 계층 | 주 책임 | 대표 위치 | 알면 되는 것 | 알면 안 되는 것 |
| --- | --- | --- | --- | --- |
| Presentation | 화면 조립, 사용자 입력, 렌더링 | `flutter/lib/features/*/presentation` | View state, UI action | DB 쿼리, 직접적인 socket payload 해석 |
| Provider/Application | 상태 번역, 오케스트레이션, 흐름 제어 | `flutter/lib/features/*/providers` | 도메인 모델, 서비스, 상태 전이 | 구체적인 위젯 레이아웃 |
| Domain | 역할/미션/투표/규칙 계산 | `backend/src/game`, 일부 Flutter domain model | 규칙, 정책, 상태 전이 | Flutter/Fastify/Socket.IO SDK 세부 구현 |
| Infrastructure | DB, Redis, mediasoup, FCM, 외부 API | `backend/src/config`, `backend/src/media`, `flutter/lib/core/services` | 외부 시스템 연결 | 화면 조립, 게임 정책 결정 |

## Flutter 분리 기준

### `presentation/`

- 화면 조립만 담당합니다.
- 큰 화면은 섹션 위젯, 오버레이 위젯, 액션 위젯으로 먼저 나눕니다.
- `ref.listen` 같은 상태 반응이 커지면 별도 코디네이터/헬퍼로 분리합니다.

### `providers/`

- 서버 이벤트를 “앱이 이해하는 상태”로 번역합니다.
- 위치 기반 계산, 미션 판정, 이벤트 구독 등록이 커지면 별도 계산기/구독기/정규화기로 분리합니다.
- Widget 세부사항을 알지 않도록 유지합니다.

### `core/services/`

- Socket, 위치, 알림, 오디오, 앱 초기화처럼 외부 시스템 연결만 담당합니다.
- Riverpod 화면 상태와 UI 문구를 직접 포함하지 않습니다.

## Backend 분리 기준

### `routes/`

- HTTP 요청/응답과 인증, 검증, 서비스 호출만 담당합니다.
- SQL과 비즈니스 규칙을 라우트 파일에 직접 흩뿌리지 않습니다.

### `websocket/`

- `index.js`는 연결 생성과 핸들러 등록 허브 역할만 유지합니다.
- 새 이벤트는 `handlers/` 하위 도메인 파일에 추가합니다.
- 이벤트 상수와 런타임 헬퍼는 중앙 모듈에 둡니다.

### `game/`

- 역할 배정, 미션, 회의, 투표, 쿨다운, 라운드 전이 같은 규칙을 담당합니다.
- 가능하면 프레임워크 비의존 로직으로 유지합니다.

### `media/`

- mediasoup 실행과 방/피어 상태 동기화를 담당합니다.
- 음성 채널 실행은 여기서 하되, “왜 mute/unmute 해야 하는가”의 정책은 게임 규칙에서 결정되게 유지합니다.

## 리팩터링 우선순위

### 1. `game_main_screen.dart`

우선 분리할 것:

- 오버레이
- 액션 버튼
- 상태 반응 로직
- 섹션별 화면 조립

하지 말아야 할 것:

- 새 게임 규칙을 화면 파일에 직접 추가
- socket payload 해석 로직을 widget 안으로 끌어오기

### 2. `game_provider.dart`

우선 분리할 것:

- 소켓 이벤트 구독 등록
- 서버 상태 정규화
- 위치 기반 미션 계산
- 스폰/판정 보조 로직

하지 말아야 할 것:

- UI 문구와 화면 분기 책임 추가
- 서비스 호출과 렌더링 규칙 결합

### 3. `Room.js`

우선 분리할 것:

- 방/피어 상태 관리
- 게임 정책에 따른 음성 적용 규칙
- 외부 이벤트에 대한 mediasoup 실행 로직

하지 말아야 할 것:

- 게임 규칙 판단과 미디어 명령을 한 메서드에 과도하게 섞기

### 4. `websocket/`

현재처럼 아래 구조를 유지합니다.

- `index.js`: 허브
- `socketProtocol.js`: 이벤트 계약
- `socketRuntime.js`: 공통 런타임 헬퍼
- `handlers/*`: 도메인별 이벤트 처리

새 기능이 생겨도 다시 단일 대형 파일로 회귀하지 않게 합니다.

## 로컬 실행

### 필수 도구

- Node.js
- Flutter SDK
- Docker Desktop

### 인프라 실행

```bash
docker compose up -d
```

기본 인프라:

- PostgreSQL/PostGIS: `localhost:5433`
- Redis: `localhost:6379`
- Redis Commander: `localhost:8081`

### Backend 실행

```bash
cd backend
npm install
npm run migrate
npm run dev
```

### Flutter 실행

```bash
cd flutter
flutter pub get
flutter run
```

## `backend/.env` 예시

아래는 로컬 개발용 예시입니다. 실제 비밀값은 커밋하지 않습니다.

```env
NODE_ENV=development
PORT=3000
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080

DB_HOST=localhost
DB_PORT=5433
DB_NAME=location_sharing
DB_USER=postgres
DB_PASSWORD=postgres1234

REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=redis1234

JWT_SECRET=change-me
JWT_EXPIRES_IN=7d

GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json

MEDIASOUP_LISTEN_IP=0.0.0.0
MEDIASOUP_ANNOUNCED_IP=127.0.0.1
MEDIASOUP_WORKER_COUNT=1
MEDIASOUP_RTC_MIN_PORT=40000
MEDIASOUP_RTC_MAX_PORT=40100

LLM_PROVIDER=gemini
GEMINI_API_KEY=
GEMINI_MODEL=
LOCAL_LLM_URL=
LOCAL_LLM_MODEL=

SUPABASE_URL=
SUPABASE_SERVICE_KEY=
```

참고:

- Gemini, Supabase, Firebase 계열 값은 사용하는 기능이 있을 때만 채웁니다.
- 로컬 비밀 파일은 버전 관리 대상에서 제외하는 것이 원칙입니다.

## 새 기능 추가 전 체크리스트

- 이 로직은 화면, 상태 번역, 도메인 규칙, 인프라 중 어디에 속하는가?
- 기존 허브 파일에 책임을 더 쌓지 않고 별도 파일로 분리할 수 있는가?
- 새 Socket.IO 이벤트라면 계약 파일과 양쪽 소비 지점을 함께 바꾸는가?
- 일반 이름 대신 도메인 이름으로 설명 가능한가?
- 구조 변경과 동작 변경을 한 번에 과하게 섞지 않았는가?

## 권장 작업 순서

새 요구사항이 들어오면 아래 순서를 기본으로 따릅니다.

1. 영향 받는 계층을 먼저 정합니다.
2. payload/상태 전이/도메인 모델을 먼저 정리합니다.
3. 순수 계산 로직을 분리합니다.
4. Provider나 handler에 연결합니다.
5. 마지막에 화면과 입출력을 붙입니다.

## 유지보수 원칙

- 큰 화면 파일을 더 키우기보다 하위 위젯과 상태 반응 단위로 분리합니다.
- 이벤트가 늘어날수록 중앙 허브가 아니라 도메인 핸들러를 늘립니다.
- “빨리 붙이는 코드”보다 “다음 변경 때 덜 아픈 코드”를 선택합니다.
- 구조가 바뀌면 `docs/`와 `graphify-out` 기반 문서도 함께 갱신합니다.

## 읽기 순서 추천

프로젝트를 처음 파악할 때는 아래 순서를 권장합니다.

1. 이 `README.md`
2. `graphify-out/PROJECT_FULL_REPORT_KO.md`
3. `backend/src/server.js`
4. `backend/src/websocket/`
5. `flutter/lib/app.dart`
6. `flutter/lib/features/game/providers/game_provider.dart`
7. `flutter/lib/features/game/presentation/game_main_screen.dart`

## 결론

이 프로젝트는 이미 좋은 기능 단위 구조를 상당 부분 갖추고 있습니다. 다만 복잡도가 높은 게임 런타임 특성상, 몇몇 허브 파일에 책임이 다시 몰리기 쉬운 형태입니다.
앞으로의 유지보수 방향은 새 기능을 무작정 덧붙이는 것이 아니라, `game_main_screen.dart`, `game_provider.dart`, `Room.js`, `websocket/` 경계를 계속 더 선명하게 만드는 데 맞춰야 합니다.
