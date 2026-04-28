import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/socket_service.dart';
import '../../home/data/session_repository.dart';

enum AiMasterPhase { ok, failed, retrying }

class AiMasterState {
  const AiMasterState({
    this.phase = AiMasterPhase.ok,
    this.message,
  });

  final AiMasterPhase phase;
  final String? message;

  bool get showRetry => phase == AiMasterPhase.failed;
}

class AiMasterNotifier extends StateNotifier<AiMasterState> {
  AiMasterNotifier(this._sessionId, this._ref)
      : super(const AiMasterState()) {
    _init();
  }

  final String _sessionId;
  final Ref _ref;
  StreamSubscription<dynamic>? _sub;

  void _init() {
    final socket = SocketService();

    _sub = socket
        .onGameEvent('ai:failed')
        .where((data) => data['sessionId'] == _sessionId)
        .listen((data) {
      if (!mounted) return;
      state = AiMasterState(
        phase: AiMasterPhase.failed,
        message: data['message'] as String?,
      );
    });

    socket
        .onGameEvent('ai:recovered')
        .where((data) => data['sessionId'] == _sessionId)
        .listen((_) {
      if (!mounted) return;
      state = const AiMasterState(phase: AiMasterPhase.ok);
    });
  }

  Future<void> retry() async {
    if (state.phase == AiMasterPhase.retrying) return;
    state = const AiMasterState(phase: AiMasterPhase.retrying);

    try {
      final repo = _ref.read(sessionRepositoryProvider);
      await repo.retryLlm(_sessionId);
      // 실제 성공/실패는 소켓 이벤트(ai:failed / ai:recovered)로 업데이트됨
    } on DioException catch (e) {
      debugPrint('[AI] retry-llm failed: $e');
      state = const AiMasterState(
        phase: AiMasterPhase.failed,
        message: '재시도 실패. 네트워크를 확인해주세요.',
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final aiMasterProvider = StateNotifierProvider.autoDispose
    .family<AiMasterNotifier, AiMasterState, String>(
  (ref, sessionId) => AiMasterNotifier(sessionId, ref),
);
