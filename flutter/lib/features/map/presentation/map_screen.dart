// lib/features/map/presentation/map_screen.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/location_service.dart';
import '../../../features/auth/data/auth_repository.dart';
import '../../../features/home/data/session_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 멤버 실시간 위치 상태
// ─────────────────────────────────────────────────────────────────────────────

class MemberState {
  final String userId;
  final String nickname;
  final double lat;
  final double lng;
  final int? battery;
  final String status; // 'moving' | 'stopped'
  final String role;   // 'host' | 'admin' | 'member'
  final bool sharingEnabled;
  final DateTime updatedAt;

  const MemberState({
    required this.userId,
    required this.nickname,
    required this.lat,
    required this.lng,
    this.battery,
    required this.status,
    this.role = 'member',
    this.sharingEnabled = true,
    required this.updatedAt,
  });

  MemberState copyWith({
    double? lat,
    double? lng,
    int? battery,
    String? status,
    String? role,
    bool? sharingEnabled,
    DateTime? updatedAt,
  }) =>
      MemberState(
        userId:         userId,
        nickname:       nickname,
        lat:            lat            ?? this.lat,
        lng:            lng            ?? this.lng,
        battery:        battery        ?? this.battery,
        status:         status         ?? this.status,
        role:           role           ?? this.role,
        sharingEnabled: sharingEnabled ?? this.sharingEnabled,
        updatedAt:      updatedAt      ?? this.updatedAt,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// 세션 지도 Notifier
// ─────────────────────────────────────────────────────────────────────────────

class MapSessionState {
  final Map<String, MemberState> members;
  final Position? myPosition;
  final bool isConnected;
  final bool sosTriggered;
  final String? sessionName;
  final bool sharingEnabled;
  final Set<String> hiddenMembers;
  final bool wasKicked;
  final String myRole; // 'host' | 'admin' | 'member'

  /// 한 번이라도 연결 성공 여부 (connecting vs reconnecting 구분용)
  final bool hasEverConnected;

  const MapSessionState({
    required this.members,
    this.myPosition,
    this.isConnected = false,
    this.hasEverConnected = false,
    this.sosTriggered = false,
    this.sessionName,
    this.sharingEnabled = true,
    this.hiddenMembers = const {},
    this.wasKicked = false,
    this.myRole = 'member',
  });

  MapSessionState copyWith({
    Map<String, MemberState>? members,
    Position? myPosition,
    bool? isConnected,
    bool? hasEverConnected,
    bool? sosTriggered,
    String? sessionName,
    bool? sharingEnabled,
    Set<String>? hiddenMembers,
    bool? wasKicked,
    String? myRole,
  }) =>
      MapSessionState(
        members:          members          ?? this.members,
        myPosition:       myPosition       ?? this.myPosition,
        isConnected:      isConnected      ?? this.isConnected,
        hasEverConnected: hasEverConnected ?? this.hasEverConnected,
        sosTriggered:     sosTriggered     ?? this.sosTriggered,
        sessionName:      sessionName      ?? this.sessionName,
        sharingEnabled:   sharingEnabled   ?? this.sharingEnabled,
        hiddenMembers:    hiddenMembers    ?? this.hiddenMembers,
        wasKicked:        wasKicked        ?? this.wasKicked,
        myRole:           myRole           ?? this.myRole,
      );
}

class MapSessionNotifier extends StateNotifier<MapSessionState> {
  MapSessionNotifier(this._sessionId, this._ref)
      : super(const MapSessionState(members: {})) {
    _init();
  }

  final String _sessionId;
  final Ref _ref;

  final _socket   = SocketService();
  final _gps      = GpsLocationService();

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

  Timer? _joinRetryTimer;

  // 위치 업데이트 일괄 처리 (500ms 간격, 50m 이상 이동 시만 반영)
  final Map<String, MemberState> _pendingUpdates = {};
  Timer? _markerFlushTimer;

  Future<void> _init() async {
    // 1. 세션 이름: sessionListProvider 캐시에서 조회
    final cachedSessions = _ref.read(sessionListProvider).valueOrNull ?? [];
    final cached = cachedSessions.where((s) => s.id == _sessionId);
    if (cached.isNotEmpty) {
      state = state.copyWith(sessionName: cached.first.name);
    }

    // 숨김 멤버 로컬 저장소에서 복원
    final prefs = await SharedPreferences.getInstance();
    final hiddenList = prefs.getStringList('hidden_$_sessionId') ?? [];
    if (hiddenList.isNotEmpty) {
      state = state.copyWith(hiddenMembers: Set.from(hiddenList));
    }

    // 2. 소켓 이벤트 구독을 connect() 호출 전에 설정

    // 강제 퇴장 수신
    _kickedSub = _socket.onKicked.listen((data) {
      state = state.copyWith(wasKicked: true);
    });

    // 역할 변경 수신
    _roleChangedSub = _socket.onRoleChanged.listen((data) {
      final userId = data['userId'] as String?;
      final role   = data['role']   as String?;
      if (userId == null || role == null) return;
      final authUser = _ref.read(authProvider).valueOrNull;
      if (userId == authUser?.id) {
        state = state.copyWith(myRole: role);
      }
      // 멤버 목록에서도 역할 업데이트
      final updated = Map<String, MemberState>.from(state.members);
      if (updated.containsKey(userId)) {
        updated[userId] = updated[userId]!.copyWith(role: role);
        state = state.copyWith(members: updated);
      }
    });

    // 연결 상태: 연결 완료 시점에 session:join 전송
    _connectionSub = _socket.onConnectionChange.listen((connected) {
      state = state.copyWith(
        isConnected: connected,
        hasEverConnected: connected ? true : state.hasEverConnected,
      );
      if (connected) {
        _socket.joinSession(_sessionId);
      }
    });

    // 500ms마다 pending 버퍼를 state에 일괄 반영
    _markerFlushTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_pendingUpdates.isEmpty) return;
      final updated = Map<String, MemberState>.from(state.members)
        ..addAll(_pendingUpdates);
      _pendingUpdates.clear();
      state = state.copyWith(members: updated);
    });

