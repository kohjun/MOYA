import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maps_toolkit/maps_toolkit.dart' as mt;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/services/socket_service.dart';
import '../../../core/services/sound_service.dart';
import '../data/game_models.dart';
import 'mission/mission_entity_controller.dart';
import 'mission/mission_geo_utils.dart';
import 'mission/mission_proximity_evaluator.dart';

// ── 미션 상수 ─────────────────────────────────────────────────────────────
/// COIN_COLLECT: 코인 수집 가능 반경(m).
const double _kCoinCollectRadius = 10.0;

/// CAPTURE_ANIMAL: 동물 포획 가능 반경(m).
const double _kAnimalCaptureRadius = 5.0;

/// COIN_COLLECT: 미션당 생성 코인 개수.
const int _kCoinCount = 3;

/// COIN_COLLECT: 코인 간 최소 거리(m).
const double _kCoinMinSeparation = 8.0;

/// CAPTURE_ANIMAL: 동물 1틱 이동 최소/최대 거리(m).
const double _kAnimalMinStep = 1.5;
const double _kAnimalMaxStep = 3.0;

/// CAPTURE_ANIMAL: 동물 이동 틱 주기.
const Duration _kAnimalTickInterval = Duration(seconds: 1);

/// GPS 스트림 distanceFilter(m). 이 이상 움직였을 때만 재판정.
const int _kPositionStreamDistanceFilter = 3;

final gameProvider =
    StateNotifierProvider.family<GameNotifier, AmongUsGameState, String>(
  (ref, sessionId) => GameNotifier(sessionId),
);

class GameNotifier extends StateNotifier<AmongUsGameState> {
  GameNotifier(this._sessionId) : super(const AmongUsGameState()) {
    _entityController = MissionEntityController(
      readState: () => state,
      writeState: (next) => state = next,
      onEntitiesMoved: () {
        final pos = _lastKnownPosition;
        if (pos != null) _onLocationForMissions(pos);
      },
      coinCount: _kCoinCount,
      coinMinSeparation: _kCoinMinSeparation,
      animalMinStep: _kAnimalMinStep,
      animalMaxStep: _kAnimalMaxStep,
      animalTickInterval: _kAnimalTickInterval,
    );
    _subscribeToEvents();
    if (_socket.isConnected) {
      _socket.requestGameState(_sessionId);
    }
  }

  final String _sessionId;
  final _socket = SocketService();
  final List<StreamSubscription> _subs = [];
  int _logIdCounter = 0;
  Timer? _meetingCooldownTimer;

  // 맵 기반 미션 / 영역 이탈 감지
  StreamSubscription<Position>? _missionLocationSub;
  Position? _lastKnownPosition;

  late final MissionEntityController _entityController;

  // ── 폴리곤 캐시 ─────────────────────────────────────────────────────────
  List<mt.LatLng>? _cachedMtPolygon;
  List<Map<String, double>>? _cachedMtPolygonSource;

  List<mt.LatLng>? _getMtPolygon() {
    final area = state.playableArea;
    if (!identical(_cachedMtPolygonSource, area) || _cachedMtPolygon == null) {
      _cachedMtPolygon = MissionGeoUtils.buildPolygon(area);
      _cachedMtPolygonSource = area;
    }
    return _cachedMtPolygon;
  }

  String _resolveMinigameId(GameMission mission) {
    if (mission.minigameId.isNotEmpty) return mission.minigameId;

    final haystack = '${mission.title} ${mission.description}'.toLowerCase();
    if (haystack.contains('전선') || haystack.contains('wire')) {
      return 'wire_fix';
    }
    if (haystack.contains('카드') ||
        haystack.contains('card') ||
        haystack.contains('swipe')) {
      return 'card_swipe';
    }
    return 'wire_fix';
  }

