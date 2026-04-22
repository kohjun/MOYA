import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/socket_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../game/presentation/game_ui_plugin.dart';
import '../../game/presentation/playable_area_painter_screen.dart';
import '../../home/data/session_repository.dart'
    show
        FantasyWarsTeamConfig,
        Session,
        SessionMember,
        sessionListProvider;
import '../providers/lobby_provider.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({
    super.key,
    required this.sessionId,
    this.gameType,
  });

  final String sessionId;
  final String? gameType;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  Timer? _countdownTimer;
  StreamSubscription? _kickedSub;
  String _countdownText = '--:--:--';
  bool _startingGame = false;
  bool _didNavigateToGame = false;
  bool _layoutSavedInThisVisit = false;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });

    _kickedSub = SocketService().onKicked.listen((_) {
      if (!mounted) {
        return;
      }
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
    if (!mounted) {
      return;
    }

    final expiresAt = ref.read(lobbyProvider(widget.sessionId)).sessionInfo?.expiresAt;
    if (expiresAt == null) {
      return;
    }

    final diff = expiresAt.difference(DateTime.now());
    setState(() {
      if (diff.isNegative) {
        _countdownText = '00:00:00';
      } else {
        final hours = diff.inHours.toString().padLeft(2, '0');
        final minutes = (diff.inMinutes % 60).toString().padLeft(2, '0');
        final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
        _countdownText = '$hours:$minutes:$seconds';
      }
    });
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('세션 나가기'),
        content: const Text('이 로비를 나가고 홈으로 돌아가시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );

    if (leave != true || !mounted) {
      return;
    }

    try {
      await ref.read(sessionListProvider.notifier).leaveSession(widget.sessionId);
      await ref
          .read(lobbyProvider(widget.sessionId).notifier)
          .releaseRealtimeResources(notifyServer: false);
      if (!mounted) {
        return;
      }
      context.go('/');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError('나가기 실패: $error');
    }
  }

  Future<void> _startGame() async {
    setState(() => _startingGame = true);
    try {
      await ref.read(lobbyProvider(widget.sessionId).notifier).startGame();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError('게임 시작 실패: $error');
    } finally {
      if (mounted) {
        setState(() => _startingGame = false);
      }
    }
  }

  Future<void> _openBattlefieldEditor() async {
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => PlayableAreaPainterScreen(sessionId: widget.sessionId),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() => _layoutSavedInThisVisit = true);
    await ref.read(lobbyProvider(widget.sessionId).notifier).refresh();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lobbyState = ref.watch(lobbyProvider(widget.sessionId));
    final authUser = ref.watch(authProvider).valueOrNull;
    final session = lobbyState.sessionInfo;
    final members = lobbyState.members;
    final myUserId = authUser?.id ?? '';
    final gameType = session?.gameType ?? widget.gameType ?? 'among_us';
    final isFantasyWars = _isFantasyWars(gameType);

    if (lobbyState.isGameStarted && !_didNavigateToGame) {
      _didNavigateToGame = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        context.go('/game/${widget.sessionId}?gameType=$gameType');
      });
    }

    final isHost = (session?.isHost ?? false) ||
        members.any((member) => member.userId == myUserId && member.role == 'host');
    final minPlayers = GameUiPluginRegistry.minPlayersFor(gameType);
    final teams = _teamConfigsFor(session);
    final layoutStatus = _FantasyWarsLayoutStatus.fromSession(session, teams.length);
    final canStart = members.length >= minPlayers &&
        (isFantasyWars
            ? (layoutStatus.isReady || _layoutSavedInThisVisit)
            : (session?.playableArea?.length ?? 0) >= 3 || _layoutSavedInThisVisit);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_confirmLeave());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(session?.name.isNotEmpty == true ? session!.name : '로비'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _confirmLeave,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: '초대 코드 복사',
              onPressed: session == null
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: session.code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('초대 코드가 복사되었습니다.')),
                      );
                    },
            ),
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: '초대 코드 공유',
              onPressed: session == null
                  ? null
                  : () => Share.share('초대 코드 ${session.code}로 제 세션에 참가해주세요.'),
            ),
          ],
        ),
        body: lobbyState.isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () =>
                    ref.read(lobbyProvider(widget.sessionId).notifier).refresh(),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _SessionSummaryCard(
                      session: session,
                      countdownText: _countdownText,
                      gameType: gameType,
                      memberCount: members.length,
                    ),
                    const SizedBox(height: 16),
                    if (isFantasyWars) ...[
                      _FantasyWarsLayoutCard(status: layoutStatus),
                      const SizedBox(height: 16),
                      _FantasyWarsTeamBoard(
                        teams: teams,
                        members: members,
                        myUserId: myUserId,
                        isHost: isHost,
                        sessionId: widget.sessionId,
                      ),
                    ] else ...[
                      _MemberList(
                        members: members,
                        myUserId: myUserId,
                        isHost: isHost,
                        sessionId: widget.sessionId,
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (isHost) ...[
                      OutlinedButton.icon(
                        onPressed: _openBattlefieldEditor,
                        icon: const Icon(Icons.map_outlined),
                        label: Text(
                          isFantasyWars
                              ? (layoutStatus.isReady
                                  ? '전장 수정'
                                  : '전장 설정')
                              : ((session?.playableArea?.length ?? 0) >= 3
                                  ? '플레이 구역 수정'
                                  : '플레이 구역 설정'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (isFantasyWars && !layoutStatus.isReady)
                        Text(
                          layoutStatus.missingSummary,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.orange),
                        ),
                      if (!isFantasyWars && (session?.playableArea?.length ?? 0) < 3)
                        const Text(
                          '게임을 시작하기 전에 플레이 구역을 설정해주세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.orange),
                        ),
                      if (members.length < minPlayers)
                        Text(
                          '최소 $minPlayers명 이상 필요합니다.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.orange),
                        ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: canStart && !_startingGame ? _startGame : null,
                        icon: _startingGame
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.play_arrow),
                        label: Text(_startingGame ? '시작 중...' : '게임 시작'),
                      ),
                    ] else
                      const Text(
                        '길드를 선택한 뒤 호스트가 게임을 시작할 때까지 기다려주세요.',
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

bool _isFantasyWars(String gameType) =>
    gameType == 'fantasy_wars_artifact' || gameType == 'fantasy_wars';

List<FantasyWarsTeamConfig> _teamConfigsFor(Session? session) {
  if (session?.fantasyWarsTeams.isNotEmpty == true) {
    return session!.fantasyWarsTeams;
  }

  return const [
    FantasyWarsTeamConfig(
      teamId: 'guild_alpha',
      displayName: '붉은 길드',
      color: '#DC2626',
    ),
    FantasyWarsTeamConfig(
      teamId: 'guild_beta',
      displayName: '푸른 길드',
      color: '#2563EB',
    ),
    FantasyWarsTeamConfig(
      teamId: 'guild_gamma',
      displayName: '초록 길드',
      color: '#16A34A',
    ),
  ];
}

class _FantasyWarsLayoutStatus {
  const _FantasyWarsLayoutStatus({
    required this.hasArea,
    required this.controlPointCount,
    required this.expectedControlPointCount,
    required this.spawnZoneCount,
    required this.expectedSpawnZoneCount,
  });

  final bool hasArea;
  final int controlPointCount;
  final int expectedControlPointCount;
  final int spawnZoneCount;
  final int expectedSpawnZoneCount;

  bool get isReady =>
      hasArea &&
      controlPointCount == expectedControlPointCount &&
      spawnZoneCount == expectedSpawnZoneCount;

  String get missingSummary {
    final parts = <String>[];
    if (!hasArea) {
      parts.add('플레이 구역');
    }
    if (controlPointCount != expectedControlPointCount) {
      parts.add('점령지 5개');
    }
    if (spawnZoneCount != expectedSpawnZoneCount) {
      parts.add('길드 시작 지점 3개');
    }
    return parts.isEmpty
        ? '전장 설정이 완료되었습니다.'
        : '아직 필요한 항목: ${parts.join(', ')}';
  }

  static _FantasyWarsLayoutStatus fromSession(Session? session, int teamCount) {
    final expectedControlPointCount =
        (session?.gameConfig['controlPointCount'] as num?)?.toInt() ?? 5;
    return _FantasyWarsLayoutStatus(
      hasArea: (session?.playableArea?.length ?? 0) >= 3,
      controlPointCount: session?.fantasyWarsControlPoints.length ?? 0,
      expectedControlPointCount: expectedControlPointCount,
      spawnZoneCount: session?.fantasyWarsSpawnZones.length ?? 0,
      expectedSpawnZoneCount: teamCount,
    );
  }
}

class _SessionSummaryCard extends StatelessWidget {
  const _SessionSummaryCard({
    required this.session,
    required this.countdownText,
    required this.gameType,
    required this.memberCount,
  });

  final Session? session;
  final String countdownText;
  final String gameType;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    final plugin = GameUiPluginRegistry.get(gameType);
    final gameLabel = plugin?.displayName ?? gameType;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session?.name.isNotEmpty == true ? session!.name : '세션',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text('게임: $gameLabel'),
            Text('코드: ${session?.code ?? '------'}'),
            Text('인원: $memberCount명'),
            Text('남은 시간: $countdownText'),
          ],
        ),
      ),
    );
  }
}

