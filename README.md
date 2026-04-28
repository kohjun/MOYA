# MOYA

> **GPS · BLE · UWB 기반 오프라인 상호작용 게임 플랫폼**
> 실제 공간에서 만나고, 마주치고, 겨루는 위치 기반 멀티플레이의 런타임.

MOYA는 화면 안에서 끝나는 모바일 게임이 아닙니다. 플레이어가 **실제 도시 공간을 무대로 움직이며**, GPS로 위치를 공유하고, BLE로 근접을 감지하고, 백엔드의 AI 마스터가 **RAG 기반으로 규칙을 해석**해 실시간으로 게임을 진행시키는 — 오프라인 상호작용 게임 플랫폼입니다.

대표 게임 모드는 **판타지 워즈 — 성유물 쟁탈전(fantasy_wars_artifact)** 과 **컬러 체이서(color_chaser)** 이며, 동일한 플랫폼 위에 새로운 게임을 플러그인으로 얹을 수 있는 구조를 지향합니다.

---

## 1. 프로젝트 소개 및 비전

### 한 줄 정의

> 위치(GPS), 근접(BLE/UWB), 음성(mediasoup), AI(RAG)을 하나의 실시간 런타임으로 묶어, 오프라인 공간에서 진행되는 멀티플레이 게임을 가능하게 하는 플랫폼.

### 비전

- **공간을 게임 보드로**: 실제 공원·캠퍼스·동네가 그대로 게임 맵이 됩니다. 플레이어의 GPS 좌표가 토큰의 위치이고, BLE/UWB 근접이 "마주침" 이벤트입니다.
- **게임 규칙은 데이터, 진행은 AI**: 게임 규칙·아이템·역할은 RAG 지식 베이스에 데이터로 정의됩니다. AI 마스터(AIDirector)가 이를 검색해 상황에 맞는 안내·판정·이벤트를 만들어냅니다.
- **여러 게임을 한 플랫폼 위에**: 게임 모드는 백엔드의 `GamePlugin` 인터페이스와 Flutter의 `GameUiPlugin`을 구현해 추가합니다. 코어 런타임(세션·위치·음성·AI)은 공통, 게임 규칙만 플러그인으로 분리됩니다.
- **오프라인 상호작용 우선**: 화면 탭이 아닌 실제 만남으로 게임이 진행됩니다. BLE 페리페럴/센트럴 듀얼 모드로 같은 공간에 있는 플레이어를 식별하고, 근접 증거(ProximityEvidence)를 서버가 검증합니다.

---

## 2. 아키텍처 및 주요 기술 스택

### 시스템 구성

```
┌──────────────────┐         WebSocket (Socket.IO)
│  Flutter App     │◄──── 게임 상태 / 위치 / 음성 시그널 ─────┐
│  (location_      │                                          │
│   sharing_app)   │◄──── REST (Dio) / FCM Push ──────────┐  │
└──────┬───────────┘                                       │  │
       │                                                   │  │
       │ GPS / BLE / 마이크                                ▼  ▼
       │                              ┌─────────────────────────────┐
       ▼                              │   Backend (Node.js / ESM)   │
   실제 공간                          │  ┌─────────────────────┐    │
   (다른 플레이어와                   │  │ Fastify (REST/Auth) │    │
   BLE 근접 / GPS 좌표)               │  ├─────────────────────┤    │
                                      │  │ Socket.IO Hub       │◄── 세션·게임 이벤트
                                      │  ├─────────────────────┤    │
                                      │  │ mediasoup           │◄── 음성 채널
                                      │  ├─────────────────────┤    │
                                      │  │ Game Plugins        │◄── fantasy_wars_artifact
                                      │  │ (GamePlugin)        │    color_chaser
                                      │  ├─────────────────────┤    │
                                      │  │ AIDirector + RAG    │◄── Gemini
                                      │  └─────────────────────┘    │
                                      └────┬─────────┬────────┬─────┘
                                           ▼         ▼        ▼
                                      PostgreSQL   Redis   Firebase
                                      + PostGIS    (pub/sub) (FCM)
```

