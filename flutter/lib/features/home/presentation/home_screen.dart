// lib/features/home/presentation/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../auth/data/auth_repository.dart';
import '../data/session_repository.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

 
  bool _hasActiveSession(BuildContext context, WidgetRef ref) {
    final sessions = ref.read(sessionListProvider).valueOrNull ?? [];
    if (sessions.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('입장 불가'),
          content: const Text('이미 참여 중인 세션이 있습니다. 기존 세션을 나가거나 종료한 뒤 새 세션에 참여해주세요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return true; 
    }
    return false; 
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState    = ref.watch(authProvider);
    final sessionState = ref.watch(sessionListProvider);
    final user         = authState.valueOrNull;


    final hasSession = (sessionState.valueOrNull?.isNotEmpty ?? false);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('세션 목록', style: TextStyle(fontWeight: FontWeight.bold)),
            if (user != null)
              Text(
                user.nickname,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: () => ref.read(sessionListProvider.notifier).refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '설정',
            onPressed: () => context.push(AppRoutes.settings),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () => _confirmLogout(context, ref),
          ),
        ],
      ),

      body: sessionState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.read(sessionListProvider.notifier).refresh(),
        ),
        data: (sessions) => sessions.isEmpty
            ? _EmptyView(
                onCreateSession: () => _showCreateDialog(context, ref),
                onJoinSession:   () => _showJoinDialog(context, ref),
              )
            : RefreshIndicator(
                onRefresh: () => ref.read(sessionListProvider.notifier).refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _SessionCard(
                    session: sessions[index],
                    onTap: () {
                      final s = sessions[index];
                      if (s.gameStatus == 'playing') {
                        context.push('/game/${s.id}?gameType=${s.gameType}');
                      } else {
                        context.push('/lobby/${s.id}?gameType=${s.gameType}');
                      }
                    },
                    onLeave: () => _confirmLeave(context, ref, sessions[index]),
                  ),
                ),
              ),
      ),

    
      floatingActionButton: hasSession 
          ? null 
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'join',
                  onPressed: () => _showJoinDialog(context, ref),
                  icon: const Icon(Icons.group_add),
                  label: const Text('코드로 참가'),
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF2196F3),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'create',
                  onPressed: () => _showCreateDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('세션 생성'),
                ),
              ],
            ),
    );
  }

  
  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    if (_hasActiveSession(context, ref)) return;

    final ctrl = TextEditingController();
    int selectedHours = 1;
    double maxMembers = 3;
    String selectedGameType = _kGameCatalog.first.gameType;

    final Map<int, String> durationOptions = {
      1: '1시간 (기본)',
      6: '6시간',
      24: '24시간',
      72: '3일',
      120: '5일',
      168: '7일',
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('새 세션 생성'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLength: 30,
                    decoration: const InputDecoration(
                      labelText: '세션 이름',
                      hintText: '예: MOYA 판타지 워즈',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: selectedHours,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '세션 유지 시간'),
                    items: durationOptions.entries
                        .map((e) => DropdownMenuItem<int>(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedHours = v);
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('최대 인원',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${maxMembers.toInt()}명',
                          style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: maxMembers,
                    min: 3,
                    max: 20,
                    divisions: 17,
                    label: '${maxMembers.toInt()}명',
                    onChanged: (v) =>
                        setDialogState(() => maxMembers = v),
                  ),
                  const Text(
                    '최소 3명에서 최대 20명까지 설정할 수 있습니다.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),

              
                  const Text('게임 선택',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._kGameCatalog.map((game) => _GameCatalogCard(
                        info: game,
                        selected: selectedGameType == game.gameType,
                        onTap: () => setDialogState(
                            () => selectedGameType = game.gameType),
                      )),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = ctrl.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(ctx);

                  try {
                    final session = await ref
                        .read(sessionListProvider.notifier)
                        .createSession(
                          name,
                          durationHours: selectedHours,
                          maxMembers: maxMembers.toInt(),
                          gameType: selectedGameType,
                        );

                    if (context.mounted) {
                      context.push(
                          '/lobby/${session.id}?gameType=${session.gameType}');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('세션 생성 실패: $e'),
                            backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                child: const Text('생성'),
              ),
            ],
          );
        },
      ),
    );
  }

 
  void _showJoinDialog(BuildContext context, WidgetRef ref) {
    if (_hasActiveSession(context, ref)) return;

    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('초대 코드로 참가'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9a-z]')),
            LengthLimitingTextInputFormatter(8),
          ],
          decoration: const InputDecoration(
            labelText: '초대 코드',
            hintText: 'ABCD1234',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = ctrl.text.trim().toUpperCase();
              if (code.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final session = await ref.read(sessionListProvider.notifier).joinSession(code);
                if (context.mounted) {
                  context.push('/lobby/${session.id}?gameType=${session.gameType}');
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('참가 실패: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('참가'),
          ),
        ],
      ),
    );
  }

 
  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authProvider.notifier).logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
  }

  // ?? ?몄뀡 ?섍?湲??뺤씤 ??????????????????????????????????????????????????????
  void _confirmLeave(BuildContext context, WidgetRef ref, Session session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('세션 나가기'),
        content: Text('"${session.name}" 세션에서 나가시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(sessionListProvider.notifier).leaveSession(session.id);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('나가기 실패: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
  }
}