    // 다른 멤버 실시간 위치 — 50m 이상 이동 시에만 버퍼에 적재
    _locationSub = _socket.onLocationChanged.listen((payload) {
      // pending 버퍼의 최신값 우선, 없으면 현재 state에서 조회
      final current =
          _pendingUpdates[payload.userId] ?? state.members[payload.userId];

      if (current != null && (current.lat != 0 || current.lng != 0)) {
        final dist = Geolocator.distanceBetween(
          current.lat, current.lng,
          payload.lat, payload.lng,
        );
        if (dist < 50) return; // 50m 미만 이동은 무시
      }

      _pendingUpdates[payload.userId] = current != null
          ? current.copyWith(
              lat:       payload.lat,
              lng:       payload.lng,
              battery:   payload.battery,
              status:    payload.status,
              updatedAt: DateTime.now(),
            )
          : MemberState(
              userId:    payload.userId,
              nickname:  payload.nickname ?? payload.userId,
              lat:       payload.lat,
              lng:       payload.lng,
              battery:   payload.battery,
              status:    payload.status,
              updatedAt: DateTime.now(),
            );
    });

    _memberJoinSub = _socket.onMemberJoined.listen((data) {
      final userId   = data['userId']   as String? ?? '';
      final nickname = data['nickname'] as String? ?? userId;
      final updated  = Map<String, MemberState>.from(state.members);
      if (!updated.containsKey(userId)) {
        updated[userId] = MemberState(
          userId:    userId,
          nickname:  nickname,
          lat:       0,
          lng:       0,
          status:    'idle',
          updatedAt: DateTime.now(),
        );
        state = state.copyWith(members: updated);
      }
    });

    _memberLeftSub = _socket.onMemberLeft.listen((data) {
      final userId = data['userId'] as String? ?? '';
      final updated = Map<String, MemberState>.from(state.members)..remove(userId);
      state = state.copyWith(members: updated);
    });

