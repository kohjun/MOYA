// Color Chaser — Phase 3~6 게임 화면.
// 본인 색/타겟 색 카드 + 거점 미션 + nearby 멤버 태그 + 힌트 + 종료 화면.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/router/app_router.dart';
import '../../../../../core/services/socket_service.dart';
import '../../../../auth/data/auth_repository.dart';
import '../../../../map/data/map_session_provider.dart';
import '../../../../map/presentation/map_session_models.dart';
import 'color_chaser_models.dart';
import 'color_chaser_provider.dart';
import 'widgets/cc_body_profile_dialog.dart';
import 'widgets/cc_game_over_dialog.dart';
import 'widgets/cc_mission_dialog.dart';
import 'widgets/cc_static_map_view.dart';

class ColorChaserGameScreen extends ConsumerStatefulWidget {
  const ColorChaserGameScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ColorChaserGameScreen> createState() =>
      _ColorChaserGameScreenState();
}

class _ColorChaserGameScreenState extends ConsumerState<ColorChaserGameScreen> {
  // tag range는 서버 config 와 일치 (Phase 3 default = 5m).
  // 클라이언트는 약간 더 넓은 30m 까지 노출해 "근접 후보"로 보여준다.
  static const double _tagRangeMeters = 5.0;
  static const double _showRangeMeters = 30.0;

  bool _tagInProgress = false;
  bool _missionInProgress = false;
  bool _bodyProfileDialogOpen = false;
  bool _gameOverDialogOpen = false;
  Timer? _clockTicker;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;
  StreamSubscription<CcCpLifecycleEvent>? _cpEventSub;