  /// 현재 GPS 위치와 target 사이의 거리(m). GPS 미확보 시 null.
  Future<double?> distanceToLatLng(NLatLng target) async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      return Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        target.latitude,
        target.longitude,
      );
    } catch (e) {
      debugPrint('[Game] distanceToLatLng 실패: $e');
      return null;
    }
  }

  /// 동기 거리 계산 헬퍼 (Geolocator 그대로 위임).
  static double distanceBetween(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2);

  // ── GPS 콜백 → 근접/영역 이탈 판정 ─────────────────────────────────────
  void _onLocationForMissions(Position pos) {
    _lastKnownPosition = pos;

    final eval = MissionProximityEvaluator.evaluate(
      myMissions: state.myMissions,
      missionCoins: state.missionCoins,
      missionAnimals: state.missionAnimals,
      lat: pos.latitude,
      lng: pos.longitude,
      polygon: _getMtPolygon(),
      coinRadius: _kCoinCollectRadius,
      animalRadius: _kAnimalCaptureRadius,
    );

    final current = state.nearbyMissionIds;
    final nearby = eval.nearbyMissionIds;
    final nearbyChanged = nearby.length != current.length ||
        nearby.any((id) => !current.contains(id));
    final boundsChanged = eval.isOutOfBounds != null &&
        eval.isOutOfBounds != state.isOutOfBounds;
    if (!nearbyChanged && !boundsChanged) return;

    final updatedMyMissions = nearbyChanged
        ? MissionProximityEvaluator.applyProximityToMissions(
            myMissions: state.myMissions,
            nearbyIds: nearby,
          )
        : state.myMissions;

    state = state.copyWith(
      nearbyMissionIds: nearbyChanged ? nearby : current,
      myMissions: updatedMyMissions,
      isOutOfBounds: eval.isOutOfBounds ?? state.isOutOfBounds,
    );
  }

  /// CAPTURE_ANIMAL 미션의 동물을 포획 (5m 이내일 때만 성공).
  Future<bool> captureAnimalFor(String missionId) async {
    final animal = state.missionAnimals[missionId];
    if (animal == null) return false;

    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition();
    } catch (e) {
      debugPrint('[Game] captureAnimalFor: GPS 조회 실패 $e');
      return false;
    }
    final dist = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, animal.lat, animal.lng);
    if (dist > _kAnimalCaptureRadius) return false;

    _entityController.removeAnimal(missionId);
    completeMission(missionId);
    return true;
  }

  /// GPS 구독을 시작합니다. 이미 실행 중이면 무시.
  void _startMissionLocationTracking() {
    if (_missionLocationSub != null) return;
    _missionLocationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _kPositionStreamDistanceFilter,
      ),
    ).listen(_onLocationForMissions, onError: (e) {
      debugPrint('[Game] GPS stream 오류: $e');
    });
  }

  String _nextLogId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${_logIdCounter++}';

  // ── 소켓 이벤트 구독 ───────────────────────────────────────────────────
  //
  // `_subscribeToEvents`는 도메인별로 쪼갠 메서드들을 단순히 호출하는
  // 오케스트레이션 역할만 한다. 새 이벤트 유형이 생기면 해당 도메인 메서드에
  // 추가한다.
  void _subscribeToEvents() {
    _subscribeConnectionEvents();
    _subscribeLifecycleEvents();
    _subscribeMeetingEvents();
    _subscribeSabotageEvents();
    _subscribeAiEvents();
    _subscribeMissionEvents();
  }

  void _subscribeConnectionEvents() {
    _subs.add(_socket.onConnectionChange.listen((connected) {
      if (connected) {
        _socket.requestGameState(_sessionId);
      }
    }));

    _subs.add(_socket.onGameStateUpdate.listen((data) {
      final role = data['role'] as String?;
      final team = data['team'] as String?;
      final recoveredRole = role != null && team != null
          ? GameRole(
              role: role,
              team: team,
              impostors:
                  (data['impostors'] as List?)?.whereType<String>().toList() ??
                      const [],
            )
          : null;

      state = state.copyWith(
        isStarted: (data['status'] as String? ?? 'none') != 'none',
        totalPlayers: data['aliveCount'] as int? ?? state.totalPlayers,
        myRole: recoveredRole ?? state.myRole,
        shouldNavigateToRole: recoveredRole != null && state.myRole == null
            ? true
            : state.shouldNavigateToRole,
      );
    }));
  }

  void _subscribeLifecycleEvents() {
    _subs.add(_socket.onGameEvent(SocketService.gameStarted).listen((data) {
      WakelockPlus.enable();
      SoundService().playGameStart();
      _meetingCooldownTimer?.cancel();
      // 재게임 대비: 이전 게임의 역할·미션·채팅·투표 등 모든 상태를 초기화.
      // playableArea는 호스트가 게임 전에 설정하므로 유지한다.
      final currentArea = state.playableArea;
      state = AmongUsGameState(
        isStarted: true,
        totalPlayers: data['playerCount'] as int? ?? 0,
        playableArea: currentArea,
      );
      _cachedMtPolygon = null;
      _cachedMtPolygonSource = null;
    }));

    _subs
        .add(_socket.onGameEvent(SocketService.gameRoleAssigned).listen((data) {
      // 소켓 재연결로 이벤트가 중복 수신돼도 중복 역할 화면 진입을 막는다.
      final alreadyHasRole = state.myRole != null;
      state = state.copyWith(
        myRole: GameRole.fromMap(data),
        shouldNavigateToRole: alreadyHasRole ? state.shouldNavigateToRole : true,
      );
    }));

    _subs.add(_socket.onGameEvent(SocketService.gameOver).listen((data) {
      WakelockPlus.disable();
      SoundService().playGameOver();
      state = state.copyWith(
        gameOverWinner: data['winner'] as String,
      );
    }));

    _subs.add(_socket.onGameEvent(SocketService.gameKillConfirmed).listen((_) {
      // Reserved for local self-state updates when needed.
    }));
  }

  void _subscribeMeetingEvents() {
    _subs.add(
      _socket.onGameEvent(SocketService.gameMeetingStarted).listen((data) {
        state = state.copyWith(
          meetingPhase: 'discussion',
          meetingRemaining: data['discussionTime'] as int? ?? 90,
          totalVoted: 0,
          preVoteCount: 0,
          voteResult: null,
          shouldNavigateToMeeting: true,
          isMeetingCoolingDown: false,
        );
      }),
    );

    _subs.add(_socket.onGameEvent(SocketService.gameMeetingTick).listen((data) {
      state = state.copyWith(
        meetingPhase: data['phase'] as String,
        meetingRemaining: data['remaining'] as int,
      );
    }));

    _subs.add(_socket.onGameEvent(SocketService.gameVotingStarted).listen((_) {
      state = state.copyWith(meetingPhase: 'voting');
    }));

    _subs.add(
      _socket.onGameEvent(SocketService.gamePreVoteSubmitted).listen((data) {
        state = state.copyWith(
          preVoteCount: data['totalPreVotes'] as int? ?? 0,
          totalPlayers: data['totalPlayers'] as int? ?? state.totalPlayers,
        );
      }),
    );

    _subs.add(
      _socket.onGameEvent(SocketService.gameVoteSubmitted).listen((data) {
        state = state.copyWith(
          totalVoted: data['totalVotes'] as int? ?? 0,
          totalPlayers: data['totalPlayers'] as int? ?? state.totalPlayers,
        );
      }),
    );

    _subs.add(_socket.onGameEvent(SocketService.gameVoteResult).listen((data) {
      state = state.copyWith(
        meetingPhase: 'result',
        voteResult: VoteResult.fromMap(data),
      );
    }));

    _subs.add(_socket.onGameEvent(SocketService.gameMeetingEnded).listen((_) {
      state = state.copyWith(
        meetingPhase: 'none',
        isMeetingCoolingDown: true,
      );
      _meetingCooldownTimer?.cancel();
      _meetingCooldownTimer = Timer(const Duration(seconds: 30), () {
        state = state.copyWith(isMeetingCoolingDown: false);
      });
    }));
  }

  void _subscribeSabotageEvents() {
    _subs.add(
      _socket.onGameEvent(SocketService.gameSabotageActive).listen((data) {
        final missionId = data['missionId'] as String?;
        if (missionId == null) return;
        final updated = state.myMissions.map((m) {
          if (m.id == missionId) return m.copyWith(isSabotaged: true);
          return m;
        }).toList();
        state = state.copyWith(myMissions: updated);
      }),
    );

    _subs.add(
      _socket.onGameEvent(SocketService.gameSabotageFixed).listen((data) {
        final missionId = data['missionId'] as String?;
        if (missionId == null) return;
        final updated = state.myMissions.map((m) {
          if (m.id == missionId) return m.copyWith(isSabotaged: false);
          return m;
        }).toList();
        state = state.copyWith(myMissions: updated);
      }),
    );
  }

  void _subscribeAiEvents() {
    _subs.add(_socket.onGameEvent(SocketService.gameAiMessage).listen((data) {
      final log = ChatLog(
        id: _nextLogId(),
        type: ChatLogType.aiAnnounce,
        message: data['message'] as String,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(chatLogs: [...state.chatLogs, log]);
    }));

    _subs.add(_socket.onGameEvent(SocketService.gameAiReply).listen((data) {
      final isError = data['isError'] as bool? ?? false;
      final message = data['answer'] as String? ?? 'Failed to load AI response.';

      final log = ChatLog(
        id: _nextLogId(),
        type: isError ? ChatLogType.system : ChatLogType.aiReply,
        message: message,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(chatLogs: [...state.chatLogs, log]);
    }));
  }

  void _subscribeMissionEvents() {
    _subs.add(
      _socket.onGameEvent(SocketService.gameMissionProgress).listen((data) {
        final missionId = data['missionId'] as String?;
        final completed = (data['completed'] as num?)?.toInt() ?? 0;
        final total = (data['total'] as num?)?.toInt() ?? 0;
        final percent = (data['percent'] as num?)?.toDouble() ?? 0;
        final hasMission = missionId != null &&
            state.missions.any((mission) => mission.id == missionId);

        final updatedMissions = missionId == null
            ? state.missions
            : [
                ...state.missions.map(
                  (mission) => mission.id == missionId
                      ? mission.copyWith(
                          status: completed >= total && total > 0
                              ? 'completed'
                              : 'in_progress',
                        )
                      : mission,
                ),
                if (!hasMission)
                  GameMission(
                    id: missionId,
                    title: data['title'] as String? ?? missionId,
                    description: data['description'] as String? ?? '',
                    zone: data['zone'] as String? ?? '',
                    type: data['type'] as String? ?? 'MINIGAME',
                    status: completed >= total && total > 0
                        ? 'completed'
                        : 'in_progress',
                    isFake: data['isFake'] as bool? ??
                        data['fake'] as bool? ??
                        false,
                    templateTitle: data['templateTitle'] as String? ?? '',
                    minigameId: data['minigameId'] as String? ?? '',
                  ),
              ];

        state = state.copyWith(
          missions: updatedMissions,
          missionProgress: {
            'completed': completed,
            'total': total,
            'percent': percent,
          },
        );
      }),
    );

    // 서버가 전체 태스크 진행도를 broadcast로 쏘는 채널.
    _subs.add(_socket.onGameEvent(SocketService.gameTaskProgress).listen((data) {
      final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
      state = state.copyWith(totalTaskProgress: progress.clamp(0.0, 1.0));
    }));

    // 게임 시작 시 서버에서 미션 목록 수신
    _subs.add(_socket.onGameEvent(SocketService.gameMissionsAssigned).listen((data) {
      final rawList = data['missions'] as List? ?? [];
      final rawMaps = rawList
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      final gameMissions =
          rawMaps.map((m) => GameMission.fromMap(m)).toList();

      // GameMission → Mission 변환 (신규 3-타입 미션 시스템)
      // 모든 타입을 locked로 시작한다. 사용자가 미션 목록에서 '시작'을 눌러야
      // 코인/동물이 맵에 스폰되거나 미니게임 화면이 열린다.
      final myMissions = <Mission>[];
      for (final gm in gameMissions) {
        final missionType = MissionTypeX.fromWire(gm.type);
        myMissions.add(Mission(
          id: gm.id,
          title: gm.title,
          description: gm.isFake ? '[임포스터 가짜 미션] ${gm.title}' : gm.title,
          type: missionType,
          status:
              gm.isCompleted ? MissionStatus.completed : MissionStatus.locked,
          minigameId: _resolveMinigameId(gm),
          targetLatitude: gm.lat,
          targetLongitude: gm.lng,
          radius: missionType == MissionType.captureAnimal ? 5.0 : 10.0,
          isFake: gm.isFake,
        ));
      }

      final normalizedMissions = [
        for (final mission in myMissions)
          mission.copyWith(
            description: gameMissions
                    .firstWhere((gm) => gm.id == mission.id)
                    .description
                    .isNotEmpty
                ? gameMissions.firstWhere((gm) => gm.id == mission.id).description
                : mission.description,
          ),
      ];

      state = state.copyWith(
        missions: gameMissions,
        myMissions: normalizedMissions,
      );

      // 위치 트래킹은 미리 시작해 둔다 — 이후 사용자가 '시작'을 누른 미션의
      // started↔ready 전환을 즉시 반영하기 위함.
      final hasMapMission = normalizedMissions.any((m) => m.type.isMapBased);
      if (hasMapMission) _startMissionLocationTracking();
    }));
  }

  void startGame() => _socket.startGame(_sessionId);

  void sendKill(String targetUserId) =>
      _socket.sendKill(_sessionId, targetUserId);

  void sendEmergency([Function(Map)? onResult]) =>
      _socket.sendEmergencyMeeting(_sessionId, onResult);

  void sendReport(String bodyId) => _socket.sendReport(_sessionId, bodyId);

  void sendVote(String targetId, Function(Map) onResult) =>
      _socket.sendVote(_sessionId, targetId, onResult);

  // ── 미션 상태 전이 ─────────────────────────────────────────────────────
  List<Mission> get myMissions => state.myMissions;

  /// 사용자가 미션 목록에서 '시작' 버튼을 눌렀을 때 호출한다.
  /// - 맵 기반 미션이면 코인/동물을 스폰한 뒤 상태를 `started`로 올린다.
  /// - 이미 근처에 서 있으면 즉시 `ready`까지 전이된다.
  /// 반환값: 실제로 시작 처리된 [Mission] (없으면 null).
  Mission? startMission(String missionId) {
    final idx = state.myMissions.indexWhere((m) => m.id == missionId);
    if (idx < 0) return null;
    final mission = state.myMissions[idx];
    if (mission.status != MissionStatus.locked) return mission;

    if (mission.type.isMapBased) {
      final spawned = _entityController.spawnFor(mission, _getMtPolygon());
      if (!spawned) {
        debugPrint('[Game] startMission $missionId: 스폰 실패 (플레이 영역 확인 필요)');
        return null;
      }
    }

    final updated = List<Mission>.from(state.myMissions);
    updated[idx] = mission.copyWith(status: MissionStatus.started);
    state = state.copyWith(myMissions: updated);

    if (mission.type.isMapBased) {
      _startMissionLocationTracking();
      final pos = _lastKnownPosition;
      if (pos != null) _onLocationForMissions(pos);
    }

    return updated[idx];
  }

  /// 미션을 완료 처리하고 서버에 알립니다.
  /// 동일 missionId로 두 번 호출돼도 중복 전송/중복 progress 증가가 없도록 guard.
  /// 임포스터의 fake 미션은 전체 진행도에 반영하지 않는다.
  void completeMission(String missionId) {
    final idx = state.myMissions.indexWhere((m) => m.id == missionId);
    if (idx < 0) return;
    final target = state.myMissions[idx];
    if (target.status == MissionStatus.completed) return;
    final shouldAffectProgress = !target.isFake;

    final updated = List<Mission>.from(state.myMissions);
    updated[idx] = target.copyWith(status: MissionStatus.completed);

    // 낙관적 진행도 업데이트 — 서버가 나중에 정확한 값으로 덮어쓴다.
    final prog = state.missionProgress;
    final prevCompleted = (prog['completed'] as num?)?.toInt() ?? 0;
    final total = (prog['total'] as num?)?.toInt() ?? 0;
    final newCompleted =
        shouldAffectProgress ? prevCompleted + 1 : prevCompleted;
    final optimisticProgress = <String, dynamic>{
      'completed': newCompleted,
      'total': total,
      'percent': total > 0 ? ((newCompleted / total) * 100).round() : 0,
    };

    state = state.copyWith(
      myMissions: updated,
      missionProgress:
          shouldAffectProgress ? optimisticProgress : state.missionProgress,
      nearbyMissionIds:
          state.nearbyMissionIds.where((id) => id != missionId).toList(),
    );

    _socket.sendMissionComplete(_sessionId, missionId);
  }

  /// 임포스터가 특정 미션에 사보타지를 발동합니다.
  void triggerSabotage(String missionId) {
    _socket.sendTriggerSabotage(_sessionId, missionId);
  }

  /// 크루원이 사보타지 수리 미니게임을 클리어하면 호출됩니다.
  void fixSabotage(String missionId) {
    final updated = state.myMissions.map((m) {
      if (m.id == missionId) return m.copyWith(isSabotaged: false);
      return m;
    }).toList();
    state = state.copyWith(myMissions: updated);
    _socket.sendFixSabotage(_sessionId, missionId);
  }

  /// GameMeetingScreen 이동 후 호출하여 플래그를 리셋합니다.
  void resetMeetingNavigation() {
    state = state.copyWith(shouldNavigateToMeeting: false);
  }

  /// 긴급 회의를 소집합니다.
  void callMeeting([Function(Map)? callback]) {
    state = state.copyWith(isMeetingCoolingDown: true);
    _socket.sendEmergencyMeeting(_sessionId, callback);
  }

  /// 호스트가 설정한 플레이 가능 영역 폴리곤을 상태에 저장합니다.
  /// null을 전달하면 이탈 경고 판정이 비활성화됩니다.
  void setPlayableArea(List<Map<String, double>>? area) {
    state = state.copyWith(
      playableArea: area,
      isOutOfBounds: area == null || area.length < 3 ? false : state.isOutOfBounds,
    );
    _cachedMtPolygon = null;
    _cachedMtPolygonSource = null;
    if (area != null && area.length >= 3) {
      // 코인/동물 스폰은 사용자가 미션별 '시작'을 눌러야 일어난다 (auto-spawn 금지).
      _startMissionLocationTracking();
    }
  }

  /// COIN_COLLECT 미션의 가장 가까운 미수집 코인을 수집합니다.
  /// 모든 코인 수집 시 미션 완료 처리 후 서버 동기화합니다.
  /// 반환값:
  ///   - `null` : 수집 실패 (GPS 범위 밖 등)
  ///   - `false`: 코인 1개 수집, 아직 남은 코인이 있음
  ///   - `true` : 마지막 코인 수집 → 미션 완료 처리됨
  Future<bool?> collectNearestCoinFor(String missionId) async {
    final coins = state.missionCoins[missionId];
    if (coins == null || coins.isEmpty) return null;

    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition();
    } catch (e) {
      debugPrint('[Game] collectNearestCoinFor: GPS 조회 실패 $e');
      return null;
    }

    int? bestIdx;
    double bestDist = double.infinity;
    for (var i = 0; i < coins.length; i++) {
      final c = coins[i];
      if (c.collected) continue;
      final d = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, c.lat, c.lng);
      if (d < bestDist && d <= _kCoinCollectRadius) {
        bestDist = d;
        bestIdx = i;
      }
    }
    if (bestIdx == null) return null;

    final updated = List<CoinPoint>.from(coins);
    updated[bestIdx] = updated[bestIdx].copyWith(collected: true);
    final map = Map<String, List<CoinPoint>>.from(state.missionCoins)
      ..[missionId] = updated;
    state = state.copyWith(missionCoins: map);

    if (updated.every((c) => c.collected)) {
      completeMission(missionId);
      return true;
    }
    return false;
  }

  void resetRoleNavigation() {
    state = state.copyWith(shouldNavigateToRole: false);
  }

  void askAI(String question) {
    final myLog = ChatLog(
      id: _nextLogId(),
      type: ChatLogType.myQuestion,
      message: question,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(chatLogs: [...state.chatLogs, myLog]);

    _socket.sendAiQuestion(_sessionId, question, (res) {
      if (res['ok'] == true) return;

      final errLog = ChatLog(
        id: _nextLogId(),
        type: ChatLogType.system,
        message: 'Failed to send: ${res['error']}',
        timestamp: DateTime.now(),
      );
      state = state.copyWith(chatLogs: [...state.chatLogs, errLog]);
    });
  }

  @override
  void dispose() {
    // Provider 해제 시 WakeLock 반드시 해제 (메모리 누수 방지)
    WakelockPlus.disable();
    _meetingCooldownTimer?.cancel();
    _entityController.dispose();
    for (final sub in _subs) {
      sub.cancel();
    }
    _missionLocationSub?.cancel();
    super.dispose();
  }
}
