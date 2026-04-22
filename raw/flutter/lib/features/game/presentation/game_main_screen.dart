// lib/features/game/presentation/game_main_screen.dart
//
// 단일 진입점 게임 메인 화면
// - 배경: NaverMap (지도 위에 마커/플레이영역 폴리곤)
// - 오버레이: 반투명 상단 헤더 + 텍스트 기반 플로팅 버튼들
// - 접이식 패널: AI 채팅, 멤버 목록, 미션 목록 등은 바텀시트로
// - 아이콘/이모지 금지: 오직 텍스트로만 UI 구성

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/app_initialization_service.dart';
import '../../../core/services/mediasoup_audio_service.dart';
import '../../../core/services/socket_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../home/data/session_repository.dart';
import '../../map/data/map_session_provider.dart';
import '../../map/presentation/map_session_models.dart';
import '../data/game_models.dart';
import '../providers/game_provider.dart';
import 'game_meeting_screen.dart';
import 'minigames/minigame_wrapper_screen.dart';
import 'qr_scanner_screen.dart';
import 'session_info_screen.dart';
import 'game_mode_plugin.dart';
import 'widgets/ai_chat_panel.dart';
import 'widgets/mission_list_sheet.dart';

class GameMainScreen extends ConsumerStatefulWidget {
  const GameMainScreen({
    super.key,
    required this.sessionId,
    required this.sessionType,
  });

  final String sessionId;
  final SessionType sessionType;

  @override
  ConsumerState<GameMainScreen> createState() => _GameMainScreenState();
}

