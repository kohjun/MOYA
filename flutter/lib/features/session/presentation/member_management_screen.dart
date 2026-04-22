import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/data/auth_repository.dart';
import '../../../features/home/data/session_repository.dart';

final _sessionMembersProvider = FutureProvider.family<Session, String>(
  (ref, sessionId) => ref.read(sessionRepositoryProvider).getSession(sessionId),
);

class MemberManagementScreen extends ConsumerStatefulWidget {
  const MemberManagementScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<MemberManagementScreen> createState() =>
      _MemberManagementScreenState();
}

class _MemberManagementScreenState
    extends ConsumerState<MemberManagementScreen> {
  Future<void> _refresh() async {
    ref.invalidate(_sessionMembersProvider(widget.sessionId));
  }

  Future<void> _kickMember(String targetUserId, String nickname) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('참가자 강퇴'),
        content: Text('$nickname님을 이 세션에서 내보내시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('강퇴'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(sessionRepositoryProvider)
          .kickMember(widget.sessionId, targetUserId);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$nickname님을 강퇴했습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('강퇴 실패: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(_sessionMembersProvider(widget.sessionId));
    final authUser = ref.watch(authProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('참가자 관리'),
      ),
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('참가자 정보를 불러오지 못했습니다.\n$e'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _refresh,
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (session) {
          final members = session.members;
          final myRole = members
              .where((member) => member.userId == authUser?.id)
              .map((member) => member.role)
              .firstWhere((_) => true, orElse: () => 'member');
          final canManage = myRole == 'host';

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _SessionHeader(
                  sessionName: session.name.isEmpty ? '세션' : session.name,
                  sessionCode: session.code,
                ),
                const SizedBox(height: 16),
                ...members.map((member) {
                  final isMe = member.userId == authUser?.id;
                  final canKick = canManage && !isMe && !member.isHost;
                  return _MemberCard(
                    member: member,
                    isMe: isMe,
                    canKick: canKick,
                    onKick: canKick
                        ? () => _kickMember(member.userId, member.nickname)
                        : null,
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.sessionName,
    required this.sessionCode,
  });

  final String sessionName;
  final String sessionCode;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sessionName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '초대 코드: $sessionCode',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '코드 복사',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: sessionCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('초대 코드가 복사되었습니다.')),
                );
              },
              icon: const Icon(Icons.copy),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.isMe,
    required this.canKick,
    this.onKick,
  });

  final SessionMember member;
  final bool isMe;
  final bool canKick;
  final VoidCallback? onKick;

  String _roleLabel(String role) => role == 'host' ? '호스트' : '참가자';

  Color _roleColor(String role) =>
      role == 'host' ? const Color(0xFF2196F3) : Colors.grey;

  String? _teamLabel(String? teamId) {
    switch (teamId) {
      case 'guild_alpha':
        return '붉은 팀';
      case 'guild_beta':
        return '푸른 팀';
      case 'guild_gamma':
        return '초록 팀';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleColor = _roleColor(member.role);
    final teamLabel = _teamLabel(member.teamId);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: roleColor.withValues(alpha: 0.15),
              child: Text(
                member.nickname.isNotEmpty
                    ? member.nickname[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  color: roleColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${member.nickname}${isMe ? ' (나)' : ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: roleColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: roleColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          _roleLabel(member.role),
                          style: TextStyle(
                            fontSize: 11,
                            color: roleColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        member.sharingEnabled
                            ? Icons.location_on
                            : Icons.location_off,
                        size: 14,
                        color:
                            member.sharingEnabled ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        member.sharingEnabled
                            ? '위치 공유 켜짐'
                            : '위치 공유 꺼짐',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              member.sharingEnabled ? Colors.green : Colors.grey,
                        ),
                      ),
                      if (teamLabel != null) ...[
                        const SizedBox(width: 12),
                        Text(
                          teamLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (canKick)
              IconButton(
                icon: const Icon(
                  Icons.person_remove,
                  color: Colors.red,
                  size: 20,
                ),
                tooltip: '강퇴',
                onPressed: onKick,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}
