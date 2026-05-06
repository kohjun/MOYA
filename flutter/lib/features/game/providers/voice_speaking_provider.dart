import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/socket_service.dart';

/// 서버 fanout(`voice:speaking`)으로부터 받은 "현재 발화 중" userId 집합.
///
/// `lobby_provider` 도 같은 stream을 구독하지만, Fantasy Wars 게임 화면이
/// lobby state shape에 의존하지 않도록 별도 provider로 분리한다.
///
/// 본인 발화 상태는 이 provider에 포함되지 않는다 — 서버 round-trip latency를
/// 피하기 위해 호출 측에서 `MediaSoupAudioService().isSpeakingStream` 을
/// 직접 구독해 합쳐 사용한다.
final voiceSpeakingProvider = StateNotifierProvider.autoDispose
    .family<VoiceSpeakingNotifier, Set<String>, String>(
  (ref, sessionId) => VoiceSpeakingNotifier(SocketService()),
);

class VoiceSpeakingNotifier extends StateNotifier<Set<String>> {
  VoiceSpeakingNotifier(this._socket) : super(const <String>{}) {
    _sub = _socket.onVoiceSpeaking.listen(_onEvent);
  }

  final SocketService _socket;
  StreamSubscription<Map<String, dynamic>>? _sub;

  void _onEvent(Map<String, dynamic> data) {
    final userId = data['userId'] as String? ?? '';
    if (userId.isEmpty) return;
    final isSpeaking = data['isSpeaking'] as bool? ?? false;

    if (isSpeaking) {
      if (state.contains(userId)) return;
      state = {...state, userId};
    } else {
      if (!state.contains(userId)) return;
      final next = Set<String>.from(state)..remove(userId);
      state = next;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