### 역할 분담

| 영역 | 책임 |
|------|------|
| **Flutter (frontend)** | 사용자 경험의 중심. 지도/HUD 렌더링, GPS·BLE 센서 수집, 마이크 입출력, 화면 상태 번역. 게임 규칙 판정은 하지 않음. |
| **Backend (runtime)** | 단순 REST 서버가 아니라 **실시간 게임 런타임**. 세션 라이프사이클, 게임 플러그인 실행, 위치 검증, BLE 근접 증거 판정, mediasoup 음성 정책, AI 마스터 진행. |
| **AI Director + RAG** | `backend/src/ai/`. RAG 지식 베이스에서 게임 규칙·아이템·플레이어 컨텍스트를 검색하여 상황별 안내·판정·내러티브를 생성. |
| **인프라** | PostgreSQL/PostGIS(공간 인덱스), Redis(세션 상태·pub/sub·소켓 어댑터), FCM(푸시), Gemini(LLM). |

### 주요 기술 스택

#### Backend (`backend/`)
- **런타임**: Node.js (ESM, `"type": "module"`) · `nodemon` (dev)
- **HTTP**: `fastify@5` + `@fastify/cors` `@fastify/cookie` `@fastify/jwt` `@fastify/multipart` `@fastify/websocket`
- **실시간**: `socket.io@4` + `@socket.io/redis-streams-adapter`
- **WebRTC SFU**: `mediasoup@3`
- **DB / 캐시**: `pg` (PostgreSQL/PostGIS) · `redis@4`
- **외부**: `firebase-admin` (FCM) · `@google/generative-ai` (Gemini RAG) · `@supabase/supabase-js`
- **유틸**: `zod` (스키마 검증) · `node-cron` · `bcrypt` · `jsonwebtoken`

#### Flutter (`flutter/`)
- **상태 관리**: `flutter_riverpod` + `riverpod_annotation`
- **네트워킹**: `dio` · `socket_io_client`
- **지도**: `flutter_naver_map` · `flutter_polyline_points` · `maps_toolkit`
- **위치 / 근접**: `geolocator` (GPS) · `flutter_reactive_ble` (BLE Central) · `flutter_ble_peripheral` (BLE Peripheral)
- **WebRTC**: `mediasoup_client_flutter` · `flutter_webrtc` *(둘 다 `packages/`에 벤더링된 로컬 패키지를 우선 사용)*
- **백그라운드**: `flutter_background_service` · `wakelock_plus` · `battery_plus`
- **UI / 게임**: `flame` (미니게임) · `mobile_scanner` (QR) · `audioplayers` (효과음)
- **푸시 / 저장소**: `firebase_messaging` · `flutter_local_notifications` · `flutter_secure_storage` · `hive_flutter`
- **라우팅 / 코드젠**: `go_router` · `freezed` · `json_serializable`

---

## 3. 핵심 기능

### 3.1 실시간 위치 공유 & 공간 게임 보드

- 플레이어의 GPS 좌표가 `socket.io`로 서버에 스트리밍되고, 서버는 세션 단위로 `visibleLocationSnapshotForUser()`로 가시 범위를 필터링해 재배포합니다.
- 백엔드는 PostgreSQL/PostGIS 기반으로 **세션 영역(playable area)** 을 폴리곤으로 관리하며, 플레이어 이탈·미션 좌표 판정에 활용합니다.
- 클라이언트는 `flutter_background_service`로 화면이 꺼져도 위치 송신을 유지합니다 (Task 2: OS Background Kill 예방).

### 3.2 BLE 기반 오프라인 근접 상호작용

GPS만으로는 "두 사람이 진짜로 같은 자리에 있다"는 사실을 검증할 수 없습니다. MOYA는 BLE를 1차 검증 채널로 씁니다.

