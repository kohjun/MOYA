// lib/core/services/socket_service.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../network/api_client.dart';

const _wsUrl = 'http://10.0.2.2:3000';

// ─────────────────────────────────────────────────────────────────────────────
// 위치 데이터 모델
// ─────────────────────────────────────────────────────────────────────────────
class LocationPayload {
  final String userId;
  final String? nickname;
  final double lat;
  final double lng;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final String source;
  final int? battery;
  final String status;
  final int ts;

  const LocationPayload({
    required this.userId,
    this.nickname,
    required this.lat,
    required this.lng,
    this.accuracy,
    this.speed,
    this.heading,
    this.source = 'gps',
    this.battery,
    this.status = 'moving',
    required this.ts,
  });

  factory LocationPayload.fromMap(Map<String, dynamic> map) => LocationPayload(
        userId:   map['userId']   as String,
        nickname: map['nickname'] as String?,
        lat:      (map['lat']     as num).toDouble(),
        lng:      (map['lng']     as num).toDouble(),
        accuracy: (map['accuracy'] as num?)?.toDouble(),
        speed:    (map['speed']   as num?)?.toDouble(),
        heading:  (map['heading'] as num?)?.toDouble(),
        source:   map['source']   as String? ?? 'gps',
        battery:  map['battery']  as int?,
        status:   map['status']   as String? ?? 'moving',
        ts:       map['ts']       as int? ?? DateTime.now().millisecondsSinceEpoch,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Socket 이벤트 상수 (백엔드 EVENTS와 동기화)
// ─────────────────────────────────────────────────────────────────────────────
class SocketEvents {
  // Client → Server
  static const joinSession    = 'session:join';
  static const leaveSession   = 'session:leave';
  static const locationUpdate = 'location:update';
  static const statusUpdate   = 'status:update';
  static const sosTrigger     = 'sos:trigger';

  // Server → Client
  static const sessionJoined   = 'session:joined';
  static const memberJoined    = 'member:joined';
  static const memberLeft      = 'member:left';
  static const locationChanged = 'location:changed';
  static const statusChanged   = 'status:changed';
  static const sosAlert        = 'sos:alert';
  static const sessionSnapshot = 'session:snapshot';
  static const kicked          = 'kicked';
  static const roleChanged     = 'role_changed';
  static const error           = 'error';
}

// ─────────────────────────────────────────────────────────────────────────────
// SocketService - 싱글톤
// ─────────────────────────────────────────────────────────────────────────────
class SocketService {
  io.Socket? _socket;
  bool _isConnected = false;
  String? _currentSessionId;

  // ── 지수 백오프 재연결 ────────────────────────────────────────────────────
  int    _reconnectAttempts   = 0;
  bool   _reconnectScheduled  = false;
  Timer? _reconnectTimer;
  static const _baseDelayMs      = 3000;  // 초기 대기 시간: 3s
  static const _maxDelayMs       = 30000; // 최대 대기 시간: 30s
  static const _maxReconnectAttempts = 3; // 최대 재연결 횟수

  // 스트림 컨트롤러 (UI 레이어에서 구독)
  final _locationController    = StreamController<LocationPayload>.broadcast();
  final _memberJoinController  = StreamController<Map<String, dynamic>>.broadcast();
  final _memberLeftController  = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController      = StreamController<Map<String, dynamic>>.broadcast();
  final _sosController         = StreamController<Map<String, dynamic>>.broadcast();
  final _snapshotController    = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController  = StreamController<bool>.broadcast();
  final _kickedController      = StreamController<Map<String, dynamic>>.broadcast();
  final _roleChangedController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<LocationPayload>         get onLocationChanged => _locationController.stream;
  Stream<Map<String, dynamic>>    get onMemberJoined    => _memberJoinController.stream;
  Stream<Map<String, dynamic>>    get onMemberLeft      => _memberLeftController.stream;
  Stream<Map<String, dynamic>>    get onStatusChanged   => _statusController.stream;
  Stream<Map<String, dynamic>>    get onSosAlert        => _sosController.stream;
  Stream<Map<String, dynamic>>    get onSnapshot        => _snapshotController.stream;
  Stream<bool>                    get onConnectionChange => _connectionController.stream;
  Stream<Map<String, dynamic>>    get onKicked          => _kickedController.stream;
  Stream<Map<String, dynamic>>    get onRoleChanged     => _roleChangedController.stream;
  bool get isConnected => _isConnected;

  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  // ─────────────────────────────────────────────────────────────────────────
  // WebSocket 연결 (Access Token 전달)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> connect() async {
    if (_isConnected) return;

    final token = await ApiClient().getAccessToken();
    if (token == null) throw Exception('NOT_AUTHENTICATED');

    _socket = io.io(
      _wsUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()          // 핸들러 등록 후 수동 연결
          .disableReconnection()         // socket.io 내장 재연결 비활성화 → 직접 관리
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .setAuth({'token': token})
          .build(),
    );

    _registerEventHandlers();
    _socket!.connect(); // 핸들러 등록 후 연결 시작
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 이벤트 핸들러 등록
  // ─────────────────────────────────────────────────────────────────────────
  void _registerEventHandlers() {
    _socket!
      ..onConnect((_) {
        _isConnected = true;
        _reconnectAttempts  = 0;         // 성공 시 카운터 초기화
        _reconnectScheduled = false;
        _reconnectTimer?.cancel();
        _connectionController.add(true);
        debugPrint('[Socket] Connected');
      })
      ..onDisconnect((reason) {
        _isConnected = false;
        _connectionController.add(false);
        debugPrint('[Socket] Disconnected: $reason');
        // 클라이언트 측 수동 해제가 아닐 때만 재연결 시도
        if (reason != 'io client disconnect') {
          _scheduleReconnect();
        }
      })
      ..onConnectError((err) {
        debugPrint('[Socket] Connect error: $err');
        _scheduleReconnect();
      })

      // 다른 멤버 위치 수신
      ..on(SocketEvents.locationChanged, (data) {
        try {
          final payload = LocationPayload.fromMap(Map<String, dynamic>.from(data));
          _locationController.add(payload);
        } catch (e) {
          debugPrint('[Socket] locationChanged parse error: $e');
        }
      })

      // 멤버 입장/퇴장
      ..on(SocketEvents.memberJoined, (data) =>
          _memberJoinController.add(Map<String, dynamic>.from(data)))
      ..on(SocketEvents.memberLeft, (data) =>
          _memberLeftController.add(Map<String, dynamic>.from(data)))

      // 상태 변경
      ..on(SocketEvents.statusChanged, (data) =>
          _statusController.add(Map<String, dynamic>.from(data)))

      // SOS 알림
      ..on(SocketEvents.sosAlert, (data) =>
          _sosController.add(Map<String, dynamic>.from(data)))

      // 세션 참가 시 전체 스냅샷
      ..on(SocketEvents.sessionSnapshot, (data) =>
          _snapshotController.add(Map<String, dynamic>.from(data)))

      // 강제 퇴장
      ..on(SocketEvents.kicked, (data) =>
          _kickedController.add(Map<String, dynamic>.from(data as Map? ?? {})))

      // 역할 변경 브로드캐스트
      ..on(SocketEvents.roleChanged, (data) =>
          _roleChangedController.add(Map<String, dynamic>.from(data as Map? ?? {})));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 세션 참가
  // ─────────────────────────────────────────────────────────────────────────
  void joinSession(String sessionId) {
    _currentSessionId = sessionId;
    _socket?.emit(SocketEvents.joinSession, {'sessionId': sessionId});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 내 위치 전송 (GPS / BLE / UWB 공통)
  // ─────────────────────────────────────────────────────────────────────────
  void sendLocation({
    required double lat,
    required double lng,
    double? accuracy,
    double? altitude,
    double? speed,
    double? heading,
    String source = 'gps',
    int? battery,
    String status = 'moving',
  }) {
    if (!_isConnected || _currentSessionId == null) return;

    _socket?.emit(SocketEvents.locationUpdate, {
      'sessionId': _currentSessionId,
      'lat':       lat,
      'lng':       lng,
      'accuracy':  accuracy,
      'altitude':  altitude,
      'speed':     speed,
      'heading':   heading,
      'source':    source,
      'battery':   battery,
      'status':    status,
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SOS 발송
  // ─────────────────────────────────────────────────────────────────────────
  void sendSOS({double? lat, double? lng, String? message}) {
    if (!_isConnected || _currentSessionId == null) return;

    _socket?.emit(SocketEvents.sosTrigger, {
      'sessionId': _currentSessionId,
      'lat':       lat,
      'lng':       lng,
      'message':   message ?? '긴급 상황 발생!',
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 상태 업데이트 (이동중/정지/SOS)
  // ─────────────────────────────────────────────────────────────────────────
  void updateStatus(String status, {int? battery}) {
    _socket?.emit(SocketEvents.statusUpdate, {
      'sessionId': _currentSessionId,
      'status':    status,
      'battery':   battery,
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 지수 백오프 재연결 스케줄러
  // 2s → 4s → 8s → 16s → 30s(최대) 순으로 대기 후 재연결
  // ─────────────────────────────────────────────────────────────────────────
  void _scheduleReconnect() {
    if (_reconnectScheduled) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[Socket] 최대 재연결 횟수 초과 ($_maxReconnectAttempts회)');
      return;
    }
    _reconnectScheduled = true;

    final delayMs = math.min(
      _baseDelayMs * math.pow(2, _reconnectAttempts).toInt(),
      _maxDelayMs,
    );
    debugPrint('[Socket] 재연결 예약: ${delayMs}ms 후 (시도 ${_reconnectAttempts + 1}/$_maxReconnectAttempts)');

    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      _reconnectScheduled = false;
      _reconnectAttempts++;
      _socket?.connect();
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 연결 해제
  // ─────────────────────────────────────────────────────────────────────────
  void disconnect() {
    _reconnectTimer?.cancel();         // 예약된 재연결 취소
    _reconnectAttempts  = 0;
    _reconnectScheduled = false;
    _socket?.disconnect();
    _socket = null;
    _isConnected = false;
    _currentSessionId = null;
  }

  void dispose() {
    _reconnectTimer?.cancel();
    disconnect();
    _locationController.close();
    _memberJoinController.close();
    _memberLeftController.close();
    _statusController.close();
    _sosController.close();
    _snapshotController.close();
    _connectionController.close();
    _kickedController.close();
    _roleChangedController.close();
  }
}