class _SessionCard extends StatefulWidget {
  const _SessionCard({
    required this.session,
    required this.onTap,
    required this.onLeave,
  });

  final Session session;
  final VoidCallback onTap;
  final VoidCallback onLeave;

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  
  String _getRemainingTime(DateTime? expiresAt) {
    if (expiresAt == null) return '만료 시간 없음';
    
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return '만료됨';

    if (diff.inDays > 0) {
      return '${diff.inDays}일 ${diff.inHours % 24}시간 남음';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}시간 ${diff.inMinutes % 60}분 남음';
    } else {
      return '${diff.inMinutes}분 남음';
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final remainingTimeText = _getRemainingTime(session.expiresAt);
    final isExpired = session.expiresAt != null && session.expiresAt!.isBefore(DateTime.now());

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
     
        onTap: isExpired 
            ? () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('만료된 세션입니다. 새로고침 후 다시 확인해주세요.'),
                    backgroundColor: Colors.grey,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            : widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // ?몄뀡 ?꾩씠肄?(湲곕낯 留덉빱 ?꾩씠肄?
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.location_on, color: Color(0xFF2196F3)),
                  ),
                  const SizedBox(width: 12),

           
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                session.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (session.isHost)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2196F3),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  '호스트',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 11),
                                ),
                              ),
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: session.gameStatus == 'playing'
                                    ? Colors.green
                                    : Colors.orange,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                session.gameStatus == 'playing' ? '플레이 중' : '로비',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                           
                            const Icon(Icons.people_outlined, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              '${session.memberCount}명',
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                            
                            const SizedBox(width: 12),
                            
                           
                            Icon(
                              Icons.timer_outlined, 
                              size: 14, 
                              color: isExpired ? Colors.red : Colors.orange[700]
                            ),
                            const SizedBox(width: 4),
                            Text(
                              remainingTimeText,
                              style: TextStyle(
                                color: isExpired ? Colors.red : Colors.orange[700], 
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (session.code.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: session.code));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('초대 코드가 복사되었습니다.'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  session.code,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.copy, size: 12, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.exit_to_app,
                            size: 20, color: Colors.red),
                        tooltip: '세션 나가기',
                        onPressed: widget.onLeave,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _GameInfo {
  const _GameInfo({
    required this.gameType,
    required this.displayName,
    required this.description,
    required this.icon,
    required this.color,
  });
  final String   gameType;
  final String   displayName;
  final String   description;
  final IconData icon;
  final Color    color;
}

const List<_GameInfo> _kGameCatalog = [
  _GameInfo(
    gameType:    'fantasy_wars_artifact',
    displayName: '판타지 워즈: 성유물 쟁탈전',
    description: '전장을 설정하고 세 길드로 나뉘어 다섯 거점을 두고 경쟁합니다.',
    icon:        Icons.castle,
    color:       Color(0xFF7B2FBE),
  ),
];

class _GameCatalogCard extends StatelessWidget {
  const _GameCatalogCard({
    required this.info,
    required this.selected,
    required this.onTap,
  });

  final _GameInfo    info;
  final bool         selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? info.color.withValues(alpha: 0.10)
              : Colors.grey[50],
          border: Border.all(
            color: selected ? info.color : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: info.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(info.icon, color: info.color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: selected ? info.color : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    info.description,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: info.color, size: 20),
          ],
        ),
      ),
    );
  }
}


class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.onCreateSession,
    required this.onJoinSession,
  });

  final VoidCallback onCreateSession;
  final VoidCallback onJoinSession;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_off, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            '참여 중인 세션이 없습니다',
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: onJoinSession,
            icon: const Icon(Icons.group_add),
            label: const Text('코드로 참가'),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onCreateSession,
            icon: const Icon(Icons.add),
            label: const Text('세션 생성'),
          ),
        ],
      ),
    );
  }
}



class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String       message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 60, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}