- **Peripheral / Central 듀얼 모드**: `FantasyWarsBlePresenceService`가 동일 단말에서 BLE 광고와 스캔을 동시에 수행해, 같은 세션의 다른 플레이어를 RSSI 기준으로 발견합니다.
- **근접 증거(ProximityEvidence)**: 서버의 `backend/src/game/duel/ProximityEvidence.js`가 양쪽 단말의 BLE 관측을 페어 키(`pairKey()`)로 묶어 **상호 관측 + 시간 윈도우 + RSSI 임계** 기준으로만 듀얼·만남 이벤트를 인정합니다.
- **UWB 확장 슬롯**: 현재 메인 채널은 BLE이며, UWB는 정밀 근접이 필요한 게임 모드(예: 1m 이내 듀얼)에서 동일 인터페이스로 추가됩니다.

### 3.3 게임 플러그인 아키텍처

게임 모드는 코어 런타임에서 분리됩니다.

- **백엔드**: `backend/src/game/plugins/<game>/` 에 `index.js` `schema.js` `service.js` `sessionConfig.js` `startValidation.js` 를 두고 `GamePlugin` 인터페이스를 구현합니다.
- **Flutter**: `flutter/lib/features/game/presentation/plugins/<game>/` 에 화면/HUD/Provider를 두고 `_registerGamePlugins(...)`(main.dart)로 `GameUiPlugin`을 등록합니다.

현재 등록된 게임:

| 게임 | 백엔드 위치 | Flutter 위치 | 특징 |
|------|------------|-------------|------|
| **판타지 워즈 — 성유물 쟁탈전** | `backend/src/game/plugins/fantasy_wars_artifact/` | `flutter/lib/features/game/presentation/plugins/fantasy_wars/` | 진영(faction) · 듀얼 · BLE 근접 점유 · 성유물 컨트롤 포인트 |
| **컬러 체이서** | `backend/src/game/plugins/color_chaser/` | `flutter/lib/features/game/presentation/plugins/color_chaser/` | 영역 색칠 · 추격 · 미션·힌트·소거 시스템 |

### 3.4 AI Director (RAG 기반 게임 마스터)

- `backend/src/ai/AIDirector.js`가 진행 허브. `addHistory()` `ask()` `askWithModel()` `askWithRetry()` 등으로 LLM 호출과 컨텍스트 누적을 관리합니다.
- 규칙은 코드가 아닌 **데이터**입니다. `backend/src/ai/rag/knowledgeBase/fantasy_wars/` 같은 게임별 지식 베이스에서 검색해 프롬프트를 구성합니다 (`backend/src/ai/prompt.js`).
- 게임 이벤트(시작/종료/듀얼 결과/성유물 점령)에 반응해 내러티브와 안내를 생성하며, Flutter 측 `ai_master_provider.dart`로 스트리밍됩니다.

### 3.5 mediasoup 기반 음성 채널 + 게임 연동 정책

- 일반 보이스챗이 아니라 **게임 상태에 의존하는 음성 정책**입니다. 회의/투표/사망/사보타주에 따라 mute·채널 격리·서브룸 분리가 자동으로 적용됩니다.
- 서버 측 `backend/src/media/`가 mediasoup 워커/라우터/룸을 관리하고, 클라이언트는 벤더링된 `flutter/packages/mediasoup_client_flutter`로 연결합니다.

### 3.6 세션 라이프사이클 & 푸시

- `sessionService.js`: `createSession()` `joinSession()` `leaveSession()` `generateSessionCode()` `getMySessions()` 등 세션 진입 흐름.
- `cron/sessionCleaner.js`: 만료 세션 정리.
- `firebase-admin` 기반 FCM 푸시(`fcmService`)로 초대·게임 이벤트 알림.

---

## 4. 주요 디렉토리 구조

