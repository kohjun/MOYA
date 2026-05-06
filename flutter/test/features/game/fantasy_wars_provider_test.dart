import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location_sharing_app/features/game/presentation/plugins/fantasy_wars/services/fw_notification_service.dart';
import 'package:location_sharing_app/features/game/providers/fantasy_wars_provider.dart';

// 테스트 환경에서는 HapticFeedback / AudioPlayer 가 platform binding 을 요구해
// 실패한다. 알림 동작 자체는 다른 단위 테스트가 검증하므로 여기선 no-op 으로 대체.
Override _noopNotifyOverride() => fwNotificationServiceProvider.overrideWith(
      (ref) => FwNotificationService(
        playSound: (_) async {},
        triggerHaptic: (_) {},
      ),
    );

class FakeFantasyWarsSocketClient implements FantasyWarsSocketClient {
  FakeFantasyWarsSocketClient({this.connected = false});

  bool connected;
  final requestedSessionIds = <String>[];
  Map<String, dynamic> duelChallengeResponse = const {
    'ok': true,
    'duelId': 'duel-1'
  };
  Map<String, dynamic> duelAcceptResponse = const {'ok': true};
  final _connectionController = StreamController<bool>.broadcast();
  final _gameStateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _gameEventControllers =
      <String, StreamController<Map<String, dynamic>>>{};
  final _fwDuelChallengedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _fwDuelAcceptedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _fwDuelRejectedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _fwDuelCancelledController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _fwDuelStartedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _fwDuelResultController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _fwDuelInvalidatedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _fwDuelStateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _fwDuelPlayArmedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final duelActionCalls = <Map<String, dynamic>>[];
  Map<String, dynamic> duelActionResponse = const {'ok': true};

  @override
  bool get isConnected => connected;

  @override
  Stream<bool> get onConnectionChange => _connectionController.stream;

  @override
  Stream<Map<String, dynamic>> get onGameStateUpdate =>
      _gameStateController.stream;

  @override
  Stream<Map<String, dynamic>> onGameEvent(String event) {
    return _gameEventControllers
        .putIfAbsent(
          event,
          () => StreamController<Map<String, dynamic>>.broadcast(),
        )
        .stream;
  }

  @override
  Stream<Map<String, dynamic>> get onFwDuelChallenged =>
      _fwDuelChallengedController.stream;

  @override
  Stream<Map<String, dynamic>> get onFwDuelAccepted =>
      _fwDuelAcceptedController.stream;

  @override
  Stream<Map<String, dynamic>> get onFwDuelRejected =>
      _fwDuelRejectedController.stream;

  @override
  Stream<Map<String, dynamic>> get onFwDuelCancelled =>
      _fwDuelCancelledController.stream;

  @override
  Stream<Map<String, dynamic>> get onFwDuelStarted =>
      _fwDuelStartedController.stream;

  @override
  Stream<Map<String, dynamic>> get onFwDuelResult =>
      _fwDuelResultController.stream;

  @override
  Stream<Map<String, dynamic>> get onFwDuelInvalidated =>
      _fwDuelInvalidatedController.stream;

  @override
  Stream<Map<String, dynamic>> get onFwDuelState =>
      _fwDuelStateController.stream;

  @override
  Stream<Map<String, dynamic>> get onFwDuelPlayArmed =>
      _fwDuelPlayArmedController.stream;

  void emitConnection(bool value) {
    connected = value;
    _connectionController.add(value);
  }

  void emitGameState(Map<String, dynamic> data) =>
      _gameStateController.add(data);

  void emitGameEvent(String event, Map<String, dynamic> data) {
    _gameEventControllers
        .putIfAbsent(
          event,
          () => StreamController<Map<String, dynamic>>.broadcast(),
        )
        .add(data);
  }

  void emitDuelStarted(Map<String, dynamic> data) =>
      _fwDuelStartedController.add(data);

  void emitDuelResult(Map<String, dynamic> data) =>
      _fwDuelResultController.add(data);

