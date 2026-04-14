import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/app_initialization_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/providers/connection_provider.dart'; // ★ 추가된 Provider
import '../../auth/data/auth_repository.dart';
import '../../home/data/session_repository.dart';
import '../../map/presentation/map_leaf_widgets.dart';
import '../../map/presentation/map_overlay_widgets.dart';
import '../../map/presentation/map_screen.dart';
import '../../map/presentation/map_session_models.dart';
import '../data/game_models.dart';
import '../providers/game_provider.dart';
import 'session_info_screen.dart';
import 'widgets/ai_chat_panel.dart';

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
  // ── 세션 정보 오버레이 (GoRouter push 대신 setState 오버레이 사용)
  // GoRouter의 형제 라우트 전환 시 기존 게임 화면이 dispose되는 문제를 방지
  bool _showSessionInfo = false;

  void _openSessionInfo() => setState(() => _showSessionInfo = true);
  void _closeSessionInfo() => setState(() => _showSessionInfo = false);

  // ── [Task 1] 리사이즈 가능 AI 채팅 패널 ───────────────────────────────────
  // 상단 pill 핸들을 드래그하면 패널 높이가 조정됩니다.
  double? _chatPanelHeight;
  static const double _kChatMinHeight = 200.0;
  static const double _kChatMaxHeightFactor = 0.72;

  void _onChatDragUpdate(DragUpdateDetails details) {
    final screenH = MediaQuery.of(context).size.height;
    setState(() {
      _chatPanelHeight =
          ((_chatPanelHeight ?? screenH * 0.5) - details.delta.dy)
              .clamp(_kChatMinHeight, screenH * _kChatMaxHeightFactor);
    });
  }
  // ─────────────────────────────────────────────────────────────────────────────

  // ── [Stage 2] 구역 이탈 경고 ────────────────────────────────────────────────
  bool _isOutOfBounds = false;
  bool _boundsAlertPulse = false; // 오버레이 맥박 애니메이션
  Timer? _boundsAlertTimer;
  StreamSubscription<Position>? _boundsCheckSub;

  /// Ray-Casting 알고리즘: 점이 폴리곤 내부에 있으면 true
  static bool _pointInPolygon(
      double lat, double lng, List<Map<String, double>> polygon) {
    final n = polygon.length;
    if (n < 3) return false;
    var inside = false;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i]['lng']!, yi = polygon[i]['lat']!;
      final xj = polygon[j]['lng']!, yj = polygon[j]['lat']!;
      final intersect =
          ((yi > lat) != (yj > lat)) && (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  void _startBoundsCheck(List<Map<String, double>> area) {
    _boundsCheckSub?.cancel();
    _boundsCheckSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3, // 3m 이상 이동 시에만 재판정
      ),
    ).listen((pos) {
      if (!mounted) return;
      final outside = !_pointInPolygon(pos.latitude, pos.longitude, area);
      if (outside == _isOutOfBounds) return;
      setState(() => _isOutOfBounds = outside);
      if (outside) {
        // 맥박 타이머 시작 (경고 오버레이 빛남 효과)
        _boundsAlertTimer?.cancel();
        _boundsAlertTimer =
            Timer.periodic(const Duration(milliseconds: 700), (_) {
          if (!mounted) {
            _boundsAlertTimer?.cancel();
            return;
          }
          setState(() => _boundsAlertPulse = !_boundsAlertPulse);
        });
      } else {
        _boundsAlertTimer?.cancel();
        setState(() => _boundsAlertPulse = false);
      }
    });
  }
  // ─────────────────────────────────────────────────────────────────────────────

  // ── [Task 3] KILL 쿨타임 ─────────────────────────────────────────────────
  static const int _kKillCooldownDefault = 30;
  int _killCooldownSecs = 0;
  int _killCooldownDuration = _kKillCooldownDefault; // initState에서 세션 설정으로 초기화
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
  // ─────────────────────────────────────────────────────────────────────────────

  // ── [Task 2] AppLifecycle 감지 ──────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 세션 설정에서 killCooldown을 미리 읽어 캐시 (킬할 때마다 목록 순회 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sessions =
          ref.read(sessionListProvider).valueOrNull ?? const <Session>[];
      final match = sessions.where((s) => s.id == widget.sessionId);
      if (match.isNotEmpty) {
        final session = match.first;
        _killCooldownDuration = session.killCooldown;

        // [Stage 2] 플레이 가능 영역이 설정된 경우 구역 이탈 감지 시작
        final area = session.playableArea;
        if (area != null && area.length >= 3) {
          ref
              .read(gameProvider(widget.sessionId).notifier)
              .setPlayableArea(area);
          _startBoundsCheck(area);
        }
      } else {
        _killCooldownDuration = _kKillCooldownDefault;
      }
    });
  }

  @override
  void dispose() {
    _killCooldownTimer?.cancel();
    _boundsCheckSub?.cancel();   // [Stage 2] 구역 이탈 GPS 구독 해제
    _boundsAlertTimer?.cancel(); // [Stage 2] 맥박 타이머 해제
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 앱이 백그라운드에서 포그라운드로 복귀할 때 호출됩니다.
  /// OS가 백그라운드에서 소켓 전송을 일시 중단했을 수 있으므로,
  /// 최신 게임 상태와 세션 스냅샷을 즉시 재요청하여 일관성을 복구합니다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[App] 포그라운드 복귀 → 소켓 상태 즉시 동기화 시작');
      // 1) 게임 상태 재요청 (역할·미션·투표 등)
      SocketService().requestGameState(widget.sessionId);
      // 2) 세션 재참가 → 서버가 session:snapshot 을 응답하여
      //    멤버 위치·상태가 최신으로 복구됩니다.
      SocketService().emit(
        SocketEvents.joinSession,
        {'sessionId': widget.sessionId},
      );
    }
  }
  // ────────────────────────────────────────────────────────────────────────────

  // ── 누락되었던 필수 기능 메서드 복구 ──

  // ── [Task 4] 아이템 상점 ─────────────────────────────────────────────────
  void _openShopSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        const items = [
          _ShopItem(
              name: '이동속도 증가',
              desc: '30초간 이동 속도 +50%',
              price: 50,
              icon: Icons.speed_rounded),
          _ShopItem(
              name: '시야 확장',
              desc: '60초간 시야 범위 +100%',
              price: 80,
              icon: Icons.visibility_rounded),
          _ShopItem(
              name: '위치 은폐',
              desc: '30초간 위치 추적 불가',
              price: 100,
              icon: Icons.location_off_rounded),
          _ShopItem(
              name: '순간이동',
              desc: '임의 위치로 순간이동',
              price: 150,
              icon: Icons.flash_on_rounded),
          _ShopItem(
              name: '함정 설치',
              desc: '이동 경로에 함정 배치',
              price: 120,
              icon: Icons.pest_control_rounded),
          _ShopItem(
              name: '쿨타임 감소',
              desc: '킬 쿨타임 -50% (1회)',
              price: 200,
              icon: Icons.timer_off_rounded),
        ];

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.38,
          maxChildSize: 0.88,
          builder: (ctx, scrollCtrl) {
            return DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Row(
                        children: [
                          const Icon(Icons.storefront_rounded,
                              color: Colors.white, size: 22),
                          const SizedBox(width: 10),
                          const Text('아이템 상점',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF6DA),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.monetization_on_rounded,
                                    color: Color(0xFFC58A00), size: 16),
                                SizedBox(width: 4),
                                Text('준비 중',
                                    style: TextStyle(
                                        color: Color(0xFFC58A00),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 1.35,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(item.icon,
                                    color: Colors.cyanAccent, size: 26),
                                const SizedBox(height: 6),
                                Text(item.name,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                                const SizedBox(height: 2),
                                Expanded(
                                  child: Text(item.desc,
                                      style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.6),
                                          fontSize: 11),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                Row(
                                  children: [
                                    const Icon(Icons.monetization_on_rounded,
                                        color: Color(0xFFC58A00), size: 13),
                                    const SizedBox(width: 3),
                                    Text('${item.price}',
                                        style: const TextStyle(
                                            color: Color(0xFFC58A00),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12)),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: () => ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('아이템 구매 기능은 준비 중입니다.'),
                                            duration: Duration(seconds: 2)),
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF7C3AED),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: const Text('구매',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
      },
    );
  }
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _openMapSheet() {
    final mapState = ref.read(mapSessionProvider(widget.sessionId));
    final myUserId = ref.read(authProvider).valueOrNull?.id;
    final isGhostMode = mapState.eliminatedUserIds.contains(myUserId);

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _GameMapSheet(
          sessionId: widget.sessionId,
          sessionType: widget.sessionType,
          isGhostMode: isGhostMode,
        ),
      ),
    );
  }

  Future<void> _openMissionSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MissionBottomSheet(sessionId: widget.sessionId),
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
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text('시체 신고',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final player in deadPlayers)
                ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: Color(0x1AFF3B30),
                      child: Icon(Icons.dangerous, color: Colors.red)),
                  title: Text(player.nickname),
                  subtitle: Text(player.userId),
                  onTap: () {
                    Navigator.of(context).pop();
                    ref
                        .read(gameProvider(widget.sessionId).notifier)
                        .sendReport(player.userId);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _handleEmergency() {
    ref.read(gameProvider(widget.sessionId).notifier).sendEmergency((result) {
      if (!mounted || result['ok'] == true) return;
      final error = result['error']?.toString() ?? '회의를 소집할 수 없습니다.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    });
  }

  @override
  Widget build(BuildContext context) {
    // ── 네비게이션 및 사이드 이펙트 처리 ──
    // ⚠️ addPostFrameCallback으로 감싸서 '!_debugLocked' 에러 방지
    // (finalizeTree/unmount 단계에서 직접 navigate 호출 시 Navigator lock 충돌 발생)
    ref.listen<AmongUsGameState>(
      gameProvider(widget.sessionId),
      (previous, next) {
        if (previous?.shouldNavigateToRole != true &&
            next.shouldNavigateToRole) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            context.push('/game/${widget.sessionId}/role');
            ref
                .read(gameProvider(widget.sessionId).notifier)
                .resetRoleNavigation();
          });
        }
        // gameOverWinner: null = 진행 중, 'crew'|'impostor' = 게임 종료
        if (previous?.gameOverWinner == null && next.gameOverWinner != null) {
          final winner = next.gameOverWinner!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            context.go('/game/${widget.sessionId}/result/$winner');
          });
        }
      },
    );

    ref.listen<MapSessionState>(
      mapSessionProvider(widget.sessionId),
      (previous, next) {
        if (previous?.wasKicked != true && next.wasKicked) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            context.go('/');
          });
        }
      },
    );

    // ── [Task 1] 채팅 패널 초기 높이 (한 번만) ───────────────────────────────
    _chatPanelHeight ??= MediaQuery.of(context).size.height * 0.50;

    // ── 상태 읽기 ──
    final gameState = ref.watch(gameProvider(widget.sessionId));
    final mapState = ref.watch(mapSessionProvider(widget.sessionId));
    final authUser = ref.watch(authProvider).valueOrNull;

    // 네트워크 연결 상태
    final isConnectedAsync = ref.watch(socketConnectionProvider);
    final isConnected = isConnectedAsync.value ?? true;

    // 변수 계산
    final myUserId = authUser?.id;
    final isGhostMode = mapState.eliminatedUserIds.contains(myUserId);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final isKeyboardVisible = bottomInset > 0;

    // 미션 진행도 계산
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

    return PopScope(
      // canPop: false → 시스템 뒤로가기를 항상 onPopInvokedWithResult에서 처리
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // 세션 정보가 열려 있으면 닫기, 아니면 열기
        // GoRouter/Navigator를 전혀 건드리지 않고 setState만 사용
        if (_showSessionInfo) {
          _closeSessionInfo();
        } else {
          _openSessionInfo();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: const Color(0xFFF1F5F9),
        body: SafeArea(
          child: Stack(
            children: [
              // 메인 화면 레이아웃
              DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFEAF3FF),
                      Color(0xFFF4F6FB),
                      Color(0xFFF8FAFC)
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    // 뒤로가기(←) 버튼 + 상단 정보 바
                    // defaultType도 포함하여 항상 표시
                    _GameMainTopBar(
                      role: widget.sessionType != SessionType.defaultType
                          ? gameState.myRole
                          : null,
                      progress: progress,
                      completed: progressCompleted,
                      total: progressTotal,
                      coinCount: 0,
                      showProgressBar:
                          widget.sessionType != SessionType.defaultType,
                      onBack: _openSessionInfo,
                    ),

                    // ── [Task 1] 리사이즈 가능 AI 채팅 패널 ───────────────────
                    SizedBox(
                      height: _chatPanelHeight,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(28)),
                          child: AIChatPanel(
                            sessionId: widget.sessionId,
                            isGhostMode: isGhostMode,
                            height: double.infinity,
                            onDragUpdate: _onChatDragUpdate,
                          ),
                        ),
                      ),
                    ),

                    if (!isKeyboardVisible)
                      _GameBottomDock(
                        actions: [
                          // ── [Task 3] KILL / TAG 버튼 ─────────────────────────
                          // 표시 조건: 임포스터이거나 chase 모드 (유령 모드 제외)
                          if ((gameState.myRole?.isImpostor == true ||
                                  widget.sessionType == SessionType.chase) &&
                              !isGhostMode)
                            _GameActionItem(
                              icon: widget.sessionType == SessionType.chase
                                  ? Icons.touch_app_rounded
                                  : Icons.close,
                              // 쿨타임 중엔 남은 시간 표시
                              label: _killCooldownSecs > 0
                                  ? '${widget.sessionType == SessionType.chase ? '태그' : '킬'} (${_killCooldownSecs}s)'
                                  : (widget.sessionType == SessionType.chase
                                      ? '태그'
                                      : '킬'),
                              backgroundColor: _killCooldownSecs > 0
                                  ? const Color(0xFF7F1D1D)
                                      .withValues(alpha: 0.55)
                                  : const Color(0xFF7F1D1D),
                              // BT/UWB 근접 탐지 구현 전까지는 proximateTargetId 없이도 킬 가능하도록
                              onTap: _killCooldownSecs == 0
                                  ? () {
                                      final targetId =
                                          mapState.proximateTargetId;
                                      if (targetId != null) {
                                        _handleKill(targetId);
                                      } else {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text('근처에 대상이 없습니다.')),
                                        );
                                      }
                                    }
                                  : null,
                            ),

                          // ── 지도 (전체 공통) ──────────────────────────────────
                          _GameActionItem(
                            icon: Icons.map_outlined,
                            label: '지도',
                            backgroundColor: const Color(0xFF1D4ED8),
                            onTap: _openMapSheet,
                          ),

                          // ── 시체 신고 (verbal 전용) ───────────────────────────
                          if (widget.sessionType == SessionType.verbal)
                            _GameActionItem(
                              icon: Icons.report_gmailerrorred_rounded,
                              label: '시체 신고',
                              backgroundColor: const Color(0xFFD14343),
                              onTap: (!isGhostMode &&
                                      mapState.eliminatedUserIds.isNotEmpty)
                                  ? () => _showReportSheet(mapState)
                                  : null,
                            ),

                          // ── 긴급호출 (verbal 전용) ────────────────────────────
                          if (widget.sessionType == SessionType.verbal)
                            _GameActionItem(
                              icon: Icons.warning_amber_rounded,
                              label: '긴급호출',
                              backgroundColor: const Color(0xFFB45309),
                              onTap: !isGhostMode ? _handleEmergency : null,
                            ),

                          // ── 미션 (location 전용) ──────────────────────────────
                          if (widget.sessionType == SessionType.location)
                            _GameActionItem(
                              icon: Icons.assignment_outlined,
                              label: '미션',
                              backgroundColor: const Color(0xFF0F766E),
                              onTap: !isGhostMode ? _openMissionSheet : null,
                            ),

                          // ── [Task 4] 아이템 상점 (game 모드 전용) ─────────────
                          if (widget.sessionType != SessionType.defaultType)
                            _GameActionItem(
                              icon: Icons.storefront_rounded,
                              label: '상점',
                              backgroundColor: const Color(0xFF7C3AED),
                              onTap: !isGhostMode ? _openShopSheet : null,
                            ),
                        ],
                      ),
                  ],
                ),
              ),

              // 유령 모드 오버레이
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
                                fontSize: 24,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),

              // ── [Stage 2] 구역 이탈 경고 오버레이 ──────────────────────────
              // playableArea가 설정되어 있고 플레이어가 영역 밖에 있을 때 표시
              // IgnorePointer: true → 사용자가 UI를 계속 조작할 수 있음
              if (_isOutOfBounds)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 700),
                      color: Colors.red.withValues(
                          alpha: _boundsAlertPulse ? 0.40 : 0.22),
                      child: Center(
                        child: AnimatedScale(
                          scale: _boundsAlertPulse ? 1.04 : 1.0,
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeInOut,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 32),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7F1D1D).withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.red.shade300.withValues(alpha: 0.8),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withValues(alpha: 0.4),
                                  blurRadius: 24,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fmd_bad_rounded,
                                  color: Colors.red.shade200,
                                  size: 44,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  '플레이 구역을 벗어났습니다!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '구역으로 돌아가주세요',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.red.shade200,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // 오프라인(네트워크 단절) 경고 배너
              if (!isConnected)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 300),
                    tween: Tween(begin: -50.0, end: 0.0),
                    builder: (context, value, child) {
                      return Transform.translate(
                          offset: Offset(0, value), child: child);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: Colors.redAccent,
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('서버와 연결이 끊겼습니다. 재연결 중...',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── 세션 정보 오버레이 ───────────────────────────────────────
              // GoRouter push 없이 게임 화면 위에 슬라이드로 올라오는 오버레이
              // 이 방식은 게임 화면을 dispose하지 않으므로 소켓이 유지됩니다
              AnimatedSlide(
                offset: _showSessionInfo ? Offset.zero : const Offset(-1, 0),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut,
                child: AnimatedOpacity(
                  opacity: _showSessionInfo ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  child: _showSessionInfo
                      ? _SessionInfoOverlay(
                          sessionId: widget.sessionId,
                          sessionType: widget.sessionType,
                          onClose: _closeSessionInfo,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ), // Scaffold
    ); // PopScope
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// [Stage 3] 미션 BottomSheet
// ConsumerStatefulWidget으로 ref.watch를 사용해 실시간 상태 반영
// ══════════════════════════════════════════════════════════════════════════════

class _MissionBottomSheet extends ConsumerStatefulWidget {
  const _MissionBottomSheet({required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<_MissionBottomSheet> createState() =>
      _MissionBottomSheetState();
}

class _MissionBottomSheetState extends ConsumerState<_MissionBottomSheet> {
  // 확장된 미션 ID 집합 — 탭하면 상세설명 토글
  final Set<String> _expandedIds = {};

  void _toggleExpand(String id) =>
      setState(() => _expandedIds.contains(id)
          ? _expandedIds.remove(id)
          : _expandedIds.add(id));

  /// [Stage 4] 미션 완료 처리 — 소켓으로 완료 이벤트 전송 + 피드백 표시
  void _completeMission(BuildContext ctx, String missionId) {
    ref
        .read(gameProvider(widget.sessionId).notifier)
        .completeMission(missionId);

    // 확장 패널 닫기
    setState(() => _expandedIds.remove(missionId));

    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: Colors.white, size: 18),
            SizedBox(width: 10),
            Text('미션을 완료했습니다!',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ref.watch → 미션 완료 이벤트 수신 시 즉시 리빌드
    final gameState = ref.watch(gameProvider(widget.sessionId));
    final missions = gameState.missions;

    final completed =
        (gameState.missionProgress['completed'] as num?)?.toInt() ?? 0;
    final total =
        (gameState.missionProgress['total'] as num?)?.toInt() ?? 0;
    final rawPercent =
        (gameState.missionProgress['percent'] as num?)?.toDouble() ??
            (total > 0 ? completed / total : 0.0);
    final progress = ((rawPercent > 1 ? rawPercent / 100 : rawPercent)
            .clamp(0.0, 1.0) as num)
        .toDouble();

    // 역할에 따른 강조색
    final isImpostor = gameState.myRole?.isImpostor == true;
    final accentColor = isImpostor ? const Color(0xFFEF4444) : const Color(0xFF10B981);

    // 미완료 / 완료 분리
    final pending = missions.where((m) => !m.isCompleted).toList();
    final done = missions.where((m) => m.isCompleted).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                // ── 핸들 ──────────────────────────────────────────────────
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── 헤더 ──────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.assignment_rounded,
                            color: accentColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isImpostor ? '임포스터 미션' : '내 미션',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700),
                            ),
                            Text(
                              total > 0
                                  ? '전체 진행도 $completed / $total'
                                  : '미션이 아직 배정되지 않았습니다',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      // 완료 카운트 뱃지
                      if (missions.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${done.length}/${missions.length}',
                            style: TextStyle(
                                color: accentColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── 전체 크루 진행 Progress Bar ──────────────────────────
                // GameProvider의 missionProgress와 실시간 연동
                if (total > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '전체 크루 미션 진행도',
                              style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.6),
                                  fontSize: 11),
                            ),
                            Text(
                              '${(progress * 100).round()}%',
                              style: TextStyle(
                                  color: accentColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: progress),
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOut,
                            builder: (_, val, __) => LinearProgressIndicator(
                              value: val,
                              minHeight: 8,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.08),
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(accentColor),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),
                Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.08)),
                const SizedBox(height: 4),

                // ── 미션 목록 ─────────────────────────────────────────────
                Expanded(
                  child: missions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.hourglass_empty_rounded,
                                  color: Colors.white.withValues(alpha: 0.25),
                                  size: 44),
                              const SizedBox(height: 12),
                              Text(
                                '게임이 시작되면\n미션이 배정됩니다',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.4),
                                    fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          controller: scrollCtrl,
                          padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 32),
                          children: [
                            // 미완료 섹션
                            if (pending.isNotEmpty) ...[
                              _SectionHeader(
                                label: '남은 미션',
                                count: pending.length,
                                color: Colors.amber.shade400,
                              ),
                              const SizedBox(height: 8),
                              ...pending.map((m) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _MissionCard(
                                      mission: m,
                                      isExpanded:
                                          _expandedIds.contains(m.id),
                                      onTap: () => _toggleExpand(m.id),
                                      // [Stage 4] 위치가 없는 미션은 항상 활성화,
                                      // 위치가 있는 미션은 반경 내에 있을 때만 활성화
                                      onComplete: m.isFake
                                          ? null
                                          : (!m.hasLocation ||
                                                  gameState.nearbyMissionIds
                                                      .contains(m.id))
                                              ? () => _completeMission(
                                                  context, m.id)
                                              : null,
                                    ),
                                  )),
                            ],

                            // 완료 섹션
                            if (done.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              _SectionHeader(
                                label: '완료된 미션',
                                count: done.length,
                                color: Colors.green.shade400,
                              ),
                              const SizedBox(height: 8),
                              ...done.map((m) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _MissionCard(
                                      mission: m,
                                      isExpanded:
                                          _expandedIds.contains(m.id),
                                      onTap: () => _toggleExpand(m.id),
                                      onComplete: null,
                                    ),
                                  )),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── 섹션 헤더 ─────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 미션 카드 ─────────────────────────────────────────────────────────────────

class _MissionCard extends StatelessWidget {
  const _MissionCard({
    required this.mission,
    required this.isExpanded,
    required this.onTap,
    required this.onComplete, // null이면 버튼 비활성화
  });

  final GameMission mission;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final isDone = mission.isCompleted;
    final isFake = mission.isFake;

    // 상태별 색상
    final cardBg = isDone
        ? const Color(0xFF14532D).withValues(alpha: 0.55)
        : isFake
            ? const Color(0xFF450A0A).withValues(alpha: 0.55)
            : const Color(0xFF1E293B);

    final borderColor = isDone
        ? const Color(0xFF16A34A).withValues(alpha: 0.5)
        : isFake
            ? const Color(0xFFEF4444).withValues(alpha: 0.4)
            : Colors.white.withValues(alpha: 0.07);

    final iconBg = isDone
        ? const Color(0xFF166534).withValues(alpha: 0.6)
        : isFake
            ? const Color(0xFF7F1D1D).withValues(alpha: 0.6)
            : const Color(0xFF334155);

    final iconColor = isDone
        ? const Color(0xFF4ADE80)
        : isFake
            ? const Color(0xFFF87171)
            : const Color(0xFF94A3B8);

    final icon = isDone
        ? Icons.check_circle_rounded
        : isFake
            ? Icons.warning_amber_rounded
            : Icons.radio_button_unchecked_rounded;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 카드 헤더 행 ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                children: [
                  // 상태 아이콘
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: iconBg, shape: BoxShape.circle),
                    child: Icon(icon, color: iconColor, size: 18),
                  ),
                  const SizedBox(width: 12),

                  // 제목 + 뱃지들
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                mission.title.isEmpty
                                    ? mission.id
                                    : mission.title,
                                style: TextStyle(
                                  color: isDone
                                      ? Colors.white.withValues(alpha: 0.5)
                                      : Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  decoration: isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor:
                                      Colors.white.withValues(alpha: 0.3),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // 뱃지 행
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            if (isFake)
                              const _Badge(
                                  label: '가짜 미션',
                                  color: Color(0xFFEF4444)),
                            if (mission.hasLocation)
                              const _Badge(
                                  label: '📍 위치 있음',
                                  color: Color(0xFF3B82F6)),
                            if (mission.zone.isNotEmpty && !isFake)
                              _Badge(
                                  label: mission.zone,
                                  color: const Color(0xFF64748B)),
                            _Badge(
                              label: _typeLabel(mission.type),
                              color: const Color(0xFF475569),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 확장 화살표
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white.withValues(alpha: 0.35),
                    size: 20,
                  ),
                ],
              ),
            ),

            // ── 확장 영역: 상세 설명 + 수행하기 버튼 ───────────────────
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 구분선
                    Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.07)),
                    const SizedBox(height: 12),

                    // 상세 설명 (있을 때만)
                    if (mission.zone.isNotEmpty) ...[
                      _DetailRow(
                          icon: Icons.place_outlined,
                          text: mission.zone),
                      const SizedBox(height: 6),
                    ],
                    if (mission.hasLocation) ...[
                      _DetailRow(
                        icon: Icons.my_location_rounded,
                        text:
                            '${mission.lat!.toStringAsFixed(6)}, ${mission.lng!.toStringAsFixed(6)}',
                      ),
                      const SizedBox(height: 6),
                    ],
                    _DetailRow(
                      icon: Icons.info_outline_rounded,
                      text: isFake
                          ? '이 미션은 가짜입니다. 수행하는 척하며 크루를 속이세요.'
                          : _typeDescription(mission.type),
                    ),

                    // 수행하기 버튼 — 위치 없는 미션은 항상 활성화
                    //                위치 있는 미션은 반경 내에 있을 때만 활성화
                    if (!isDone && !isFake) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onComplete,
                          style: FilledButton.styleFrom(
                            backgroundColor: onComplete != null
                                ? const Color(0xFF10B981)
                                : Colors.white.withValues(alpha: 0.08),
                            foregroundColor: onComplete != null
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.3),
                            padding:
                                const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: Icon(
                            onComplete != null
                                ? Icons.check_rounded
                                : Icons.location_searching_rounded,
                            size: 18,
                          ),
                          label: Text(
                            onComplete != null
                                ? '미션 수행하기'
                                : mission.hasLocation
                                    ? '📍 ${GameNotifier.kActivationRadius.toInt()}m 이내로 접근하면 활성화됩니다'
                                    : '수행하기',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 220),
            ),

            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    return switch (type) {
      'qr_scan'   => 'QR 스캔',
      'mini_game' => '미니게임',
      'stay'      => '대기',
      _           => type,
    };
  }

  String _typeDescription(String type) {
    return switch (type) {
      'qr_scan'   => '해당 장소의 QR 코드를 스캔하여 완료하세요.',
      'mini_game' => '미션 위치에서 미니게임을 완료하세요.',
      'stay'      => '지정된 위치에 일정 시간 머물러 완료하세요.',
      _           => '미션을 수행하여 완료하세요.',
    };
  }
}