```text
.
├─ backend/                               # Node.js ESM 실시간 런타임
│  └─ src/
│     ├─ server.js                        # 진입점: Fastify + Socket.IO + mediasoup 부팅
│     ├─ config/
│     │  ├─ database.js                   # PostgreSQL 풀
│     │  ├─ redis.js                      # Redis 클라이언트
│     │  └─ migrate.js                    # 스키마 마이그레이션
│     ├─ middleware/                      # 인증·검증
│     ├─ routes/                          # REST API (sessions, auth, ...)
│     ├─ services/                        # 도메인 서비스
│     │  ├─ sessionService.js             # 세션 CRUD, 팀 정규화, 게임 설정 빌드
│     │  ├─ locationService.js            # 위치 스냅샷, 가시성 필터
│     │  └─ ...
│     ├─ websocket/
│     │  ├─ index.js                      # 등록 허브 (라우팅만)
│     │  ├─ socketProtocol.js             # 이벤트 계약 상수
│     │  ├─ socketRuntime.js              # 공통 런타임 헬퍼
│     │  └─ handlers/                     # 도메인별 이벤트 핸들러
│     │     ├─ sessionHandlers.js
│     │     ├─ gameHandlers.js
│     │     └─ aiHandlers.js
│     ├─ media/                           # mediasoup Room/Peer
│     ├─ game/
│     │  ├─ GamePlugin.js                 # 플러그인 인터페이스
│     │  ├─ index.js                      # 플러그인 레지스트리
│     │  ├─ startGameService.js           # 게임 시작 오케스트레이션
│     │  ├─ duel/                         # BLE 근접 듀얼 시스템
│     │  │  ├─ DuelService.js
│     │  │  ├─ ProximityEvidence.js       # 상호 관측 검증
│     │  │  ├─ TransportAdapter.js
│     │  │  └─ FantasyWarsMinigames.js
│     │  └─ plugins/
│     │     ├─ fantasy_wars_artifact/     # 성유물 쟁탈전
│     │     │  ├─ index.js
│     │     │  ├─ schema.js
│     │     │  ├─ service.js
│     │     │  ├─ sessionConfig.js
│     │     │  └─ startValidation.js
│     │     └─ color_chaser/              # 컬러 체이서
│     ├─ ai/
│     │  ├─ AIDirector.js                 # 게임 마스터 허브
│     │  ├─ prompt.js                     # 프롬프트 빌더
│     │  └─ rag/
│     │     └─ knowledgeBase/
│     │        ├─ index.js
│     │        └─ fantasy_wars/           # 게임별 규칙·아이템 지식
│     └─ cron/                            # 주기 작업 (sessionCleaner 등)
│
├─ flutter/                               # Flutter 클라이언트
│  ├─ lib/
│  │  ├─ main.dart                        # 진입점, 게임 플러그인 등록
│  │  ├─ app.dart                         # Riverpod ProviderScope + go_router
│  │  ├─ core/
│  │  │  └─ services/                     # 외부 시스템 연결만
│  │  │     ├─ fcm_service.dart
│  │  │     ├─ permission_lock.dart
│  │  │     ├─ location_service.dart
│  │  │     └─ fantasy_wars_ble_presence_service.dart   # BLE 듀얼 모드
│  │  └─ features/
│  │     ├─ auth/                         # 로그인
│  │     ├─ home/                         # 세션 목록/생성
│  │     ├─ map/                          # 지도 & 세션 진입
│  │     │  └─ data/map_session_provider.dart
│  │     ├─ session/
│  │     ├─ settings/
│  │     └─ game/
│  │        ├─ providers/                 # 상태 번역 (Riverpod)
│  │        │  ├─ game_provider.dart
│  │        │  ├─ fantasy_wars_provider.dart
│  │        │  ├─ ble_duel_provider.dart
│  │        │  └─ ai_master_provider.dart
│  │        └─ presentation/
│  │           ├─ game_ui_plugin.dart     # 플러그인 인터페이스
│  │           ├─ playable_area_painter_screen.dart
│  │           └─ plugins/
│  │              ├─ fantasy_wars/
│  │              │  ├─ fantasy_wars_game_screen.dart
│  │              │  ├─ fantasy_wars_hud.dart
│  │              │  └─ duel/fw_duel_minigames_v2.dart
│  │              └─ color_chaser/
│  │                 └─ color_chaser_game_screen.dart
│  ├─ packages/                           # 벤더링된 로컬 패키지 (반드시 이 경로 사용)
│  │  ├─ flutter_webrtc/
│  │  └─ mediasoup_client_flutter/
│  ├─ test/
│  └─ pubspec.yaml
│
├─ docs/
│  ├─ fantasy_wars_plugin_architecture.md
│  ├─ fantasy_wars_test_plan.md
│  └─ refactor-roadmap.md
│
├─ raw/                                   # graphify 분석용 스냅샷 (운영 코드 아님)
├─ graphify-out/                          # 지식 그래프 산출물
│  ├─ graph.html
│  ├─ graph.json
│  └─ GRAPH_REPORT.md
│
├─ CLAUDE.md
└─ README.md
```

