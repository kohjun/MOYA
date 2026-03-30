// lib/core/services/socket_service.dart

import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../network/api_client.dart';

const _wsUrl = 'http://localhost:3000';

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
  static const error           = 'error';
}

// ─────────────────────────────────────────────────────────────────────────────
// SocketService - 싱글톤
// ─────────────────────────────────────────────────────────────────────────────
class SocketService {
  io.Socket? _socket;
  bool _isConnected = false;
  String? _currentSessionId;

  // 스트림 컨트롤러 (UI 레이어에서 구독)
  final _locationController    = StreamController<LocationPayload>.broadcast();
  final _memberJoinController  = StreamController<Map<String, dynamic>>.broadcast();
  final _memberLeftController  = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController      = StreamController<Map<String, dynamic>>.broadcast();
  final _sosController         = StreamController<Map<String, dynamic>>.broadcast();
  final _snapshotController    = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController  = StreamController<bool>.broadcast();

  Stream<LocationPayload>         get onLocationChanged => _locationController.stream;
  Stream<Map<String, dynamic>>    get onMemberJoined    => _memberJoinController.stream;
  Stream<Map<String, dynamic>>    get onMemberLeft      => _memberLeftController.stream;
  Stream<Map<String, dynamic>>    get onStatusChanged   => _statusController.stream;
  Stream<Map<String, dynamic>>    get onSosAlert        => _sosController.stream;
  Stream<Map<String, dynamic>>    get onSnapshot        => _snapshotController.stream;
  Stream<bool>                    get onConnectionChange => _connectionController.stream;
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
          .enableAutoConnect()
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .setAuth({'token': token})  // Socket.IO auth 방식
          .setReconnectionAttempts(5)
          .setReconnectionDelay(2000)
          .build(),
    );

    _registerEventHandlers();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 이벤트 핸들러 등록
  // ─────────────────────────────────────────────────────────────────────────
  void _registerEventHandlers() {
    _socket!
      ..onConnect((_) {
        _isConnected = true;
        _connectionController.add(true);
        print('[Socket] Connected');
      })
      ..onDisconnect((reason) {
        _isConnected = false;
        _connectionController.add(false);
        print('[Socket] Disconnected: $reason');
      })
      ..onConnectError((err) {
        print('[Socket] Connect error: $err');
      })

      // 다른 멤버 위치 수신
      ..on(SocketEvents.locationChanged, (data) {
        try {
          final payload = LocationPayload.fromMap(Map<String, dynamic>.from(data));
          _locationController.add(payload);
        } catch (e) {
          print('[Socket] locationChanged parse error: $e');
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
          _snapshotController.add(Map<String, dynamic>.from(data)));
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
  // 연결 해제
  // ─────────────────────────────────────────────────────────────────────────
  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _isConnected = false;
    _currentSessionId = null;
  }

  void dispose() {
    disconnect();
    _locationController.close();
    _memberJoinController.close();
    _memberLeftController.close();
    _statusController.close();
    _sosController.close();
    _snapshotController.close();
    _connectionController.close();
  }
}
