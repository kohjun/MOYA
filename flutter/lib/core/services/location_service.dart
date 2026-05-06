// lib/core/services/location_service.dart

import 'dart:async';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'permission_lock.dart';
import 'socket_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 위치 수집 설정
// ─────────────────────────────────────────────────────────────────────────────
class LocationConfig {
  // 이동 중: 고정밀, 짧은 간격
  // 포그라운드 UI 내부에서 GpsLocationService가 동작하므로 알림 설정은
  // background_service.dart 쪽에만 둡니다.
  static final AndroidSettings androidMoving = AndroidSettings(
    accuracy: LocationAccuracy.high,
    intervalDuration: const Duration(seconds: 5),
    distanceFilter: 12,
  );

  // 정지 중: 배터리 절약 모드
  static final AndroidSettings androidIdle = AndroidSettings(
    accuracy: LocationAccuracy.medium,
    intervalDuration: const Duration(seconds: 30),
    distanceFilter: 30,
  );

  static final AppleSettings iosSettings = AppleSettings(
    accuracy: LocationAccuracy.high,
    activityType: ActivityType.fitness,
    distanceFilter: 10,
    pauseLocationUpdatesAutomatically: true,
    showBackgroundLocationIndicator: true,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// GPS 서비스
// ─────────────────────────────────────────────────────────────────────────────
class GpsLocationService {
  StreamSubscription<Position>? _positionSub;
  Position? _lastPosition;
  DateTime? _lastSentAt;
  DateTime? _lastBroadcastAt;
  Position? _lastBroadcastPosition;
  bool _isTracking = false;
  bool _isMoving = false;
  bool _publicSharingEnabled = false;
  String? _sessionId;

  final _battery = Battery();
  Timer? _statusTimer;

  final _positionController = StreamController<Position>.broadcast();
  Stream<Position> get positionStream => _positionController.stream;
  Position? get lastPosition => _lastPosition;

  // ─────────────────────────────────────────────────────────────────────────
  // 권한 요청 및 확인
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      // BLE/Audio 권한과 동시 진행 시 native 측 race 가능 → 전역 lock 으로 직렬화.
      permission = await PermissionLock.run<LocationPermission>(() async {
        try {
          return await Geolocator.requestPermission();
        } catch (e) {
          debugPrint('[GPS] permission request failed: $e');
          return LocationPermission.denied;
        }
      });
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;

    return true; // whileInUse 또는 always
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 세션 ID 설정 (null 전달 시 전송 중지)
  // ─────────────────────────────────────────────────────────────────────────
  void setSessionId(String? sessionId) {
    _sessionId = sessionId;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 위치 추적 시작
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> startTracking() async {
    if (_isTracking) return;

    final hasPermission = await requestPermission();
    if (!hasPermission) throw Exception('LOCATION_PERMISSION_DENIED');

    _isTracking = true;

    final locationSettings = Platform.isAndroid
        ? LocationConfig.androidMoving
        : LocationConfig.iosSettings;

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _onPositionUpdate,
      onError: (error) => debugPrint('[GPS] Error: $error'),
    );

    // 상태(이동중/정지) 감지 타이머
    _startStatusDetection();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 위치 업데이트 처리
  // ─────────────────────────────────────────────────────────────────────────
  void _onPositionUpdate(Position position) {
    // ── [Anti-Cheat] Mock(가상) 위치 감지 ────────────────────────────────────
    // 릴리스 빌드에서만 적용. 에뮬레이터/개발 환경은 모든 위치가 mocked이므로
    // 디버그 모드에서는 건너뜀.
    if (!kDebugMode && position.isMocked) {
      debugPrint('[GPS] ⚠️ Mock(가상) 위치 감지! 치트 신고 후 추적을 중단합니다.');
      SocketService().emit(
        SocketEvents.actionInteract,
        {
          'sessionId': _sessionId,
          'actionType': 'CHEAT_DETECTED',
        },
      );
      Future.microtask(stopTracking);
      return;
    }
    // ─────────────────────────────────────────────────────────────────────────

    _lastPosition = position;

    // 이동 상태 감지 (속도 0.5 m/s 이상이면 이동 중)
    final speed = position.speed;
    _isMoving = speed > 0.5;

    // 다운스트림 throttle: 지도 platform view rebuild 폭주를 막기 위해
    // 2.5초 또는 8m 이상 이동 시에만 UI/provider로 broadcast한다.
    final nowBroadcast = DateTime.now();
    final shouldBroadcast = _lastBroadcastAt == null ||
        nowBroadcast.difference(_lastBroadcastAt!).inMilliseconds >= 2500 ||
        (_lastBroadcastPosition != null &&
            Geolocator.distanceBetween(
                  _lastBroadcastPosition!.latitude,
                  _lastBroadcastPosition!.longitude,
                  position.latitude,
                  position.longitude,
                ) >=
                8.0);
    if (shouldBroadcast) {
      _lastBroadcastAt = nowBroadcast;
      _lastBroadcastPosition = position;
      _positionController.add(position);
    }

    // WebSocket으로 전송 (최소 1초 간격)
    final now = DateTime.now();
    final timeSinceLast = _lastSentAt == null
        ? 999999
        : now.difference(_lastSentAt!).inMilliseconds;

    if (timeSinceLast >= 5000) {
      _sendToSocket(position);
      _lastSentAt = now;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 위치 공유 ON/OFF 제어
  // ─────────────────────────────────────────────────────────────────────────
  void setSharingEnabled(bool enabled) {
    _publicSharingEnabled = enabled;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Socket으로 위치 전송
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _sendToSocket(Position position) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;

    int? batteryLevel;
    try {
      batteryLevel = await _battery.batteryLevel;
    } catch (e) {
      debugPrint('[Battery] 배터리 레벨 읽기 실패: $e');
      batteryLevel = null; // null로 처리하고 계속 진행
    }

    final status = _isMoving ? 'moving' : 'stopped';

    SocketService().sendLocationWithSession(
      sessionId: sessionId,
      lat: position.latitude,
      lng: position.longitude,
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed.isNaN ? null : position.speed,
      heading: position.heading.isNaN ? null : position.heading,
      source: 'gps',
      battery: batteryLevel,
      status: status,
      visibility: _publicSharingEnabled ? 'public' : 'private',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 이동 상태 감지 (정지 시 전송 빈도 줄임)
  // ─────────────────────────────────────────────────────────────────────────
  void _startStatusDetection() {
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_lastPosition == null) return;
      final sessionId = _sessionId;
      if (sessionId == null) return;

      // 30초 동안 이동이 없으면 상태 업데이트
      int? battery;
      try {
        battery = await _battery.batteryLevel;
      } catch (_) {}

      final pos = _lastPosition!;
      SocketService().sendLocationWithSession(
        sessionId: sessionId,
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        altitude: pos.altitude,
        speed: pos.speed.isNaN ? null : pos.speed,
        heading: pos.heading.isNaN ? null : pos.heading,
        source: 'gps',
        battery: battery,
        status: _isMoving ? 'moving' : 'stopped',
        visibility: _publicSharingEnabled ? 'public' : 'private',
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 추적 중지
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> stopTracking() async {
    await _positionSub?.cancel();
    _statusTimer?.cancel();
    _isTracking = false;
    _lastPosition = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 현재 위치 즉시 조회 (일회성)
  // ─────────────────────────────────────────────────────────────────────────
  Future<Position> getCurrentPosition() async {
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // ── [Anti-Cheat] 일회성 조회에도 Mock 위치 검사 적용 (릴리스 빌드만) ────────
    if (!kDebugMode && position.isMocked) {
      debugPrint('[GPS] ⚠️ Mock(가상) 위치 감지! (일회성 getCurrentPosition)');
      SocketService().emit(
        SocketEvents.actionInteract,
        {
          'sessionId': _sessionId,
          'actionType': 'CHEAT_DETECTED',
        },
      );
      throw Exception('MOCK_LOCATION_DETECTED');
    }
    // ─────────────────────────────────────────────────────────────────────────

    return position;
  }

  bool get isTracking => _isTracking;

  void dispose() {
    stopTracking();
    _positionController.close();
  }
}