> **소스 오브 트루스**: 실 런타임 코드는 `backend/`, `flutter/`. `raw/`와 `graphify-out/`는 **분석/문서화 산출물이며 운영 코드가 아닙니다**. 기능 변경은 항상 `backend/`·`flutter/`에 반영합니다.

---

## 5. 설치 및 실행 방법

### 5.1 필수 도구

- **Node.js** 20.x 이상
- **Flutter SDK** 3.2 이상 (`environment.sdk: '>=3.2.0 <4.0.0'`)
- **Docker Desktop** (PostgreSQL/PostGIS · Redis 로컬 인프라용)
- **Android 실기기 또는 iOS 실기기** — BLE 페리페럴/센트럴이 필요하므로 에뮬레이터로는 게임 진행 검증 불가

### 5.2 인프라 부팅

```bash
docker compose up -d
```

기본 포트:

| 서비스 | 포트 |
|--------|------|
| PostgreSQL / PostGIS | `localhost:5433` |
| Redis | `localhost:6379` |
| Redis Commander | `localhost:8081` |

### 5.3 Backend 실행

```bash
cd backend
npm install
npm run migrate     # 스키마 마이그레이션
npm run dev         # nodemon dev 서버
# (배포: npm start)
```

테스트:

```bash
npm test            # node:test (--test-isolation=none)
```

### 5.4 Flutter 실행

```bash
cd flutter
flutter pub get
flutter run         # 연결된 실기기 / Android·iOS 시뮬레이터
```

> **벤더링된 패키지**: `flutter_webrtc`와 `mediasoup_client_flutter`는 `pubspec.yaml`의 `dependency_overrides` 및 `path:` 지정으로 `flutter/packages/` 폴더의 로컬 코드를 사용합니다. pub.dev 캐시 버전이 아니므로 **이 폴더를 지우거나 수정하면 빌드가 깨집니다**.

코드젠이 필요한 경우:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### 5.5 `backend/.env` 예시

로컬 개발 기본값입니다. 실제 비밀값은 절대 커밋하지 않습니다.

```env
NODE_ENV=development
PORT=3000
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080

# PostgreSQL / PostGIS
DB_HOST=localhost
DB_PORT=5433
DB_NAME=location_sharing
DB_USER=postgres
DB_PASSWORD=postgres1234

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=redis1234

# Auth
JWT_SECRET=change-me
JWT_EXPIRES_IN=7d

# Firebase Admin (FCM)
GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json

# mediasoup
MEDIASOUP_LISTEN_IP=0.0.0.0
MEDIASOUP_ANNOUNCED_IP=127.0.0.1            # LAN 테스트 시 PC의 LAN IP로
MEDIASOUP_WORKER_COUNT=1
MEDIASOUP_RTC_MIN_PORT=40000
MEDIASOUP_RTC_MAX_PORT=40100

# AI / RAG
LLM_PROVIDER=gemini
GEMINI_API_KEY=
GEMINI_MODEL=
LOCAL_LLM_URL=
LOCAL_LLM_MODEL=

# Supabase (선택)
SUPABASE_URL=
SUPABASE_SERVICE_KEY=
```

