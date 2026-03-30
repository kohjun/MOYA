// lib/core/services/location_service.dart

import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'socket_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 위치 수집 설정
// ─────────────────────────────────────────────────────────────────────────────
class LocationConfig {
  // 이동 중: 고정밀, 짧은 간격
  static const AndroidSettings androidMoving = AndroidSettings(
    accuracy: LocationAccuracy.high,
    intervalDuration: Duration(seconds: 3),
    distanceFilter: 5,  // 5m 이상 이동 시에만 갱신
    foregroundNotificationConfig: ForegroundNotificationConfig(
      notificationText: '위치를 공유하고 있습니다',
      notificationTitle: '📍 위치 공유 중',
      enableWakeLock: true,
    ),
  );

  // 정지 중: 배터리 절약 모드
  static const AndroidSettings androidIdle = AndroidSettings(
    accuracy: LocationAccuracy.medium,
    intervalDuration: Duration(seconds: 15),
    distanceFilter: 20,
  );

  static const AppleSettings iosSettings = AppleSettings(
    accuracy: LocationAccuracy.high,
    activityType: ActivityType.fitness,
    distanceFilter: 5,
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
  bool _isTracking = false;
  bool _isMoving = false;

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
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;

    return true;  // whileInUse 또는 always
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 위치 추적 시작
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> startTracking() async {
    if (_isTracking) return;

    final hasPermission = await requestPermission();
    if (!hasPermission) throw Exception('LOCATION_PERMISSION_DENIED');

    _isTracking = true;

    // 플랫폼별 설정
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _onPositionUpdate,
      onError: (error) => print('[GPS] Error: $error'),
    );

    // 상태(이동중/정지) 감지 타이머
    _startStatusDetection();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 위치 업데이트 처리
  // ─────────────────────────────────────────────────────────────────────────
  void _onPositionUpdate(Position position) {
    _lastPosition = position;
    _positionController.add(position);

    // 이동 상태 감지 (속도 0.5 m/s 이상이면 이동 중)
    final speed = position.speed;
    _isMoving = speed > 0.5;

    // WebSocket으로 전송 (최소 1초 간격)
    final now = DateTime.now();
    final timeSinceLast = _lastSentAt == null
        ? 999999
        : now.difference(_lastSentAt!).inMilliseconds;

    if (timeSinceLast >= 1000) {
      _sendToSocket(position);
      _lastSentAt = now;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Socket으로 위치 전송
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _sendToSocket(Position position) async {
    int? batteryLevel;
    try {
      batteryLevel = await _battery.batteryLevel;
    } catch (_) {}

    final status = _isMoving ? 'moving' : 'stopped';

    SocketService().sendLocation(
      lat:      position.latitude,
      lng:      position.longitude,
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed:    position.speed.isNaN ? null : position.speed,
      heading:  position.heading.isNaN ? null : position.heading,
      source:   'gps',
      battery:  batteryLevel,
      status:   status,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 이동 상태 감지 (정지 시 전송 빈도 줄임)
  // ─────────────────────────────────────────────────────────────────────────
  void _startStatusDetection() {
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_lastPosition == null) return;

      // 30초 동안 이동이 없으면 상태 업데이트
      int? battery;
      try { battery = await _battery.batteryLevel; } catch (_) {}

      SocketService().updateStatus(
        _isMoving ? 'moving' : 'stopped',
        battery: battery,
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
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  bool get isTracking => _isTracking;

  void dispose() {
    stopTracking();
    _positionController.close();
  }
}
