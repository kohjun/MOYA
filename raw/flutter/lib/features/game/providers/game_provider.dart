import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maps_toolkit/maps_toolkit.dart' as mt;
import 'package:wakelock_plus/wakelock_plus.dart'; // Task 2: 화면 꺼짐 방지

import '../../../core/services/socket_service.dart';
import '../../../core/services/sound_service.dart';
import '../data/game_models.dart';

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

  // ── [Stage 4] 위치 기반 미션 / 영역 이탈 감지 ─────────────────────────────
  StreamSubscription<Position>? _missionLocationSub;

  /// 가장 최근 GPS 위치 (동물 이동 틱 후 재-proximity 판정용).
  Position? _lastKnownPosition;

  /// CAPTURE_ANIMAL 동물 이동 타이머.
  Timer? _animalMovementTimer;

  /// 현재 `state.playableArea`에 대응하는 캐시된 `mt.LatLng` 폴리곤.
  /// setPlayableArea 호출 시마다 무효화되어 lazily 재생성됩니다.
  List<mt.LatLng>? _cachedMtPolygon;
  List<Map<String, double>>? _cachedMtPolygonSource;

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

  /// 캐시된 mt.LatLng 폴리곤을 반환. 없으면 null.
  List<mt.LatLng>? _getMtPolygon() {
    final area = state.playableArea;
    if (area == null || area.length < 3) {
      _cachedMtPolygon = null;
      _cachedMtPolygonSource = null;
      return null;
    }
    if (!identical(_cachedMtPolygonSource, area) || _cachedMtPolygon == null) {
      _cachedMtPolygon = area
          .map((p) => mt.LatLng(p['lat'] ?? 0.0, p['lng'] ?? 0.0))
          .toList(growable: false);
      _cachedMtPolygonSource = area;
    }
    return _cachedMtPolygon;
  }

  /// GPS 위치를 받을 때마다 근접 판정 + 영역 이탈 감지를 수행합니다.
  void _onLocationForMissions(Position pos) {
    _lastKnownPosition = pos;

    // 1) 플레이 영역 이탈 감지
    final poly = _getMtPolygon();
    final bool? outOfBounds = poly == null
        ? null
        : !mt.PolygonUtil.containsLocation(
            mt.LatLng(pos.latitude, pos.longitude), poly, false);

    // 2) 근접 판정 — 사용자가 '시작'한 미션(started/ready)만 평가한다.
    //    locked 상태는 스폰 전이므로 건드리지 않는다.
    final nearby = <String>[];
    for (final mission in state.myMissions) {
      if (mission.status == MissionStatus.completed) continue;
      if (mission.status == MissionStatus.locked) continue;

      switch (mission.type) {
        case MissionType.coinCollect:
          final coins = state.missionCoins[mission.id];
          if (coins == null) break;
          final hit = coins.any((c) =>
              !c.collected &&
              Geolocator.distanceBetween(
                      pos.latitude, pos.longitude, c.lat, c.lng) <=
                  _kCoinCollectRadius);
          if (hit) nearby.add(mission.id);
          break;
        case MissionType.captureAnimal:
          final animal = state.missionAnimals[mission.id];
          if (animal == null) break;
          final d = Geolocator.distanceBetween(
              pos.latitude, pos.longitude, animal.lat, animal.lng);
          if (d <= _kAnimalCaptureRadius) nearby.add(mission.id);
          break;
        case MissionType.minigame:
          // MINIGAME은 위치 무관 — '시작'을 누르면 바로 플레이 화면으로 진입하므로
          // proximity 근접 후보에서 제외한다.
          break;
      }
    }

    // 3) 변경 감지 (불필요한 리빌드 방지)
    final current = state.nearbyMissionIds;
    final nearbyChanged = nearby.length != current.length ||
        nearby.any((id) => !current.contains(id));
    final boundsChanged =
        outOfBounds != null && outOfBounds != state.isOutOfBounds;
    if (!nearbyChanged && !boundsChanged) return;

    final updatedMyMissions = nearbyChanged
        ? state.myMissions.map((m) {
            if (m.status == MissionStatus.completed) return m;
            if (m.status == MissionStatus.locked) return m;
            // minigame은 started에서 바로 플레이되므로 proximity 무관.
            if (m.type == MissionType.minigame) return m;
            final isNear = nearby.contains(m.id);
            if (isNear && m.status == MissionStatus.started) {
              return m.copyWith(status: MissionStatus.ready);
            }
            if (!isNear && m.status == MissionStatus.ready) {
              return m.copyWith(status: MissionStatus.started);
            }
            return m;
          }).toList()
        : state.myMissions;

    state = state.copyWith(
      nearbyMissionIds: nearbyChanged ? nearby : current,
      myMissions: updatedMyMissions,
      isOutOfBounds: outOfBounds ?? state.isOutOfBounds,
    );
  }

  /// 폴리곤 내부의 랜덤 좌표 하나를 반환. 실패 시 무게 중심으로 폴백.
  static mt.LatLng _randomPointInPolygon(
    List<mt.LatLng> polygon, {
    int maxRetries = 60,
  }) {
    double minLat = polygon.first.latitude, maxLat = polygon.first.latitude;
    double minLng = polygon.first.longitude, maxLng = polygon.first.longitude;
    for (final p in polygon) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final rng = math.Random();
    for (var i = 0; i < maxRetries; i++) {
      final candidate = mt.LatLng(
        minLat + rng.nextDouble() * (maxLat - minLat),
        minLng + rng.nextDouble() * (maxLng - minLng),
      );
      if (mt.PolygonUtil.containsLocation(candidate, polygon, false)) {
        return candidate;
      }
    }

    final cLat =
        polygon.map((p) => p.latitude).reduce((a, b) => a + b) / polygon.length;
    final cLng =
        polygon.map((p) => p.longitude).reduce((a, b) => a + b) /
            polygon.length;
    return mt.LatLng(cLat, cLng);
  }

  /// 폴리곤 내부에서 서로 [minSep]m 이상 떨어진 [count]개의 좌표를 샘플링.
  static List<mt.LatLng> _randomPointsInPolygon(
    List<mt.LatLng> polygon, {
    required int count,
    required double minSep,
    int maxGuard = 200,
  }) {
    final result = <mt.LatLng>[];
    var guard = 0;
    while (result.length < count && guard < maxGuard) {
      guard++;
      final p = _randomPointInPolygon(polygon);
      final tooClose = result.any((q) =>
          Geolocator.distanceBetween(
              q.latitude, q.longitude, p.latitude, p.longitude) <
          minSep);
      if (tooClose) continue;
      result.add(p);
    }
    return result;
  }

  /// 단일 미션의 월드 엔티티(코인/동물)를 스폰한다.
  /// - 폴리곤이 없거나 3 미만이면 no-op.
  /// - 이미 스폰돼 있으면 idempotent하게 건너뜀.
  /// - minigame 타입은 스폰할 엔티티가 없어 no-op.
  /// 반환값: 실제로 스폰이 수행됐는지 여부.
  bool _spawnMissionEntities(Mission mission) {
    final poly = _getMtPolygon();
    if (poly == null) return false;
    if (mission.status == MissionStatus.completed) return false;

    switch (mission.type) {
      case MissionType.coinCollect:
        final existing = state.missionCoins[mission.id];
        if (existing != null && existing.isNotEmpty) return false;
        final pts = _randomPointsInPolygon(
          poly,
          count: _kCoinCount,
          minSep: _kCoinMinSeparation,
        );
        if (pts.isEmpty) return false;
        final coins = Map<String, List<CoinPoint>>.from(state.missionCoins)
          ..[mission.id] = pts
              .map((p) => CoinPoint(lat: p.latitude, lng: p.longitude))
              .toList();
        state = state.copyWith(missionCoins: coins);
        return true;

      case MissionType.captureAnimal:
        if (state.missionAnimals.containsKey(mission.id)) return false;
        final p = _randomPointInPolygon(poly);
        final animals = Map<String, AnimalPoint>.from(state.missionAnimals)
          ..[mission.id] = AnimalPoint(
            lat: p.latitude,
            lng: p.longitude,
            headingDeg: math.Random().nextDouble() * 360,
          );
        state = state.copyWith(missionAnimals: animals);
        _startAnimalMovement();
        return true;

      case MissionType.minigame:
        return false;
    }
  }

  /// 매 틱 각 동물을 1.5~3.0m 랜덤 이동시키는 타이머 시작.
  void _startAnimalMovement() {
    if (_animalMovementTimer != null) return;
    if (state.missionAnimals.isEmpty) return;
    _animalMovementTimer =
        Timer.periodic(_kAnimalTickInterval, (_) => _tickAnimals());
  }

  /// 동물 1틱 이동: 현재 heading → 폴리곤 밖이면 180° 반사 → 랜덤 재시도.
  void _tickAnimals() {
    final poly = _getMtPolygon();
    if (poly == null) return;
    if (state.missionAnimals.isEmpty) {
      _animalMovementTimer?.cancel();
      _animalMovementTimer = null;
      return;
    }

    final rng = math.Random();
    final updated = <String, AnimalPoint>{};
    var changed = false;

    state.missionAnimals.forEach((missionId, animal) {
      // 완료된 미션의 동물은 제거.
      final mission = state.myMissions.firstWhere(
        (m) => m.id == missionId,
        orElse: () => const Mission(
          id: '',
          title: '',
          description: '',
          type: MissionType.captureAnimal,
          minigameId: '',
          status: MissionStatus.completed,
        ),
      );
      if (mission.id.isEmpty || mission.status == MissionStatus.completed) {
        changed = true;
        return;
      }

      final distance = _kAnimalMinStep +
          rng.nextDouble() * (_kAnimalMaxStep - _kAnimalMinStep);
      final from = mt.LatLng(animal.lat, animal.lng);

      mt.LatLng? candidate;
      var heading = animal.headingDeg;

      for (var attempt = 0; attempt < 3; attempt++) {
        final next = mt.SphericalUtil.computeOffset(from, distance, heading);
        if (mt.PolygonUtil.containsLocation(next, poly, false)) {
          candidate = next;
          break;
        }
        heading = attempt == 0
            ? (heading + 180) % 360
            : rng.nextDouble() * 360;
      }

      if (candidate != null) {
        updated[missionId] = AnimalPoint(
          lat: candidate.latitude,
          lng: candidate.longitude,
          headingDeg: heading,
        );
      } else {
        updated[missionId] =
            animal.copyWith(headingDeg: rng.nextDouble() * 360);
      }
      changed = true;
    });

    if (!changed) return;
    state = state.copyWith(missionAnimals: updated);

    final pos = _lastKnownPosition;
    if (pos != null) _onLocationForMissions(pos);

    if (updated.isEmpty) {
      _animalMovementTimer?.cancel();
      _animalMovementTimer = null;
    }
  }

  /// CAPTURE_ANIMAL 미션의 동물을 포획 (5m 이내일 때만 성공).
  /// 반환값: 실제로 포획에 성공했는지 여부 (UI 스낵바 분기용).
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

    final map = Map<String, AnimalPoint>.from(state.missionAnimals)
      ..remove(missionId);
    state = state.copyWith(missionAnimals: map);

    if (map.isEmpty) {
      _animalMovementTimer?.cancel();
      _animalMovementTimer = null;
    }

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
  // ─────────────────────────────────────────────────────────────────────────

  String _nextLogId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${_logIdCounter++}';

  void _subscribeToEvents() {
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

    _subs.add(_socket.onGameEvent(SocketService.gameStarted).listen((data) {
      // [Task 2] 게임 시작 시 WakeLock 활성화 + 효과음
      WakelockPlus.enable();
      SoundService().playGameStart();
      state = state.copyWith(
        isStarted: true,
        totalPlayers: data['playerCount'] as int? ?? 0,
      );
    }));

    _subs
        .add(_socket.onGameEvent(SocketService.gameRoleAssigned).listen((data) {
      // 역할이 아직 없을 때만 화면 전환 플래그를 세웁니다.
      // 소켓 재연결로 이벤트가 중복 수신돼도 중복 진입을 막습니다.
      final alreadyHasRole = state.myRole != null;
      state = state.copyWith(
        myRole: GameRole.fromMap(data),
        shouldNavigateToRole: alreadyHasRole ? state.shouldNavigateToRole : true,
      );
    }));

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
      // 30초 후 쿨타임 해제
      _meetingCooldownTimer?.cancel();
      _meetingCooldownTimer = Timer(const Duration(seconds: 30), () {
        state = state.copyWith(isMeetingCoolingDown: false);
      });
    }));

    // ── 사보타지 이벤트 ───────────────────────────────────────────────────
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

    // [4단계] 서버에서 전체 태스크 진행도 수신
    _subs.add(_socket.onGameEvent(SocketService.gameTaskProgress).listen((data) {
      final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
      state = state.copyWith(totalTaskProgress: progress.clamp(0.0, 1.0));
    }));

    _subs.add(_socket.onGameEvent(SocketService.gameOver).listen((data) {
      // [Task 2] 게임 종료 시 WakeLock 해제 + 효과음
      WakelockPlus.disable();
      SoundService().playGameOver();
      state = state.copyWith(
        gameOverWinner: data['winner'] as String,
      );
    }));

    _subs.add(_socket.onGameEvent(SocketService.gameKillConfirmed).listen((_) {
      // Reserved for local self-state updates when needed.
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

  // ── [1단계] 미니게임 미션 관리 ────────────────────────────────────────────────

  List<Mission> get myMissions => state.myMissions;

  /// 사용자가 미션 목록에서 '시작' 버튼을 눌렀을 때 호출한다.
  /// - 해당 미션의 코인/동물을 스폰하고 상태를 [MissionStatus.started]로 올린다.
  /// - 맵 기반이면 즉시 proximity 재평가를 돌려, 이미 근처에 서 있으면 바로
  ///   [MissionStatus.ready]까지 전이된다.
  /// - 이미 started/ready/completed 상태이거나 존재하지 않는 미션이면 no-op.
  /// 반환값: 실제로 시작 처리된 [Mission] (없으면 null).
  Mission? startMission(String missionId) {
    final idx = state.myMissions.indexWhere((m) => m.id == missionId);
    if (idx < 0) return null;
    final mission = state.myMissions[idx];
    if (mission.status != MissionStatus.locked) return mission;

    if (mission.type.isMapBased) {
      final spawned = _spawnMissionEntities(mission);
      if (!spawned) {
        // 폴리곤 미설정 등으로 스폰 실패 시 상태를 전환하지 않는다.
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
  void completeMission(String missionId) {
    final idx = state.myMissions.indexWhere((m) => m.id == missionId);
    if (idx < 0) return;
    final target = state.myMissions[idx];
    if (target.status == MissionStatus.completed) return;
    final shouldAffectProgress = !target.isFake;

    // 1) myMissions 업데이트
    final updated = List<Mission>.from(state.myMissions);
    updated[idx] = target.copyWith(status: MissionStatus.completed);

    // 2) 진행도 낙관적 업데이트 — 서버가 나중에 정확한 값으로 덮어쓴다.
    //    로컬에서 즉시 진행 바를 움직여 피드백 딜레이를 제거.
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

    // 3) 서버 동기화 — 서버가 실제 total/percent를 계산해 broadcast로 덮어쓴다.
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
      // 영역이 사라지면 이탈 플래그도 해제.
      isOutOfBounds: area == null || area.length < 3 ? false : state.isOutOfBounds,
    );
    // 폴리곤 캐시 무효화.
    _cachedMtPolygon = null;
    _cachedMtPolygonSource = null;
    if (area != null && area.length >= 3) {
      // 코인/동물 스폰은 사용자가 미션별 '시작'을 눌렀을 때 일어난다 (auto-spawn 금지).
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

    // 모두 수집했으면 미션 완료
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
    // [Task 2] Provider 해제 시 WakeLock 반드시 해제 (메모리 누수 방지)
    WakelockPlus.disable();
    _meetingCooldownTimer?.cancel();
    _animalMovementTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    _missionLocationSub?.cancel(); // [Stage 4] 미션 GPS 구독 해제
    super.dispose();
  }
}