> Gemini·Supabase·Firebase 키는 사용 기능이 있을 때만 채웁니다. `serviceAccountKey.json` 등 로컬 비밀 파일은 `.gitignore` 대상.

### 5.6 실기기 BLE 테스트 시 주의

- **Android**: `BLUETOOTH_ADVERTISE` `BLUETOOTH_SCAN` `BLUETOOTH_CONNECT` 런타임 권한 필수. 위치 권한도 함께 요청됩니다 (BLE 스캔의 OS 요건).
- **iOS**: `Info.plist`에 `NSBluetoothAlwaysUsageDescription` 필요. iOS는 백그라운드 광고 제약이 있으므로 듀얼 검증 시나리오는 포그라운드 기준으로 설계합니다.
- BLE 듀얼 검증은 두 대 이상의 실기기가 필요합니다. 한 대는 페리페럴, 한 대는 센트럴 모드로 동시에 동작해야 `ProximityEvidence`가 페어를 인정합니다.

---

## 6. 정기모임팀 운영 가이드라인 및 특수 세팅

> 이 프로젝트는 정기 모임으로 운영됩니다. 빠른 기능 추가보다 **다음 변경 때 덜 아픈 코드**를 우선합니다.

### 6.1 계층별 책임 규칙

| 계층 | 주 책임 | 위치 | 알면 안 되는 것 |
|------|--------|------|----------------|
| Presentation | 화면 조립, 입력, 렌더링 | `flutter/lib/features/*/presentation` | DB 쿼리, 직접 socket payload 해석 |
| Provider | 상태 번역, 오케스트레이션 | `flutter/lib/features/*/providers` | 위젯 레이아웃 |
| Domain (Game) | 역할·미션·투표·근접·규칙 계산 | `backend/src/game/` | Fastify/Socket.IO/Flutter SDK 세부 |
| Infrastructure | DB/Redis/mediasoup/FCM/외부 API | `backend/src/config`, `backend/src/media`, `flutter/lib/core/services` | 화면 조립, 게임 정책 결정 |

### 6.2 새 기능 추가 전 체크리스트

새 기능을 시작하기 전 반드시 통과시킬 5개 질문:

1. 이 로직은 **화면 / 상태 번역 / 도메인 규칙 / 인프라** 중 어디에 속하는가?
2. 기존 허브 파일에 책임을 더 쌓지 않고 별도 파일로 분리할 수 있는가?
3. 새 Socket.IO 이벤트라면 `socketProtocol.js`와 양쪽 소비 지점을 함께 바꾸는가?
4. 일반 이름(`getData`, `handleThing`) 대신 **도메인 이름**(`fetchSessionMembers`, `emitDuelResult`)으로 설명 가능한가?
5. 구조 변경과 동작 변경을 한 번에 과하게 섞지 않았는가?

### 6.3 새 게임 모드 추가 흐름

기존 `fantasy_wars_artifact` 구현을 참고 모델로 사용합니다.

1. `backend/src/game/plugins/<new_game>/` 생성 — `schema.js`, `sessionConfig.js`, `startValidation.js`, `service.js`, `index.js`.
2. `backend/src/game/index.js`에 플러그인 등록.
3. AI 마스터를 사용한다면 `backend/src/ai/rag/knowledgeBase/<new_game>/`에 규칙·아이템 지식 베이스 추가.
4. `flutter/lib/features/game/presentation/plugins/<new_game>/` 에 게임 화면·HUD·전용 Provider 추가.
5. `flutter/lib/main.dart`의 `_registerGamePlugins(...)`에 `GameUiPlugin` 등록.
6. `docs/`에 플러그인 아키텍처 노트 추가 (`fantasy_wars_plugin_architecture.md` 형식 준수).
7. `flutter/test/features/game/<new_game>_provider_test.dart` 등 단위 테스트 추가.

### 6.4 Socket.IO 이벤트 계약 운영

