// lib/features/session/presentation/member_management_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/data/auth_repository.dart';
import '../../../features/home/data/session_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Provider: 세션 멤버 목록
// ─────────────────────────────────────────────────────────────────────────────

final _sessionMembersProvider = FutureProvider.family<Session, String>(
  (ref, sessionId) => ref.read(sessionRepositoryProvider).getSession(sessionId),
);

// ─────────────────────────────────────────────────────────────────────────────
// MemberManagementScreen
// ─────────────────────────────────────────────────────────────────────────────

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

  Future<void> _changeRole(
    String targetUserId,
    String currentRole,
    String myRole,
  ) async {
    final newRole = currentRole == 'admin' ? 'member' : 'admin';
    final label   = newRole == 'admin' ? '관리자로 변경' : '일반 멤버로 변경';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('역할 변경'),
        content: Text('$label 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('변경'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(sessionRepositoryProvider)
          .updateMemberRole(widget.sessionId, targetUserId, newRole);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('역할이 변경되었습니다: $label')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('역할 변경 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _kickMember(String targetUserId, String nickname) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('강제 퇴장'),
        content: Text('$nickname 님을 세션에서 퇴장시키겠습니까?'),
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
            child: const Text('퇴장'),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$nickname 님을 퇴장시켰습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('퇴장 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(_sessionMembersProvider(widget.sessionId));
    final authUser     = ref.watch(authProvider).valueOrNull;

    // 세션 코드: sessionListProvider 캐시에서 조회
    final cachedSessions = ref.watch(sessionListProvider).valueOrNull ?? [];
    final cached = cachedSessions.where((s) => s.id == widget.sessionId);
    final sessionCode = cached.isNotEmpty ? cached.first.code : '';
    final sessionName = cached.isNotEmpty ? cached.first.name : '멤버 관리';

    return Scaffold(
      appBar: AppBar(
        title: Text(sessionName),
        actions: [
          if (sessionCode.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: Text(
                sessionCode,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: sessionCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('세션 코드가 복사되었습니다.')),
                );
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('멤버를 불러올 수 없습니다.\n$e'),
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

          // 내 역할 결정
          final myMemberList =
              members.where((m) => m.userId == authUser?.id).toList();
          final myRole =
              myMemberList.isNotEmpty ? myMemberList.first.role : 'member';
          final canManage = myRole == 'host' || myRole == 'admin';

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: members.length,
              itemBuilder: (context, i) {
                final member = members[i];
                final isMe = member.userId == authUser?.id;
                final canActOn = canManage &&
                    !isMe &&
                    member.role != 'host' &&
                    // 관리자는 다른 관리자 관리 불가
                    !(myRole == 'admin' && member.role == 'admin');

                return _MemberCard(
                  member:       member,
                  isMe:         isMe,
                  canManage:    canActOn,
                  onRoleChange: canActOn
                      ? () => _changeRole(member.userId, member.role, myRole)
                      : null,
                  onKick: canActOn
                      ? () => _kickMember(member.userId, member.nickname)
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 멤버 카드
// ─────────────────────────────────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.isMe,
    required this.canManage,
    this.onRoleChange,
    this.onKick,
  });

  final SessionMember member;
  final bool          isMe;
  final bool          canManage;
  final VoidCallback? onRoleChange;
  final VoidCallback? onKick;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 아바타
            CircleAvatar(
              radius: 22,
              backgroundColor:
                  const Color(0xFF2196F3).withValues(alpha: 0.15),
              child: Text(
                member.nickname.isNotEmpty
                    ? member.nickname[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Color(0xFF2196F3),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // 이름 + 역할 + 상태
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
                      _RoleBadge(role: member.role),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // 위치 공유 상태
                      Icon(
                        member.sharingEnabled
                            ? Icons.location_on
                            : Icons.location_off,
                        size: 14,
                        color: member.sharingEnabled
                            ? Colors.green
                            : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        member.sharingEnabled ? '위치 공유 중' : '위치 공유 꺼짐',
                        style: TextStyle(
                          fontSize: 12,
                          color: member.sharingEnabled
                              ? Colors.green
                              : Colors.grey,
                        ),
                      ),
                      if (member.battery != null) ...[
                        const SizedBox(width: 12),
                        Icon(
                          _batteryIcon(member.battery!),
                          size: 14,
                          color: member.battery! < 20
                              ? Colors.red
                              : Colors.grey,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${member.battery}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: member.battery! < 20
                                ? Colors.red
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // 액션 버튼 (host/admin만)
            if (canManage)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 역할 변경
                  if (onRoleChange != null)
                    TextButton(
                      onPressed: onRoleChange,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        member.role == 'admin' ? '멤버로' : '관리자로',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  // 강제 퇴장
                  if (onKick != null)
                    IconButton(
                      icon: const Icon(
                        Icons.person_remove,
                        color: Colors.red,
                        size: 20,
                      ),
                      tooltip: '강제 퇴장',
                      onPressed: onKick,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  IconData _batteryIcon(int level) {
    if (level >= 80) return Icons.battery_full;
    if (level >= 50) return Icons.battery_4_bar;
    if (level >= 20) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 역할 뱃지
// ─────────────────────────────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (role) {
      'host'  => ('호스트', Colors.red),
      'admin' => ('관리자', Colors.orange),
      _       => ('멤버',   Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