  void emitDuelInvalidated(Map<String, dynamic> data) =>
      _fwDuelInvalidatedController.add(data);

  @override
  void requestGameState(String sessionId) {
    requestedSessionIds.add(sessionId);
  }

  @override
  Future<Map<String, dynamic>> sendFwCaptureStart(
          String sessionId, String controlPointId) async =>
      const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendFwCaptureCancel(
          String sessionId, String controlPointId) async =>
      const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendFwCaptureDisrupt(
          String sessionId, String controlPointId) async =>
      const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendFwDungeonEnter(
    String sessionId, {
    String dungeonId = 'dungeon_main',
  }) async =>
      const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendFwRevive(String sessionId) async =>
      const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendFwUseSkill(
    String sessionId, {
    required String skill,
    String? targetUserId,
    String? controlPointId,
  }) async =>
      const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendDuelChallenge(
    String sessionId,
    String targetUserId, {
    Map<String, dynamic>? proximity,
  }) async =>
      duelChallengeResponse;

  @override
  Future<Map<String, dynamic>> sendDuelAccept(
    String duelId, {
    Map<String, dynamic>? proximity,
  }) async =>
      duelAcceptResponse;

  @override
  Future<Map<String, dynamic>> sendDuelReject(String duelId) async =>
      const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendDuelCancel(String duelId) async =>
      const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendDuelSubmit(
    String duelId,
    Map<String, dynamic> result,
  ) async =>
      const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendDuelAction(
    String duelId,
    Map<String, dynamic> action,
  ) async {
    duelActionCalls.add({'duelId': duelId, 'action': action});
    return duelActionResponse;
  }

  void emitFwDuelState(Map<String, dynamic> data) =>
      _fwDuelStateController.add(data);

  void emitFwDuelPlayArmed(Map<String, dynamic> data) =>
      _fwDuelPlayArmedController.add(data);

