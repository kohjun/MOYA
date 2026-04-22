# 프로젝트 전체 리포트

생성일: 2026-04-19  
범위: `C:\MOYA` 프로젝트 전체, `graphify-out/graph.json`, `graphify-out/GRAPH_REPORT.md`, 핵심 엔트리 파일 기준

## 한줄 요약

이 프로젝트는 단순 위치 공유 앱이 아니라, 실시간 세션 관리와 음성 라우팅 위에 어몽어스형 역할 게임을 올린 모바일 중심 멀티플레이 시스템입니다.

- 백엔드: Fastify, Socket.IO, Redis, PostgreSQL, mediasoup, Firebase Admin, Gemini 연동
- 모바일: Flutter, Riverpod, GoRouter, Dio, Socket.IO client, mediasoup client, Naver Map, Flame 미니게임
- 핵심 사용자 흐름: 로그인, 세션 생성/참가, 로비, 게임 시작, 역할 배정, 미션 수행, 회의/투표, 음성 채널 제어, AI 메시지
- 구조 중심축: Flutter 게임 UI와 상태 관리가 가장 크고, 서버는 게임 오케스트레이션과 미디어 제어가 핵심

## 그래프 요약

- 분석 파일 수: 99
- 대략적 코퍼스 크기: 66,880 단어
- 노드 수: 1009
- 엣지 수: 1391
- 커뮤니티 수: 34
- 추출 품질: EXTRACTED 90%, INFERRED 10%, AMBIGUOUS 0%
- 관계 유형 분포: `defines` 588, `imports` 334, `calls` 249, `contains` 140, `method` 80
- 노드 분포: Flutter 749, Backend 260

해석:

- 구현량과 복잡도는 Flutter 쪽이 더 큽니다.
- 그래프는 충분히 조밀해서 영향 범위 분석과 구조 탐색에 쓸 만합니다.
- 다만 `INFERRED` 엣지는 정적 추론 결과라서, 실제 런타임 사실로 단정하면 안 됩니다.

## 시스템 전체 구조

프로젝트는 크게 네 층으로 나뉩니다.

- 클라이언트 앱 계층: Flutter 화면, Provider, 라우팅, 디바이스 서비스
- 게임 도메인 계층: 역할, 미션, 회의, 투표, 사보타주, QR, 미니게임
- 실시간 통신 계층: Socket.IO 이벤트 + mediasoup 음성 채널
- 데이터/플랫폼 계층: PostgreSQL, Redis, FCM, 인증, 지오펜스, 세션 정리 작업

핵심 엔트리:

- 백엔드 시작점: `backend/src/server.js`
- 게임 시작 오케스트레이션: `backend/src/game/startGameService.js`
- 실시간 이벤트 허브: `backend/src/websocket/index.js`
- Flutter 앱 시작점: `flutter/lib/app.dart`
- Flutter 라우터: `flutter/lib/core/router/app_router.dart`
- 게임 상태 핵심: `flutter/lib/features/game/providers/game_provider.dart`
- 메인 게임 화면: `flutter/lib/features/game/presentation/game_main_screen.dart`

## 백엔드 구조

### 1. 서버 부트스트랩

`backend/src/server.js`는 Fastify 앱을 만들고, 이후 실시간 게임 서버에 필요한 인프라를 붙입니다.

- 인증, 세션, 지오펜스 라우트 등록
- DB 연결 확인용 헬스체크 제공
- Redis 연결
- mediasoup 워커 초기화
- Socket.IO 서버 생성
- 세션 정리용 cron 시작

즉 백엔드는 REST API 서버이면서 동시에 실시간 게임 런타임입니다.

### 2. 실시간 이벤트 허브

`backend/src/websocket/index.js`는 프로젝트 런타임의 중심입니다.

- 클라이언트-서버 이벤트 프로토콜 정의
- 세션 참가/이탈 처리
- 위치, 상태, SOS, 지오펜스, 미션, 회의, 투표, 사보타주, AI 이벤트 연결
- Redis Streams adapter로 Socket.IO 확장성 확보
- mediasoup signaling과 게임 상태 동기화 연결

