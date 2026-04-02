// lib/features/home/data/session_repository.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 데이터 모델
// ─────────────────────────────────────────────────────────────────────────────

class SessionMember {
  final String userId;
  final String nickname;
  final String? avatarUrl;
  final bool isHost;
  final String role; // 'host' | 'admin' | 'member'
  final bool sharingEnabled;
  final double? latitude;
  final double? longitude;
  final int? battery;
  final String status; // 'moving' | 'idle'

  const SessionMember({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    required this.isHost,
    this.role = 'member',
    this.sharingEnabled = true,
    this.latitude,
    this.longitude,
    this.battery,
    this.status = 'idle',
  });

  factory SessionMember.fromMap(Map<String, dynamic> m) {
    // GET /sessions/:id 응답: 위치 데이터는 lastLocation에 중첩
    final loc = m['lastLocation'] as Map<String, dynamic>?;
    return SessionMember(
      userId:         m['user_id']         as String,
      nickname:       m['nickname']        as String,
      avatarUrl:      m['avatar_url']      as String?,
      isHost:         m['is_host']         as bool? ?? false,
      role:           m['role']            as String? ?? 'member',
      sharingEnabled: m['sharing_enabled'] as bool? ?? true,
      latitude:       (loc?['lat']         as num?)?.toDouble(),
      longitude:      (loc?['lng']         as num?)?.toDouble(),
      battery:        loc?['battery']      as int?,
      status:         loc?['status']       as String? ?? 'idle',
    );
  }
}

class Session {
  final String id;
  final String name;
  final String code;
  final bool isHost;
  final int memberCount;
  final List<SessionMember> members;
  final DateTime createdAt;

  const Session({
    required this.id,
    required this.name,
    required this.code,
    required this.isHost,
    required this.memberCount,
    required this.members,
    required this.createdAt,
  });

  factory Session.fromMap(Map<String, dynamic> m) {
    final rawMembers = m['members'] as List<dynamic>? ?? [];
    return Session(
      id:          m['id']           as String,
      name:        m['name']         as String,
      code:        (m['session_code'] ?? m['code']) as String? ?? '',
      isHost:      m['is_host']      as bool? ?? false,
      memberCount: int.tryParse(m['member_count'].toString()) ?? rawMembers.length,
      members:     rawMembers
          .whereType<Map<String, dynamic>>()
          .map(SessionMember.fromMap)
          .toList(),
      createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Repository
// ─────────────────────────────────────────────────────────────────────────────

class SessionRepository {
  final ApiClient _api = ApiClient();

  Future<List<Session>> getMySessions() async {
    final res = await _api.get('/sessions');
    final list = res.data['sessions'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Session.fromMap)
        .toList();
  }

  Future<Session> createSession(String name) async {
    final res = await _api.post('/sessions', data: {'name': name});
    return Session.fromMap(res.data['session'] as Map<String, dynamic>);
  }

  Future<Session> joinSession(String code) async {
    final res = await _api.post('/sessions/join', data: {'code': code});
    return Session.fromMap(res.data['session'] as Map<String, dynamic>);
  }

  Future<Session> getSession(String id) async {
    try {
      final res = await _api.get('/sessions/$id');
      // res.data가 null이거나 Map이 아닐 경우를 방어
      final data = res.data as Map<String, dynamic>?;
      final rawMembers = data?['members'] as List<dynamic>? ?? [];
      final members = rawMembers
          .whereType<Map<String, dynamic>>()
          .map(SessionMember.fromMap)
          .toList();
      return Session(
        id:          id,
        name:        '',
        code:        '',
        isHost:      false,
        memberCount: members.length,
        members:     members,
        createdAt:   DateTime.now(),
      );
    } catch (e) {
      debugPrint('[SessionRepository] getSession($id) error: $e');
      return Session(
        id:          id,
        name:        '',
        code:        '',
        isHost:      false,
        memberCount: 0,
        members:     [],
        createdAt:   DateTime.now(),
      );
    }
  }

  Future<void> leaveSession(String id) async {
    await _api.post('/sessions/$id/leave');
  }

  Future<void> endSession(String id) async {
    await _api.post('/sessions/$id/end');
  }

  Future<void> toggleSharing(String sessionId, bool enabled) async {
    await _api.patch('/sessions/$sessionId/sharing', data: {'enabled': enabled});
  }

  Future<void> updateMemberRole(String sessionId, String userId, String role) async {
    await _api.patch(
      '/sessions/$sessionId/members/$userId/role',
      data: {'role': role},
    );
  }

  Future<void> kickMember(String sessionId, String userId) async {
    await _api.delete('/sessions/$sessionId/members/$userId');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final sessionRepositoryProvider = Provider((ref) => SessionRepository());

// 내 세션 목록 상태 관리
class SessionListNotifier extends AsyncNotifier<List<Session>> {
  @override
  Future<List<Session>> build() => _fetch();

  Future<List<Session>> _fetch() =>
      ref.read(sessionRepositoryProvider).getMySessions();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<String> createSession(String name) async {
    final session = await ref.read(sessionRepositoryProvider).createSession(name);
    await refresh();
    return session.code;
  }

  Future<void> joinSession(String code) async {
    await ref.read(sessionRepositoryProvider).joinSession(code);
    await refresh();
  }

  Future<void> leaveSession(String sessionId) async {
    await ref.read(sessionRepositoryProvider).leaveSession(sessionId);
    await refresh();
  }
}

final sessionListProvider =
    AsyncNotifierProvider<SessionListNotifier, List<Session>>(
  SessionListNotifier.new,
);