    _statusSub = _socket.onStatusChanged.listen((data) {
      final userId  = data['userId']  as String? ?? '';
      final status  = data['status']  as String? ?? 'idle';
      final battery = data['battery'] as int?;
      final updated = Map<String, MemberState>.from(state.members);
      if (updated.containsKey(userId)) {
        updated[userId] = updated[userId]!.copyWith(status: status, battery: battery);
        state = state.copyWith(members: updated);
      }
    });

    _sosSub = _socket.onSosAlert.listen((_) {
      state = state.copyWith(sosTriggered: true);
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) state = state.copyWith(sosTriggered: false);
      });
    });

    // session:snapshot: join 직후 서버가 전송하는 전체 상태
    _snapshotSub = _socket.onSnapshot.listen((data) {
      final members = data['members'] as List<dynamic>? ?? [];
      final updated = Map<String, MemberState>.from(state.members);
      for (final m in members) {
        if (m is! Map<String, dynamic>) continue;
        final userId         = m['user_id']         as String? ?? '';
        final nickname       = m['nickname']        as String? ?? userId;
        if (userId.isEmpty) continue;
        final loc            = m['lastLocation']    as Map<String, dynamic>?;
        final lat            = (loc?['lat']         as num?)?.toDouble();
        final lng            = (loc?['lng']         as num?)?.toDouble();
        final role           = m['role']            as String? ?? 'member';
        final sharingEnabled = m['sharing_enabled'] as bool?   ?? true;
        updated[userId] = MemberState(
          userId:         userId,
          nickname:       nickname,
          lat:            lat ?? 0,
          lng:            lng ?? 0,
          battery:        loc?['battery']  as int?,
          status:         loc?['status']   as String? ?? 'idle',
          role:           role,
          sharingEnabled: sharingEnabled,
          updatedAt:      DateTime.now(),
        );
      }
      state = state.copyWith(members: updated);

      // 내 역할 및 공유 상태 초기화
      final authUser = _ref.read(authProvider).valueOrNull;
      if (authUser != null && updated.containsKey(authUser.id)) {
        final me = updated[authUser.id]!;
        state = state.copyWith(myRole: me.role, sharingEnabled: me.sharingEnabled);
        _gps.setSharingEnabled(me.sharingEnabled);
      }
    });

    // 3. 소켓 연결
    try {
      await _socket.connect();
      // 싱글톤이 이미 연결된 상태면 onConnectionChange 이벤트가 오지 않으므로 직접 반영
      if (_socket.isConnected) {
        state = state.copyWith(isConnected: true, hasEverConnected: true);
        _socket.joinSession(_sessionId);
      }
    } catch (e) {
      debugPrint('[Map] Socket connect failed: $e');
    }

    // session:join 재시도: 연결 후 30초 내 members가 비어있으면 자동 재시도
    _joinRetryTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && state.members.isEmpty && state.isConnected) {
        _socket.joinSession(_sessionId);
      }
    });

    // 4. GPS 추적 시작
    try {
      await _gps.startTracking();
      _myPositionSub = _gps.positionStream.listen((pos) {
        state = state.copyWith(myPosition: pos);
      });
    } catch (e) {
      debugPrint('[Map] GPS failed: $e');
    }

    // 5. REST API로 초기 멤버 위치 로드 (snapshot 이전 또는 오프라인 멤버 대비)
    try {
      final session = await _ref
          .read(sessionRepositoryProvider)
          .getSession(_sessionId);
      final initialMembers = Map<String, MemberState>.from(state.members);
      for (final m in session.members) {
        if (!initialMembers.containsKey(m.userId)) {
          initialMembers[m.userId] = MemberState(
            userId:         m.userId,
            nickname:       m.nickname,
            lat:            m.latitude ?? 0,
            lng:            m.longitude ?? 0,
            battery:        m.battery,
            status:         m.status,
            role:           m.role,
            sharingEnabled: m.sharingEnabled,
            updatedAt:      DateTime.now(),
          );
        }
      }
      state = state.copyWith(members: initialMembers);

      // 내 역할/공유 상태 설정 (snapshot이 아직 없을 때 대비)
      final authUser = _ref.read(authProvider).valueOrNull;
      if (authUser != null) {
        final myList = session.members.where((m) => m.userId == authUser.id).toList();
        if (myList.isNotEmpty) {
          final me = myList.first;
          state = state.copyWith(
            myRole: me.role,
            sharingEnabled: me.sharingEnabled,
          );
          _gps.setSharingEnabled(me.sharingEnabled);
        }
      }
    } catch (e) {
      debugPrint('[Map] Failed to load session members: $e');
    }
  }

  // ── 위치 공유 ON/OFF 토글 ────────────────────────────────────────────────
  Future<void> toggleSharing(bool enabled) async {
    try {
      await _ref.read(sessionRepositoryProvider).toggleSharing(_sessionId, enabled);
      _gps.setSharingEnabled(enabled);
      state = state.copyWith(sharingEnabled: enabled);
    } catch (e) {
      debugPrint('[Map] toggleSharing failed: $e');
    }
  }

  // ── 멤버 숨김 토글 ──────────────────────────────────────────────────────
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

  Future<void> reconnect() async {
    try {
      await _socket.connect();
      if (_socket.isConnected) {
        state = state.copyWith(isConnected: true, hasEverConnected: true);
        _socket.joinSession(_sessionId);
      }
    } catch (e) {
      debugPrint('[Map] Socket reconnect failed: $e');
    }
  }

  @override
  void dispose() {
    _joinRetryTimer?.cancel();
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
    _gps.stopTracking();
    _socket.disconnect();
    super.dispose();
  }
}