// ── 뱃지 ─────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── 상세 정보 행 ──────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon,
            size: 14,
            color: Colors.white.withValues(alpha: 0.4)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 12,
                height: 1.5),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 세션 정보 오버레이 – GameMainScreen Stack 위에 올라오는 전체화면 위젯
// GoRouter/Navigator를 사용하지 않으므로 게임 상태(소켓 등)가 유지됩니다
// ══════════════════════════════════════════════════════════════════════════════

class _SessionInfoOverlay extends StatelessWidget {
  const _SessionInfoOverlay({
    required this.sessionId,
    required this.sessionType,
    required this.onClose,
  });

  final String sessionId;
  final SessionType sessionType;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0F0A2A),
      child: SafeArea(
        child: SessionInfoContent(
          sessionId: sessionId,
          sessionType: sessionType,
          onClose: onClose,
        ),
      ),
    );
  }
}

// ==========================================
// 하위 위젯들은 기존 코드와 완벽하게 동일합니다.
// ==========================================

class _GameMainTopBar extends StatelessWidget {
  const _GameMainTopBar({
    required this.role,
    required this.progress,
    required this.completed,
    required this.total,
    required this.coinCount,
    required this.onBack,
    this.showProgressBar = true,
  });
  final GameRole? role;
  final double progress;
  final int completed;
  final int total;
  final int coinCount;
  final VoidCallback onBack;
  final bool showProgressBar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
      child: Row(
        children: [
          // ← 뒤로가기 버튼 (세션 정보 화면으로 이동)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 18, color: Color(0xFF1F2937)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 역할 배지
          if (role != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: role!.isImpostor
                    ? Colors.red.withValues(alpha: 0.14)
                    : Colors.green.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                role!.isImpostor ? '임포스터' : '크루원',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: role!.isImpostor ? Colors.red : Colors.green,
                    fontWeight: FontWeight.w700),
              ),
            ),
          if (role != null) const SizedBox(width: 10),
          // 미션 진행도
          if (showProgressBar)
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 14,
                        offset: const Offset(0, 6))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('미션 $completed / $total',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12)),
                    const SizedBox(height: 6),
                    ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor:
                                Colors.green.withValues(alpha: 0.12),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.green))),
                  ],
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 10),
          // 코인 표시
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF6DA),
                borderRadius: BorderRadius.circular(14)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.monetization_on_rounded,
                    color: Color(0xFFC58A00), size: 16),
                const SizedBox(width: 5),
                Text('$coinCount',
                    style: const TextStyle(
                        color: Color(0xFFC58A00),
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GameBottomDock extends StatelessWidget {
  const _GameBottomDock({required this.actions});
  final List<_GameActionItem> actions;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.white, boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -8))
      ]),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  for (var index = 0; index < actions.length; index++) ...[
                    Expanded(child: _GameActionButton(item: actions[index])),
                    if (index != actions.length - 1) const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameActionButton extends StatelessWidget {
  const _GameActionButton({required this.item});
  final _GameActionItem item;

  @override
  Widget build(BuildContext context) {
    final enabled = item.onTap != null;
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: item.onTap,
        icon: Icon(item.icon),
        label: Text(item.label),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              enabled ? item.backgroundColor : const Color(0xFFB7BDC8),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    );
  }
}