이 파일은 단순 WebSocket 래퍼가 아니라, 게임 진행과 미디어 상태를 함께 조정하는 허브입니다.

### 3. 게임 도메인 서비스

`backend/src/game` 아래가 게임 규칙 핵심입니다.

- `startGameService.js`: 게임 시작 검증, 역할 배정, Redis 상태 초기화, 미디어 룸 상태 적용, 역할/시작 이벤트 전송, 미션 배정
- `MissionSystem.js`: 미션 풀 생성, 플레이어별 미션 할당, 진행도 계산, 완료 처리
- `VoteSystem.js`: 회의와 투표 흐름 관리
- `KillCooldownManager.js`: 임포스터 킬 쿨다운 관리
- `GamePluginRegistry.js`, `AmongUsPlugin.js`: 게임 모드/플러그인 구성
- `EventBus.js`: 내부 이벤트 연결

그래프상으로도 게임 서브시스템은 별도 제품 도메인처럼 분리되어 보입니다. 다만 여전히 `websocket/index.js`가 너무 많은 조율 책임을 가지고 있습니다.

### 4. 음성/미디어 계층

이 프로젝트의 음성 처리는 단순 통화가 아니라 게임 규칙에 종속됩니다.

- `backend/src/media/MediaServer.js`: mediasoup 워커와 룸 관리
- `backend/src/media/Room.js`: peer 관리, 채널 관리, 생존/사망 상태 반영, 강제 mute, 회의 중 음성 상태 전환
- `backend/src/media/Peer.js`: 개별 참가자 미디어 상태

특히 `Room.js`는 그래프에서도 강한 허브입니다. 회의 중 음성 허용 여부, 사망자 음성 차단 같은 규칙이 게임 로직과 직접 연결되어 있음을 보여줍니다.

### 5. 데이터와 플랫폼 서비스

의존성과 소스 구조상 백엔드는 다음 책임을 집니다.

- PostgreSQL: 사용자, 세션, 멤버십, 지오펜스 같은 영속 데이터
- Redis: 게임 상태, 세션 상태, TTL 데이터, Socket.IO adapter
- Firebase Admin: 알림 발송
- Gemini: AI 디렉터/공지 메시지

추론 엣지가 많이 몰린 백엔드 파일은 다음입니다.

- `media/Room.js`
- `services/sessionService.js`
- `services/authService.js`
- `game/VoteSystem.js`
- `game/startGameService.js`

즉 백엔드 복잡도는 미디어, 세션, 인증, 게임 진행 조율에 집중돼 있습니다.

## Flutter 구조

### 1. 앱 셸과 라우팅

`flutter/lib/app.dart`는 `MaterialApp.router`를 구성하고, `core/router/app_router.dart`가 인증 상태 기반 라우팅을 담당합니다.

주요 라우트:

- 로그인
- 회원가입
- 홈
- 로비
- 게임
- 히스토리
- 지오펜스
- 설정
- 세션 멤버 관리

라우터 자체는 표준적이지만, 인증과 세션/게임 흐름을 잇는 진입점이라 중요도가 높습니다.

### 2. 공통 서비스 계층

`flutter/lib/core/services`는 디바이스와 실시간 연결을 담당합니다.

- `socket_service.dart`
- `mediasoup_audio_service.dart`
- `location_service.dart`
- `background_service.dart`
- `fcm_service.dart`
- `notification_service.dart`
- `sound_service.dart`
- `app_initialization_service.dart`

그래프상 `socket_service.dart`와 `mediasoup_audio_service.dart`는 클라이언트 내부에서 연결도가 매우 높은 편입니다. 실시간 통신과 음성 제어가 앱 핵심 기능이라는 뜻입니다.

### 3. 기능별 모듈 구조