// Provider: sessionId 파라미터를 받기 위해 family 사용
final mapSessionProvider = StateNotifierProvider.family
    .autoDispose<MapSessionNotifier, MapSessionState, String>(
  (ref, sessionId) => MapSessionNotifier(sessionId, ref),
);

// ─────────────────────────────────────────────────────────────────────────────
// MapScreen
// ─────────────────────────────────────────────────────────────────────────────

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  GoogleMapController? _mapController;
  bool _followMe = true;

  // ── 마커 캐시 ─────────────────────────────────────────────────────────────
  // members/sharingEnabled/hiddenMembers가 실제로 변경됐을 때만 마커를 재계산한다.
  // myPosition이 바뀌는 경우(GPS 업데이트)에는 재계산하지 않는다.
  Set<Marker>               _cachedMarkers      = {};
  Map<String, MemberState>? _prevMembers;
  bool?                     _prevSharingEnabled;
  Set<String>?              _prevHiddenMembers;
  String?                   _prevMyUserId;

  @override
  Widget build(BuildContext context) {
    // 강제 퇴장 감지 → 홈으로 이동
    ref.listen<MapSessionState>(
      mapSessionProvider(widget.sessionId),
      (prev, next) {
        if (next.wasKicked) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.go(AppRoutes.home);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('세션에서 강제 퇴장 처리되었습니다.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          });
        }
      },
    );

    final mapState = ref.watch(mapSessionProvider(widget.sessionId));
    final authUser = ref.watch(authProvider).valueOrNull;

    // 내 위치 따라가기
    final myPos = mapState.myPosition;
    if (_followMe && myPos != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(LatLng(myPos.latitude, myPos.longitude)),
      );
    }

    // 마커 캐시: 마커에 영향 주는 상태가 실제로 바뀐 경우에만 재계산
    // identical()로 Map/Set 참조를 비교 → copyWith가 새 객체를 만들 때만 true
    final myUserId = authUser?.id;
    if (!identical(_prevMembers,      mapState.members)      ||
        _prevSharingEnabled          != mapState.sharingEnabled ||
        !identical(_prevHiddenMembers, mapState.hiddenMembers) ||
        _prevMyUserId                != myUserId) {
      _prevMembers        = mapState.members;
      _prevSharingEnabled = mapState.sharingEnabled;
      _prevHiddenMembers  = mapState.hiddenMembers;
      _prevMyUserId       = myUserId;
      _cachedMarkers = _buildMarkers(
        mapState.members,
        myUserId,
        mapState.sharingEnabled,
        mapState.hiddenMembers,
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // ── Google Maps ───────────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: myPos != null
                  ? LatLng(myPos.latitude, myPos.longitude)
                  : const LatLng(37.5665, 126.9780),
              zoom: 14.0,
              tilt: 0.0,
            ),
            onMapCreated: (ctrl) => _mapController = ctrl,
            markers: _cachedMarkers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            buildingsEnabled: false,
            onCameraMoveStarted: () => setState(() => _followMe = false),
          ),

          // ── 상단 앱바 ─────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopBar(
              sessionId:        widget.sessionId,
              sessionName:      mapState.sessionName ?? '세션',
              isConnected:      mapState.isConnected,
              hasEverConnected: mapState.hasEverConnected,
              memberCount:      mapState.members.length,
              sharingEnabled:   mapState.sharingEnabled,
              myRole:           mapState.myRole,
              onSharingToggle: (enabled) => ref
                  .read(mapSessionProvider(widget.sessionId).notifier)
                  .toggleSharing(enabled),
              onReconnect: () => ref
                  .read(mapSessionProvider(widget.sessionId).notifier)
                  .reconnect(),
            ),
          ),

          // ── 오른쪽 FAB들 ──────────────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: 280,
            child: Column(
              children: [
                // 내 위치 따라가기
                FloatingActionButton.small(
                  heroTag: 'follow',
                  onPressed: () {
                    setState(() => _followMe = true);
                    if (myPos != null) {
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLng(
                          LatLng(myPos.latitude, myPos.longitude),
                        ),
                      );
                    }
                  },
                  backgroundColor: _followMe ? const Color(0xFF2196F3) : Colors.white,
                  foregroundColor: _followMe ? Colors.white : Colors.black54,
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 8),
                // 전체 보기
                FloatingActionButton.small(
                  heroTag: 'fit',
                  onPressed: () => _fitAllMembers(mapState.members, myPos),
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black54,
                  child: const Icon(Icons.zoom_out_map),
                ),
              ],
            ),
          ),

          // ── SOS 경고 배너 ─────────────────────────────────────────────────
          if (mapState.sosTriggered)
            Positioned(
              top: MediaQuery.of(context).padding.top + 72,
              left: 16,
              right: 16,
              child: Material(
                borderRadius: BorderRadius.circular(12),
                color: Colors.red,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'SOS 알림을 받았습니다!',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── 하단 멤버 패널 ─────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomMemberPanel(
              members: mapState.members.values.toList(),
              myPosition: myPos,
              hiddenMembers: mapState.hiddenMembers,
              onSOS: () => _confirmSOS(context, ref),
              onMemberTap: (member) {
                if (member.lat == 0 && member.lng == 0) return;
                setState(() => _followMe = false);
                _mapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(member.lat, member.lng),
                    15,
                  ),
                );
              },
              onHideToggle: (userId) => ref
                  .read(mapSessionProvider(widget.sessionId).notifier)
                  .toggleHideMember(userId),
            ),
          ),
        ],
      ),
    );
  }

  Set<Marker> _buildMarkers(
    Map<String, MemberState> members,
    String? myUserId,
    bool sharingEnabled,
    Set<String> hiddenMembers,
  ) {
    final markers = <Marker>{};
    for (final m in members.values) {
      if (m.lat == 0 && m.lng == 0) continue;
      final isMe = m.userId == myUserId;
      if (isMe && !sharingEnabled) continue;   // 공유 OFF 시 내 마커 숨김
      if (hiddenMembers.contains(m.userId)) continue; // 숨긴 멤버 제외
      markers.add(
        Marker(
          markerId:   MarkerId(m.userId),
          position:   LatLng(m.lat, m.lng),
          icon:       BitmapDescriptor.defaultMarkerWithHue(
            isMe ? BitmapDescriptor.hueRed : BitmapDescriptor.hueBlue,
          ),
          infoWindow: InfoWindow(
            title:   '${m.nickname}${isMe ? ' (나)' : ''}',
            snippet: _markerSnippet(m),
          ),
        ),
      );
    }
    return markers;
  }

  String _markerSnippet(MemberState m) {
    final parts = <String>[];
    if (m.status == 'moving') {
      parts.add('이동 중');
    } else {
      parts.add('정지');
    }
    if (m.battery != null) parts.add('배터리 ${m.battery}%');
    return parts.join(' · ');
  }

  void _fitAllMembers(Map<String, MemberState> members, Position? myPos) {
    if (_mapController == null) return;
    setState(() => _followMe = false);

    final points = <LatLng>[
      if (myPos != null) LatLng(myPos.latitude, myPos.longitude),
      ...members.values
          .where((m) => m.lat != 0 || m.lng != 0)
          .map((m) => LatLng(m.lat, m.lng)),
    ];

    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 15),
      );
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  void _confirmSOS(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red),
            SizedBox(width: 8),
            Text('SOS 발송'),
          ],
        ),
        content: const Text('모든 세션 멤버에게 긴급 알림을 보내시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(mapSessionProvider(widget.sessionId).notifier).triggerSOS();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('SOS 알림을 전송했습니다'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('전송'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 상단 바
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.sessionId,
    required this.sessionName,
    required this.isConnected,
    required this.hasEverConnected,
    required this.memberCount,
    required this.sharingEnabled,
    required this.myRole,
    required this.onSharingToggle,
    this.onReconnect,
  });

  final String sessionId;
  final String sessionName;
  final bool   isConnected;
  final bool   hasEverConnected;
  final int    memberCount;
  final bool   sharingEnabled;
  final String myRole;
  final ValueChanged<bool> onSharingToggle;
  final VoidCallback? onReconnect;

  Color _statusColor() {
    if (isConnected) return Colors.green;
    if (hasEverConnected) return Colors.red;
    return Colors.orange;
  }

  String _statusText() {
    if (isConnected) return '연결됨';
    if (hasEverConnected) return '재연결 중...';
    return '연결 중...';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        bottom: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 뒤로가기
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),

          // 세션 이름 + 멤버 수
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sessionName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$memberCount명 참여 중',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),

          // 연결 상태 표시 (연결 끊김 시 탭으로 수동 재연결)
          GestureDetector(
            onTap: !isConnected ? onReconnect : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor().withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _statusColor(),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _statusText(),
                    style: TextStyle(
                      fontSize: 12,
                      color: _statusColor(),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 위치 공유 토글
          IconButton(
            icon: Icon(
              sharingEnabled ? Icons.location_on : Icons.location_off,
              color: sharingEnabled ? const Color(0xFF2196F3) : Colors.grey,
            ),
            tooltip: sharingEnabled ? '위치 공유 중' : '위치 공유 꺼짐',
            onPressed: () => onSharingToggle(!sharingEnabled),
            visualDensity: VisualDensity.compact,
          ),
          // 더보기 메뉴
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'history':
                  context.push(AppRoutes.history
                      .replaceFirst(':sessionId', sessionId));
                case 'geofence':
                  context.push(AppRoutes.geofence
                      .replaceFirst(':sessionId', sessionId));
                case 'members':
                  context.push('/session/$sessionId/members');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'history',
                child: Row(
                  children: [
                    Icon(Icons.history, size: 20),
                    SizedBox(width: 12),
                    Text('위치 기록'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'geofence',
                child: Row(
                  children: [
                    Icon(Icons.radio_button_checked, size: 20),
                    SizedBox(width: 12),
                    Text('지오펜스'),
                  ],
                ),
              ),
              if (myRole == 'host' || myRole == 'admin')
                const PopupMenuItem(
                  value: 'members',
                  child: Row(
                    children: [
                      Icon(Icons.manage_accounts, size: 20),
                      SizedBox(width: 12),
                      Text('멤버 관리'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 하단 멤버 패널
// ─────────────────────────────────────────────────────────────────────────────

class _BottomMemberPanel extends StatelessWidget {
  const _BottomMemberPanel({
    required this.members,
    required this.myPosition,
    required this.onSOS,
    required this.onMemberTap,
    required this.hiddenMembers,
    required this.onHideToggle,
  });

  final List<MemberState>         members;
  final Position?                 myPosition;
  final VoidCallback              onSOS;
  final ValueChanged<MemberState> onMemberTap;
  final Set<String>               hiddenMembers;
  final ValueChanged<String>      onHideToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 패널 헤더
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Text(
                  '멤버 위치',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const Spacer(),
                // SOS 버튼
                ElevatedButton.icon(
                  onPressed: onSOS,
                  icon: const Icon(Icons.warning_amber, size: 18),
                  label: const Text('SOS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(80, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 멤버 목록
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                '다른 멤버가 없습니다',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            SizedBox(
              height: 78,
              child: members.length >= 5
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          for (final m in members)
                            _MemberChip(
                              member:      m,
                              myPosition:  myPosition,
                              isHidden:    hiddenMembers.contains(m.userId),
                              onTap:       () => onMemberTap(m),
                              onLongPress: () => _showMemberSheet(
                                context, m,
                                hiddenMembers.contains(m.userId),
                                onMemberTap, onHideToggle,
                              ),
                            ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          for (final m in members)
                            _MemberChip(
                              member:      m,
                              myPosition:  myPosition,
                              isHidden:    hiddenMembers.contains(m.userId),
                              onTap:       () => onMemberTap(m),
                              onLongPress: () => _showMemberSheet(
                                context, m,
                                hiddenMembers.contains(m.userId),
                                onMemberTap, onHideToggle,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  static void _showMemberSheet(
    BuildContext context,
    MemberState member,
    bool isHidden,
    ValueChanged<MemberState> onLocate,
    ValueChanged<String> onHideToggle,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                member.nickname,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('위치로 이동'),
              enabled: member.lat != 0 || member.lng != 0,
              onTap: () {
                Navigator.pop(ctx);
                onLocate(member);
              },
            ),
            ListTile(
              leading: Icon(
                isHidden ? Icons.visibility : Icons.visibility_off,
                color: isHidden ? Colors.blue : null,
              ),
              title: Text(isHidden ? '숨기기 해제' : '이 멤버 숨기기'),
              onTap: () {
                Navigator.pop(ctx);
                onHideToggle(member.userId);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 멤버 칩 (하단 패널 아이템)
// ─────────────────────────────────────────────────────────────────────────────

class _MemberChip extends StatelessWidget {
  const _MemberChip({
    required this.member,
    required this.myPosition,
    required this.onTap,
    required this.onLongPress,
    required this.isHidden,
  });

  final MemberState  member;
  final Position?    myPosition;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool         isHidden;

  @override
  Widget build(BuildContext context) {
    final distance = _calcDistance();

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Opacity(
        opacity: isHidden ? 0.4 : 1.0,
        child: Container(
          width: 72,
          height: 78,
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        const Color(0xFF2196F3).withValues(alpha: 0.15),
                    child: Text(
                      member.nickname.isNotEmpty
                          ? member.nickname[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Color(0xFF2196F3),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: member.status == 'moving'
                          ? Colors.green
                          : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                member.nickname,
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (distance != null)
                Text(
                  distance,
                  style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? _calcDistance() {
    if (myPosition == null || (member.lat == 0 && member.lng == 0)) {
      return null;
    }
    final meters = Geolocator.distanceBetween(
      myPosition!.latitude,
      myPosition!.longitude,
      member.lat,
      member.lng,
    );
    if (meters < 1000) {
      return '${meters.round()}m';
    }
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  IconData _batteryIcon(int level) {
    if (level >= 80) return Icons.battery_full;
    if (level >= 50) return Icons.battery_4_bar;
    if (level >= 20) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }
}