class _GameActionItem {
  const _GameActionItem(
      {required this.icon,
      required this.label,
      required this.backgroundColor,
      required this.onTap});
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final VoidCallback? onTap;
}

// ── [Task 4] 상점 아이템 데이터 모델 ──────────────────────────────────────────
class _ShopItem {
  const _ShopItem(
      {required this.name,
      required this.desc,
      required this.price,
      required this.icon});
  final String name;
  final String desc;
  final int price;
  final IconData icon;
}

class _MapMemberPanelToggle extends StatelessWidget {
  const _MapMemberPanelToggle({required this.memberCount, required this.onTap});
  final int memberCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 8))
              ]),
          child: Row(
            children: [
              const Icon(Icons.people_alt_rounded, color: Color(0xFF1F2937)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text('멤버 위치 보기 · $memberCount명',
                      style: const TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w700))),
              const Icon(Icons.keyboard_arrow_up_rounded,
                  color: Color(0xFF4B5563)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── verbal 모드 임포스터 킬 버튼 (지도 시트 전용) ─────────────────────────
class _VerbalKillMapButton extends StatelessWidget {
  const _VerbalKillMapButton({
    required this.hasTarget,
    required this.onKill,
  });

  final bool hasTarget;
  final VoidCallback onKill;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: ElevatedButton.icon(
        onPressed: onKill,
        style: ElevatedButton.styleFrom(
          backgroundColor: hasTarget ? Colors.red : Colors.grey.shade600,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: hasTarget ? 6 : 0,
          shadowColor:
              hasTarget ? Colors.red.withValues(alpha: 0.4) : Colors.transparent,
        ),
        icon: Icon(hasTarget
            ? Icons.dangerous_rounded
            : Icons.dangerous_outlined),
        label: Text(
          hasTarget ? '제거' : '범위 밖',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}

class _GameMapSheet extends ConsumerStatefulWidget {
  const _GameMapSheet(
      {required this.sessionId,
      required this.sessionType,
      required this.isGhostMode});
  final String sessionId;
  final SessionType sessionType;
  final bool isGhostMode;
  @override
  ConsumerState<_GameMapSheet> createState() => _GameMapSheetState();
}

class _GameMapSheetState extends ConsumerState<_GameMapSheet> {
  NaverMapController? _mapController;
  bool _mapSdkReady = false;
  bool _followMe = true;
  bool _isMemberPanelExpanded = false;
  final Map<String, NMarker> _activeMarkers = {};
  Map<String, MemberState>? _previousMembers;
  bool? _previousSharingEnabled;
  Set<String>? _previousHiddenMembers;
  Set<String>? _previousEliminatedUserIds;
  String? _previousUserId;

  // ── 플레이 영역 폴리곤 캐시 ─────────────────────────────────────────────
  NPolygonOverlay? _playableAreaPolygon;
  List<Map<String, double>>? _prevPlayableArea;
  bool _polygonScheduled = false;

  NPolygonOverlay? _buildPlayableAreaPolygon(
      List<Map<String, double>>? area) {
    if (area == null || area.length < 3) return null;
    final coords =
        area.map((p) => NLatLng(p['lat'] ?? 0.0, p['lng'] ?? 0.0)).toList();
    return NPolygonOverlay(
      id: 'playable_area_sheet',
      coords: coords,
      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
      outlineColor: const Color(0xFF2563EB),
      outlineWidth: 2,
    );
  }

  /// 기존 폴리곤을 지우고 새 폴리곤을 지도에 추가합니다.
  /// build() 안에서 직접 호출하지 말고 addPostFrameCallback을 통해 호출하세요.
  void _syncPlayableAreaOverlay() {
    final ctrl = _mapController;
    if (ctrl == null) return;
    // 기존 폴리곤 제거 (없어도 무방 – 예외 무시)
    try {
      ctrl.deleteOverlay(const NOverlayInfo(
        type: NOverlayType.polygonOverlay,
        id: 'playable_area_sheet',
      ));
    } catch (_) {}
    final polygon = _playableAreaPolygon;
    if (polygon != null) ctrl.addOverlay(polygon);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_ensureMapSdkReady());
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
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapSessionProvider(widget.sessionId));
    final gameState = ref.watch(gameProvider(widget.sessionId));
    final authUser = ref.watch(authProvider).valueOrNull;
    final myPosition = mapState.myPosition;
    final myUserId = authUser?.id;
    final activeModules = widget.sessionType.toModules().toSet();

    if (_followMe && myPosition != null && _mapController != null) {
      _mapController!.updateCamera(NCameraUpdate.scrollAndZoomTo(
          target: NLatLng(myPosition.latitude, myPosition.longitude))
        ..setAnimation(animation: NCameraAnimation.easing));
    }

    if (!identical(_previousMembers, mapState.members) ||
        _previousSharingEnabled != mapState.sharingEnabled ||
        !identical(_previousHiddenMembers, mapState.hiddenMembers) ||
        !identical(_previousEliminatedUserIds, mapState.eliminatedUserIds) ||
        _previousUserId != myUserId) {
      _previousMembers = mapState.members;
      _previousSharingEnabled = mapState.sharingEnabled;
      _previousHiddenMembers = mapState.hiddenMembers;
      _previousEliminatedUserIds = mapState.eliminatedUserIds;
      _previousUserId = myUserId;
      _syncMarkers(mapState.members, myUserId, mapState.sharingEnabled,
          mapState.hiddenMembers, mapState.eliminatedUserIds);
    }

    final playableArea = gameState.playableArea;
    if (!identical(_prevPlayableArea, playableArea)) {
      _prevPlayableArea = playableArea;
      _playableAreaPolygon = _buildPlayableAreaPolygon(playableArea);
      if (!_polygonScheduled) {
        _polygonScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _polygonScheduled = false;
          if (mounted) _syncPlayableAreaOverlay();
        });
      }
    }

    final canUseChaseAction = widget.sessionType == SessionType.chase &&
        !widget.isGhostMode &&
        !mapState.isEliminated &&
        mapState.proximateTargetId != null &&
        mapState.gameState.status == 'in_progress';
    // verbal 모드 임포스터 킬
    final isImpostor = gameState.myRole?.isImpostor == true;
    final showVerbalKill = widget.sessionType == SessionType.verbal &&
        isImpostor &&
        !widget.isGhostMode &&
        !mapState.isEliminated &&
        mapState.gameState.status == 'in_progress';
    final verbalKillHasTarget = mapState.proximateTargetId != null;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final memberCount = mapState.members.length;
    final memberPanelReserve =
        _isMemberPanelExpanded ? 168.0 + bottomPadding : 72.0 + bottomPadding;
    final floatingControlsBottom =
        memberPanelReserve + (canUseChaseAction ? 88 : 20);
    final chaseButtonBottom = memberPanelReserve + 16;

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: ColoredBox(
          color: Colors.white,
          child: Stack(
            children: [
              if (_mapSdkReady)
                NaverMap(
                  options: NaverMapViewOptions(
                    initialCameraPosition: NCameraPosition(
                        target: myPosition != null
                            ? NLatLng(myPosition.latitude, myPosition.longitude)
                            : const NLatLng(37.5665, 126.9780),
                        zoom: 14),
                    locationButtonEnable: false,
                    zoomGesturesEnable: true,
                  ),
                  onMapReady: (controller) {
                    _mapController = controller;
                    _syncMarkers(
                        mapState.members,
                        myUserId,
                        mapState.sharingEnabled,
                        mapState.hiddenMembers,
                        mapState.eliminatedUserIds);
                    _syncPlayableAreaOverlay();
                  },
                  onCameraChange: (reason, _) {
                    if (reason == NCameraUpdateReason.gesture) {
                      setState(() => _followMe = false);
                    }
                  },
                )
              else
                const Center(child: CircularProgressIndicator()),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(18)),
                            child: const Text('지도',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700))),
                        const Spacer(),
                        IconButton.filled(
                            onPressed: () => Navigator.of(context).pop(),
                            style: IconButton.styleFrom(
                                backgroundColor:
                                    Colors.black.withValues(alpha: 0.7)),
                            icon: const Icon(Icons.close, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
              MapFloatingControls(
                followMe: _followMe,
                bottomOffset: floatingControlsBottom,
                onFollowPressed: () {
                  setState(() => _followMe = true);
                  if (myPosition != null) {
                    _mapController?.updateCamera(NCameraUpdate.scrollAndZoomTo(
                        target:
                            NLatLng(myPosition.latitude, myPosition.longitude))
                      ..setAnimation(animation: NCameraAnimation.easing));
                  }
                },
                onFitPressed: () =>
                    _fitAllMembers(mapState.members, myPosition),
              ),
              if (gameState.myRole != null)
                Positioned(
                  top: 76,
                  left: 16,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: gameState.myRole!.isImpostor
                            ? Colors.red.withValues(alpha: 0.9)
                            : Colors.green.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(gameState.myRole!.isImpostor ? '임포스터' : '크루원',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              if (showVerbalKill)
                Positioned(
                  left: 16,
                  bottom: chaseButtonBottom,
                  child: SafeArea(
                    top: false,
                    child: _VerbalKillMapButton(
                      hasTarget: verbalKillHasTarget,
                      onKill: verbalKillHasTarget
                          ? () => ref
                              .read(mapSessionProvider(widget.sessionId)
                                  .notifier)
                              .sendKillAction(mapState.proximateTargetId!)
                          : () => ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      '근처에 대상이 없습니다. 상대방에게 더 가까이 이동하세요.'),
                                  duration: Duration(seconds: 2),
                                ),
                              ),
                    ),
                  ),
                ),
              if (widget.sessionType == SessionType.chase)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: chaseButtonBottom,
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: canUseChaseAction
                            ? () => ref
                                .read(mapSessionProvider(widget.sessionId)
                                    .notifier)
                                .sendKillAction(mapState.proximateTargetId!)
                            : null,
                        style: ElevatedButton.styleFrom(
                            backgroundColor:
                                canUseChaseAction ? Colors.red : Colors.grey,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18))),
                        icon: Icon(activeModules.contains('tag')
                            ? Icons.touch_app_rounded
                            : Icons.gps_fixed_rounded),
                        label: Text(activeModules.contains('tag') ? '태그' : '킬',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                    ),
                  ),
                ),
              if (widget.isGhostMode)
                Positioned.fill(
                  child: AbsorbPointer(
                    absorbing: true,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.18),
                      alignment: Alignment.topCenter,
                      padding: const EdgeInsets.only(top: 76),
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(16)),
                          child: const Text('사망 - 유령으로 관전 중',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700))),
                    ),
                  ),
                ),
              if (_isMemberPanelExpanded)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: MapBottomMemberPanel(
                    members: mapState.members.values.toList(),
                    myPosition: myPosition,
                    hiddenMembers: mapState.hiddenMembers,
                    eliminatedUserIds: mapState.eliminatedUserIds,
                    onSOS: widget.isGhostMode
                        ? () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('유령 상태에서는 SOS를 사용할 수 없습니다.')))
                        : () => ref
                            .read(mapSessionProvider(widget.sessionId).notifier)
                            .triggerSOS(),
                    onMemberTap: (member) {
                      if (member.lat == 0 && member.lng == 0) return;
                      setState(() => _followMe = false);
                      _mapController?.updateCamera(
                          NCameraUpdate.scrollAndZoomTo(
                              target: NLatLng(member.lat, member.lng), zoom: 15)
                            ..setAnimation(animation: NCameraAnimation.easing));
                    },
                    onHideToggle: (userId) => ref
                        .read(mapSessionProvider(widget.sessionId).notifier)
                        .toggleHideMember(userId),
                  ),
                )
              else
                Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16 + bottomPadding,
                    child: _MapMemberPanelToggle(
                        memberCount: memberCount,
                        onTap: () =>
                            setState(() => _isMemberPanelExpanded = true))),
              if (_isMemberPanelExpanded)
                Positioned(
                  right: 16,
                  bottom: memberPanelReserve - 8,
                  child: SafeArea(
                    top: false,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _isMemberPanelExpanded = false),
                      style: TextButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.62),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999))),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      label: const Text('멤버 숨기기',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── [Task 3] 거리 기반 마커 클러스터링 ──────────────────────────────────────
  //
  // 알고리즘 개요 (Greedy Single-Pass Clustering):
  //   1. 유효 멤버를 순회하면서, 아직 어떤 클러스터에도 속하지 않은 멤버를
  //      기준점(anchor)으로 삼아 새 클러스터를 생성합니다.
  //   2. 나머지 미할당 멤버 중 anchor와 위·경도 차이가 모두
  //      _kClusterThreshDeg(≈5 m) 이내이면 같은 클러스터에 묶습니다.
  //   3. 클러스터 크기 == 1 → 기존 개별 마커 로직 유지
  //      클러스터 크기 >= 2 → 보라색 클러스터 마커(👥 N명) 렌더링
  //   4. 클러스터에 '나'가 포함되면 캡션에 "(나 포함)" 을 추가합니다.
  //
  // 마커 ID 전략:
  //   - 개별: userId 그대로 사용
  //   - 클러스터: "cluster_<정렬된 userId 첫 번째>" → 동일 그룹이면 같은 ID 유지

  /// 약 5 m 에 해당하는 위·경도 차이 (1° ≈ 111,111 m)
  static const double _kClusterThreshDeg = 0.000045;

  void _syncMarkers(
    Map<String, MemberState> members,
    String? myUserId,
    bool sharingEnabled,
    Set<String> hiddenMembers,
    Set<String> eliminatedUserIds,
  ) {
    if (_mapController == null) return;

    // ── 1. 유효 멤버 필터링 ──────────────────────────────────────────────────
    final validMembers = members.values.where((m) {
      if (m.lat == 0 && m.lng == 0) return false;
      if (m.userId == myUserId && !sharingEnabled) return false;
      if (hiddenMembers.contains(m.userId)) return false;
      return true;
    }).toList();

    // '나'를 앞에 배치하여 클러스터 anchor로 우선 선택되게 합니다
    validMembers.sort((a, b) {
      if (a.userId == myUserId) return -1;
      if (b.userId == myUserId) return 1;
      return 0;
    });

    // ── 2. Greedy 클러스터링 ─────────────────────────────────────────────────
    final Set<String> assigned = {};
    final List<List<MemberState>> clusters = [];

    for (final anchor in validMembers) {
      if (assigned.contains(anchor.userId)) continue;

      final cluster = <MemberState>[anchor];
      assigned.add(anchor.userId);

      for (final other in validMembers) {
        if (assigned.contains(other.userId)) continue;
        final dLat = (anchor.lat - other.lat).abs();
        final dLng = (anchor.lng - other.lng).abs();
        if (dLat < _kClusterThreshDeg && dLng < _kClusterThreshDeg) {
          cluster.add(other);
          assigned.add(other.userId);
        }
      }
      clusters.add(cluster);
    }

    // ── 3. 마커 ID 맵 구성 ───────────────────────────────────────────────────
    // key: 마커 ID,  value: 해당 클러스터의 멤버 목록
    final Map<String, List<MemberState>> markerMap = {};
    for (final cluster in clusters) {
      if (cluster.length == 1) {
        markerMap[cluster.first.userId] = cluster;
      } else {
        // 클러스터 ID = "cluster_" + 정렬된 userId 중 첫 번째
        final sortedIds = cluster.map((m) => m.userId).toList()..sort();
        markerMap['cluster_${sortedIds.first}'] = cluster;
      }
    }

    // ── 4. 사라진 마커 제거 ──────────────────────────────────────────────────
    final newMarkerIds = markerMap.keys.toSet();
    final toRemove =
        _activeMarkers.keys.where((id) => !newMarkerIds.contains(id)).toList();
    for (final id in toRemove) {
      final marker = _activeMarkers.remove(id);
      if (marker != null) _mapController!.deleteOverlay(marker.info);
    }

    // ── 5. 마커 추가 / 업데이트 ─────────────────────────────────────────────
    for (final entry in markerMap.entries) {
      final markerId = entry.key;
      final clusterMembers = entry.value;

      if (clusterMembers.length == 1) {
        // ── 개별 마커 (기존 로직) ────────────────────────────────────────────
        final m = clusterMembers.first;
        final isMe = m.userId == myUserId;
        final isEliminated = eliminatedUserIds.contains(m.userId);

        final pinColor = isEliminated
            ? Colors.grey
            : (isMe ? const Color(0xFF2196F3) : Colors.redAccent);
        final captionColor = isEliminated
            ? Colors.grey
            : (isMe ? const Color(0xFF2196F3) : Colors.black87);
        final captionText = isEliminated
            ? 'X ${m.nickname}'
            : (isMe ? '${m.nickname} (나)' : m.nickname);
        final subCaptionText = isEliminated ? '탈락' : _markerSnippet(m);
        final pos = NLatLng(m.lat, m.lng);
        final caption = NOverlayCaption(
            text: captionText,
            textSize: 14,
            color: captionColor,
            haloColor: Colors.white);
        final subCaption = NOverlayCaption(
            text: subCaptionText,
            textSize: 12,
            color: isEliminated ? Colors.grey : Colors.grey.shade700,
            haloColor: Colors.white);

        if (_activeMarkers.containsKey(markerId)) {
          final marker = _activeMarkers[markerId]!;
          marker.setPosition(pos);
          marker.setIconTintColor(pinColor);
          marker.setCaption(caption);
          marker.setSubCaption(subCaption);
        } else {
          final marker = NMarker(id: markerId, position: pos)
            ..setIconTintColor(pinColor)
            ..setCaption(caption)
            ..setSubCaption(subCaption);
          _activeMarkers[markerId] = marker;
          _mapController!.addOverlay(marker);
        }
      } else {
        // ── 클러스터 마커 ────────────────────────────────────────────────────
        final count = clusterMembers.length;
        final hasMe = clusterMembers.any((m) => m.userId == myUserId);

        // 클러스터 중심: 멤버 좌표 평균
        final avgLat =
            clusterMembers.map((m) => m.lat).reduce((a, b) => a + b) / count;
        final avgLng =
            clusterMembers.map((m) => m.lng).reduce((a, b) => a + b) / count;
        final pos = NLatLng(avgLat, avgLng);

        // '나'가 포함된 클러스터는 캡션으로 명시
        final captionText = hasMe ? '👥 $count명 (나 포함)' : '👥 $count명';
        // 서브캡션: 멤버 닉네임 나열
        final nicknames = clusterMembers.map((m) => m.nickname).join(', ');

        const pinColor = Colors.purple;
        final caption = NOverlayCaption(
            text: captionText,
            textSize: 14,
            color: Colors.purple,
            haloColor: Colors.white);
        final subCaption = NOverlayCaption(
            text: nicknames,
            textSize: 11,
            color: Colors.grey.shade700,
            haloColor: Colors.white);

        if (_activeMarkers.containsKey(markerId)) {
          final marker = _activeMarkers[markerId]!;
          marker.setPosition(pos);
          marker.setIconTintColor(pinColor);
          marker.setCaption(caption);
          marker.setSubCaption(subCaption);
        } else {
          final marker = NMarker(id: markerId, position: pos)
            ..setIconTintColor(pinColor)
            ..setCaption(caption)
            ..setSubCaption(subCaption);
          _activeMarkers[markerId] = marker;
          _mapController!.addOverlay(marker);
        }
      }
    }
  }
  // ─────────────────────────────────────────────────────────────────────────────

  String _markerSnippet(MemberState member) {
    final parts = <String>[member.status == 'moving' ? '이동중' : '대기'];
    if (member.battery != null) parts.add('배터리 ${member.battery}%');
    return parts.join(' • ');
  }

  void _fitAllMembers(Map<String, MemberState> members, Position? myPosition) {
    if (_mapController == null) return;
    setState(() => _followMe = false);
    final points = <NLatLng>[
      if (myPosition != null)
        NLatLng(myPosition.latitude, myPosition.longitude),
      ...members.values
          .where((member) => member.lat != 0 || member.lng != 0)
          .map((member) => NLatLng(member.lat, member.lng)),
    ];
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController!.updateCamera(
          NCameraUpdate.scrollAndZoomTo(target: points.first, zoom: 15)
            ..setAnimation(animation: NCameraAnimation.easing));
      return;
    }
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    final bounds = NLatLngBounds(
        southWest: NLatLng(minLat, minLng), northEast: NLatLng(maxLat, maxLng));
    _mapController!.updateCamera(
        NCameraUpdate.fitBounds(bounds, padding: const EdgeInsets.all(80))
          ..setAnimation(animation: NCameraAnimation.easing));
  }
}
