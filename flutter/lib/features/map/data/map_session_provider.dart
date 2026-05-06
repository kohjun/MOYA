// lib/features/map/data/map_session_provider.dart
//
// MapSessionNotifier + mapSessionProvider
// (map_screen.dart에서 추출. 소켓/GPS/오디오/지오펜스 상태를 통합 관리)

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../../../core/services/background_service.dart';
import '../../../core/services/fantasy_wars_ble_presence_service.dart';
import '../../../core/services/mediasoup_audio_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart';
import '../../home/data/session_repository.dart';
import '../../geofence/data/geofence_repository.dart';
import '../presentation/map_session_models.dart';

// BLE presence enum 의 이름을 문자열로 변환. enum.name 게터에 의존하면
// 빌드 캐시/hot-reload 불일치 시 NoSuchMethodError 가 polluting GC 까지 유발한
// 사례가 있어, 명시적 매핑으로 안정화한다.
String _blePresenceStateLabel(BlePresenceLifecycleState s) => switch (s) {
      BlePresenceLifecycleState.idle => 'idle',
      BlePresenceLifecycleState.unsupported => 'unsupported',
      BlePresenceLifecycleState.requestingPermission => 'requestingPermission',
      BlePresenceLifecycleState.permissionDenied => 'permissionDenied',
      BlePresenceLifecycleState.bluetoothUnavailable => 'bluetoothUnavailable',
      BlePresenceLifecycleState.starting => 'starting',
      BlePresenceLifecycleState.running => 'running',
      BlePresenceLifecycleState.error => 'error',
    };

