import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location_sharing_app/features/game/providers/fantasy_wars_provider.dart';

class FakeFantasyWarsSocketClient implements FantasyWarsSocketClient {
  FakeFantasyWarsSocketClient({this.connected = false});

  bool connected;
  final requestedSessionIds = <String>[];
  Map<String, dynamic> duelChallengeResponse = const {'ok': true, 'duelId': 'duel-1'};
  final _connectionController = StreamController<bool>.broadcast();
  final _gameStateController = StreamController<Map<String, dynamic>>.broadcast();
  final _gameEventControllers = <String, StreamController<Map<String, dynamic>>>{};
  final _fwDuelChallengedController = StreamController<Map<String, dynamic>>.broadcast();
  final _fwDuelAcceptedController = StreamController<Map<String, dynamic>>.broadcast();
  final _fwDuelRejectedController = StreamController<Map<String, dynamic>>.broadcast();
  final _fwDuelCancelledController = StreamController<Map<String, dynamic>>.broadcast();
  final _fwDuelStartedController = StreamController<Map<String, dynamic>>.broadcast();
  final _fwDuelResultController = StreamController<Map<String, dynamic>>.broadcast();
  final _fwDuelInvalidatedController = StreamController<Map<String, dynamic>>.broadcast();

  @override
  bool get isConnected => connected;

  @override
  Stream<bool> get onConnectionChange => _connectionController.stream;

  @override
  Stream<Map<String, dynamic>> get onGameStateUpdate => _gameStateController.stream;

  @override
  Stream<Map<String, dynamic>> onGameEvent(String event) {
    return _gameEventControllers.putIfAbsent(
      event,
      () => StreamController<Map<String, dynamic>>.broadcast(),
    ).stream;
  }

  @override
  Stream<Map<String, dynamic>> get onFwDuelChallenged => _fwDuelChallengedController.stream;

  @override
  Stream<Map<String, dynamic>> get onFwDuelAccepted => _fwDuelAcceptedController.stream;

  @override
  Stream<Map<String, dynamic>> get onFwDuelRejected => _fwDuelRejectedController.stream;

  @override
  Stream<Map<String, dynamic>> get onFwDuelCancelled => _fwDuelCancelledController.stream;

  @override
  Stream<Map<String, dynamic>> get onFwDuelStarted => _fwDuelStartedController.stream;

  @override
  Stream<Map<String, dynamic>> get onFwDuelResult => _fwDuelResultController.stream;

  @override
  Stream<Map<String, dynamic>> get onFwDuelInvalidated => _fwDuelInvalidatedController.stream;

  void emitConnection(bool value) {
    connected = value;
    _connectionController.add(value);
  }

  void emitGameState(Map<String, dynamic> data) => _gameStateController.add(data);

  void emitGameEvent(String event, Map<String, dynamic> data) {
    _gameEventControllers.putIfAbsent(
      event,
      () => StreamController<Map<String, dynamic>>.broadcast(),
    ).add(data);
  }

  void emitDuelStarted(Map<String, dynamic> data) => _fwDuelStartedController.add(data);

  void emitDuelResult(Map<String, dynamic> data) => _fwDuelResultController.add(data);

  @override
  void requestGameState(String sessionId) {
    requestedSessionIds.add(sessionId);
  }

  @override
  Future<Map<String, dynamic>> sendFwCaptureStart(String sessionId, String controlPointId) async =>
      const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendFwCaptureCancel(String sessionId, String controlPointId) async =>
      const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendFwDungeonEnter(
    String sessionId, {
    String dungeonId = 'dungeon_main',
  }) async => const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendFwUseSkill(
    String sessionId, {
    required String skill,
    String? targetUserId,
    String? controlPointId,
  }) async => const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendDuelChallenge(String sessionId, String targetUserId) async =>
      duelChallengeResponse;

  @override
  Future<Map<String, dynamic>> sendDuelAccept(String duelId) async => const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendDuelReject(String duelId) async => const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendDuelCancel(String duelId) async => const {'ok': true};

  @override
  Future<Map<String, dynamic>> sendDuelSubmit(
    String duelId,
    Map<String, dynamic> result,
  ) async => const {'ok': true};

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

    test('hydrates state from game state update including dungeons and private fields', () async {
      final socket = FakeFantasyWarsSocketClient(connected: true);
      final container = ProviderContainer(
        overrides: [
          fantasyWarsSocketClientProvider.overrideWithValue(socket),
          fantasyWarsCurrentUserIdProvider.overrideWithValue('user-1'),
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

    test('updates only my hp when player attacked event targets current user', () async {
      final socket = FakeFantasyWarsSocketClient();
      final container = ProviderContainer(
        overrides: [
          fantasyWarsSocketClientProvider.overrideWithValue(socket),
          fantasyWarsCurrentUserIdProvider.overrideWithValue('user-1'),
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
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });

      final notifier = container.read(fantasyWarsProvider('session-a').notifier);
      await notifier.challengeDuel('enemy-1');

      var state = container.read(fantasyWarsProvider('session-a'));
      expect(state.duel.phase, 'challenging');
      expect(state.duel.duelId, 'duel-1');
      expect(state.duel.opponentId, 'enemy-1');

      socket.emitDuelStarted({
        'duelId': 'duel-1',
        'minigameType': 'reaction',
        'params': {'seed': 'abc'},
        'startedAt': 1000,
        'gameTimeoutMs': 30000,
      });
      await _flush();

      state = container.read(fantasyWarsProvider('session-a'));
      expect(state.duel.phase, 'in_game');
      expect(state.duel.minigameType, 'reaction');
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
  });
}