  void dispose() {
    _connectionController.close();
    _gameStateController.close();
    for (final controller in _gameEventControllers.values) {
      controller.close();
    }
    _fwDuelChallengedController.close();
    _fwDuelAcceptedController.close();
    _fwDuelRejectedController.close();
    _fwDuelCancelledController.close();
    _fwDuelStartedController.close();
    _fwDuelResultController.close();
    _fwDuelInvalidatedController.close();
    _fwDuelStateController.close();
    _fwDuelPlayArmedController.close();
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('FantasyWarsNotifier', () {
    test('requests game state on reconnect', () async {
      final socket = FakeFantasyWarsSocketClient();
      final container = ProviderContainer(
        overrides: [
          fantasyWarsSocketClientProvider.overrideWithValue(socket),
          fantasyWarsCurrentUserIdProvider.overrideWithValue('user-1'),
          _noopNotifyOverride(),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });

      container.read(fantasyWarsProvider('session-a'));
      socket.emitConnection(true);
      await _flush();

      expect(socket.requestedSessionIds, contains('session-a'));
    });

    test(
        'hydrates state from game state update including dungeons and private fields',
        () async {
      final socket = FakeFantasyWarsSocketClient(connected: true);
      final container = ProviderContainer(
        overrides: [
          fantasyWarsSocketClientProvider.overrideWithValue(socket),
          fantasyWarsCurrentUserIdProvider.overrideWithValue('user-1'),
          _noopNotifyOverride(),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });

      container.read(fantasyWarsProvider('session-a'));
      socket.emitGameState({
        'sessionId': 'session-a',
        'status': 'in_progress',
        'guilds': {
          'guild_alpha': {
            'guildId': 'guild_alpha',
            'displayName': 'Alpha',
            'score': 2,
            'memberIds': ['user-1', 'user-2'],
            'guildMasterId': 'user-1',
          },
        },
        'controlPoints': [
          {
            'id': 'cp-1',
            'displayName': 'Ancient Gate',
            'capturedBy': 'guild_alpha',
            'capturingGuild': 'guild_alpha',
            'captureProgress': 55,
            'readyCount': 2,
            'requiredCount': 2,
            'blockadedBy': 'guild_beta',
            'blockadeExpiresAt': DateTime.now().millisecondsSinceEpoch + 5000,
            'location': {'lat': 37.1, 'lng': 127.1},
          },
        ],
        'dungeons': [
          {
            'id': 'dungeon_main',
            'displayName': 'Forgotten Vault',
            'status': 'contested',
            'artifact': {
              'id': 'artifact_main',
              'heldBy': 'user-9',
            },
          },
        ],
        'alivePlayerIds': ['user-1', 'user-2'],
        'eliminatedPlayerIds': ['user-9'],
        'guildId': 'guild_alpha',
        'job': 'ranger',
        'isGuildMaster': true,
        'isAlive': true,
        'hp': 88,
        'remainingLives': 1,
        'shields': [
          {'from': 'user-2'},
        ],
        'buffedUntil': 123456,
        'revealUntil': 234567,
        'trackedTargetUserId': 'enemy-1',
        'dungeonEntered': false,
      });
      await _flush();

      final state = container.read(fantasyWarsProvider('session-a'));
      expect(state.status, 'in_progress');
      expect(state.guilds['guild_alpha']?.score, 2);
      expect(state.controlPoints.single.displayName, 'Ancient Gate');
      expect(state.controlPoints.single.isPreparing, isTrue);
      expect(state.dungeons.single.artifact.heldBy, 'user-9');
      expect(state.alivePlayerIds, ['user-1', 'user-2']);
      expect(state.eliminatedPlayerIds, ['user-9']);
      expect(state.myState.guildId, 'guild_alpha');
      expect(state.myState.job, 'ranger');
      expect(state.myState.isGuildMaster, isTrue);
      expect(state.myState.hp, 88);
      expect(state.myState.shieldCount, 1);
      expect(state.myState.buffedUntil, 123456);
      expect(state.myState.revealUntil, 234567);
      expect(state.myState.trackedTargetUserId, 'enemy-1');
    });

    test('updates only my hp when player attacked event targets current user',
        () async {
      final socket = FakeFantasyWarsSocketClient();
      final container = ProviderContainer(
        overrides: [
          fantasyWarsSocketClientProvider.overrideWithValue(socket),
          fantasyWarsCurrentUserIdProvider.overrideWithValue('user-1'),
          _noopNotifyOverride(),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });

      container.read(fantasyWarsProvider('session-a'));
      socket.emitGameState({
        'sessionId': 'session-a',
        'guildId': 'guild_alpha',
        'job': 'warrior',
        'hp': 100,
      });
      await _flush();

      socket.emitGameEvent('fw:player_attacked', {
        'targetId': 'user-1',
        'targetHp': 73,
      });
      await _flush();
      expect(container.read(fantasyWarsProvider('session-a')).myState.hp, 73);

      socket.emitGameEvent('fw:player_attacked', {
        'targetId': 'user-2',
        'targetHp': 10,
      });
      await _flush();
      expect(container.read(fantasyWarsProvider('session-a')).myState.hp, 73);
    });

    test('tracks duel lifecycle from challenge to result', () async {
      final socket = FakeFantasyWarsSocketClient();
      final container = ProviderContainer(
        overrides: [
          fantasyWarsSocketClientProvider.overrideWithValue(socket),
          fantasyWarsCurrentUserIdProvider.overrideWithValue('user-1'),
          _noopNotifyOverride(),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });

      final notifier =
          container.read(fantasyWarsProvider('session-a').notifier);
      await notifier.challengeDuel('enemy-1');

      var state = container.read(fantasyWarsProvider('session-a'));
      expect(state.duel.phase, 'challenging');
      expect(state.duel.duelId, 'duel-1');
      expect(state.duel.opponentId, 'enemy-1');

      socket.emitDuelStarted({
        'duelId': 'duel-1',
        'minigameType': 'reaction_time',
        'params': {'signalDelayMs': 1200},
        'startedAt': 1000,
        'gameTimeoutMs': 30000,
      });
      await _flush();

      state = container.read(fantasyWarsProvider('session-a'));
      expect(state.duel.phase, 'in_game');
      expect(state.duel.minigameType, 'reaction_time');
      expect(state.myState.inDuel, isTrue);
      expect(state.myState.duelExpiresAt, 31000);

      socket.emitDuelResult({
        'verdict': {
          'winner': 'user-1',
          'loser': 'enemy-1',
          'reason': 'minigame',
          'effects': {
            'shieldAbsorbed': true,
          },
        },
      });
      await _flush();

      state = container.read(fantasyWarsProvider('session-a'));
      expect(state.duel.phase, 'result');
      expect(state.duel.duelResult?.winnerId, 'user-1');
      expect(state.duel.duelResult?.shieldAbsorbed, isTrue);
      expect(state.myState.inDuel, isFalse);
      expect(state.myState.duelExpiresAt, isNull);
    });

    test('stores duel debug info when challenge is rejected', () async {
      final socket = FakeFantasyWarsSocketClient()
        ..duelChallengeResponse = const {
          'ok': false,
          'error': 'BLE_PROXIMITY_REQUIRED',
          'distanceMeters': 17,
          'duelRangeMeters': 20,
          'bleEvidenceFreshnessMs': 12000,
          'allowGpsFallbackWithoutBle': false,
          'proximitySource': 'gps_fallback',
          'bleConfirmed': false,
          'gpsFallbackUsed': true,
          'mutualProximity': false,
          'recentProximityReports': 1,
          'freshestEvidenceAgeMs': 900,
        };
      final container = ProviderContainer(
        overrides: [
          fantasyWarsSocketClientProvider.overrideWithValue(socket),
          fantasyWarsCurrentUserIdProvider.overrideWithValue('user-1'),
          _noopNotifyOverride(),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });

      final notifier =
          container.read(fantasyWarsProvider('session-a').notifier);
      final result = await notifier.challengeDuel('enemy-1');

      expect(result['ok'], isFalse);
      final state = container.read(fantasyWarsProvider('session-a'));
      expect(state.duel.phase, 'idle');
      expect(state.duelDebug?.stage, 'challenge');
      expect(state.duelDebug?.ok, isFalse);
      expect(state.duelDebug?.code, 'BLE_PROXIMITY_REQUIRED');
      expect(state.duelDebug?.distanceMeters, 17);
      expect(state.duelDebug?.gpsFallbackUsed, isTrue);
      expect(state.duelDebug?.freshestEvidenceAgeMs, 900);
    });

    test('stores duel debug info when accept succeeds', () async {
      final socket = FakeFantasyWarsSocketClient()
        ..duelAcceptResponse = const {
          'ok': true,
          'duelId': 'duel-9',
          'distanceMeters': 6,
          'duelRangeMeters': 20,
          'bleEvidenceFreshnessMs': 12000,
          'allowGpsFallbackWithoutBle': false,
          'proximitySource': 'ble',
          'bleConfirmed': true,
          'gpsFallbackUsed': false,
          'mutualProximity': true,
          'recentProximityReports': 2,
          'freshestEvidenceAgeMs': 250,
        };
      final container = ProviderContainer(
        overrides: [
          fantasyWarsSocketClientProvider.overrideWithValue(socket),
          fantasyWarsCurrentUserIdProvider.overrideWithValue('user-1'),
          _noopNotifyOverride(),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });

      final notifier =
          container.read(fantasyWarsProvider('session-a').notifier);
      final result = await notifier.acceptDuel('duel-9');

      expect(result['ok'], isTrue);
      final state = container.read(fantasyWarsProvider('session-a'));
      expect(state.duelDebug?.stage, 'accept');
      expect(state.duelDebug?.ok, isTrue);
      expect(state.duelDebug?.distanceMeters, 6);
      expect(state.duelDebug?.bleConfirmed, isTrue);
      expect(state.duelDebug?.mutualProximity, isTrue);
      expect(state.duelDebug?.recentProximityReports, 2);
    });

    test('stores invalidation reason in duel debug info', () async {
      final socket = FakeFantasyWarsSocketClient();
      final container = ProviderContainer(
        overrides: [
          fantasyWarsSocketClientProvider.overrideWithValue(socket),
          fantasyWarsCurrentUserIdProvider.overrideWithValue('user-1'),
          _noopNotifyOverride(),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });

      container.read(fantasyWarsProvider('session-a'));
      socket.emitDuelInvalidated({
        'duelId': 'duel-4',
        'reason': 'TARGET_OUT_OF_RANGE',
      });
      await _flush();

      final state = container.read(fantasyWarsProvider('session-a'));
      expect(state.duel.phase, 'invalidated');
      expect(state.duel.duelResult?.reason, 'invalidated');
      expect(state.duelDebug?.stage, 'invalidated');
      expect(state.duelDebug?.ok, isFalse);
      expect(state.duelDebug?.code, 'TARGET_OUT_OF_RANGE');
    });

    test(
        'refreshes private state when my guild is the disrupted (interruptedGuild) target',
        () async {
      // Codex high finding regression: disrupt 가 일어나면 서버는 끊긴 길드를
      // interruptedGuild 로 broadcast 한다. 이전엔 클라가 guildId /
      // interruptedByGuild 만 보고 새로고침을 결정해, 끊긴 길드 사용자는
      // myState.captureZone 같은 사적 상태가 stale 로 남았다.
      final socket = FakeFantasyWarsSocketClient(connected: true);
      final container = ProviderContainer(
        overrides: [
          fantasyWarsSocketClientProvider.overrideWithValue(socket),
          fantasyWarsCurrentUserIdProvider.overrideWithValue('user-1'),
          _noopNotifyOverride(),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });

      container.read(fantasyWarsProvider('session-a'));
      socket.emitGameState({
        'sessionId': 'session-a',
        'guildId': 'guild_alpha',
        'job': 'warrior',
      });
      await _flush();
      // initial sync 로 incremented 된 호출 카운트는 무시하기 위해 baseline 캡처.
      final baseline = socket.requestedSessionIds.length;

      socket.emitGameEvent('fw:capture_cancelled', {
        'controlPointId': 'cp-1',
        'reason': 'disrupted',
        'interruptedBy': 'enemy-1',
        'interruptedByGuild': 'guild_beta',
        'interruptedGuild': 'guild_alpha',
      });
      // _scheduleStateRefresh 의 120ms 타이머가 fire 되도록 기다림.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        socket.requestedSessionIds.length,
        greaterThan(baseline),
        reason: 'disrupted 길드(=내 길드) 받았을 때 _scheduleStateRefresh 가 트리거되어야 함',
      );
    });

    test(
        'duel result phase persists past former 3s auto-clear (regression: M2)',
        () async {
      // 사용자가 명시적으로 "전장으로" CTA 를 누르기 전엔 result phase 가
      // 유지되어야 한다. 이전에는 provider 가 3초 후 자동으로 clearDuelResult()
      // 를 호출해 결과 화면이 사라졌다.
      final socket = FakeFantasyWarsSocketClient(connected: true);
      final container = ProviderContainer(
        overrides: [
          fantasyWarsSocketClientProvider.overrideWithValue(socket),
          fantasyWarsCurrentUserIdProvider.overrideWithValue('user-1'),
          _noopNotifyOverride(),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });

      container.read(fantasyWarsProvider('session-a'));
      socket.emitDuelResult({
        'verdict': {
          'winner': 'user-1',
          'loser': 'enemy-1',
          'reason': 'minigame',
        },
      });
      await _flush();

      // 자동 clear 가 동작하던 임계(3s) 보다 더 길게 대기.
      await Future<void>.delayed(const Duration(milliseconds: 3500));

      final state = container.read(fantasyWarsProvider('session-a'));
      expect(state.duel.phase, 'result',
          reason: '3.5s 경과해도 사용자가 CTA 를 안 눌렀으므로 result 가 유지되어야 함');
      expect(state.duel.duelResult?.winnerId, 'user-1');
    });

    test(
        'duel invalidated phase persists past former 2s auto-clear (regression: M2)',
        () async {
      final socket = FakeFantasyWarsSocketClient(connected: true);
      final container = ProviderContainer(
        overrides: [
          fantasyWarsSocketClientProvider.overrideWithValue(socket),
          fantasyWarsCurrentUserIdProvider.overrideWithValue('user-1'),
          _noopNotifyOverride(),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });

      container.read(fantasyWarsProvider('session-a'));
      socket.emitDuelInvalidated({
        'duelId': 'duel-9',
        'reason': 'TARGET_OUT_OF_RANGE',
      });
      await _flush();

      await Future<void>.delayed(const Duration(milliseconds: 2500));

      final state = container.read(fantasyWarsProvider('session-a'));
      expect(state.duel.phase, 'invalidated',
          reason: '2.5s 경과해도 invalidated 가 유지되어야 함 (사용자 CTA 만 종료)');
    });

    test('clearDuelResult resets duel state (CTA path still works)', () async {
      final socket = FakeFantasyWarsSocketClient(connected: true);
      final container = ProviderContainer(
        overrides: [
          fantasyWarsSocketClientProvider.overrideWithValue(socket),
          fantasyWarsCurrentUserIdProvider.overrideWithValue('user-1'),
          _noopNotifyOverride(),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });

      final notifier =
          container.read(fantasyWarsProvider('session-a').notifier);
      socket.emitDuelResult({
        'verdict': {
          'winner': 'user-1',
          'loser': 'enemy-1',
          'reason': 'minigame',
        },
      });
      await _flush();
      expect(container.read(fantasyWarsProvider('session-a')).duel.phase,
          'result');

      // CTA 동작 시 명시적 clear.
      notifier.clearDuelResult();
      expect(
          container.read(fantasyWarsProvider('session-a')).duel.phase, 'idle');
    });

    test(
        'fw:duel:play_armed shifts duelExpiresAt by pre-play duration (regression: Codex P2-2)',
        () async {
      final socket = FakeFantasyWarsSocketClient();
      final container = ProviderContainer(
        overrides: [
          fantasyWarsSocketClientProvider.overrideWithValue(socket),
          fantasyWarsCurrentUserIdProvider.overrideWithValue('user-1'),
          _noopNotifyOverride(),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });

      // Notifier 생성으로 listen 들이 구독되도록 한다.
      container.read(fantasyWarsProvider('session-a').notifier);

      // accept 시점에 fw:duel:started 가 startedAt=1000, gameTimeoutMs=30000 으로
      // 도착해 duelExpiresAt = 31000.
      socket.emitDuelStarted({
        'duelId': 'duel-armed',
        'minigameType': 'reaction_time',
        'params': const {'signalDelayMs': 1000},
        'startedAt': 1000,
        'gameTimeoutMs': 30000,
      });
      await _flush();
      expect(
        container.read(fantasyWarsProvider('session-a')).myState.duelExpiresAt,
        31000,
      );

      // VS+briefing 후 서버가 본 게임 타이머를 가동하면서 startedAt=16000 통지.
      // 클라는 새 startedAt + gameTimeoutMs = 46000 으로 expiry 를 갱신한다.
      socket.emitFwDuelPlayArmed({
        'duelId': 'duel-armed',
        'startedAt': 16000,
        'gameTimeoutMs': 30000,
      });
      await _flush();
      expect(
        container.read(fantasyWarsProvider('session-a')).myState.duelExpiresAt,
        46000,
      );
    });
  });
}
