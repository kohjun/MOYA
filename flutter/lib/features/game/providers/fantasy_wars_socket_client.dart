import '../../../core/services/socket_service.dart';

abstract class FantasyWarsSocketClient {
  bool get isConnected;
  Stream<bool> get onConnectionChange;
  Stream<Map<String, dynamic>> get onGameStateUpdate;
  Stream<Map<String, dynamic>> onGameEvent(String event);
  Stream<Map<String, dynamic>> get onFwDuelChallenged;
  Stream<Map<String, dynamic>> get onFwDuelAccepted;
  Stream<Map<String, dynamic>> get onFwDuelRejected;
  Stream<Map<String, dynamic>> get onFwDuelCancelled;
  Stream<Map<String, dynamic>> get onFwDuelStarted;
  Stream<Map<String, dynamic>> get onFwDuelResult;
  Stream<Map<String, dynamic>> get onFwDuelInvalidated;
  // 턴 기반 미니게임의 새 public state broadcast.
  Stream<Map<String, dynamic>> get onFwDuelState;
  // 본 게임 타이머 가동 신호 (startedAt 갱신 + 정확한 gameTimeoutMs 통지).
  Stream<Map<String, dynamic>> get onFwDuelPlayArmed;
  void requestGameState(String sessionId);
  Future<Map<String, dynamic>> sendFwCaptureStart(
      String sessionId, String controlPointId);
  Future<Map<String, dynamic>> sendFwCaptureCancel(
      String sessionId, String controlPointId);
  Future<Map<String, dynamic>> sendFwCaptureDisrupt(
      String sessionId, String controlPointId);
  Future<Map<String, dynamic>> sendFwDungeonEnter(
    String sessionId, {
    String dungeonId = 'dungeon_main',
  });
  Future<Map<String, dynamic>> sendFwRevive(String sessionId);
  Future<Map<String, dynamic>> sendFwUseSkill(
    String sessionId, {
    required String skill,
    String? targetUserId,
    String? controlPointId,
  });
  Future<Map<String, dynamic>> sendDuelChallenge(
    String sessionId,
    String targetUserId, {
    Map<String, dynamic>? proximity,
  });
  Future<Map<String, dynamic>> sendDuelAccept(
    String duelId, {
    Map<String, dynamic>? proximity,
  });
  Future<Map<String, dynamic>> sendDuelReject(String duelId);
  Future<Map<String, dynamic>> sendDuelCancel(String duelId);
  Future<Map<String, dynamic>> sendDuelSubmit(
      String duelId, Map<String, dynamic> result);
  // 턴 기반 미니게임용 액션 전송.
  Future<Map<String, dynamic>> sendDuelAction(
      String duelId, Map<String, dynamic> action);
}

class SocketServiceFantasyWarsClient implements FantasyWarsSocketClient {
  SocketServiceFantasyWarsClient(this._socket);

  final SocketService _socket;

  @override
  bool get isConnected => _socket.isConnected;

  @override
  Stream<bool> get onConnectionChange => _socket.onConnectionChange;

  @override
  Stream<Map<String, dynamic>> get onGameStateUpdate =>
      _socket.onGameStateUpdate;

  @override
  Stream<Map<String, dynamic>> onGameEvent(String event) =>
      _socket.onGameEvent(event);

  @override
  Stream<Map<String, dynamic>> get onFwDuelChallenged =>
      _socket.onFwDuelChallenged;

  @override
  Stream<Map<String, dynamic>> get onFwDuelAccepted => _socket.onFwDuelAccepted;

  @override
  Stream<Map<String, dynamic>> get onFwDuelRejected => _socket.onFwDuelRejected;

  @override
  Stream<Map<String, dynamic>> get onFwDuelCancelled =>
      _socket.onFwDuelCancelled;

  @override
  Stream<Map<String, dynamic>> get onFwDuelStarted => _socket.onFwDuelStarted;

  @override
  Stream<Map<String, dynamic>> get onFwDuelResult => _socket.onFwDuelResult;

  @override
  Stream<Map<String, dynamic>> get onFwDuelInvalidated =>
      _socket.onFwDuelInvalidated;

  @override
  Stream<Map<String, dynamic>> get onFwDuelState => _socket.onFwDuelState;

  @override
  Stream<Map<String, dynamic>> get onFwDuelPlayArmed =>
      _socket.onFwDuelPlayArmed;

  @override
  void requestGameState(String sessionId) =>
      _socket.requestGameState(sessionId);

  @override
  Future<Map<String, dynamic>> sendFwCaptureStart(
          String sessionId, String controlPointId) =>
      _socket.sendFwCaptureStart(sessionId, controlPointId);

  @override
  Future<Map<String, dynamic>> sendFwCaptureCancel(
          String sessionId, String controlPointId) =>
      _socket.sendFwCaptureCancel(sessionId, controlPointId);

  @override
  Future<Map<String, dynamic>> sendFwCaptureDisrupt(
          String sessionId, String controlPointId) =>
      _socket.sendFwCaptureDisrupt(sessionId, controlPointId);

  @override
  Future<Map<String, dynamic>> sendFwDungeonEnter(
    String sessionId, {
    String dungeonId = 'dungeon_main',
  }) =>
      _socket.sendFwDungeonEnter(sessionId, dungeonId: dungeonId);

  @override
  Future<Map<String, dynamic>> sendFwRevive(String sessionId) =>
      _socket.sendFwRevive(sessionId);

  @override
  Future<Map<String, dynamic>> sendFwUseSkill(
    String sessionId, {
    required String skill,
    String? targetUserId,
    String? controlPointId,
  }) =>
      _socket.sendFwUseSkill(
        sessionId,
        skill: skill,
        targetUserId: targetUserId,
        controlPointId: controlPointId,
      );

  @override
  Future<Map<String, dynamic>> sendDuelChallenge(
    String sessionId,
    String targetUserId, {
    Map<String, dynamic>? proximity,
  }) =>
      _socket.sendDuelChallenge(
        sessionId,
        targetUserId,
        proximity: proximity,
      );

  @override
  Future<Map<String, dynamic>> sendDuelAccept(
    String duelId, {
    Map<String, dynamic>? proximity,
  }) =>
      _socket.sendDuelAccept(duelId, proximity: proximity);

  @override
  Future<Map<String, dynamic>> sendDuelReject(String duelId) =>
      _socket.sendDuelReject(duelId);

  @override
  Future<Map<String, dynamic>> sendDuelCancel(String duelId) =>
      _socket.sendDuelCancel(duelId);

  @override
  Future<Map<String, dynamic>> sendDuelSubmit(
          String duelId, Map<String, dynamic> result) =>
      _socket.sendDuelSubmit(duelId, result);

  @override
  Future<Map<String, dynamic>> sendDuelAction(
          String duelId, Map<String, dynamic> action) =>
      _socket.sendDuelAction(duelId, action);
}
