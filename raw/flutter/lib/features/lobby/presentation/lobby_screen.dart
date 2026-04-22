// lib/features/lobby/presentation/lobby_screen.dart

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/mediasoup_audio_service.dart';
import '../../../core/services/socket_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../game/presentation/playable_area_painter_screen.dart';
import '../../home/data/session_repository.dart';
import '../providers/lobby_provider.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({
    super.key,
    required this.sessionId,
    required this.sessionType,
  });

  final String sessionId;
  final SessionType sessionType;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  Timer? _countdownTimer;
  String _countdownText = '--:--:--';
  bool _startingGame = false;
  bool _didNavigateToMap = false;
  bool _playableAreaSet = false; // 이번 세션에서 영역을 설정했는지 로컬 추적
  bool _voicePrompted = false; // 로비 진입 보이스 Dialog 1회성
  bool _micPublished = false;
  StreamSubscription? _kickedSub;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _voicePrompted) return;
      _voicePrompted = true;
      unawaited(_promptLobbyVoice());
    });

    _kickedSub = SocketService().onKicked.listen((_) async {
      await _releaseRealtimeResources(notifyServer: false);
      if (!mounted) return;

      try {
        await ref.read(sessionListProvider.notifier).refresh();
      } catch (e) {
        debugPrint('[Lobby] Failed to refresh sessions after kick: $e');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('세션에서 강제 퇴장되었습니다.'),
          backgroundColor: Colors.red,
        ),
      );
      context.go('/');
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _kickedSub?.cancel();
    super.dispose();
  }

  void _updateCountdown() {
    if (!mounted) return;
    final lobbyState = ref.read(lobbyProvider(widget.sessionId));
    final expiresAt = lobbyState.sessionInfo?.expiresAt;
    if (expiresAt == null) return;

    final diff = expiresAt.difference(DateTime.now());
    setState(() {
      if (diff.isNegative) {
        _countdownText = '00:00:00';
      } else {
        final h = diff.inHours.toString().padLeft(2, '0');
        final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
        final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
        _countdownText = '$h:$m:$s';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lobbyState = ref.watch(lobbyProvider(widget.sessionId));
    final authUser = ref.watch(authProvider).valueOrNull;

    if (lobbyState.isGameStarted && !_didNavigateToMap) {
      _didNavigateToMap = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/game/${widget.sessionId}?type=${widget.sessionType.name}');
        }
      });
    }

    final session = lobbyState.sessionInfo;
    final members = lobbyState.members;
    final myUserId = authUser?.id ?? '';
    final isHost = (session?.isHost ?? false) ||
        members.any(
          (member) =>
              member.userId == myUserId &&
              (member.isHost || member.role == 'host'),
        );

    final minPlayers = widget.sessionType.minPlayers;
    final currentCount = members.length;
    final hasPlayableArea =
        _playableAreaSet || (session?.playableArea?.length ?? 0) >= 3;
    final canStart = currentCount >= minPlayers && hasPlayableArea;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmLeave(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('대기실'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _confirmLeave(context),
          ),
          actions: [
            _AppBarMicToggle(
              sessionId: widget.sessionId,
              micPublished: _micPublished,
              onRequestPublish: () async {
                final status = await Permission.microphone.request();
                if (!status.isGranted) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('마이크 권한이 필요합니다.')),
                  );
                  return;
                }
                try {
                  await MediaSoupAudioService().publishMic();
                  if (mounted) setState(() => _micPublished = true);
                } catch (e) {
                  debugPrint('[Lobby] publishMic failed: $e');
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              tooltip: '세션 나가기',
              onPressed: () => _confirmLeave(context),
            ),
          ],
        ),
        body: lobbyState.isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () =>
                    ref.read(lobbyProvider(widget.sessionId).notifier).refresh(),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SessionInfoSection(
                        session: session,
                        countdownText: _countdownText,
                        sessionType: widget.sessionType,
                      ),
                      const SizedBox(height: 20),
                      _ParticipantListSection(
                        members: members,
                        myUserId: myUserId,
                        isHost: isHost,
                        sessionId: widget.sessionId,
                        speakingUserIds: lobbyState.speakingUserIds,
                      ),
                      const SizedBox(height: 24),
                      if (!lobbyState.isGameStarted) ...[
                        _AudioCheckSection(sessionId: widget.sessionId),
                        const SizedBox(height: 20),
                      ],
                      if (isHost) ...[
                        // ── 플레이 영역 설정 버튼 ────────────────────────────
                        // ── 플레이 영역 설정 버튼 ───────────────────────────
                        OutlinedButton(
                          onPressed: () async {
                            final result = await Navigator.push<dynamic>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PlayableAreaPainterScreen(
                                  sessionId: widget.sessionId,
                                ),
                              ),
                            );
                            if (result != null && mounted) {
                              setState(() => _playableAreaSet = true);
                              // 서버 최신 상태 반영
                              unawaited(ref
                                  .read(lobbyProvider(widget.sessionId).notifier)
                                  .refresh());
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('플레이 영역이 설정되었습니다.'),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(
                              color: hasPlayableArea
                                  ? Colors.green
                                  : Colors.orange,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                hasPlayableArea
                                    ? '플레이 영역 재설정'
                                    : '플레이 영역 설정 (필수)',
                                style: TextStyle(
                                  color: hasPlayableArea
                                      ? Colors.green
                                      : Colors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (!hasPlayableArea) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    '미설정',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // ── 조건 미충족 안내 문구 ────────────────────────────
                        if (!hasPlayableArea)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '플레이 영역을 먼저 설정해야 게임을 시작할 수 있습니다.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.orange[700],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        if (currentCount < minPlayers)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '최소 $minPlayers명 필요 (현재 $currentCount명)',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        ElevatedButton(
                          onPressed: (canStart && !_startingGame)
                              ? () => _startGame(context)
                              : null,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor:
                                canStart ? Colors.green : Colors.grey,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _startingGame
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  '게임 시작',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '방장이 게임을 시작하길 기다리는 중',
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: session != null
                            ? () => _shareInviteCode(session.code)
                            : null,
                        icon: const Icon(Icons.share),
                        label: const Text('초대 코드 공유'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _startGame(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _startingGame = true);
    try {
      await ref.read(lobbyProvider(widget.sessionId).notifier).startGame();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('게임 시작 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _startingGame = false);
      }
    }
  }

  void _shareInviteCode(String code) {
    Share.share('세션 초대 코드: $code\n앱에서 코드를 입력해 참가하세요!');
  }

  /// 로비 진입 시 마이크 사용 의사를 확인하고 Mediasoup 연결을 초기화.
  /// - 허용: 마이크 권한 요청 → produce + consume
  /// - 거절: consume 전용으로 연결 (듣기만)
  Future<void> _promptLobbyVoice() async {
    final allow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('로비 음성 채팅'),
        content: const Text('마이크를 사용하여 로비 음성 채팅에 참여하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('거절'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('허용'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (allow != true) {
      // 듣기 전용으로만 연결
      try {
        await MediaSoupAudioService()
            .ensureJoined(widget.sessionId, publishMic: false);
      } catch (e) {
        debugPrint('[Lobby] consume-only join failed: $e');
      }
      if (mounted) setState(() => _micPublished = false);
      return;
    }

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('마이크 권한이 거부되어 듣기 전용으로 연결합니다.')),
      );
      try {
        await MediaSoupAudioService()
            .ensureJoined(widget.sessionId, publishMic: false);
      } catch (e) {
        debugPrint('[Lobby] consume-only join failed: $e');
      }
      if (mounted) setState(() => _micPublished = false);
      return;
    }

    try {
      await MediaSoupAudioService()
          .ensureJoined(widget.sessionId, publishMic: true);
      if (mounted) setState(() => _micPublished = true);
    } catch (e) {
      debugPrint('[Lobby] full join failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('음성 서버 연결 실패: $e')),
        );
      }
    }
  }

  Future<void> _releaseRealtimeResources({
    required bool notifyServer,
  }) async {
    try {
      await ref
          .read(lobbyProvider(widget.sessionId).notifier)
          .releaseRealtimeResources(notifyServer: notifyServer);
    } catch (e) {
      debugPrint('[Lobby] Failed to release realtime resources: $e');
    }
  }

  void _confirmLeave(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('세션 나가기'),
        content: const Text('대기실에서 나가시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final messenger = ScaffoldMessenger.of(context);
              final router = GoRouter.of(context);
              try {
                await ref
                    .read(sessionRepositoryProvider)
                    .leaveSession(widget.sessionId);
                await _releaseRealtimeResources(notifyServer: true);
                await ref.read(sessionListProvider.notifier).refresh();
                if (!mounted) return;
                router.go('/');
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('나가기 실패: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
  }
}

class _SessionInfoSection extends StatelessWidget {
  const _SessionInfoSection({
    required this.session,
    required this.countdownText,
    required this.sessionType,
  });

  final Session? session;
  final String countdownText;
  final SessionType sessionType;

  String _sessionTypeLabel() {
    switch (sessionType) {
      case SessionType.defaultType:
        return '기본 위치공유';
      case SessionType.chase:
        return '공간 추격전';
      case SessionType.verbal:
        return '언어 추론';
      case SessionType.location:
        return '위치 탐색';
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = session?.code ?? '------';
    final name = session?.name ?? '로딩 중...';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _sessionTypeLabel(),
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  tooltip: '복사',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('초대 코드가 복사되었습니다'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: Colors.orange,
                ),
                const SizedBox(width: 6),
                Text(
                  '남은 시간: $countdownText',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantListSection extends ConsumerWidget {
  const _ParticipantListSection({
    required this.members,
    required this.myUserId,
    required this.isHost,
    required this.sessionId,
    required this.speakingUserIds,
  });

  final List<SessionMember> members;
  final String myUserId;
  final bool isHost;
  final String sessionId;
  final Set<String> speakingUserIds;

  Color _badgeColor(String role) {
    switch (role) {
      case 'host':
        return const Color(0xFF2196F3);
      case 'admin':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _badgeLabel(String role) {
    switch (role) {
      case 'host':
        return '방장';
      case 'admin':
        return '관리자';
      default:
        return '멤버';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '참가자 목록',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...members.map((member) {
          final isMe = member.userId == myUserId;
          final canManage = isHost && !member.isHost;
          final isSpeaking = speakingUserIds.contains(member.userId) ||
              (isMe && MediaSoupAudioService().isSpeaking);

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _SpeakingDot(isSpeaking: isSpeaking),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${member.nickname}${isMe ? ' (나)' : ''}',
                      style: TextStyle(
                        fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _badgeColor(member.role),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _badgeLabel(member.role),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                  if (canManage) ...[
                    const SizedBox(width: 4),
                    if (member.role != 'admin')
                      IconButton(
                        icon: const Icon(
                          Icons.star_border,
                          size: 18,
                          color: Colors.purple,
                        ),
                        tooltip: '관리자로 승격',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => ref
                            .read(lobbyProvider(sessionId).notifier)
                            .promoteToAdmin(member.userId),
                      ),
                    IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        size: 18,
                        color: Colors.red,
                      ),
                      tooltip: '강퇴',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _confirmKick(context, ref, member),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 4),
        Text(
          '대기 중인 플레이어 ${members.length}명',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      ],
    );
  }

  void _confirmKick(BuildContext context, WidgetRef ref, SessionMember member) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('멤버 강퇴'),
        content: Text('${member.nickname}님을 강퇴하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(lobbyProvider(sessionId).notifier)
                    .kickMember(member.userId);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('강퇴 실패: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('강퇴'),
          ),
        ],
      ),
    );
  }
}

enum _CheckPhase {
  idle,
  checkingPermission,
  checkingServer,
  testingSound,
  done,
  failed,
}

class _AudioCheckSection extends StatefulWidget {
  const _AudioCheckSection({required this.sessionId});

  final String sessionId;

  @override
  State<_AudioCheckSection> createState() => _AudioCheckSectionState();
}

class _AudioCheckSectionState extends State<_AudioCheckSection> {
  _CheckPhase _phase = _CheckPhase.idle;
  String _statusText = '게임 시작 전에 마이크 및 스피커를 미리 점검할 수 있습니다.';
  String? _detailText;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  bool get _isRunning =>
      _phase == _CheckPhase.checkingPermission ||
      _phase == _CheckPhase.checkingServer ||
      _phase == _CheckPhase.testingSound;

  String get _phaseLabel => switch (_phase) {
        _CheckPhase.checkingPermission => '마이크 권한 확인 중',
        _CheckPhase.checkingServer => '미디어 서버 연결 확인 중',
        _CheckPhase.testingSound => '스피커 출력 테스트 중',
        _ => '',
      };

  Color get _statusColor => switch (_phase) {
        _CheckPhase.done => Colors.green[700]!,
        _CheckPhase.failed => Colors.red[700]!,
        _ => Colors.blue[700]!,
      };

  Future<void> _runCheck() async {
    if (_isRunning) return;

    _setPhase(_CheckPhase.checkingPermission, '마이크 권한을 확인하는 중입니다.');

    final permissionStatus = await Permission.microphone.request();
    if (!permissionStatus.isGranted) {
      _setPhase(
        _CheckPhase.failed,
        '마이크 권한이 거부되었습니다.',
        detail: '기기 설정에서 마이크 권한을 허용한 후 다시 시도해 주세요.',
      );
      return;
    }

    _setPhase(_CheckPhase.checkingServer, '미디어 서버에 연결하는 중입니다.');

    try {
      await MediaSoupAudioService().ensureJoined(widget.sessionId);
    } catch (e) {
      _setPhase(
        _CheckPhase.failed,
        '미디어 서버 연결에 실패하였습니다.',
        detail: e.toString().replaceFirst(RegExp(r'^StateError: '), ''),
      );
      return;
    }

    _setPhase(
      _CheckPhase.testingSound,
      '스피커 출력을 테스트하는 중입니다. 소리가 들리면 정상입니다.',
    );

    try {
      await _audioPlayer.play(AssetSource('sounds/emergency.mp3'));
      await _audioPlayer.onPlayerComplete.first
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      _setPhase(
        _CheckPhase.done,
        '마이크 연결은 정상입니다. 테스트 사운드 재생에 실패하였습니다.',
        detail: '기기 볼륨 및 사운드 설정을 확인해 주세요.',
      );
      return;
    }

    _setPhase(
      _CheckPhase.done,
      '마이크 연결 및 스피커 출력이 정상적으로 확인되었습니다.',
    );
  }

  void _setPhase(_CheckPhase phase, String status, {String? detail}) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _statusText = status;
      _detailText = detail;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '오디오 및 마이크 점검',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              _statusText,
              style: TextStyle(fontSize: 13, color: _statusColor),
            ),
            if (_detailText != null) ...[
              const SizedBox(height: 4),
              Text(
                _detailText!,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (_isRunning) ...[
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _phaseLabel,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else
                  const Spacer(),
                ElevatedButton(
                  onPressed: _isRunning ? null : _runCheck,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _phase == _CheckPhase.idle ? '점검 시작' : '다시 점검',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            // ── 점검 완료 후: 마이크 컨트롤 영역 ─────────────────────────
            if (_phase == _CheckPhase.done) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),
              Row(
                children: [
                  // 마이크 음소거 토글
                  _MicToggleButton(sessionId: widget.sessionId),
                  const SizedBox(width: 16),
                  // 로컬 speaking 인디케이터
                  StreamBuilder<bool>(
                    stream: MediaSoupAudioService().isSpeakingStream,
                    initialData: false,
                    builder: (context, snap) {
                      final speaking = snap.data ?? false;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: speaking
                              ? Colors.green.withValues(alpha: 0.12)
                              : Colors.grey.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: speaking
                                ? Colors.green.shade400
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              speaking
                                  ? Icons.mic_rounded
                                  : Icons.mic_none_rounded,
                              size: 16,
                              color: speaking
                                  ? Colors.green.shade700
                                  : Colors.grey.shade500,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              speaking ? '말하는 중...' : '대기 중',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: speaking
                                    ? Colors.green.shade700
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 말하는 중 점 인디케이터 ──────────────────────────────────────────────────
class _SpeakingDot extends StatefulWidget {
  const _SpeakingDot({required this.isSpeaking});
  final bool isSpeaking;

  @override
  State<_SpeakingDot> createState() => _SpeakingDotState();
}

class _SpeakingDotState extends State<_SpeakingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isSpeaking) {
      return Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
        ),
      );
    }

    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: Colors.green.shade500,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.green.withValues(alpha: 0.5),
              blurRadius: 6,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(Icons.mic_rounded, size: 9, color: Colors.white),
      ),
    );
  }
}

// ── 마이크 음소거 토글 버튼 ────────────────────────────────────────────────
class _MicToggleButton extends StatefulWidget {
  const _MicToggleButton({required this.sessionId});
  final String sessionId;

  @override
  State<_MicToggleButton> createState() => _MicToggleButtonState();
}

class _MicToggleButtonState extends State<_MicToggleButton> {
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _isMuted = MediaSoupAudioService().isMuted;
  }

  Future<void> _toggle() async {
    await MediaSoupAudioService().toggleMute();
    if (!mounted) return;
    setState(() {
      _isMuted = MediaSoupAudioService().isMuted;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: _isMuted
              ? Colors.red.withValues(alpha: 0.1)
              : Colors.green.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(
            color: _isMuted ? Colors.red.shade400 : Colors.green.shade400,
            width: 2,
          ),
        ),
        child: Icon(
          _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          color: _isMuted ? Colors.red.shade600 : Colors.green.shade600,
          size: 26,
        ),
      ),
    );
  }
}

/// AppBar 우측에 항상 표시되는 플로팅 마이크 토글.
/// - 마이크 송출 중: 탭 시 toggleMute로 로컬 트랙 enabled를 전환
/// - 거절/미권한 상태: 탭 시 재요청 → 허용되면 publishMic
class _AppBarMicToggle extends StatefulWidget {
  const _AppBarMicToggle({
    required this.sessionId,
    required this.micPublished,
    required this.onRequestPublish,
  });

  final String sessionId;
  final bool micPublished;
  final Future<void> Function() onRequestPublish;

  @override
  State<_AppBarMicToggle> createState() => _AppBarMicToggleState();
}

class _AppBarMicToggleState extends State<_AppBarMicToggle> {
  StreamSubscription<bool>? _muteSub;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _isMuted = MediaSoupAudioService().isMuted;
    _muteSub = MediaSoupAudioService().isMutedStream.listen((muted) {
      if (!mounted) return;
      setState(() => _isMuted = muted);
    });
  }

  @override
  void dispose() {
    _muteSub?.cancel();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (!widget.micPublished) {
      await widget.onRequestPublish();
      return;
    }
    await MediaSoupAudioService().toggleMute();
  }

  @override
  Widget build(BuildContext context) {
    final published = widget.micPublished;
    final muted = _isMuted;
    final icon = !published || muted
        ? Icons.mic_off_rounded
        : Icons.mic_rounded;
    final color = !published
        ? Colors.grey.shade400
        : (muted ? Colors.red.shade400 : Colors.green.shade500);
    final tooltip = !published
        ? '마이크 송출 시작'
        : (muted ? '음소거 해제' : '음소거');

    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: color),
      onPressed: _onTap,
    );
  }
}