class _GameMainScreenState extends ConsumerState<GameMainScreen>
    with WidgetsBindingObserver {
  // ── 지도 컨트롤러 및 상태 ───────────────────────────────────────────────
  NaverMapController? _mapController;
  bool _mapSdkReady = false;
  bool _followMe = true;

  // userId → 현재 지도에 올라간 NMarker. setPosition으로 제자리 이동.
  final Map<String, NMarker> _liveUserMarkers = {};
  int _overlaySyncRequestId = 0;

  // ── 모드 플러그인 ─────────────────────────────────────────────────
  late final GameModePlugin _modePlugin;

  // ── AI 채팅 패널 ─────────────────────────────────────────────────
  bool _aiChatExpanded = false;
  static const double _kChatHandleH = 48.0;
  static const double _kChatContentH = 320.0;

  // ── 세션 정보 오버레이 ───────────────────────────────────────────────
  bool _showSessionInfo = false;
  void _openSessionInfo() => setState(() => _showSessionInfo = true);
  void _closeSessionInfo() => setState(() => _showSessionInfo = false);

  // ── 구역 이탈 경고 ──────────────────────────────────────────────────
  // 이탈 판정은 GameNotifier가 수행하며, 본 화면은 state.isOutOfBounds를 읽어
  // 펄스 애니메이션만 로컬에서 관리합니다.
  bool _boundsAlertPulse = false;
  Timer? _boundsAlertTimer;

  void _startBoundsPulse() {
    _boundsAlertTimer?.cancel();
    _boundsAlertTimer =
        Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) {
        _boundsAlertTimer?.cancel();
        return;
      }
      setState(() => _boundsAlertPulse = !_boundsAlertPulse);
    });
  }

  void _stopBoundsPulse() {
    _boundsAlertTimer?.cancel();
    _boundsAlertTimer = null;
    if (_boundsAlertPulse) setState(() => _boundsAlertPulse = false);
  }

  // ── KILL 쿨타임 ─────────────────────────────────────────────────────
  static const int _kKillCooldownDefault = 30;
  int _killCooldownSecs = 0;
  int _killCooldownDuration = _kKillCooldownDefault;
  Timer? _killCooldownTimer;

  void _handleKill(String targetId) {
    if (_killCooldownSecs > 0) return;
    ref.read(gameProvider(widget.sessionId).notifier).sendKill(targetId);
    _startKillCooldown();
  }

  void _startKillCooldown() {
    setState(() => _killCooldownSecs = _killCooldownDuration);
    _killCooldownTimer?.cancel();
    _killCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _killCooldownSecs--;
        if (_killCooldownSecs <= 0) {
          _killCooldownSecs = 0;
          timer.cancel();
          _killCooldownTimer = null;
        }
      });
    });
  }

  // ── 역할 화면 중복 진입 방지 가드 ──────────────────────────────────
  // 한 번 true가 되면 절대 false로 되돌리지 않음 → 소켓 재연결/재빌드 시 중복 push 방지
  bool _roleNavDone = false;

  // ── 게임 보이스 채널 상태 ──────────────────────────────────────────
  // 기본값: 미연결. 사용자가 "게임 보이스 채널 연결" 버튼을 눌러야 연결됨.
  bool _gameVoiceConnected = false;
  bool _gameVoiceConnecting = false;

  // ── Lifecycle ───────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _modePlugin = createPlugin(widget.sessionType);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_ensureMapSdkReady());
    unawaited(_loadSessionConfig());
    // 게임 화면 진입 시 로비 보이스 연결을 끊는다.
    // 사용자가 명시적으로 "게임 보이스 채널 연결"을 눌러야 재연결.
    unawaited(MediaSoupAudioService().leaveSession());
  }

  Future<void> _connectGameVoice() async {
    if (_gameVoiceConnecting || _gameVoiceConnected) return;
    setState(() => _gameVoiceConnecting = true);
    try {
      await MediaSoupAudioService().ensureJoined(
        widget.sessionId,
        publishMic: true,
        channelId: 'game',
      );
      if (!mounted) return;
      setState(() {
        _gameVoiceConnected = true;
        _gameVoiceConnecting = false;
      });
    } catch (e) {
      debugPrint('[GameMain] game voice connect failed: $e');
      if (!mounted) return;
      setState(() => _gameVoiceConnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('게임 보이스 연결 실패: $e')),
      );
    }
  }

  Future<void> _disconnectGameVoice() async {
    await MediaSoupAudioService().leaveSession();
    if (!mounted) return;
    setState(() => _gameVoiceConnected = false);
  }

  /// 서버에서 세션을 직접 조회해 플레이 영역 및 쿨타임을 초기화합니다.
  /// 플레이 영역은 GameProvider에 반영되고, ref.listen이 폴리곤 렌더링과
  /// bounds check 시작을 자동으로 트리거합니다.
  Future<void> _loadSessionConfig() async {
    try {
      final session = await ref
          .read(sessionRepositoryProvider)
          .getSession(widget.sessionId);
      if (!mounted) return;
      setState(() => _killCooldownDuration = session.killCooldown);
      final area = session.playableArea;
      if (area != null && area.length >= 3) {
        ref
            .read(gameProvider(widget.sessionId).notifier)
            .setPlayableArea(area);
      }
    } catch (e) {
      debugPrint('[GameMain] 세션 설정 로드 실패: $e');
      _killCooldownDuration = _kKillCooldownDefault;
    }
  }

  static const String _kPlayableAreaOverlayId = 'playable_area_polygon';

  /// 플레이 영역 폴리곤을 맵에 idempotent하게 적용합니다.
  /// - 기존에 동일 ID의 폴리곤이 있으면 먼저 제거한 뒤 재생성
  /// - 좌표가 3개 미만이면 제거만 수행
  /// - 진실의 원천은 gameProvider.state.playableArea
  Future<void> _applyPlayableAreaPolygon({
    NaverMapController? controller,
  }) async {
    final ctrl = controller ?? _mapController;
    if (ctrl == null) return;

    // 기존 폴리곤 제거 (없어도 예외 없이 통과하도록 try/catch)
    try {
      await ctrl.deleteOverlay(
        const NOverlayInfo(
          type: NOverlayType.polygonOverlay,
          id: _kPlayableAreaOverlayId,
        ),
      );
    } catch (_) {
      // 오버레이가 존재하지 않을 수 있음 — 무시
    }

    if (!mounted || _mapController != ctrl) return;

    final area = ref.read(gameProvider(widget.sessionId)).playableArea;
    if (area == null || area.length < 3) return;

    final coords = area
        .map((p) => NLatLng(p['lat'] ?? 0.0, p['lng'] ?? 0.0))
        .toList();

    // flutter_naver_map NPolygonOverlay는 닫힌 도형을 요구한다
    // (coords.first == coords.last assertion). 열려있으면 첫 좌표를 끝에 추가.
    if (coords.isNotEmpty && coords.first != coords.last) {
      coords.add(coords.first);
    }

    final polygon = NPolygonOverlay(
      id: _kPlayableAreaOverlayId,
      coords: coords,
      color: Colors.red.withValues(alpha: 0.3),
      outlineColor: Colors.red.withValues(alpha: 0.6),
      outlineWidth: 3,
    );

    if (!mounted || _mapController != ctrl) return;
    await ctrl.addOverlay(polygon);
  }

  /// '내 위치' 버튼 핸들러.
  /// 1) 위치 권한 확인/요청
  /// 2) 권한 OK → 지도 tracking mode를 follow로 (현 위치 센터 + 추적)
  /// 3) myPosition이 아직 없으면 Geolocator로 즉시 현재 좌표를 얻어 카메라 이동
  Future<void> _onMyLocationPressed() async {
    final granted = await _ensureLocationPermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('위치 권한이 필요합니다. 설정에서 허용해 주세요.')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _followMe = true);

    final controller = _mapController;
    if (controller == null) return;

    try {
      controller.setLocationTrackingMode(NLocationTrackingMode.follow);
    } catch (e) {
      debugPrint('[GameMain] setLocationTrackingMode 실패: $e');
    }

    // 이미 알고 있는 좌표가 있으면 즉시 카메라만 이동해 UX 끊김 방지.
    final known = ref.read(mapSessionProvider(widget.sessionId)).myPosition;
    if (known != null) {
      await controller.updateCamera(
        NCameraUpdate.withParams(
          target: NLatLng(known.latitude, known.longitude),
          zoom: 17,
        )..setAnimation(animation: NCameraAnimation.easing),
      );
      return;
    }

    // 아직 GPS fix가 없다면 직접 한 번 가져와 카메라 이동.
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      if (!mounted || _mapController != controller) return;
      await controller.updateCamera(
        NCameraUpdate.withParams(
          target: NLatLng(position.latitude, position.longitude),
          zoom: 17,
        )..setAnimation(animation: NCameraAnimation.easing),
      );
    } catch (e) {
      debugPrint('[GameMain] getCurrentPosition 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 위치를 가져올 수 없습니다.')),
      );
    }
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  Future<void> _ensureMapSdkReady() async {
    try {
      await AppInitializationService().ensureNaverMapInitialized();
      if (!mounted) return;
      setState(() => _mapSdkReady = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('지도 초기화 실패: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _modePlugin.dispose();
    _killCooldownTimer?.cancel();
    _boundsAlertTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[App] 포그라운드 복귀 → 소켓 상태 즉시 동기화 시작');
      SocketService().requestGameState(widget.sessionId);
      SocketService().emit(
        SocketEvents.joinSession,
        {'sessionId': widget.sessionId},
      );
    }
  }

  // ── 세션 모듈 조회 ──────────────────────────────────────────────────
  // sessionListProvider가 비어있을 경우 sessionType.toModules()로 폴백
  Set<String> _getActiveModules() {
    final sessions = ref.read(sessionListProvider).valueOrNull ?? const [];
    final match = sessions.where((s) => s.id == widget.sessionId);
    if (match.isNotEmpty) return match.first.activeModules.toSet();
    // 폴백: 세션 타입에서 모듈 목록 추론
    return widget.sessionType.toModules().toSet();
  }

  // ── 나가기 ─────────────────────────────────────────────────────────
  Future<void> _confirmLeaveGame() async {
    final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('게임 나가기'),
            content: const Text('지금 나가면 게임 연결과 위치 공유가 종료됩니다. 정말로 나가시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('나가기'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldLeave || !mounted) return;
    await _leaveGame();
  }

  Future<void> _leaveGame() async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(sessionRepositoryProvider).leaveSession(widget.sessionId);
      SocketService().leaveSession(sessionId: widget.sessionId);
      await MediaSoupAudioService().leaveSession();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('bg_active', false);
      FlutterBackgroundService().invoke('stopService');
      if (!mounted) return;
      router.go(AppRoutes.home);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('게임 나가기 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ── 유저 마커 동기화 (위치 변경 시 setPosition, 신규/제거만 addOverlay/delete) ──
  Future<void> _syncUserMarkers(
    Map<String, MemberState> members,
    String? myUserId,
    Set<String> hiddenMembers,
    Set<String> eliminatedUserIds,
  ) async {
    final ctrl = _mapController;
    if (ctrl == null) return;

    final wantedIds = <String>{};

    for (final m in members.values) {
      if (m.lat == 0 && m.lng == 0) continue;
      if (m.userId == myUserId) continue;
      if (hiddenMembers.contains(m.userId)) continue;

      wantedIds.add(m.userId);

      final isEliminated = eliminatedUserIds.contains(m.userId);
      final newPos = NLatLng(m.lat, m.lng);
      final nameCaption = isEliminated ? '[탈락] ${m.nickname}' : m.nickname;
      final pinColor = isEliminated ? Colors.grey : Colors.redAccent;
      final captionColor = isEliminated ? Colors.grey : Colors.black87;
      final snippetText = isEliminated ? '탈락' : _markerSnippet(m);

      final existing = _liveUserMarkers[m.userId];
      if (existing != null) {
        // 이미 지도에 있는 마커 → 위치·캡션만 업데이트
        existing.setPosition(newPos);
        existing.setIconTintColor(pinColor);
        existing.setCaption(NOverlayCaption(
          text: nameCaption,
          textSize: 14,
          color: captionColor,
          haloColor: Colors.white,
        ));
        existing.setSubCaption(NOverlayCaption(
          text: snippetText,
          textSize: 12,
          color: isEliminated ? Colors.grey : Colors.grey[700]!,
          haloColor: Colors.white,
        ));
      } else {
        // 새 멤버 → 마커 생성 후 addOverlay
        final marker = NMarker(id: m.userId, position: newPos)
          ..setIconTintColor(pinColor)
          ..setCaption(NOverlayCaption(
            text: nameCaption,
            textSize: 14,
            color: captionColor,
            haloColor: Colors.white,
          ))
          ..setSubCaption(NOverlayCaption(
            text: snippetText,
            textSize: 12,
            color: isEliminated ? Colors.grey : Colors.grey[700]!,
            haloColor: Colors.white,
          ));
        _liveUserMarkers[m.userId] = marker;
        try {
          await ctrl.addOverlay(marker);
        } catch (_) {}
        if (!mounted || _mapController != ctrl) return;
      }
    }

    // 사라진 멤버 마커 제거
    final toRemove = _liveUserMarkers.keys
        .where((id) => !wantedIds.contains(id))
        .toList(growable: false);
    for (final id in toRemove) {
      _liveUserMarkers.remove(id);
      try {
        await ctrl.deleteOverlay(NOverlayInfo(type: NOverlayType.marker, id: id));
      } catch (_) {}
      if (!mounted || _mapController != ctrl) return;
    }
  }

  String _markerSnippet(MemberState m) {
    final parts = <String>[];
    parts.add(m.status == 'moving' ? '이동중' : '정지');
    if (m.battery != null) parts.add('배터리(${m.battery}%)');
    return parts.join(' ');
  }

  // 폴리곤 + 미션 오버레이만 재동기화 (유저 마커는 _syncUserMarkers가 담당)
  Future<void> _syncOverlays() async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    final syncRequestId = ++_overlaySyncRequestId;

    // 유저 마커를 제외한 다른 오버레이(폴리곤, 코인, 동물)만 초기화한다.
    // NOverlayType별로 삭제해 유저 마커(NOverlayType.marker)는 건드리지 않는다.
    try {
      await ctrl.clearOverlays(type: NOverlayType.polygonOverlay);
    } catch (_) {}
    if (!mounted || _mapController != ctrl || syncRequestId != _overlaySyncRequestId) return;

    await _applyPlayableAreaPolygon(controller: ctrl);
    if (!mounted || _mapController != ctrl || syncRequestId != _overlaySyncRequestId) return;

    await _applyMissionOverlays(controller: ctrl);
  }

  // 현재 지도에 올라간 미션 마커 ID 추적
  final Set<String> _liveMissionMarkerIds = {};

  // ── 미션 마커 (COIN_COLLECT / CAPTURE_ANIMAL) ─────────────────────────────
  Future<void> _applyMissionOverlays({NaverMapController? controller}) async {
    final ctrl = controller ?? _mapController;
    if (ctrl == null) return;
    final gameState = ref.read(gameProvider(widget.sessionId));

    // 기존 미션 마커 제거
    for (final id in _liveMissionMarkerIds) {
      try {
        await ctrl.deleteOverlay(NOverlayInfo(type: NOverlayType.marker, id: id));
      } catch (_) {}
    }
    _liveMissionMarkerIds.clear();
    if (!mounted || _mapController != ctrl) return;

    // 코인 마커 추가
    for (final entry in gameState.missionCoins.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        final coin = entry.value[i];
        if (coin.collected) continue;
        final markerId = 'coin_${entry.key}_$i';
        final marker = NMarker(
          id: markerId,
          position: NLatLng(coin.lat, coin.lng),
        )
          ..setIconTintColor(const Color(0xFFFFC107))
          ..setCaption(const NOverlayCaption(
            text: '코인',
            textSize: 11,
            color: Color(0xFFB8860B),
            haloColor: Colors.white,
          ));
        try {
          await ctrl.addOverlay(marker);
          _liveMissionMarkerIds.add(markerId);
        } catch (_) {}
        if (!mounted || _mapController != ctrl) return;
      }
    }

    // 동물 마커 추가
    for (final entry in gameState.missionAnimals.entries) {
      final animal = entry.value;
      final markerId = 'animal_${entry.key}';
      final marker = NMarker(
        id: markerId,
        position: NLatLng(animal.lat, animal.lng),
      )
        ..setIconTintColor(const Color(0xFF8B4513))
        ..setCaption(const NOverlayCaption(
          text: '동물',
          textSize: 11,
          color: Color(0xFF5D2F0C),
          haloColor: Colors.white,
        ));
      try {
        await ctrl.addOverlay(marker);
        _liveMissionMarkerIds.add(markerId);
      } catch (_) {}
      if (!mounted || _mapController != ctrl) return;
    }
  }

  void _fitAllMembers(Map<String, MemberState> members, Position? myPos) {
    if (_mapController == null) return;
    setState(() => _followMe = false);

    final points = <NLatLng>[
      if (myPos != null) NLatLng(myPos.latitude, myPos.longitude),
      ...members.values
          .where((m) => m.lat != 0 || m.lng != 0)
          .map((m) => NLatLng(m.lat, m.lng)),
    ];

    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController!.updateCamera(
        NCameraUpdate.scrollAndZoomTo(target: points.first, zoom: 15)
          ..setAnimation(animation: NCameraAnimation.easing),
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
    final bounds = NLatLngBounds(
      southWest: NLatLng(minLat, minLng),
      northEast: NLatLng(maxLat, maxLng),
    );
    _mapController!.updateCamera(
      NCameraUpdate.fitBounds(bounds, padding: const EdgeInsets.all(80))
        ..setAnimation(animation: NCameraAnimation.easing),
    );
  }

  // ── 바텀시트: 멤버 목록 / 미션 / 사보타지 / 시체 신고 ─────────────────

  void _openMemberSheet(MapSessionState mapState, String? myUserId) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        final members = mapState.members.values.toList();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('참여자 (${members.length})',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('참여자가 없습니다.',
                        style: TextStyle(color: Colors.white54)),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: members.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Colors.white12, height: 1),
                      itemBuilder: (ctx, i) {
                        final m = members[i];
                        final isMe = m.userId == myUserId;
                        final isEliminated =
                            mapState.eliminatedUserIds.contains(m.userId);
                        final dist = mapState.memberDistances[m.userId];
                        final distLabel = dist != null
                            ? (dist < 1000
                                ? '${dist.toStringAsFixed(0)}m'
                                : '${(dist / 1000).toStringAsFixed(1)}km')
                            : '-';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            isMe ? '${m.nickname} (나)' : m.nickname,
                            style: TextStyle(
                              color: isEliminated
                                  ? Colors.grey
                                  : Colors.white,
                              fontWeight: FontWeight.w600,
                              decoration: isEliminated
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            isEliminated ? '탈락' : '거리 $distLabel',
                            style: TextStyle(
                                color: isEliminated
                                    ? Colors.redAccent
                                    : Colors.white54,
                                fontSize: 12),
                          ),
                          trailing: isMe
                              ? null
                              : TextButton(
                                  onPressed: () {
                                    if (m.lat == 0 && m.lng == 0) return;
                                    Navigator.pop(ctx);
                                    setState(() => _followMe = false);
                                    _mapController?.updateCamera(
                                      NCameraUpdate.scrollAndZoomTo(
                                        target: NLatLng(m.lat, m.lng),
                                        zoom: 15,
                                      )..setAnimation(
                                          animation: NCameraAnimation.easing),
                                    );
                                  },
                                  child: const Text('지도에서 보기',
                                      style: TextStyle(color: Colors.cyan)),
                                ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openSabotageSheet(List<Mission> missions) {
    final targets = missions
        .where((m) =>
            m.type.isMapBased &&
            m.status != MissionStatus.completed &&
            !m.isSabotaged)
        .toList();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('사보타지할 미션 선택',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (targets.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('사보타지할 수 있는 미션이 없습니다.',
                      style: TextStyle(color: Colors.white54)),
                )
              else
                ...targets.map((m) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(m.title,
                          style: const TextStyle(color: Colors.white)),
                      trailing: TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          SocketService()
                              .sendTriggerSabotage(widget.sessionId, m.id);
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.red.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                        ),
                        child: const Text('발동'),
                      ),
                    )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReportSheet(MapSessionState mapState) async {
    final deadPlayers = mapState.eliminatedUserIds
        .map((userId) => mapState.members[userId])
        .whereType<MemberState>()
        .toList();

    if (deadPlayers.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('신고할 시체가 없습니다.')));
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('시체 신고',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final p in deadPlayers)
              ListTile(
                title: Text(p.nickname),
                subtitle: Text(p.userId),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    ref
                        .read(gameProvider(widget.sessionId).notifier)
                        .sendReport(p.userId);
                  },
                  child: const Text('신고'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── 플러그인 컨텍스트 생성 ──────────────────────────────────────────
  GamePluginCtx _buildPluginCtx({
    required AmongUsGameState gameState,
    required MapSessionState mapState,
    required String? myUserId,
    required bool isGhostMode,
    required bool isInProgress,
    required double chatBarH,
    required bool canKill,
    required bool canOpenVote,
    required bool canShowMission,
    required bool isImpostor,
  }) {
    final readyMissions = gameState.myMissions
        .where((m) =>
            m.type.isMapBased && m.status == MissionStatus.ready)
        .toList();
    final isOutOfBounds = gameState.isOutOfBounds;

    return GamePluginCtx(
      sessionId: widget.sessionId,
      gameState: gameState,
      mapState: mapState,
      myUserId: myUserId,
      isGhostMode: isGhostMode,
      isInProgress: isInProgress,
      chatBarH: chatBarH,
      // Kill
      canKill: canKill && !isOutOfBounds,
      killCooldown: _killCooldownSecs,
      killLabel: widget.sessionType == SessionType.chase ? '태그' : '제거',
      onKill: canKill && !isOutOfBounds && _killCooldownSecs == 0
          ? () {
              final targetId = mapState.proximateTargetId;
              if (targetId != null) {
                _handleKill(targetId);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('근처에 대상이 없습니다.')),
                );
              }
            }
          : null,
      // Meeting
      canCallMeeting: canOpenVote && !isOutOfBounds,
      isMeetingCoolingDown: gameState.isMeetingCoolingDown,
      onCallMeeting: () {
        ref.read(gameProvider(widget.sessionId).notifier).callMeeting((res) {
          if (!mounted || res['ok'] == true) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['error']?.toString() ?? '회의를 소집할 수 없습니다.'),
              duration: const Duration(seconds: 2),
            ),
          );
        });
      },
      // Report
      canReport: widget.sessionType == SessionType.verbal &&
          !isGhostMode &&
          !isOutOfBounds &&
          mapState.eliminatedUserIds.isNotEmpty,
      onReport: () => _showReportSheet(mapState),
      // Mission / QR
      canShowMission: canShowMission && isInProgress && !isGhostMode && !isOutOfBounds,
      onShowMission: () {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => MissionListSheet(sessionId: widget.sessionId),
        );
      },
      onQrScan: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => QrScannerScreen(sessionId: widget.sessionId),
        ));
      },
      // Sabotage
      canSabotage: isInProgress && isImpostor && !isGhostMode && !isOutOfBounds,
      onSabotage: () => _openSabotageSheet(gameState.myMissions),
      // Location extras
      isOutOfBounds: isOutOfBounds,
      boundsAlertPulse: _boundsAlertPulse,
      readyLocationMissions: readyMissions,
      onPerformMission: readyMissions.isNotEmpty
          ? () async {
              final mission = readyMissions.first;
              final notifier =
                  ref.read(gameProvider(widget.sessionId).notifier);
              final messenger = ScaffoldMessenger.of(context);
              switch (mission.type) {
                case MissionType.coinCollect:
                  final result = await notifier.collectNearestCoinFor(mission.id);
                  if (!mounted) return;
                  if (result == null) {
                    messenger.showSnackBar(const SnackBar(
                      content: Text('범위를 벗어났습니다. 코인 10m 이내로 이동하세요.'),
                      duration: Duration(seconds: 1),
                    ));
                  } else if (result == true) {
                    messenger.showSnackBar(const SnackBar(
                      content: Text('모든 코인을 수집했습니다! 미션 완료'),
                      backgroundColor: Color(0xFF22C55E),
                      duration: Duration(milliseconds: 1200),
                    ));
                  } else {
                    messenger.showSnackBar(const SnackBar(
                      content: Text('코인을 수집했습니다.'),
                      duration: Duration(seconds: 1),
                    ));
                  }
                  break;
                case MissionType.captureAnimal:
                  final ok = await notifier.captureAnimalFor(mission.id);
                  if (!mounted) return;
                  if (ok) {
                    messenger.showSnackBar(const SnackBar(
                      content: Text('동물을 포획했습니다! 미션 완료'),
                      backgroundColor: Color(0xFF22C55E),
                      duration: Duration(milliseconds: 1200),
                    ));
                  } else {
                    messenger.showSnackBar(const SnackBar(
                      content: Text('범위를 벗어났습니다. 동물 5m 이내로 이동하세요.'),
                      duration: Duration(seconds: 1),
                    ));
                  }
                  break;
                case MissionType.minigame:
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => MinigameWrapperScreen(
                      sessionId: widget.sessionId,
                      mission: mission,
                    ),
                  ));
                  break;
              }
            }
          : null,
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // 게임 상태 변화 리스닝 (역할 화면, 결과 화면 라우팅)
    ref.listen<AmongUsGameState>(
      gameProvider(widget.sessionId),
      (previous, next) {
        if (next.shouldNavigateToRole && !_roleNavDone) {
          _roleNavDone = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            context.push('/game/${widget.sessionId}/role');
            ref
                .read(gameProvider(widget.sessionId).notifier)
                .resetRoleNavigation();
          });
        }
        if (previous?.gameOverWinner == null && next.gameOverWinner != null) {
          final winner = next.gameOverWinner!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            context.go('/game/${widget.sessionId}/result/$winner');
          });
        }
        // 플레이 영역 변경 감지 → 폴리곤 재렌더링
        // (이탈 판정 자체는 GameNotifier가 GPS 스트림으로 수행)
        final prevArea = previous?.playableArea;
        final nextArea = next.playableArea;
        if (!identical(prevArea, nextArea)) {
          unawaited(_applyPlayableAreaPolygon());
        }

        // 이탈 상태 변경 → 펄스 애니메이션 토글
        if (previous?.isOutOfBounds != next.isOutOfBounds) {
          if (next.isOutOfBounds) {
            _startBoundsPulse();
          } else {
            _stopBoundsPulse();
          }
        }

        // 미션 마커(코인/동물) 변경 → 오버레이 전체 재동기화
        if (previous?.missionCoins != next.missionCoins ||
            previous?.missionAnimals != next.missionAnimals) {
          unawaited(_syncOverlays());
        }

        // 회의 시작 시 GameMeetingScreen 푸시
        if (previous?.shouldNavigateToMeeting != true &&
            next.shouldNavigateToMeeting) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final mapState = ref.read(mapSessionProvider(widget.sessionId));
            final authUser = ref.read(authProvider).valueOrNull;
            final memberNames = {
              for (final e in mapState.members.entries) e.key: e.value.nickname
            };
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GameMeetingScreen(
                sessionId: widget.sessionId,
                memberNames: memberNames,
                myUserId: authUser?.id ?? '',
              ),
            ));
            ref
                .read(gameProvider(widget.sessionId).notifier)
                .resetMeetingNavigation();
          });
        }
      },
    );

    // 강제 퇴장 감지 + 유저 마커 실시간 동기화
    ref.listen<MapSessionState>(
      mapSessionProvider(widget.sessionId),
      (previous, next) {
        if (previous?.wasKicked != true && next.wasKicked) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            context.go(AppRoutes.home);
          });
        }

        // 멤버 위치·상태·숨김·탈락 변경 시 마커 동기화
        final authUser = ref.read(authProvider).valueOrNull;
        if (!identical(previous?.members, next.members) ||
            !identical(previous?.hiddenMembers, next.hiddenMembers) ||
            !identical(previous?.eliminatedUserIds, next.eliminatedUserIds)) {
          unawaited(_syncUserMarkers(
            next.members,
            authUser?.id,
            next.hiddenMembers,
            next.eliminatedUserIds,
          ));
        }
      },
    );

    final gameState = ref.watch(gameProvider(widget.sessionId));
    final mapState = ref.watch(mapSessionProvider(widget.sessionId));
    final authUser = ref.watch(authProvider).valueOrNull;
    final myUserId = authUser?.id;
    final isGhostMode =
        myUserId != null && mapState.eliminatedUserIds.contains(myUserId);

    final activeModules = _getActiveModules();
    final isInProgress = mapState.gameState.status == 'in_progress';
    final isDefaultMode = widget.sessionType == SessionType.defaultType;

    // 미션 진행도
    final progressCompleted =
        (gameState.missionProgress['completed'] as num?)?.toInt() ?? 0;
    final progressTotal =
        (gameState.missionProgress['total'] as num?)?.toInt() ?? 0;
    final rawPercent =
        (gameState.missionProgress['percent'] as num?)?.toDouble() ??
            (progressTotal > 0 ? progressCompleted / progressTotal : 0);
    final progress = ((rawPercent > 1 ? rawPercent / 100 : rawPercent)
            .clamp(0.0, 1.0) as num)
        .toDouble();

    // 카메라 추적
    final myPos = mapState.myPosition;
    if (_followMe && myPos != null && _mapController != null) {
      _mapController!.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: NLatLng(myPos.latitude, myPos.longitude),
        )..setAnimation(animation: NCameraAnimation.easing),
      );
    }


    final winnerId = mapState.gameState.winnerId;
    final winnerName = winnerId != null
        ? (mapState.members[winnerId]?.nickname ?? winnerId)
        : '-';

    // AI 채팅 하단 패널 높이 계산
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final chatBarH = _aiChatExpanded
        ? _kChatHandleH + _kChatContentH
        : _kChatHandleH + bottomSafe;

    // 액션 가능 여부
    final isImpostor = gameState.myRole?.isImpostor == true;
    final canUseKill = (activeModules.contains('proximity') ||
            widget.sessionType == SessionType.chase) &&
        !isGhostMode &&
        isInProgress;
    final canOpenVote = activeModules.contains('round') &&
        activeModules.contains('vote') &&
        !isGhostMode &&
        isInProgress;
    final canShowMission = widget.sessionType == SessionType.location ||
        activeModules.contains('mission');

    // 플러그인 컨텍스트 생성
    final pluginCtx = _buildPluginCtx(
      gameState: gameState,
      mapState: mapState,
      myUserId: myUserId,
      isGhostMode: isGhostMode,
      isInProgress: isInProgress,
      chatBarH: chatBarH,
      canKill: canUseKill,
      canOpenVote: canOpenVote,
      canShowMission: canShowMission,
      isImpostor: isImpostor,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_showSessionInfo) {
          _closeSessionInfo();
        } else {
          _openSessionInfo();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // ── Layer 1: NaverMap 배경 ─────────────────────────────
            if (_mapSdkReady)
              Positioned.fill(
                child: NaverMap(
                  options: NaverMapViewOptions(
                    initialCameraPosition: NCameraPosition(
                      target: myPos != null
                          ? NLatLng(myPos.latitude, myPos.longitude)
                          : const NLatLng(37.5665, 126.9780),
                      zoom: 14.0,
                    ),
                    locationButtonEnable: false,
                    zoomGesturesEnable: true,
                  ),
                  onMapReady: (controller) {
                    _mapController = controller;
                    try {
                      controller.setLocationTrackingMode(
                        NLocationTrackingMode.noFollow,
                      );
                    } catch (e) {
                      debugPrint('[GameMain] initial tracking mode 실패: $e');
                    }
                    // 지도 준비 후 현재 멤버 마커 + 폴리곤 + 미션 오버레이 적용
                    final ms = ref.read(mapSessionProvider(widget.sessionId));
                    final au = ref.read(authProvider).valueOrNull;
                    unawaited(_syncUserMarkers(
                      ms.members,
                      au?.id,
                      ms.hiddenMembers,
                      ms.eliminatedUserIds,
                    ));
                    unawaited(_syncOverlays());
                  },
                  onCameraChange: (reason, animated) {
                    if (reason == NCameraUpdateReason.gesture) {
                      setState(() => _followMe = false);
                      // follow → 사용자 제스처로 해제되면 Naver는 tracking
                      // 모드를 none으로 떨어뜨려 overlay까지 감출 수 있다.
                      // noFollow로 되돌려 위치·방향 오버레이는 유지.
                      try {
                        _mapController?.setLocationTrackingMode(
                          NLocationTrackingMode.noFollow,
                        );
                      } catch (_) {}
                    }
                  },
                ),
              )
            else
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0xFF0F172A),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),

            // ── Layer 2: 반투명 상단 헤더 ───────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopHeader(
                onBack: _openSessionInfo,
                onLeave: _confirmLeaveGame,
                role: !isDefaultMode ? gameState.myRole : null,
                progress: progress,
                completed: progressCompleted,
                total: progressTotal,
                showProgressBar: !isDefaultMode,
                isConnected: mapState.isConnected,
              ),
            ),

            // ── Layer 3: 우측 플로팅 컨트롤 (내 위치 / 줌 맞춤) ──────
            Positioned(
              right: 12,
              top: MediaQuery.of(context).padding.top + 96,
              child: _RightFloatingControls(
                followMe: _followMe,
                onFollow: () => unawaited(_onMyLocationPressed()),
                onFit: () => _fitAllMembers(mapState.members, myPos),
                onMembers: () => _openMemberSheet(mapState, myUserId),
                onAiChat: null,
              ),
            ),

            // ── Layer 4: SOS 배너 ──────────────────────────────────
            if (mapState.sosTriggered)
              Positioned(
                top: MediaQuery.of(context).padding.top + 72,
                left: 16,
                right: 16,
                child: Material(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.red,
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      'SOS 알림을 받았습니다',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),

            // ── Layer 5: 우상단 보조 칩 (생존자 / 라운드) ────────────
            if (isInProgress && mapState.gameState.aliveCount > 0)
              Positioned(
                top: MediaQuery.of(context).padding.top + 76,
                left: 16,
                child: _InfoChip(
                    label: '생존 ${mapState.gameState.aliveCount}명'),
              ),

            // ── Layer 5b: 게임 보이스 채널 연결 버튼 ────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 116,
              left: 16,
              child: _GameVoiceChannelButton(
                connected: _gameVoiceConnected,
                connecting: _gameVoiceConnecting,
                onConnect: _connectGameVoice,
                onDisconnect: _disconnectGameVoice,
              ),
            ),

            // ── Layer 6~7: 모드 플러그인 스택 레이어 ──────────────────
            // (태거 칩, 위치 미션 버튼, 구역 이탈 경고 등 모드별 레이어)
            ..._modePlugin.buildStackLayers(context, pluginCtx),

            // ── Layer 8: 하단 액션 영역 (모드 플러그인 위임) ─────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: chatBarH + 8,
              child: _modePlugin.buildBottomActions(context, pluginCtx),
            ),

            // ── Layer 9: 호스트 게임 시작 버튼 ───────────────────────
            if (mapState.myRole == 'host' &&
                mapState.gameState.status == 'none' &&
                !gameState.isStarted)
              Positioned(
                right: 16,
                bottom: chatBarH + 96,
                child: Material(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(28),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: () => ref
                        .read(gameProvider(widget.sessionId).notifier)
                        .startGame(),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Text('게임 시작',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ),

            // ── Layer 10: 유령 모드 오버레이 ─────────────────────────
            if (isGhostMode)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.28),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('사망 - 유령으로 관전 중',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),

            // ── Layer 12: 게임 종료 오버레이 ─────────────────────────
            if (mapState.gameState.status == 'finished')
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.82),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          winnerId != null && winnerId == myUserId
                              ? '승리'
                              : '게임 종료',
                          style: TextStyle(
                            color: winnerId == myUserId
                                ? const Color(0xFFFFD700)
                                : Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(winnerName,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 18)),
                        const SizedBox(height: 24),
                        TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 36, vertical: 12),
                          ),
                          onPressed: () {
                            final router = GoRouter.of(context);
                            if (router.canPop()) {
                              context.pop();
                            } else {
                              context.go(AppRoutes.home);
                            }
                          },
                          child: const Text('나가기'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Layer 14: AI 채팅 하단 패널 (항상 표시) ─────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _AiChatBar(
                sessionId: widget.sessionId,
                isGhostMode: isGhostMode,
                expanded: _aiChatExpanded,
                handleH: _kChatHandleH,
                contentH: _kChatContentH,
                onToggle: () =>
                    setState(() => _aiChatExpanded = !_aiChatExpanded),
              ),
            ),

            // ── Layer 13: 세션 정보 오버레이 (뒤로가기 시 표시) ──────
            if (_showSessionInfo)
              Positioned.fill(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: SafeArea(
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: TextButton(
                              onPressed: _closeSessionInfo,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('닫기'),
                            ),
                          ),
                        ),
                        Expanded(
                          child: SessionInfoContent(
                            sessionId: widget.sessionId,
                            sessionType: widget.sessionType,
                            onClose: _closeSessionInfo,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 하위 위젯들 (텍스트 기반, 아이콘 없음)
// ═══════════════════════════════════════════════════════════════════════

class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.onBack,
    required this.onLeave,
    required this.role,
    required this.progress,
    required this.completed,
    required this.total,
    required this.showProgressBar,
    required this.isConnected,
  });

  final VoidCallback onBack;
  final VoidCallback onLeave;
  final GameRole? role;
  final double progress;
  final int completed;
  final int total;
  final bool showProgressBar;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final roleLabel = role == null
        ? null
        : (role!.isImpostor ? '임포스터' : '크루');
    final roleColor = role == null
        ? Colors.white
        : (role!.isImpostor
            ? const Color(0xFFDC2626)
            : const Color(0xFF0EA5E9));

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.65),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TextButton(
                    onPressed: onBack,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                    ),
                    child: const Text('정보',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 4),
                  if (roleLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: roleColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: roleColor, width: 1),
                      ),
                      child: Text(roleLabel,
                          style: TextStyle(
                              color: roleColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                  const Spacer(),
                  if (!isConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('연결 끊김',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: onLeave,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                    child: const Text('나가기',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              if (showProgressBar) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '미션 $completed / $total',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF22C55E)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RightFloatingControls extends StatelessWidget {
  const _RightFloatingControls({
    required this.followMe,
    required this.onFollow,
    required this.onFit,
    required this.onMembers,
    required this.onAiChat,
  });

  final bool followMe;
  final VoidCallback onFollow;
  final VoidCallback onFit;
  final VoidCallback onMembers;
  final VoidCallback? onAiChat;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _MiniTextButton(
          label: '내 위치',
          background:
              followMe ? const Color(0xFF2196F3) : Colors.black.withValues(alpha: 0.7),
          onTap: onFollow,
        ),
        const SizedBox(height: 8),
        _MiniTextButton(
          label: '전체 보기',
          background: Colors.black.withValues(alpha: 0.7),
          onTap: onFit,
        ),
        const SizedBox(height: 8),
        _MiniTextButton(
          label: '참여자',
          background: Colors.black.withValues(alpha: 0.7),
          onTap: onMembers,
        ),
        if (onAiChat != null) ...[
          const SizedBox(height: 8),
          _MiniTextButton(
            label: 'AI 채팅',
            background: const Color(0xFF7C3AED).withValues(alpha: 0.9),
            onTap: onAiChat!,
          ),
        ],
      ],
    );
  }
}

class _MiniTextButton extends StatelessWidget {
  const _MiniTextButton({
    required this.label,
    required this.background,
    required this.onTap,
  });

  final String label;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// 게임 화면 상단에 노출되는 보이스 채널 토글.
/// - 미연결: "게임 보이스 채널 연결" 탭 시 mediasoup으로 재접속
/// - 연결됨: "보이스 연결 해제" 로 전환, 탭 시 leaveSession
class _GameVoiceChannelButton extends StatelessWidget {
  const _GameVoiceChannelButton({
    required this.connected,
    required this.connecting,
    required this.onConnect,
    required this.onDisconnect,
  });

  final bool connected;
  final bool connecting;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final bg = connected
        ? const Color(0xFF16A34A)
        : const Color(0xFF2563EB);
    final label = connecting
        ? '연결 중...'
        : (connected ? '보이스 연결 해제' : '게임 보이스 채널 연결');

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: connecting ? null : (connected ? onDisconnect : onConnect),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (connecting) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
              ] else ...[
                Icon(
                  connected ? Icons.mic_rounded : Icons.headset_mic_outlined,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── AI 채팅 하단 패널 ──────────────────────────────────────────────────
class _AiChatBar extends StatelessWidget {
  const _AiChatBar({
    required this.sessionId,
    required this.isGhostMode,
    required this.expanded,
    required this.handleH,
    required this.contentH,
    required this.onToggle,
  });

  final String sessionId;
  final bool isGhostMode;
  final bool expanded;
  final double handleH;
  final double contentH;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final totalH = expanded
        ? handleH + contentH + bottomSafe
        : handleH + bottomSafe;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      height: totalH,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        children: [
          // 핸들 바 (탭으로 토글)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: SizedBox(
              height: handleH,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'AI 채팅',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    expanded ? '닫기' : '열기',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
          ),
          // 채팅 패널 (펼쳐졌을 때만)
          if (expanded)
            Expanded(
              child: AIChatPanel(
                sessionId: sessionId,
                isGhostMode: isGhostMode,
                height: contentH,
              ),
            )
          else
            SizedBox(height: bottomSafe),
        ],
      ),
    );
  }
}
