# 리팩터링 실행 계획

기준 문서: `PROJECT_FULL_REPORT_KO.md`

## 우선순위 판단

보고서 기준 가장 먼저 손봐야 하는 지점은 아래 3곳이다.

1. `flutter/lib/features/game/presentation/game_main_screen.dart`
2. `flutter/lib/features/game/providers/game_provider.dart`
3. `backend/src/websocket/index.js`

우선순위는 "변경 빈도"와 "한 번 깨지면 영향받는 화면/흐름의 수"를 기준으로 잡는다.

- `game_main_screen.dart`: 화면 오케스트레이션이 과도하게 몰려 있음
- `game_provider.dart`: 서버 이벤트를 앱 상태로 번역하는 핵심 경계층
- `websocket/index.js`: 프로토콜 정의, 실시간 게임 조율, 세션/미디어 이벤트가 한 파일에 혼재

## 단계별 실행

### 1단계. 저위험 분리

목표: 대형 파일에서 표현 전용 코드와 상수/헬퍼를 먼저 분리한다.

- `game_main_screen.dart`
  - 프레젠테이션 전용 위젯을 별도 파일로 이동
  - 미션/QR/보이스 채널 액션을 헬퍼 메서드로 분리
- `websocket/index.js`
  - 이벤트 상수
  - 세션 타입/모듈 레지스트리
  - 게임 상태 정규화/미디어 룸 동기화 헬퍼
  - 위 항목을 별도 모듈로 분리

효과:

- 메인 파일 읽기 비용 감소
- 후속 분리 작업의 기반 확보
- 런타임 동작 변화 없이 구조 개선 가능

### 2단계. 화면 조립과 상태 반응 분리

목표: `game_main_screen.dart`에서 화면 조립과 상태 반응을 분리한다.

- `ref.listen` 블록을 별도 상태 반응 헬퍼로 이동
- 지도 오버레이 동기화 로직을 전용 코디네이터로 분리
- 세션 정보 오버레이, 게임 종료 오버레이, SOS 배너를 독립 위젯화

효과:

- 메인 빌드 메서드 축소
- 테스트 가능한 작은 단위 증가

### 3단계. 게임 상태 계산 분리

목표: `game_provider.dart`에서 위치 기반 미션 계산과 소켓 이벤트 처리의 결합을 낮춘다.

- 위치 기반 미션 계산기 분리
- 코인/동물 스폰 로직 분리
- 소켓 이벤트 구독 등록을 별도 메서드/클래스로 분리

효과:

- Provider가 "상태 저장소" 역할에 더 가까워짐
- 위치/미션 규칙 테스트 가능성 증가

### 4단계. WebSocket 도메인 분해

목표: `websocket/index.js`를 도메인별 핸들러로 쪼갠다.

- session handlers
- game handlers
- vote/meeting handlers
- location/status handlers
- alert handlers

효과:

- 이벤트 프로토콜 탐색 비용 감소
- 게임 룰 변경 시 영향 범위 축소

### 5단계. 계약 문서화

목표: 서버-클라이언트 이벤트 payload를 명시적으로 문서화한다.

- Socket.IO 이벤트 목록 문서
- payload 예시
- 필수/선택 필드 표기
- 게임 상태 전이 다이어그램 초안

효과:

- 서버/Flutter 동기화 오류 감소
- 신규 기능 추가 시 회귀 가능성 감소

## 이번 턴 적용 범위

이번 턴에서는 1단계를 실제로 수행한다.

- `game_main_screen.dart`: 프레젠테이션 위젯과 액션 헬퍼 분리
- `websocket/index.js`: 상수/런타임 헬퍼 분리
- 정적 검증까지 수행

## 이번 턴 이후 바로 이어갈 후보

다음 턴 우선순위는 아래 순서가 적절하다.

1. `game_main_screen.dart`의 `ref.listen` 반응 로직 분리
2. `game_provider.dart`의 위치 기반 미션 계산 분리
3. `websocket/index.js`의 게임 이벤트 핸들러 분리