`flutter/lib/features`는 기능 단위로 잘 나뉘어 있습니다.

- `auth`
- `home`
- `lobby`
- `game`
- `map`
- `geofence`
- `history`
- `session`
- `settings`

구조 자체는 깔끔하지만, 실제 복잡도는 `game` 기능에 압도적으로 몰려 있습니다.

## 게임 기능 구조

게임 기능은 앱 전체의 운영 중심입니다.

핵심 파일:

- `features/game/providers/game_provider.dart`: 서버 이벤트 수신, 상태 정규화, 역할/미션/진행도 관리
- `features/game/data/game_models.dart`: `AmongUsGameState`, `GameMission`, `CoinPoint`, `AnimalPoint`, `ChatLog` 같은 핵심 모델
- `features/game/presentation/game_main_screen.dart`: 메인 게임 런타임 화면
- `features/game/presentation/game_meeting_screen.dart`: 회의 및 투표 화면
- `features/game/presentation/widgets/mission_list_sheet.dart`: 미션 목록과 미션 진입점
- `features/game/presentation/minigames/*`: Flame 기반 미니게임
- `features/game/presentation/modules/*`: kill, bounds, sabotage, meeting, QR, NFC 등 런타임 모듈
- `features/game/presentation/modes/*`: 게임 모드 플러그인

그래프 관찰 결과:

- `game_main_screen.dart`가 프로젝트 전체 내부 노드 중 가장 높은 연결도를 가집니다.
- `session_info_screen.dart`, `game_provider.dart`, `game_meeting_screen.dart`, `ai_chat_panel.dart`, `game_mode_plugin.dart`도 모두 핵심 허브입니다.
- Community 3, 6, 7, 13, 18, 20, 21이 게임 UI, 미션 UX, 미니게임, 게임 모델에 집중되어 있습니다.

해석:

- 게임 기능은 플러그인/모듈 구조를 갖고 있지만, 실제 실행 흐름은 `game_main_screen.dart`와 `game_provider.dart`로 강하게 수렴합니다.
- 지금은 동작하지만, 장기적으로는 이 두 파일이 유지보수 병목이 될 가능성이 큽니다.

## 실시간 게임 루프

핵심 흐름은 아래와 같습니다.

- 사용자가 세션에 들어감
- 호스트가 게임 시작
- 백엔드 `startGameForSession()`이 역할과 상태를 초기화
- 백엔드 미션 시스템이 플레이어별 미션 할당
- WebSocket 이벤트로 게임 시작, 역할, 미션, 진행도 상태 전송
- Flutter `game_provider.dart`가 이를 표준 모델로 정규화
- `game_main_screen.dart`와 위젯들이 이를 렌더링
- 회의, 사망, 사보타주, AI 메시지가 같은 실시간 채널로 계속 흐름
- mediasoup 룸 상태가 회의/생존 상태에 맞춰 변경

즉 이 프로젝트는 미니게임 몇 개가 붙은 앱이 아니라, 하나의 일관된 실시간 게임 런타임입니다.

## 핵심 허브와 집중 지점

내부 허브 상위권:

- `flutter/lib/features/game/presentation/game_main_screen.dart`
- `flutter/lib/features/game/presentation/session_info_screen.dart`
- `flutter/lib/features/lobby/presentation/lobby_screen.dart`
- `flutter/lib/features/history/presentation/history_screen.dart`
- `flutter/lib/core/services/socket_service.dart`
- `flutter/lib/features/game/providers/game_provider.dart`
- `flutter/lib/core/services/mediasoup_audio_service.dart`
- `backend/src/game/GamePluginRegistry.js`
- `backend/src/config/database.js`
- `backend/src/media/Room.js`

의미:

- 클라이언트는 UI/상태 결합이 강합니다.
- 서버는 조율과 음성/게임 상태 결합이 강합니다.
- 음성은 부가 기능이 아니라 게임 규칙의 일부입니다.

## 그래프에서 보이는 중요한 사실

