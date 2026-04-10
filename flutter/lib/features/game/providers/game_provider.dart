// lib/features/game/providers/game_provider.dart

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/game_models.dart';
import '../../../core/services/socket_service.dart';

final gameProvider = StateNotifierProvider.family<GameNotifier, AmongUsGameState, String>(
  (ref, sessionId) => GameNotifier(sessionId),
);

class GameNotifier extends StateNotifier<AmongUsGameState> {
  GameNotifier(this._sessionId) : super(const AmongUsGameState()) {
    _subscribeToEvents();
  }

  final String _sessionId;
  final _socket = SocketService();

  final List<StreamSubscription> _subs = [];

  void _subscribeToEvents() {
    // 게임 시작
    _subs.add(_socket.onGameEvent(SocketService.gameStarted).listen((data) {
      state = state.copyWith(
        isStarted:    true,
        totalPlayers: data['playerCount'] as int? ?? 0,
      );
    }));

    // 역할 배정
    _subs.add(_socket.onGameEvent(SocketService.gameRoleAssigned).listen((data) {
      state = state.copyWith(myRole: GameRole.fromMap(data));
    }));

    // 회의 시작
    _subs.add(_socket.onGameEvent(SocketService.gameMeetingStarted).listen((data) {
      state = state.copyWith(
        meetingPhase:     'discussion',
        meetingRemaining: data['discussionTime'] as int? ?? 90,
        totalVoted:       0,
        preVoteCount:     0,
        voteResult:       null,
      );
    }));

    // 회의 틱
    _subs.add(_socket.onGameEvent(SocketService.gameMeetingTick).listen((data) {
      state = state.copyWith(
        meetingPhase:     data['phase']     as String,
        meetingRemaining: data['remaining'] as int,
      );
    }));

    // 투표 단계 시작
    _subs.add(_socket.onGameEvent(SocketService.gameVotingStarted).listen((_) {
      state = state.copyWith(meetingPhase: 'voting');
    }));

    // 사전 투표 제출 알림
    _subs.add(_socket.onGameEvent(SocketService.gamePreVoteSubmitted).listen((data) {
      state = state.copyWith(
        preVoteCount: data['totalPreVotes'] as int? ?? 0,
        totalPlayers: data['totalPlayers']  as int? ?? state.totalPlayers,
      );
    }));

    // 투표 제출 알림
    _subs.add(_socket.onGameEvent(SocketService.gameVoteSubmitted).listen((data) {
      state = state.copyWith(
        totalVoted:   data['totalVotes']  as int? ?? 0,
        totalPlayers: data['totalPlayers'] as int? ?? state.totalPlayers,
      );
    }));

    // 투표 결과
    _subs.add(_socket.onGameEvent(SocketService.gameVoteResult).listen((data) {
      state = state.copyWith(
        meetingPhase: 'result',
        voteResult:   VoteResult.fromMap(data),
      );
    }));

    // 회의 종료
    _subs.add(_socket.onGameEvent(SocketService.gameMeetingEnded).listen((_) {
      state = state.copyWith(meetingPhase: 'none');
    }));

    // AI 공개 메시지
    _subs.add(_socket.onGameEvent(SocketService.gameAiMessage).listen((data) {
      final log = ChatLog(
        id:        DateTime.now().millisecondsSinceEpoch.toString(),
        type:      ChatLogType.aiAnnounce,
        message:   data['message'] as String,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(chatLogs: [...state.chatLogs, log]);
    }));

    // AI 답변
    _subs.add(_socket.onGameEvent(SocketService.gameAiReply).listen((data) {
      final log = ChatLog(
        id:        DateTime.now().millisecondsSinceEpoch.toString(),
        type:      ChatLogType.aiReply,
        message:   data['answer'] as String,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(chatLogs: [...state.chatLogs, log]);
    }));

    // 게임 종료
    _subs.add(_socket.onGameEvent(SocketService.gameOver).listen((data) {
      state = state.copyWith(
        gameOverWinner: data['winner'] as String,
      );
    }));

    // 킬 확인 (본인 사망 처리)
    _subs.add(_socket.onGameEvent(SocketService.gameKillConfirmed).listen((data) {
      // 서버에서 victimId를 받아 본인인지 확인 (추후 userId 비교 추가)
    }));
  }

  // ── 액션 메서드 ──────────────────────────────────────────────────────────
  void startGame() => _socket.startGame(_sessionId);

  void sendKill(String targetUserId) => _socket.sendKill(_sessionId, targetUserId);

  void sendEmergency() => _socket.sendEmergencyMeeting(_sessionId);

  void sendReport(String bodyId) => _socket.sendReport(_sessionId, bodyId);

  void sendVote(String targetId, Function(Map) onResult) =>
      _socket.sendVote(_sessionId, targetId, onResult);

  void completeMission(String missionId) =>
      _socket.sendMissionComplete(_sessionId, missionId);

  void askAI(String question) {
    final myLog = ChatLog(
      id:        DateTime.now().millisecondsSinceEpoch.toString(),
      type:      ChatLogType.myQuestion,
      message:   question,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(chatLogs: [...state.chatLogs, myLog]);

    _socket.sendAiQuestion(_sessionId, question, (res) {
      if (res['ok'] != true) {
        final errLog = ChatLog(
          id:        DateTime.now().millisecondsSinceEpoch.toString(),
          type:      ChatLogType.system,
          message:   '질문 전송 실패: ${res['error']}',
          timestamp: DateTime.now(),
        );
        state = state.copyWith(chatLogs: [...state.chatLogs, errLog]);
      }
    });
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}