- 이벤트 이름과 payload 스키마는 `backend/src/websocket/socketProtocol.js`를 단일 출처로 합니다.
- 서버에서 `emit*()` 헬퍼를 추가하면 동시에 Flutter 측 `socket_service` / 해당 Provider의 구독 핸들러도 같은 PR에서 수정합니다.
- 페이로드 검증은 백엔드는 `zod`, Flutter는 `freezed` + `json_serializable`로 양쪽에서 강제합니다.
- "일단 맞춰 보자"식 암묵적 필드 추가 금지.

### 6.5 BLE / 위치 / 근접 시스템 특수 세팅

- BLE 서비스 UUID, RSSI 임계, 관측 윈도우는 `FantasyWarsBlePresenceService` (Flutter)와 `ProximityEvidence.js` (Backend) **양쪽이 짝이 맞아야** 듀얼이 인정됩니다. 한쪽만 바꾸지 않습니다.
- 위치 송신은 `flutter_background_service` 기반이므로 OS의 백그라운드 정책(특히 Android 14+ Foreground Service 타입, iOS Background Modes)을 반드시 매니페스트에 반영합니다.
- `wakelock_plus`는 게임 진행 화면에 한정 적용합니다 (앱 전역 wakelock 금지 — 배터리 이슈).

### 6.6 mediasoup 음성 채널

- 음성 정책의 **이유**는 게임 도메인에 있고, **실행**은 `backend/src/media/`에 있습니다. 둘을 한 메서드에 섞지 않습니다.
- `MEDIASOUP_ANNOUNCED_IP`는 LAN 멀티 디바이스 테스트 시 PC의 LAN IP로 바꿔야 클라이언트가 RTP를 수신합니다 (`127.0.0.1`로 두면 자기 PC에서만 동작).

### 6.7 AI / RAG 운영

- 새 규칙·아이템 추가는 코드가 아니라 **`backend/src/ai/rag/knowledgeBase/<game>/` 데이터 추가**가 1차 접근입니다.
- 프롬프트 변경은 `backend/src/ai/prompt.js`에 집중하고, 테스트 세션에서 실제 토큰 사용량과 응답 품질을 함께 검토합니다.
- AI는 **진행 보조**이지 게임 규칙 판정의 단일 출처가 아닙니다. 위치/근접/점수 같은 결정성 판정은 항상 백엔드 도메인 로직에서 합니다.

### 6.8 정기 모임 작업 흐름

1. 모임 시작 시 현재 `docs/refactor-roadmap.md` 와 `graphify-out/GRAPH_REPORT.md`를 먼저 같이 확인.
2. 영향 받는 계층을 먼저 정한다 → 페이로드/상태 전이/도메인 모델 합의 → 순수 계산 분리 → Provider/Handler 연결 → 마지막에 화면.
3. 큰 화면·허브 파일을 더 키우지 않는다. 새 기능은 새 파일에 들어간다.
4. PR 단위에서 **그래프 변화**를 확인하기 위해 코드 변경 후 `/graphify --update` 실행 후 `graphify-out/`을 함께 리뷰.
5. 구조가 바뀌면 `docs/`도 같은 PR에서 갱신.

### 6.9 읽기 순서 (신규 합류자용)

1. 이 `README.md`
2. `docs/fantasy_wars_plugin_architecture.md`
3. `backend/src/server.js`
4. `backend/src/websocket/index.js` → `handlers/`
5. `backend/src/game/index.js` → `plugins/fantasy_wars_artifact/`
6. `backend/src/game/duel/ProximityEvidence.js`
7. `flutter/lib/main.dart` → `app.dart`
8. `flutter/lib/features/game/providers/fantasy_wars_provider.dart`
9. `flutter/lib/core/services/fantasy_wars_ble_presence_service.dart`

---

## 라이선스 / 기여

내부 프로젝트. 기여 규칙은 `docs/refactor-roadmap.md` 및 본 README의 §6 운영 가이드라인을 따릅니다.