### 확실하게 보이는 점

- `startGameForSession()`은 역할 배정, 미션 배정, 게임 상태 초기화, 미디어 룸 동기화와 직접 연결됩니다.
- `Room`, `Peer`는 핵심 추상화이며, 음성 상태가 게임 규칙과 직접 연결됩니다.
- `game_models.dart`와 `game_provider.dart`는 백엔드 이벤트를 Flutter UI 상태로 번역하는 경계층입니다.
- `game_main_screen.dart`는 사실상 게임 기능의 조립 루트입니다.

### 검증이 필요한 추론 연결

- `startGameForSession()` -> `getMediaServer()`
- `createFastifyApp()` -> 인증/게임 레지스트리 내부 연결
- `startServer()` -> Redis 연결 및 세션 정리 작업

이 연결들은 실제 코드와 대체로 맞아 보이지만, 그래프에서 `INFERRED`로 나온 부분은 코드 확인을 전제로 봐야 합니다.

## 공백과 노이즈

그래프 리포트가 지적한 항목:

- 약하게 연결되거나 고립된 노드 639개
- `prompt.js`, `common.js`, `crew.js`, `faq.js`, `impostor.js`, `items.js`, `migrate.js`, `AmongUsPlugin.js`, `index.js` 같은 1노드 커뮤니티 다수

해석:

- 일부는 유틸 파일이나 텍스트성 파일이라 정상적인 노이즈입니다.
- 일부는 `build`, `get()`, `query()`처럼 일반 이름 때문에 추출 품질이 떨어진 경우입니다.
- 일부는 문서화나 네이밍 개선 여지가 있다는 신호이기도 합니다.

## 리스크

### 1. 메인 게임 화면 집중 리스크

`game_main_screen.dart`의 연결도가 지나치게 높습니다. 게임 HUD, 미션 액션, 오버레이, 회의 진입, 미니게임 진입이 한 파일로 몰릴수록 변경 충돌 가능성이 커집니다.

### 2. Provider 번역 계층 리스크

`game_provider.dart`는 서버 이벤트와 UI 상태 사이의 번역기 역할을 합니다. 여기서 버그가 나면 여러 화면이 동시에 깨질 가능성이 높습니다.

### 3. WebSocket 허브 과밀 리스크

`backend/src/websocket/index.js`는 프로토콜 정의, 상태 동기화, 알림, 게임 런타임 조율까지 함께 담당합니다. 장기적으로는 도메인별 핸들러 분리가 필요합니다.

### 4. 미디어-게임 결합 리스크

회의 상태와 생존 상태가 음성 제어에 직접 반영되므로, 미디어 레이어 수정이 게임 규칙 회귀로 이어질 수 있습니다.

## 추천 다음 단계

- 게임 서브시스템만 따로 떼어낸 세부 리포트 작성
- `game_main_screen.dart`를 HUD, 오버레이, 미션 진입, 회의 진입 등으로 분리
- `backend/src/websocket/index.js`를 세션, 게임, 미디어, 알림 핸들러로 분리
- Socket.IO 이벤트 계약을 문서화
- 서버-클라이언트 payload 스키마를 기계적으로 검증할 수 있게 정의
- 주요 리팩터링 후 `graphify update ./raw`를 다시 돌려 그래프 변화 추적

## 결론

이 프로젝트는 현재 다음 성격을 가집니다.

- 모바일 중심 실시간 멀티플레이 게임
- 역할 기반 규칙 시스템
- 미션/회의/사보타주가 결합된 게임 루프
- 상태 기반 음성 채널 제어
- AI 보조 메시징이 들어간 서버 주도형 진행

도메인 경계는 이미 어느 정도 잡혀 있습니다. 다음 성장 단계에서는 새 기능을 더 얹기보다, `game_main_screen.dart`, `game_provider.dart`, `websocket/index.js`에 몰린 조율 책임을 줄이는 쪽이 효과가 클 가능성이 높습니다.
