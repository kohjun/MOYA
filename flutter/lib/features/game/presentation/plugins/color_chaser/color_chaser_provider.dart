// Color Chaser provider — Phase 1+2 최소 구현.
// game:state_update 이벤트만 구독해 본인 색/타겟 색을 동기화한다.
// Phase 3 이후 cc:tag_result, cc:hint_unlocked 등 추가.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/services/socket_service.dart';
import 'color_chaser_models.dart';

class ColorChaserNotifier extends StateNotifier<ColorChaserGameState> {
  ColorChaserNotifier(this._sessionId)
      : super(const ColorChaserGameState()) {
    _subscribe();
    if (SocketService().isConnected) {
      SocketService().requestGameState(_sessionId);
    }
  }

  final String _sessionId;
  StreamSubscription<Map<String, dynamic>>? _stateSub;
  StreamSubscription<Map<String, dynamic>>? _tagSub;
  StreamSubscription<Map<String, dynamic>>? _cpActivatedSub;
  StreamSubscription<Map<String, dynamic>>? _cpClaimedSub;
  StreamSubscription<Map<String, dynamic>>? _cpExpiredSub;
  StreamSubscription<Map<String, dynamic>>? _gameOverSub;
  StreamSubscription<bool>? _connectionSub;

  // 거점 lifecycle 알림 콜백 (UI 가 SnackBar 등을 띄우기 위해 listen).
  final _cpEventController =
      StreamController<CcCpLifecycleEvent>.broadcast();
  Stream<CcCpLifecycleEvent> get cpEvents => _cpEventController.stream;

  void _subscribe() {
    _stateSub = SocketService().onGameStateUpdate.listen(_handleStateUpdate);
    _tagSub = SocketService()
        .onGameEvent(SocketEvents.ccPlayerTagged)
        .listen(_handleTagEvent);
    _cpActivatedSub = SocketService()
        .onGameEvent(SocketEvents.ccCpActivated)
        .listen((data) => _emitCpEvent('activated', data));
    _cpClaimedSub = SocketService()
        .onGameEvent(SocketEvents.ccCpClaimed)
        .listen((data) => _emitCpEvent('claimed', data));
    _cpExpiredSub = SocketService()
        .onGameEvent(SocketEvents.ccCpExpired)
        .listen((data) => _emitCpEvent('expired', data));
    _gameOverSub = SocketService().onGameOver.listen(_handleGameOver);
    _connectionSub = SocketService().onConnectionChange.listen((connected) {
      if (connected) {
        SocketService().joinSession(_sessionId);
        SocketService().requestGameState(_sessionId);
      }
    });
  }

  void _emitCpEvent(String kind, Map<String, dynamic> data) {
    final eventSessionId = data['sessionId'] as String?;
    if (eventSessionId != null && eventSessionId != _sessionId) return;
    _cpEventController.add(CcCpLifecycleEvent(
      kind: kind,
      cpId: data['cpId'] as String? ?? '',
      displayName: data['displayName'] as String?,
      claimedBy: data['claimedBy'] as String?,
      lat: (data['location']?['lat'] as num?)?.toDouble(),
      lng: (data['location']?['lng'] as num?)?.toDouble(),
      expiresAt: (data['expiresAt'] as num?)?.toInt(),
    ));
  }

  void _handleGameOver(Map<String, dynamic> data) {
    final eventSessionId = data['sessionId'] as String?;
    if (eventSessionId != null && eventSessionId != _sessionId) return;
    // game:state_update 가 winCondition 을 채워서 도착하므로 별도 처리 불필요.
    // status 만 즉시 'finished' 로 표시해 force-modal 류가 닫히도록.
    if (state.status != 'finished') {
      state = state.copyWith(status: 'finished');
    }
    SocketService().requestGameState(_sessionId);
  }

  void refreshState() {
    SocketService().requestGameState(_sessionId);
  }

  /// 처치 시도. ack 응답 반환.
  Future<Map<String, dynamic>> tagTarget(String targetUserId) {
    return SocketService().sendCcTagTarget(
      sessionId: _sessionId,
      targetUserId: targetUserId,
    );
  }