class _FantasyWarsLayoutCard extends StatelessWidget {
  const _FantasyWarsLayoutCard({required this.status});

  final _FantasyWarsLayoutStatus status;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '전장 설정 상태',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(
                  label: status.hasArea ? '플레이 구역 완료' : '플레이 구역 필요',
                  ready: status.hasArea,
                ),
                _StatusChip(
                  label:
                      '점령지 ${status.controlPointCount}/${status.expectedControlPointCount}',
                  ready: status.controlPointCount == status.expectedControlPointCount,
                ),
                _StatusChip(
                  label:
                      '길드 시작 지점 ${status.spawnZoneCount}/${status.expectedSpawnZoneCount}',
                  ready: status.spawnZoneCount == status.expectedSpawnZoneCount,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              status.missingSummary,
              style: TextStyle(
                color: status.isReady ? Colors.green.shade700 : Colors.orange.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.ready,
  });

  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final color = ready ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FantasyWarsTeamBoard extends ConsumerWidget {
  const _FantasyWarsTeamBoard({
    required this.teams,
    required this.members,
    required this.myUserId,
    required this.isHost,
    required this.sessionId,
  });

  final List<FantasyWarsTeamConfig> teams;
  final List<SessionMember> members;
  final String myUserId;
  final bool isHost;
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unassignedMembers = members.where((member) {
      return !teams.any((team) => team.teamId == member.teamId);
    }).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '길드',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth >= 960
                ? (constraints.maxWidth - 24) / 3
                : constraints.maxWidth >= 640
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final team in teams)
                  SizedBox(
                    width: cardWidth,
                    child: _TeamCard(
                      team: team,
                      members: members
                          .where((member) => member.teamId == team.teamId)
                          .toList(growable: false),
                      allTeams: teams,
                      myUserId: myUserId,
                      isHost: isHost,
                      sessionId: sessionId,
                    ),
                  ),
                if (unassignedMembers.isNotEmpty)
                  SizedBox(
                    width: cardWidth,
                    child: _UnassignedCard(
                      members: unassignedMembers,
                      allTeams: teams,
                      myUserId: myUserId,
                      isHost: isHost,
                      sessionId: sessionId,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TeamCard extends ConsumerWidget {
  const _TeamCard({
    required this.team,
    required this.members,
    required this.allTeams,
    required this.myUserId,
    required this.isHost,
    required this.sessionId,
  });

  final FantasyWarsTeamConfig team;
  final List<SessionMember> members;
  final List<FantasyWarsTeamConfig> allTeams;
  final String myUserId;
  final bool isHost;
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _hexToColor(team.color);
    final myMember = members.where((member) => member.userId == myUserId).firstOrNull;
    final canJoin = myUserId.isNotEmpty && myMember == null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: color, width: 5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      team.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${members.length}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (canJoin)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _moveMember(
                      context,
                      ref,
                      userId: myUserId,
                      teamId: team.teamId,
                    ),
                    child: const Text('이 길드로 이동'),
                  ),
                )
              else if (myMember != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '현재 이 길드에 있습니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (members.isEmpty)
                Text(
                  '아직 팀원이 없습니다.',
                  style: TextStyle(color: Colors.grey.shade600),
                )
              else
                ...members.map(
                  (member) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MemberTile(
                      member: member,
                      myUserId: myUserId,
                      isHost: isHost,
                      allTeams: allTeams,
                      sessionId: sessionId,
                      accentColor: color,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _moveMember(
    BuildContext context,
    WidgetRef ref, {
    required String userId,
    required String teamId,
  }) async {
    try {
      await ref.read(lobbyProvider(sessionId).notifier).moveMemberToTeam(userId, teamId);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('팀 이동 실패: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _UnassignedCard extends StatelessWidget {
  const _UnassignedCard({
    required this.members,
    required this.allTeams,
    required this.myUserId,
    required this.isHost,
    required this.sessionId,
  });

  final List<SessionMember> members;
  final List<FantasyWarsTeamConfig> allTeams;
  final String myUserId;
  final bool isHost;
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '미배정',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...members.map(
              (member) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MemberTile(
                  member: member,
                  myUserId: myUserId,
                  isHost: isHost,
                  allTeams: allTeams,
                  sessionId: sessionId,
                  accentColor: Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.member,
    required this.myUserId,
    required this.isHost,
    required this.allTeams,
    required this.sessionId,
    required this.accentColor,
  });

  final SessionMember member;
  final String myUserId;
  final bool isHost;
  final List<FantasyWarsTeamConfig> allTeams;
  final String sessionId;
  final Color accentColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMe = member.userId == myUserId;
    final canManage = isHost && !member.isHost;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: accentColor.withValues(alpha: 0.16),
          child: Text(
            member.nickname.isNotEmpty ? member.nickname[0].toUpperCase() : '?',
            style: TextStyle(color: accentColor),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${member.nickname}${isMe ? ' (나)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (member.isHost)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '호스트',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(member.role == 'host' ? '호스트' : '참가자'),
        trailing: canManage
            ? PopupMenuButton<String>(
                onSelected: (value) => _handleAction(context, ref, value),
                itemBuilder: (context) {
                  return [
                    for (final team in allTeams)
                      if (team.teamId != member.teamId)
                        PopupMenuItem(
                          value: 'move:${team.teamId}',
                          child: Text('${team.displayName}(으)로 이동'),
                        ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'kick',
                      child: Text('세션에서 강퇴'),
                    ),
                  ];
                },
              )
            : null,
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, WidgetRef ref, String value) async {
    if (value == 'kick') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('참가자 강퇴'),
          content: Text('${member.nickname}님을 이 세션에서 내보내시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('강퇴'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }

      try {
        await ref.read(lobbyProvider(sessionId).notifier).kickMember(member.userId);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('강퇴 실패: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      return;
    }

    if (value.startsWith('move:')) {
      final targetTeamId = value.substring('move:'.length);
      try {
        await ref
            .read(lobbyProvider(sessionId).notifier)
            .moveMemberToTeam(member.userId, targetTeamId);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('팀 이동 실패: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

class _MemberList extends ConsumerWidget {
  const _MemberList({
    required this.members,
    required this.myUserId,
    required this.isHost,
    required this.sessionId,
  });

  final List<SessionMember> members;
  final String myUserId;
  final bool isHost;
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '참가자',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...members.map(
          (member) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  member.nickname.isNotEmpty ? member.nickname[0].toUpperCase() : '?',
                ),
              ),
              title: Text('${member.nickname}${member.userId == myUserId ? ' (나)' : ''}'),
              subtitle: Text(member.role == 'host' ? '호스트' : '참가자'),
              trailing: isHost && !member.isHost
                  ? IconButton(
                      icon: const Icon(Icons.person_remove, color: Colors.red),
                      onPressed: () async {
                        try {
                          await ref
                              .read(lobbyProvider(sessionId).notifier)
                              .kickMember(member.userId);
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('강퇴 실패: $error'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

Color _hexToColor(String hex) {
  final normalized = hex.replaceFirst('#', '');
  final value = int.parse(normalized.length == 6 ? 'FF$normalized' : normalized, radix: 16);
  return Color(value);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