class MapSessionNotifier extends StateNotifier<MapSessionState>
    with WidgetsBindingObserver {
  MapSessionNotifier(this._sessionId, this._ref)
      : super(const MapSessionState(members: {})) {
    _init();
  }

  final String _sessionId;
  final Ref _ref;

  final _socket = SocketService();
  final _audio = MediaSoupAudioService();
  final _ble = FantasyWarsBlePresenceService();
  final _gps = GpsLocationService();

  StreamSubscription? _locationSub;
  StreamSubscription? _memberJoinSub;
  StreamSubscription? _memberLeftSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _sosSub;
  StreamSubscription? _snapshotSub;
  StreamSubscription? _connectionSub;
  StreamSubscription? _myPositionSub;
  StreamSubscription? _kickedSub;
  StreamSubscription? _roleChangedSub;
  StreamSubscription? _sessionExpiredSub;
  StreamSubscription? _proximityKilledSub;
  StreamSubscription? _playerEliminatedSub;
  StreamSubscription? _gameStateSub;
  StreamSubscription? _gameOverSub;
  StreamSubscription? _bleSightingSub;
  StreamSubscription? _bleStatusSub;

  Timer? _joinRetryTimer;
  Timer? _backgroundStartTimer;

  final Map<String, MemberState> _pendingUpdates = {};
  Timer? _markerFlushTimer;
  final Stopwatch _startupStopwatch = Stopwatch();
  bool _backgroundServiceStartRequested = false;
  bool _backgroundServiceConfigured = false;
  bool _backgroundServiceRunning = false;

  // NaverMap 첫 onMapReady 시그널. mediasoup Device.load(jingle_peerconnection_so)
  // 와 BG service flutter engine boot 가 NaverMap PlatformView 첫 attach 와
  // 같은 ~5초 윈도에 몰리면 Davey 4초+ 가 발생한다. 화면이 first map ready 를
  // 알릴 때까지 두 작업을 미뤄 동시 폭주를 분산시킨다.
  final Completer<void> _firstMapReadyCompleter = Completer<void>();
  // 안전 fallback: NaverMap auth 실패/로딩 무한 대기 시에도 두 작업이 영원히
  // 발화되지 않으면 안 되므로, 일정 시간 후 강제로 complete.
  static const Duration _firstMapReadyTimeout = Duration(seconds: 8);

  /// 게임 화면(`_handleNaverMapReady`)에서 호출. idempotent.
  void signalFirstMapReady() {
    if (_firstMapReadyCompleter.isCompleted) return;
    _firstMapReadyCompleter.complete();
  }

  Future<void> _awaitFirstMapReady() async {
    if (_firstMapReadyCompleter.isCompleted) return;
    await _firstMapReadyCompleter.future
        .timeout(_firstMapReadyTimeout, onTimeout: () {});
  }

  final Set<String> _insideGeofences = {};
  List<dynamic> _currentGeofences = [];

  // 내 위치 throttle 상태 (GPS 1틱당 cascade rebuild 방지)
  DateTime? _lastMyPosAppliedAt;
  double? _lastMyPosLat;
  double? _lastMyPosLng;

  // BLE sighting throttle 상태
  // - 동일 userId 의 RSSI 변동이 임계 미만이면 350ms 단위로 batch flush.
  // - 새 device, deviceId 변경, 임계 초과 변동은 즉시 emit.
  static const int _bleRssiDeltaThreshold = 5; // dBm
  static const Duration _bleFlushInterval = Duration(milliseconds: 350);
  final Map<String, BleMemberContact> _pendingBleContacts = {};
  Timer? _bleFlushTimer;

  StreamSubscription<T> _listen<T>(
    Stream<T> stream,
    void Function(T data) onData,
  ) {
    return stream.listen((data) {
      if (!mounted) return;
      onData(data);
    });
  }

  void _logStartupStep(String label) {}

  Future<void> _bootstrapSession(SharedPreferences prefs) async {
    await Future.microtask(() {});
    await _connectRealtime();
    _logStartupStep('connected realtime services');

    await Future.microtask(() {});
    await _startGpsTracking();
    _logStartupStep('started gps tracking');

    await Future.microtask(() {});
    await _loadInitialMembers();
    _logStartupStep('loaded initial members');

    // BackgroundService 사전 시작은 WebRTC 까지 안정된 뒤로 더 미룬다.
    // BG service 가 FlutterEngine 을 새로 띄우는 비용이 ~3-7초 Davey 의 직접
    // 원인. Android 12+ 정책상 백그라운드 진입 후 startService 가 거부되므로
    // 포그라운드인 지금 미리 startService 를 호출하되, foreground_active=true
    // 플래그로 위치 추적은 멈춰 둔다.
    //
    // 추가로 NaverMap 첫 onMapReady 시그널을 기다린 뒤 1초 더 양보 — NaverMap
    // PlatformView 첫 attach 와 BG flutter engine boot 가 같은 프레임에 메인
    // 스레드를 점유하지 않게 분산.
    unawaited(() async {
      await _awaitFirstMapReady();
      if (!mounted) return;
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      await _prepareBackgroundService(prefs);
    }());
  }

  Future<void> _connectRealtime() async {
    try {
      await _socket.connect();
      if (_socket.isConnected) {
        state = state.copyWith(isConnected: true, hasEverConnected: true);
        _socket.joinSession(_sessionId);
        _socket.requestGameState(_sessionId);
        // mediasoup device load / transport 생성은 WebRTC 네이티브 라이브러리
        // (jingle_peerconnection_so) 로딩이 무거워 메인 스레드를 길게 점유한다.
        // NaverMap PlatformView 첫 attach 와 같은 프레임에 충돌하면 Davey 2~3초.
        // → onMapReady 시그널을 기다린 뒤 짧은 추가 지연(500ms)으로 분산.
        unawaited(() async {
          await _awaitFirstMapReady();
          if (!mounted) return;
          await WidgetsBinding.instance.endOfFrame;
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          await _audio.ensureJoined(_sessionId);
        }());
      }
    } catch (e) {
      debugPrint('[Map] Socket connect failed: $e');
    }
  }

  // Android 12+ 는 앱이 백그라운드로 내려간 뒤에 location FGS 를 시작하려고 하면
  // ForegroundServiceStartNotAllowedException 으로 거부한다. 그래서 서비스는
  // 포그라운드 상태에서 미리 startService() 까지 호출해 두고,
  // bg_foreground_active=true 플래그로 백그라운드 작업 자체는 멈춰 둔다.
  // 앱이 실제로 백그라운드로 내려가면 setForegroundActive(false) invoke 만으로
  // 위치 추적이 재개되므로 추가 startService 호출이 필요 없다.
  Future<void> _prepareBackgroundService(SharedPreferences prefs) async {
    if (_backgroundServiceStartRequested) return;
    _backgroundServiceStartRequested = true;

    try {
      await prefs.setString('bg_session_id', _sessionId);
      await prefs.setString('bg_server_url', kApiBaseUrl);

      final token = await ApiClient().getAccessToken();
      if (token != null) {
        await prefs.setString('bg_token', token);
      }

      await prefs.setBool('bg_active', true);
      await prefs.setBool('bg_foreground_active', true);
      await initializeBackgroundService();
      _backgroundServiceConfigured = true;

      // Pre-start the service while still in foreground so the FGS notification
      // is visible to Android. The service stays paused via foreground_active.
      try {
        final service = FlutterBackgroundService();
        final running = await service.isRunning();
        if (!running) {
          await service.startService();
        }
        service.invoke('setForegroundActive', {'active': true});
        _backgroundServiceRunning = true;
      } catch (e) {
        debugPrint('[Background] foreground pre-start failed: $e');
      }
    } catch (e) {
      debugPrint('[Background] Failed to configure background service: $e');
      _backgroundServiceStartRequested = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_enterForegroundMode());
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state.name == 'hidden') {
      unawaited(_enterBackgroundMode());
    }
  }

  Future<void> _enterForegroundMode() async {
    _backgroundStartTimer?.cancel();
    _backgroundStartTimer = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('bg_active', true);
      await prefs.setBool('bg_foreground_active', true);
    } catch (_) {}

    // 서비스를 멈추는 대신 setForegroundActive(true) 만 보내 추적을 일시정지한다.
    // 매 lifecycle 마다 stopService 후 백그라운드에서 startService 재호출하면
    // Android 가 FGS 시작을 거부하거나 추가 Flutter 엔진이 생성된다.
    try {
      final service = FlutterBackgroundService();
      service.invoke('setForegroundActive', {'active': true});
    } catch (e) {
      debugPrint('[Background] foreground handoff failed: $e');
    }
  }

  Future<void> _enterBackgroundMode() async {
    if (!mounted) return;

    _backgroundStartTimer?.cancel();
    _backgroundStartTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_resumeBackgroundTracking());
    });
  }

  Future<void> _resumeBackgroundTracking() async {
    if (!mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('bg_active', true);
      await prefs.setBool('bg_foreground_active', false);

      final service = FlutterBackgroundService();

      // 이미 포그라운드에서 서비스가 정상 시작된 상태라면 invoke 하나만 보내고 끝낸다.
      if (_backgroundServiceRunning) {
        service.invoke('setForegroundActive', {'active': false});
        return;
      }

      // 서비스가 어떤 이유로든 아직 살아있지 않으면 한 번 더 시도한다.
      // 이때도 startService 자체는 _prepareBackgroundService 가 포그라운드에서
      // 이미 호출했어야 하는 게 정상 흐름이다.
      if (!_backgroundServiceConfigured) {
        await _prepareBackgroundService(prefs);
      }

      service.invoke('setForegroundActive', {'active': false});

      final running = await service.isRunning();
      if (!running) {
        // 포그라운드 사전 시작이 실패한 fallback 경로. 여기서 startService 가
        // ForegroundServiceStartNotAllowedException 으로 거부될 수 있으므로
        // 예외를 그대로 삼키고 다음 resume 때 다시 시도하도록 둔다.
        try {
          await service.startService();
          _backgroundServiceRunning = true;
        } catch (e) {
          debugPrint('[Background] deferred startService failed: $e');
        }
      } else {
        _backgroundServiceRunning = true;
      }
      debugPrint('[Background] resumed tracking after app backgrounded');
    } catch (e) {
      debugPrint('[Background] background resume failed: $e');
    }
  }

  Future<void> _init() async {
    _startupStopwatch.start();
    WidgetsBinding.instance.addObserver(this);
    final cachedSessions = _ref.read(sessionListProvider).valueOrNull ?? [];
    final cached = cachedSessions.where((s) => s.id == _sessionId);

    if (cached.isNotEmpty) {
      state = state.copyWith(sessionName: cached.first.name);
    }

    final prefs = await SharedPreferences.getInstance();
    final hiddenList = prefs.getStringList('hidden_$_sessionId') ?? [];
    if (hiddenList.isNotEmpty) {
      state = state.copyWith(hiddenMembers: Set.from(hiddenList));
    }

    try {
      _currentGeofences =
          await _ref.read(geofenceRepositoryProvider).getGeofences(_sessionId);
    } catch (e) {
      debugPrint('[Map] 지오펜스 로드 실패: $e');
    }

    _bindSocketStreams();
    _bindBleStreams();
    _logStartupStep('restored cached state');

    unawaited(_bootstrapSession(prefs));

    _joinRetryTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && state.members.isEmpty && state.isConnected) {
        _socket.joinSession(_sessionId);
      }
    });
  }

  void _bindSocketStreams() {
    _kickedSub = _listen(_socket.onKicked, (data) {
      state = state.copyWith(wasKicked: true);
    });

    _sessionExpiredSub = _listen(_socket.onSessionExpired, (data) {
      debugPrint('[Map] 세션 만료 수신: ${data['message']}');
      state = state.copyWith(wasKicked: true);
    });

    _proximityKilledSub = _listen(_socket.onProximityKilled, (data) {
      debugPrint('[Map] proximity:killed 수신 - killedBy: ${data['killedBy']}');
      state = state.copyWith(isEliminated: true);
    });

    _playerEliminatedSub = _listen(_socket.onPlayerEliminated, (data) {
      final eliminatedId = data['userId'] as String?;
      if (eliminatedId == null) return;
      debugPrint('[Map] player:eliminated 수신 - userId: $eliminatedId');
      state = state.copyWith(
        eliminatedUserIds: {...state.eliminatedUserIds, eliminatedId},
      );
    });

    _gameStateSub = _listen(_socket.onGameStateUpdate, (data) {
      state = state.copyWith(gameState: GameState.fromMap(data));
      unawaited(_syncBlePresenceLifecycle());
    });

    _gameOverSub = _listen(_socket.onGameOver, (data) {
      state = state.copyWith(
        gameState: GameState(
          status: 'finished',
          winnerId: data['winnerId'] as String?,
        ),
      );
      unawaited(_syncBlePresenceLifecycle());
    });

    _roleChangedSub = _listen(_socket.onRoleChanged, (data) {
      final userId = data['userId'] as String?;
      final role = data['role'] as String?;
      if (userId == null || role == null) return;
      final authUser = _ref.read(authProvider).valueOrNull;
      if (userId == authUser?.id) {
        state = state.copyWith(myRole: role);
      }
      final updated = Map<String, MemberState>.from(state.members);
      if (updated.containsKey(userId)) {
        updated[userId] = updated[userId]!.copyWith(role: role);
        state = state.copyWith(members: updated);
      }
    });

    _connectionSub = _listen(_socket.onConnectionChange, (connected) {
      state = state.copyWith(
        isConnected: connected,
        hasEverConnected: connected ? true : state.hasEverConnected,
      );
      unawaited(_syncBlePresenceLifecycle());
      if (connected) {
        _socket.joinSession(_sessionId);
        // Defer audio reconnect to avoid blocking map rendering on reconnection.
        unawaited(() async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          if (!mounted) return;
          await _audio.ensureJoined(_sessionId);
        }());
      }
    });

    // 피어 위치 업데이트는 누적해서 800ms 간격으로 한 번만 state 갱신.
    // 500ms 였을 때 매 frame 단위로 widget tree rebuild 가 일어나 GPU 부담이 컸음.
    // 800ms 면 마커 이동이 여전히 부드럽고, fwState 와 합쳐 평균 rebuild 빈도가
    // 절반 가까이 떨어진다.
    _markerFlushTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (!mounted) return;
      if (_pendingUpdates.isEmpty) return;
      final updated = Map<String, MemberState>.from(state.members)
        ..addAll(_pendingUpdates);
      _pendingUpdates.clear();
      state = state.copyWith(members: updated);
    });

    _locationSub = _listen(_socket.onLocationChanged, (payload) {
      if (payload.sessionId != null && payload.sessionId != _sessionId) {
        return;
      }
      final current =
          _pendingUpdates[payload.userId] ?? state.members[payload.userId];

      if (current != null && (current.lat != 0 || current.lng != 0)) {
        final dist = Geolocator.distanceBetween(
          current.lat,
          current.lng,
          payload.lat,
          payload.lng,
        );
        if (dist < 1) return; // 1m 미만 이동은 무시 (GPS 노이즈)
      }

      _pendingUpdates[payload.userId] = current != null
          ? current.copyWith(
              lat: payload.lat,
              lng: payload.lng,
              battery: payload.battery,
              status: payload.status,
              updatedAt: DateTime.now(),
            )
          : MemberState(
              userId: payload.userId,
              nickname: payload.nickname ?? payload.userId,
              lat: payload.lat,
              lng: payload.lng,
              battery: payload.battery,
              status: payload.status,
              updatedAt: DateTime.now(),
            );
    });

    _memberJoinSub = _listen(_socket.onMemberJoined, (data) {
      final userId = data['userId'] as String? ?? '';
      final nickname = data['nickname'] as String? ?? userId;
      final updated = Map<String, MemberState>.from(state.members);
      if (!updated.containsKey(userId)) {
        updated[userId] = MemberState(
          userId: userId,
          nickname: nickname,
          lat: 0,
          lng: 0,
          status: 'idle',
          updatedAt: DateTime.now(),
        );
        state = state.copyWith(members: updated);
      }
      unawaited(_syncBlePresenceLifecycle());
    });

    _memberLeftSub = _listen(_socket.onMemberLeft, (data) {
      final userId = data['userId'] as String? ?? '';
      final updated = Map<String, MemberState>.from(state.members)
        ..remove(userId);
      state = state.copyWith(members: updated);
      unawaited(_syncBlePresenceLifecycle());
    });

    _statusSub = _listen(_socket.onStatusChanged, (data) {
      final userId = data['userId'] as String? ?? '';
      final status = data['status'] as String? ?? 'idle';
      final battery = data['battery'] as int?;
      final updated = Map<String, MemberState>.from(state.members);
      if (updated.containsKey(userId)) {
        updated[userId] =
            updated[userId]!.copyWith(status: status, battery: battery);
        state = state.copyWith(members: updated);
      }
    });

    _sosSub = _listen(_socket.onSosAlert, (_) {
      state = state.copyWith(sosTriggered: true);
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) state = state.copyWith(sosTriggered: false);
      });
    });

    _snapshotSub = _listen(_socket.onSnapshot, (data) {
      final members = data['members'] as List<dynamic>? ?? [];
      final locations =
          (data['locations'] as Map?)?.cast<String, dynamic>() ?? const {};
      final updated = Map<String, MemberState>.from(state.members);
      for (final m in members) {
        if (m is! Map<String, dynamic>) continue;
        final userId = m['user_id'] as String? ?? '';
        final nickname = m['nickname'] as String? ?? userId;
        if (userId.isEmpty) continue;
        final loc = (locations[userId] as Map?)?.cast<String, dynamic>() ??
            (m['lastLocation'] as Map<String, dynamic>?);
        final lat = (loc?['lat'] as num?)?.toDouble();
        final lng = (loc?['lng'] as num?)?.toDouble();
        final role = m['role'] as String? ?? 'member';
        final sharingEnabled = m['sharing_enabled'] as bool? ?? true;

        updated[userId] = MemberState(
          userId: userId,
          nickname: nickname,
          lat: lat ?? 0,
          lng: lng ?? 0,
          battery: loc?['battery'] as int?,
          status: loc?['status'] as String? ?? 'idle',
          role: role,
          sharingEnabled: sharingEnabled,
          updatedAt: DateTime.now(),
        );
      }
      state = state.copyWith(members: updated);

      final authUser = _ref.read(authProvider).valueOrNull;
      if (authUser != null && updated.containsKey(authUser.id)) {
        final me = updated[authUser.id]!;
        state = state.copyWith(
          myRole: me.role,
          sharingEnabled: false,
        );
        _gps.setSharingEnabled(false);
      }
      unawaited(_syncBlePresenceLifecycle());
    });
  }

  void _bindBleStreams() {
    state = state.copyWith(
      blePresenceStatus: _ble.status.state.name,
      blePresenceMessage: _ble.status.message,
    );

    _bleSightingSub = _listen(_ble.sightings, (sighting) {
      final next = BleMemberContact(
        userId: sighting.userId,
        rssi: sighting.rssi,
        seenAtMs: sighting.seenAtMs,
        deviceId: sighting.deviceId,
      );
      _pendingBleContacts[sighting.userId] = next;

      // 즉시 emit 조건: 새 contact / deviceId 변경 / RSSI 임계 초과 변동.
      // 그 외에는 350ms 후 batch flush 로 합쳐 rebuild 폭주 방지.
      final existing = state.bleContacts[sighting.userId];
      final isNew = existing == null;
      final deviceChanged =
          existing != null && existing.deviceId != sighting.deviceId;
      final rssiDelta =
          existing == null ? 0 : (sighting.rssi - existing.rssi).abs();
      if (isNew || deviceChanged || rssiDelta >= _bleRssiDeltaThreshold) {
        _flushPendingBleContacts();
        return;
      }

      _bleFlushTimer ??= Timer(_bleFlushInterval, _flushPendingBleContacts);
    });

    _bleStatusSub = _listen(_ble.statuses, (status) {
      state = state.copyWith(
        blePresenceStatus: _blePresenceStateLabel(status.state),
        blePresenceMessage: status.message,
      );
    });
  }

  void _flushPendingBleContacts() {
    _bleFlushTimer?.cancel();
    _bleFlushTimer = null;
    if (!mounted) return;
    if (_pendingBleContacts.isEmpty) return;
    final updated = Map<String, BleMemberContact>.from(state.bleContacts)
      ..addAll(_pendingBleContacts);
    _pendingBleContacts.clear();
    state = state.copyWith(bleContacts: updated);
  }

  // BLE는 결투 수락 시점에 BleDuelNotifier가 관리하므로
  // map_session_provider에서는 자동 시작하지 않는다.
  Future<void> _syncBlePresenceLifecycle() async {}

  Future<void> _startGpsTracking() async {
    try {
      _gps.setSessionId(_sessionId);
      await _gps.startTracking();
      _myPositionSub = _listen(_gps.positionStream, (pos) {
        // ── Throttle: 2.5초 미만 & 8m 미만 이동은 무시 (NaverMap rebuild 폭주 방지) ──
        final now = DateTime.now();
        final movedEnough = _lastMyPosLat == null ||
            _haversineMeters(
                  _lastMyPosLat!,
                  _lastMyPosLng!,
                  pos.latitude,
                  pos.longitude,
                ) >=
                8.0;
        final timeEnough = _lastMyPosAppliedAt == null ||
            now.difference(_lastMyPosAppliedAt!).inMilliseconds >= 2500;
        if (!movedEnough && !timeEnough) {
          _checkGeofences(pos);
          return;
        }
        _lastMyPosAppliedAt = now;
        _lastMyPosLat = pos.latitude;
        _lastMyPosLng = pos.longitude;

        // ── 모든 변경을 단일 state 갱신으로 합침 (rebuild 1회) ──
        final authUser = _ref.read(authProvider).valueOrNull;
        if (authUser == null) {
          state = state.copyWith(myPosition: pos);
          _checkGeofences(pos);
          return;
        }

        final myId = authUser.id;
        final currentMe = state.members[myId];
        Map<String, MemberState> members = state.members;
        if (currentMe != null) {
          members = Map<String, MemberState>.from(members);
          members[myId] = currentMe.copyWith(
            lat: pos.latitude,
            lng: pos.longitude,
            updatedAt: now,
          );
        }

        final distances = <String, double>{};
        double closestDist = double.infinity;
        String? closestId;
        for (final entry in members.entries) {
          if (entry.key == myId) continue;
          final member = entry.value;
          if (member.lat == 0 && member.lng == 0) continue;
          final dist = _haversineMeters(
            pos.latitude,
            pos.longitude,
            member.lat,
            member.lng,
          );
          distances[member.userId] = dist;
          if (dist < closestDist) {
            closestDist = dist;
            closestId = member.userId;
          }
        }

        state = state.copyWith(
          myPosition: pos,
          members: members,
          memberDistances: distances,
          proximateTargetId: closestDist <= 15.0 ? closestId : null,
        );

        _checkGeofences(pos);
      });
    } catch (e) {
      debugPrint('[Map] GPS failed: $e');
    }
  }

  Future<void> _loadInitialMembers() async {
    try {
      final session =
          await _ref.read(sessionRepositoryProvider).getSession(_sessionId);
      final initialMembers = Map<String, MemberState>.from(state.members);
      for (final member in session.members) {
        if (!initialMembers.containsKey(member.userId)) {
          initialMembers[member.userId] = MemberState(
            userId: member.userId,
            nickname: member.nickname,
            lat: member.latitude ?? 0,
            lng: member.longitude ?? 0,
            battery: member.battery,
            status: member.status,
            role: member.role,
            sharingEnabled: member.sharingEnabled,
            updatedAt: DateTime.now(),
          );
        }
      }
      state = state.copyWith(members: initialMembers);

      final authUser = _ref.read(authProvider).valueOrNull;
      if (authUser != null) {
        final myList = session.members
            .where((member) => member.userId == authUser.id)
            .toList();
        if (myList.isNotEmpty) {
          final me = myList.first;
          state = state.copyWith(
            myRole: me.role,
            sharingEnabled: false,
          );
          _gps.setSharingEnabled(false);
        }
      }
    } catch (e) {
      debugPrint('[Map] Failed to load session members: $e');
    }

    unawaited(_syncBlePresenceLifecycle());
  }

  static double _haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  void _checkGeofences(Position myPos) {
    if (_currentGeofences.isEmpty) return;

    for (final gf in _currentGeofences) {
      double distance = Geolocator.distanceBetween(
        myPos.latitude,
        myPos.longitude,
        gf.latitude,
        gf.longitude,
      );

      bool isCurrentlyInside = distance <= gf.radius;
      bool wasInside = _insideGeofences.contains(gf.id);

      if (isCurrentlyInside && !wasInside) {
        _insideGeofences.add(gf.id);
        debugPrint('[Geofence] 진입: ${gf.name}');
      } else if (!isCurrentlyInside && wasInside) {
        _insideGeofences.remove(gf.id);
        debugPrint('[Geofence] 이탈: ${gf.name}');
      }
    }
  }

  Future<void> toggleSharing(bool enabled) async {
    try {
      await _ref
          .read(sessionRepositoryProvider)
          .toggleSharing(_sessionId, enabled);
      _gps.setSharingEnabled(enabled);
      state = state.copyWith(sharingEnabled: enabled);

      if (enabled) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        state = state.copyWith(myPosition: pos);

        final authUser = _ref.read(authProvider).valueOrNull;
        if (authUser != null) {
          final myId = authUser.id;
          final currentMe = state.members[myId];

          if (currentMe != null) {
            final updated = Map<String, MemberState>.from(state.members);
            updated[myId] = currentMe.copyWith(
              lat: pos.latitude,
              lng: pos.longitude,
              status: 'moving',
              updatedAt: DateTime.now(),
            );
            state = state.copyWith(members: updated);
          }

          _socket.sendLocationUpdate(
              _sessionId, pos.latitude, pos.longitude, 'moving');
        }
      }
    } catch (e) {
      debugPrint('[Map] toggleSharing failed: $e');
    }
  }

  Future<void> toggleHideMember(String userId) async {
    final updated = Set<String>.from(state.hiddenMembers);
    if (updated.contains(userId)) {
      updated.remove(userId);
    } else {
      updated.add(userId);
    }
    state = state.copyWith(hiddenMembers: updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hidden_$_sessionId', updated.toList());
  }

  void triggerSOS() {
    final pos = state.myPosition;
    _socket.sendSOS(lat: pos?.latitude, lng: pos?.longitude);
  }

  void startGame() {
    _socket.emitGameStart(_sessionId);
  }

  Future<void> reconnect() async {
    try {
      await _socket.connect();
      if (_socket.isConnected) {
        state = state.copyWith(isConnected: true, hasEverConnected: true);
        _socket.joinSession(_sessionId);
        unawaited(_syncBlePresenceLifecycle());
      }
    } catch (e) {
      debugPrint('[Map] Socket reconnect failed: $e');
    }
  }

  @override
  void dispose() {
    _joinRetryTimer?.cancel();
    _backgroundStartTimer?.cancel();
    if (!_firstMapReadyCompleter.isCompleted) {
      _firstMapReadyCompleter.complete();
    }
    WidgetsBinding.instance.removeObserver(this);
    _markerFlushTimer?.cancel();
    _locationSub?.cancel();
    _memberJoinSub?.cancel();
    _memberLeftSub?.cancel();
    _statusSub?.cancel();
    _sosSub?.cancel();
    _snapshotSub?.cancel();
    _connectionSub?.cancel();
    _myPositionSub?.cancel();
    _kickedSub?.cancel();
    _roleChangedSub?.cancel();
    _sessionExpiredSub?.cancel();
    _proximityKilledSub?.cancel();
    _playerEliminatedSub?.cancel();
    _gameStateSub?.cancel();
    _gameOverSub?.cancel();
    _bleSightingSub?.cancel();
    _bleStatusSub?.cancel();
    _bleFlushTimer?.cancel();
    _pendingBleContacts.clear();
    _gps.setSessionId(null);
    _gps.stopTracking();
    unawaited(_ble.stop());
    unawaited(_audio.leaveSession());
    _socket.disconnect();
    SharedPreferences.getInstance().then((p) async {
      await p.setBool('bg_active', false);
      await p.setBool('bg_foreground_active', false);
    });
    FlutterBackgroundService().invoke('stopService');
    debugPrint('[Background] 포그라운드 서비스 종료 신호 발송');
    super.dispose();
  }
}

final mapSessionProvider = StateNotifierProvider.family
    .autoDispose<MapSessionNotifier, MapSessionState, String>(
  (ref, sessionId) => MapSessionNotifier(sessionId, ref),
);