  @override
  void initState() {
    super.initState();
    final socket = SocketService();
    if (socket.isConnected) {
      socket.joinSession(widget.sessionId);
      socket.requestGameState(widget.sessionId);
    }
    // 1초 ticker — 남은 시간 카운트다운 + 쿨다운 표시 갱신.
    _clockTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _nowMs = DateTime.now().millisecondsSinceEpoch);
    });

    // 거점 lifecycle SnackBar 알림.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cpEventSub = ref
          .read(colorChaserProvider(widget.sessionId).notifier)
          .cpEvents
          .listen(_onCpEvent);
    });
  }

  void _onCpEvent(CcCpLifecycleEvent e) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (e.kind) {
      case 'activated':
        messenger.showSnackBar(SnackBar(
          content: Text('${e.displayName ?? "전화부스"} 활성! 먼저 도착하세요.'),
          backgroundColor: Colors.cyan.shade700,
          duration: const Duration(seconds: 3),
        ));
        break;
      case 'claimed':
        final isMe = e.claimedBy != null &&
            e.claimedBy == ref.read(authProvider).valueOrNull?.id;
        messenger.showSnackBar(SnackBar(
          content: Text(isMe
              ? '전화부스 선점! 단서를 획득했습니다.'
              : '다른 플레이어가 전화부스를 선점했습니다.'),
          backgroundColor: isMe ? Colors.green.shade700 : Colors.grey.shade800,
        ));
        break;
      case 'expired':
        messenger.showSnackBar(const SnackBar(
          content: Text('전화부스가 만료되었습니다.'),
        ));
        break;
    }
  }

  @override
  void dispose() {
    _clockTicker?.cancel();
    _cpEventSub?.cancel();
    super.dispose();
  }

  Color _parseHex(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.grey;
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return Colors.grey;
    return Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(colorChaserProvider(widget.sessionId));
    final mapState = ref.watch(mapSessionProvider(widget.sessionId));
    final myId = ref.watch(authProvider).valueOrNull?.id;
    final my = state.myState;

    final myColor = _parseHex(my.colorHex);
    final targetColor = _parseHex(my.targetColorHex);

    // 신체정보 미입력 시 force-modal (게임 진행 중 + 본인 살아있음 + attribute 정의 도착)
    if (state.status == 'in_progress' &&
        my.isAlive &&
        !my.bodyProfileComplete &&
        state.bodyAttributes.isNotEmpty &&
        !_bodyProfileDialogOpen) {
      _bodyProfileDialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showBodyProfileDialog(state);
      });
    }

    // 게임 종료 — 다이얼로그 1회 노출.
    if (state.status == 'finished' &&
        state.winCondition != null &&
        !_gameOverDialogOpen) {
      _gameOverDialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showGameOverDialog(state, myId);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('컬러 체이서'),
          actions: [
            _buildClock(state),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref
                  .read(colorChaserProvider(widget.sessionId).notifier)
                  .refreshState(),
            ),
          ],
        ),
        body: !my.hasIdentity
            ? _buildLoading()
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!my.isAlive) _buildDeadBanner(),
                      _buildMapCard(state, mapState),
                      const SizedBox(height: 12),
                      _buildIdentityCard(
                        title: '내 색깔',
                        colorLabel: my.colorLabel ?? '?',
                        color: myColor,
                      ),
                      const SizedBox(height: 12),
                      _buildIdentityCard(
                        title: '내 타겟',
                        colorLabel: my.targetColorLabel ?? '?',
                        color: targetColor,
                        subtitle: '이 색을 가진 사람을 찾아 잡으세요',
                      ),
                      const SizedBox(height: 16),
                      _buildAliveStatus(state),
                      const SizedBox(height: 16),
                      _buildHintsSection(state),
                      const SizedBox(height: 16),
                      _buildControlPointsSection(state, mapState),
                      const SizedBox(height: 16),
                      _buildNearbySection(
                        mapState: mapState,
                        myId: myId,
                        ccState: state,
                      ),
                      const SizedBox(height: 16),
                      _buildRecentTags(state),
                      const SizedBox(height: 16),
                      _buildWarning(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text(
            '게임 정보를 불러오는 중...',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildDeadBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent),
      ),
      child: const Row(
        children: [
          Icon(Icons.dangerous, color: Colors.redAccent),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '탈락했습니다. 게임은 계속 진행됩니다.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard({
    required String title,
    required String colorLabel,
    required Color color,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 16,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  colorLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAliveStatus(ColorChaserGameState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(
                '생존자 ${state.aliveCount} / ${state.palette.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: state.colorCounts.map((cc) {
              final c = _parseHex(cc.colorHex);
              final dead = cc.aliveCount == 0;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: dead
                      ? Colors.white.withValues(alpha: 0.04)
                      : c.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: dead ? Colors.white24 : c,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: dead ? Colors.white24 : c,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      cc.colorLabel,
                      style: TextStyle(
                        color: dead ? Colors.white38 : Colors.white,
                        fontSize: 12,
                        decoration:
                            dead ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNearbySection({
    required MapSessionState mapState,
    required String? myId,
    required ColorChaserGameState ccState,
  }) {
    if (myId == null || !ccState.myState.isAlive) {
      return const SizedBox.shrink();
    }

    // 살아있고 거리가 있는 다른 멤버만 노출.
    // 거리 정보가 없으면 노출하지 않음 (GPS 미공유 등).
    final entries = mapState.members.entries
        .where((e) => e.key != myId)
        .where((e) => !ccState.eliminatedPlayerIds.contains(e.key))
        .map((e) {
          final dist = mapState.memberDistances[e.key];
          return _NearbyEntry(member: e.value, distance: dist);
        })
        .where((entry) => entry.distance != null && entry.distance! <= _showRangeMeters)
        .toList()
      ..sort((a, b) => (a.distance ?? double.infinity)
          .compareTo(b.distance ?? double.infinity));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.gps_fixed, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text(
                '근처 플레이어',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 8),
              Text(
                '(30m 이내)',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '근처에 다른 플레이어가 없습니다',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            )
          else
            ...entries.map((e) => _buildNearbyTile(e)),
        ],
      ),
    );
  }

  Widget _buildNearbyTile(_NearbyEntry entry) {
    final dist = entry.distance ?? double.infinity;
    final inRange = dist <= _tagRangeMeters;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.member.nickname,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${dist.toStringAsFixed(1)}m',
                  style: TextStyle(
                    color: inRange ? Colors.greenAccent : Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: (inRange && !_tagInProgress)
                ? () => _confirmAndTag(entry.member)
                : null,
            icon: const Icon(Icons.flash_on, size: 16),
            label: const Text('잡기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: inRange ? Colors.redAccent : Colors.grey.shade800,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade900,
              disabledForegroundColor: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapCard(ColorChaserGameState state, MapSessionState mapState) {
    if (state.playableArea.length < 3) {
      return const SizedBox.shrink();
    }
    final centroid = polygonCentroid(state.playableArea);
    if (centroid == null) return const SizedBox.shrink();

    final radius = polygonBoundingRadiusMeters(
      state.playableArea,
      centroid.lat,
      centroid.lng,
    );
    final zoom = recommendedZoomForRadius(radius);

    final myPos = mapState.myPosition;
    final activeId = state.activeControlPointId;
    final activeCp = activeId == null
        ? null
        : state.controlPoints.firstWhere(
            (cp) => cp.id == activeId && cp.location != null,
            orElse: () => state.controlPoints.first,
          );

    final width = MediaQuery.of(context).size.width - 32;
    return CcStaticMapView(
      centerLat: centroid.lat,
      centerLng: centroid.lng,
      zoom: zoom,
      width: width,
      height: 200,
      myLat: myPos?.latitude,
      myLng: myPos?.longitude,
      myColorHex: state.myState.colorHex,
      activeCp: activeCp?.location != null ? activeCp : null,
      playableArea: state.playableArea,
    );
  }

  Widget _buildClock(ColorChaserGameState state) {
    if (state.status != 'in_progress' || state.startedAt == null) {
      return const SizedBox.shrink();
    }
    final endsAt = state.startedAt! + state.timeLimitSec * 1000;
    final remaining = (endsAt - _nowMs).clamp(0, state.timeLimitSec * 1000);
    final mm = (remaining ~/ 60000).toString().padLeft(2, '0');
    final ss = ((remaining % 60000) ~/ 1000).toString().padLeft(2, '0');
    final critical = remaining <= 60000;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: critical
                ? Colors.red.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$mm:$ss',
            style: TextStyle(
              color: critical ? Colors.redAccent : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showGameOverDialog(
    ColorChaserGameState state,
    String? myId,
  ) async {
    final win = state.winCondition;
    if (win == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: CcGameOverDialog(
          win: win,
          scoreboard: state.scoreboard,
          myUserId: myId,
          onLeave: () {
            Navigator.of(ctx).pop();
            if (mounted) context.go(AppRoutes.home);
          },
        ),
      ),
    );
  }

  Future<void> _showBodyProfileDialog(ColorChaserGameState state) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: CcBodyProfileDialog(
          attributes: state.bodyAttributes,
          initial: state.myState.bodyProfile,
          onSubmit: (profile) => ref
              .read(colorChaserProvider(widget.sessionId).notifier)
              .setBodyProfile(profile),
        ),
      ),
    );
    if (!mounted) return;
    _bodyProfileDialogOpen = false;
    final ok = result?['ok'] as bool? ?? false;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('신체정보 저장 완료'),
          backgroundColor: Colors.cyan,
        ),
      );
    }
  }

  Widget _buildHintsSection(ColorChaserGameState state) {
    final hints = state.myState.unlockedHints;
    final candidates = state.myState.candidates;
    if (hints.isEmpty && candidates.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology, color: Colors.purpleAccent, size: 18),
              const SizedBox(width: 8),
              const Text(
                '타겟 단서',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '후보 ${candidates.length}명',
                style: TextStyle(
                  color: candidates.length <= 2
                      ? Colors.amberAccent
                      : Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hints.isEmpty)
            const Text(
              '아직 공개된 단서가 없습니다. 거점에서 미션을 성공시키세요.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            )
          else
            ...hints.map((h) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Colors.purpleAccent, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                            children: [
                              TextSpan(text: '${h.attributeLabel}: '),
                              TextSpan(
                                text: h.optionLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.amberAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          if (candidates.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              '가능한 타겟',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: candidates
                  .map((c) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white24, width: 1),
                        ),
                        child: Text(
                          c.nickname,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildControlPointsSection(
    ColorChaserGameState state,
    MapSessionState mapState,
  ) {
    if (state.controlPoints.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.white38, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '이 게임에는 거점이 없습니다 (호스트가 플레이 영역을 그리지 않음).',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    final activeId = state.activeControlPointId;
    final activeCp = activeId == null
        ? null
        : state.controlPoints.firstWhere(
            (cp) => cp.id == activeId,
            orElse: () => state.controlPoints.first,
          );
    final inactiveCount =
        state.controlPoints.where((cp) => cp.status == 'inactive').length;
    final claimedCount =
        state.controlPoints.where((cp) => cp.status == 'claimed').length;

    if (activeCp != null && activeCp.location != null) {
      return _buildActiveCpCard(activeCp, state, mapState);
    }
    return _buildWaitingCpCard(state, inactiveCount, claimedCount);
  }

  Widget _buildActiveCpCard(
    CcControlPoint cp,
    ColorChaserGameState state,
    MapSessionState mapState,
  ) {
    final myPos = mapState.myPosition;
    final dist = (myPos == null || cp.location == null)
        ? null
        : _haversineMeters(
            myPos.latitude,
            myPos.longitude,
            cp.location!.lat,
            cp.location!.lng,
          );
    final bearing = (myPos == null || cp.location == null)
        ? null
        : _bearingDeg(
            myPos.latitude,
            myPos.longitude,
            cp.location!.lat,
            cp.location!.lng,
          );

    final radius = state.controlPointRadiusMeters;
    final inRange = dist != null && dist <= radius;
    final hasActiveMission = state.myState.activeMission != null;
    final canStart =
        inRange && !hasActiveMission && state.myState.isAlive && !_missionInProgress;

    final remainingMs = (cp.expiresAt ?? 0) - _nowMs;
    final remainingSec = (remainingMs / 1000).clamp(0, 99999).floor();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.cyan.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_phone, color: Colors.cyanAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${cp.displayName} 활성!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${remainingSec}s',
                style: TextStyle(
                  color: remainingSec <= 10
                      ? Colors.redAccent
                      : Colors.cyanAccent,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            dist == null
                ? '본인 위치 확인 중...'
                : (bearing == null
                    ? '${dist.toStringAsFixed(0)}m'
                    : '${_directionLabel(bearing)} · ${dist.toStringAsFixed(0)}m'),
            style: TextStyle(
              color: inRange ? Colors.greenAccent : Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  inRange
                      ? '진입 OK — 먼저 도착한 사람만 단서를 얻습니다.'
                      : '${radius.toInt()}m 이내로 접근하세요.',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
              ElevatedButton.icon(
                onPressed: canStart ? () => _startMissionAt(cp.id) : null,
                icon: const Icon(Icons.bolt, size: 16),
                label: const Text('미션'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      canStart ? Colors.cyan.shade700 : Colors.grey.shade800,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade900,
                  disabledForegroundColor: Colors.white38,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingCpCard(
    ColorChaserGameState state,
    int inactiveCount,
    int claimedCount,
  ) {
    final nextAt = state.nextActivationAt;
    final remainingMs = nextAt == null ? null : (nextAt - _nowMs);
    final remainingSec =
        remainingMs == null ? null : (remainingMs / 1000).clamp(0, 99999).floor();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_empty, color: Colors.white54, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '다음 전화부스 대기 중',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '획득 ${claimedCount} · 남은 거점 ${inactiveCount}'
                  '${remainingSec != null && remainingSec > 0 ? " · 다음 ${remainingSec}s" : ""}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startMissionAt(String cpId) async {
    setState(() => _missionInProgress = true);
    try {
      final ack = await ref
          .read(colorChaserProvider(widget.sessionId).notifier)
          .startMission(cpId);
      if (!mounted) return;

      final ok = ack['ok'] as bool? ?? false;
      if (!ok) {
        final err = ack['error'] as String? ?? 'UNKNOWN';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_translateMissionError(err, ack))),
        );
        return;
      }

      final word = ack['word'] as String? ?? '';
      final expiresAt = (ack['expiresAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch + 15000;

      // 다이얼로그 표시 → 결과로 처리
      final result = await showDialog<Map<String, dynamic>?>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => CcMissionDialog(
          word: word,
          expiresAt: expiresAt,
          onSubmit: (answer) => ref
              .read(colorChaserProvider(widget.sessionId).notifier)
              .submitMission(answer),
        ),
      );

      if (!mounted) return;
      _showMissionResult(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('미션 시작 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _missionInProgress = false);
    }
  }

  void _showMissionResult(Map<String, dynamic>? ack) {
    if (ack == null) {
      // 사용자 포기 — 서버 activeMission 은 timeout 으로 자동 정리됨.
      return;
    }
    final ok = ack['ok'] as bool? ?? false;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('미션 제출 실패: ${ack['error']}')),
      );
      return;
    }
    final success = ack['success'] as bool? ?? false;
    if (success) {
      final n = (ack['missionsCompleted'] as num?)?.toInt() ?? 0;
      final hintMap = ack['hint'] as Map?;
      String message = '미션 성공! 누적 $n회';
      if (hintMap != null) {
        final attrLabel = hintMap['attributeLabel'] as String? ?? '';
        final optLabel = hintMap['optionLabel'] as String? ?? '';
        final left = (hintMap['candidateCountAfter'] as num?)?.toInt() ?? 0;
        message = '단서 획득 → $attrLabel: $optLabel (후보 $left명)';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      final reason = ack['reason'] as String? ?? 'WRONG_ANSWER';
      final msg = reason == 'TIMEOUT'
          ? '시간 초과'
          : (reason == 'ALREADY_CLAIMED' ? '한발 늦었습니다 (선점됨)' : '오답');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('미션 실패: $msg')),
      );
    }
  }

  String _translateMissionError(String code, Map<String, dynamic> ack) {
    switch (code) {
      case 'OUT_OF_RANGE':
        final d = ack['distanceMeters'];
        final r = ack['radiusMeters'];
        return '거리 초과 (${d}m / ${r}m)';
      case 'CONTROL_POINT_NOT_ACTIVE':
        final s = ack['status'];
        return s == 'claimed'
            ? '이미 다른 사람이 선점했습니다'
            : (s == 'expired' ? '거점이 만료되었습니다' : '활성 상태가 아닙니다');
      case 'CONTROL_POINT_EXPIRED':
        return '거점이 만료되었습니다';
      case 'MISSION_ALREADY_ACTIVE':
        return '이미 진행 중인 미션이 있습니다';
      case 'LOCATION_STALE':
        return 'GPS 정보가 오래되어 진입 판정 불가';
      case 'LOCATION_UNAVAILABLE':
        return '위치 정보 없음';
      case 'PLAYER_DEAD':
        return '탈락 상태에서는 미션 불가';
      default:
        return '미션 시작 실패: $code';
    }
  }

  static double _haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  // 두 지점 사이 방위각 (0=북, 90=동, 180=남, 270=서).
  static double _bearingDeg(
      double lat1, double lng1, double lat2, double lng2) {
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dLng);
    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

  static String _directionLabel(double bearing) {
    const labels = ['북', '북동', '동', '남동', '남', '남서', '서', '북서'];
    final idx = ((bearing + 22.5) % 360 ~/ 45);
    return '${labels[idx]}쪽';
  }

  Widget _buildRecentTags(ColorChaserGameState state) {
    if (state.recentTags.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '최근 처치',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ...state.recentTags.take(5).map((e) {
            final label = e.eliminatedColorLabel ?? '?';
            final isWrong = e.reason == 'wrong_tag';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    isWrong ? Icons.warning : Icons.flash_on,
                    color: isWrong ? Colors.amber : Colors.greenAccent,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isWrong
                          ? '$label (자기 색 잘못 잡고 사망)'
                          : '$label 탈락',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildWarning() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.amberAccent, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '잘못된 사람을 잡으면 본인이 사망합니다. 신중하게 판단하세요.',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndTag(MemberState member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('처치 시도', style: TextStyle(color: Colors.white)),
        content: Text(
          '${member.nickname}을(를) 잡습니다.\n\n'
          '⚠️ 내 타겟 색이 아니면 본인이 사망합니다.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('잡기',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _tagInProgress = true);
    try {
      final ack = await ref
          .read(colorChaserProvider(widget.sessionId).notifier)
          .tagTarget(member.userId);
      if (!mounted) return;
      _showTagFeedback(ack);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('처치 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _tagInProgress = false);
    }
  }

  void _showTagFeedback(Map<String, dynamic> ack) {
    final ok = ack['ok'] as bool? ?? false;
    if (!ok) {
      final err = ack['error'] as String? ?? 'UNKNOWN';
      final dist = (ack['distanceMeters'] as num?)?.toInt();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_translateError(err, dist)),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }
    final success = ack['success'] as bool? ?? false;
    final color = ack['eliminatedColorLabel'] as String? ?? '?';
    final reason = ack['reason'] as String?;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$color 탈락! 새 타겟이 갱신되었습니다.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } else if (reason == 'wrong_tag') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('잘못된 타겟! 본인($color)이 탈락했습니다.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  String _translateError(String code, int? dist) {
    switch (code) {
      case 'OUT_OF_RANGE':
        return '거리 초과 (${dist ?? '?'}m). 5m 이내로 접근하세요.';
      case 'LOCATION_STALE':
        return 'GPS 정보가 오래되어 판정 불가';
      case 'LOCATION_INACCURATE':
        return 'GPS 정확도가 낮아 판정 불가';
      case 'LOCATION_UNAVAILABLE':
        return '상대 또는 본인 위치를 알 수 없습니다';
      case 'TARGET_ALREADY_DEAD':
        return '이미 탈락한 플레이어입니다';
      case 'ATTACKER_DEAD':
        return '탈락 상태에서는 처치할 수 없습니다';
      case 'GAME_NOT_IN_PROGRESS':
        return '게임이 진행 중이 아닙니다';
      default:
        return '처치 실패: $code';
    }
  }

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title:
            const Text('게임 나가기', style: TextStyle(color: Colors.white)),
        content: const Text(
          '게임에서 나가면 자동 탈락 처리됩니다. 계속하시겠어요?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('나가기',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.go(AppRoutes.home);
    }
  }
}

class _NearbyEntry {
  const _NearbyEntry({required this.member, required this.distance});

  final MemberState member;
  final double? distance;
}