  void _handleTagEvent(Map<String, dynamic> data) {
    final eventSessionId = data['sessionId'] as String?;
    if (eventSessionId != null && eventSessionId != _sessionId) return;

    final event = CcTagEvent.fromMap(data);
    final next = [event, ...state.recentTags].take(10).toList(growable: false);
    state = state.copyWith(recentTags: next);
  }

  void _handleStateUpdate(Map<String, dynamic> data) {
    final eventSessionId = data['sessionId'] as String?;
    if (eventSessionId != null && eventSessionId != _sessionId) return;

    final gameType = data['gameType'] as String?;
    if (gameType != null && gameType != 'color_chaser') return;

    final status = data['status'] as String? ?? state.status;

    final paletteRaw = (data['palette'] as List?) ?? const [];
    final palette = paletteRaw
        .whereType<Map>()
        .map((m) => CcColor.fromMap(Map<String, dynamic>.from(m)))
        .toList(growable: false);

    final colorCountsRaw = (data['colorCounts'] as List?) ?? const [];
    final colorCounts = colorCountsRaw
        .whereType<Map>()
        .map((m) => CcColorCount.fromMap(Map<String, dynamic>.from(m)))
        .toList(growable: false);

    final alivePlayerIds = ((data['alivePlayerIds'] as List?) ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final eliminatedPlayerIds =
        ((data['eliminatedPlayerIds'] as List?) ?? const [])
            .whereType<String>()
            .toList(growable: false);

    final cpRaw = (data['controlPoints'] as List?) ?? const [];
    final controlPoints = cpRaw
        .whereType<Map>()
        .map((m) => CcControlPoint.fromMap(Map<String, dynamic>.from(m)))
        .toList(growable: false);

    // bodyAttributes: { gender: { label, options }, ... }
    final bodyAttrsRaw = (data['bodyAttributes'] as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final bodyAttributes = bodyAttrsRaw.entries
        .where((e) => e.value is Map)
        .map((e) =>
            CcAttributeDef.fromMap(e.key, Map<String, dynamic>.from(e.value)))
        .toList(growable: false);

    final submittedRaw =
        (data['bodyProfileSubmittedUserIds'] as List?) ?? const [];
    final bodyProfileSubmittedUserIds =
        submittedRaw.whereType<String>().toList(growable: false);

    final hintsRaw = (data['unlockedHints'] as List?) ?? const [];
    final hints = hintsRaw
        .whereType<Map>()
        .map((m) => CcHint.fromMap(Map<String, dynamic>.from(m)))
        .toList(growable: false);

    final candidatesRaw = (data['candidates'] as List?) ?? const [];
    final candidates = candidatesRaw
        .whereType<Map>()
        .map((m) => CcCandidate.fromMap(Map<String, dynamic>.from(m)))
        .toList(growable: false);

    final myProfileRaw = (data['myBodyProfile'] as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final myProfile = <String, String>{
      for (final e in myProfileRaw.entries)
        if (e.value is String) e.key: e.value as String,
    };

    final activeMissionRaw = data['activeMission'];
    final activeMission = activeMissionRaw is Map
        ? CcActiveMission.fromMap(Map<String, dynamic>.from(activeMissionRaw))
        : null;

    final myState = CcMyState(
      colorId: data['colorId'] as String?,
      colorLabel: data['colorLabel'] as String?,
      colorHex: data['colorHex'] as String?,
      targetColorId: data['targetColorId'] as String?,
      targetColorLabel: data['targetColorLabel'] as String?,
      targetColorHex: data['targetColorHex'] as String?,
      isAlive: data['isAlive'] as bool? ?? state.myState.isAlive,
      missionsCompleted:
          (data['missionsCompleted'] as num?)?.toInt() ??
              state.myState.missionsCompleted,
      // activeMission 은 명시적으로 null 일 때도 반영해야 함 (제출 후 클리어).
      activeMission: data.containsKey('activeMission')
          ? activeMission
          : state.myState.activeMission,
      bodyProfile:
          myProfileRaw.isEmpty ? state.myState.bodyProfile : myProfile,
      bodyProfileComplete: data['myBodyProfileComplete'] as bool? ??
          state.myState.bodyProfileComplete,
      unlockedHints: data.containsKey('unlockedHints')
          ? hints
          : state.myState.unlockedHints,
      candidates:
          data.containsKey('candidates') ? candidates : state.myState.candidates,
    );

    final winRaw = data['winCondition'];
    final winCondition = winRaw is Map
        ? CcWinCondition.fromMap(Map<String, dynamic>.from(winRaw))
        : null;

    final scoreboardRaw = (data['scoreboard'] as List?) ?? const [];
    final scoreboard = scoreboardRaw
        .whereType<Map>()
        .map((m) => CcScoreEntry.fromMap(Map<String, dynamic>.from(m)))
        .toList(growable: false);

    state = state.copyWith(
      status: status,
      startedAt: (data['startedAt'] as num?)?.toInt() ?? state.startedAt,
      finishedAt: (data['finishedAt'] as num?)?.toInt() ?? state.finishedAt,
      aliveCount: (data['aliveCount'] as num?)?.toInt() ?? alivePlayerIds.length,
      alivePlayerIds: alivePlayerIds,
      eliminatedPlayerIds: eliminatedPlayerIds,
      palette: palette.isEmpty ? state.palette : palette,
      colorCounts: colorCounts.isEmpty ? state.colorCounts : colorCounts,
      myState: myState.hasIdentity ? myState : state.myState,
      winCondition: winCondition,
      scoreboard: scoreboardRaw.isEmpty ? state.scoreboard : scoreboard,
      timeLimitSec: (data['timeLimitSec'] as num?)?.toInt() ?? state.timeLimitSec,
      controlPoints: controlPoints.isEmpty ? state.controlPoints : controlPoints,
      playableArea: ((data['playableArea'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => CcGeoPoint.fromMap(Map<String, dynamic>.from(m)))
          .toList(growable: false),
      activeControlPointId: data['activeControlPointId'] as String?,
      nextActivationAt: (data['nextActivationAt'] as num?)?.toInt(),
      controlPointRadiusMeters:
          (data['controlPointRadiusMeters'] as num?)?.toDouble() ??
              state.controlPointRadiusMeters,
      tagRangeMeters: (data['tagRangeMeters'] as num?)?.toDouble() ??
          state.tagRangeMeters,
      missionTimeoutSec: (data['missionTimeoutSec'] as num?)?.toInt() ??
          state.missionTimeoutSec,
      cpActivationIntervalSec:
          (data['cpActivationIntervalSec'] as num?)?.toInt() ??
              state.cpActivationIntervalSec,
      cpLifespanSec: (data['cpLifespanSec'] as num?)?.toInt() ??
          state.cpLifespanSec,
      bodyAttributes:
          bodyAttributes.isEmpty ? state.bodyAttributes : bodyAttributes,
      bodyProfileSubmittedUserIds: submittedRaw.isEmpty
          ? state.bodyProfileSubmittedUserIds
          : bodyProfileSubmittedUserIds,
    );
  }

  Future<Map<String, dynamic>> startMission(String cpId) {
    return SocketService().sendCcMissionStart(
      sessionId: _sessionId,
      cpId: cpId,
    );
  }

  Future<Map<String, dynamic>> submitMission(String answer) {
    return SocketService().sendCcMissionSubmit(
      sessionId: _sessionId,
      answer: answer,
    );
  }

  Future<Map<String, dynamic>> setBodyProfile(Map<String, String> profile) {
    return SocketService().sendCcSetBodyProfile(
      sessionId: _sessionId,
      profile: profile,
    );
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _tagSub?.cancel();
    _cpActivatedSub?.cancel();
    _cpClaimedSub?.cancel();
    _cpExpiredSub?.cancel();
    _gameOverSub?.cancel();
    _connectionSub?.cancel();
    _cpEventController.close();
    super.dispose();
  }
}

class CcCpLifecycleEvent {
  CcCpLifecycleEvent({
    required this.kind,
    required this.cpId,
    this.displayName,
    this.claimedBy,
    this.lat,
    this.lng,
    this.expiresAt,
  });
  final String kind; // 'activated' | 'claimed' | 'expired'
  final String cpId;
  final String? displayName;
  final String? claimedBy;
  final double? lat;
  final double? lng;
  final int? expiresAt;
}

final colorChaserProvider = StateNotifierProvider.family
    .autoDispose<ColorChaserNotifier, ColorChaserGameState, String>(
  (ref, sessionId) => ColorChaserNotifier(sessionId),
);
