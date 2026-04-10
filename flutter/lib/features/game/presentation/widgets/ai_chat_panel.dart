// lib/features/game/presentation/widgets/ai_chat_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../game/providers/game_provider.dart';
import '../../../game/data/game_models.dart';

class AIChatPanel extends ConsumerStatefulWidget {
  const AIChatPanel({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<AIChatPanel> createState() => _AIChatPanelState();
}

class _AIChatPanelState extends ConsumerState<AIChatPanel> {
  final _controller  = TextEditingController();
  final _scrollCtrl  = ScrollController();
  int _prevLogCount  = 0;

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(gameProvider(widget.sessionId).notifier).askAI(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameProvider(widget.sessionId));
    final logs      = gameState.chatLogs;

    // 새 메시지 도착 시 자동 스크롤
    if (logs.length != _prevLogCount) {
      _prevLogCount = logs.length;
      _scrollToBottom();
    }

    return Container(
      height: 280,
      color: const Color(0xFF0a0a0a),
      child: Column(
        children: [
          // 상단 레이블
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF111111),
            child: const Row(
              children: [
                Text('🤖', style: TextStyle(fontSize: 16)),
                SizedBox(width: 8),
                Text(
                  'AI 진행자',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // 채팅 로그
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: logs.length,
              itemBuilder: (context, index) => _buildLogItem(logs[index]),
            ),
          ),

          // 입력창
          Container(
            color: const Color(0xFF111111),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'AI에게 질문하기...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1a1a1a),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFF00e676),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send,
                        color: Colors.black, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(ChatLog log) {
    switch (log.type) {
      case ChatLogType.aiAnnounce:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1e2a1e),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              log.message,
              style: const TextStyle(color: Color(0xFF69f0ae), fontSize: 13),
            ),
          ),
        );

      case ChatLogType.aiReply:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1e1e2a),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              log.message,
              style: const TextStyle(color: Color(0xFF81d4fa), fontSize: 13),
            ),
          ),
        );

      case ChatLogType.myQuestion:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2a1e1e),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              log.message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        );

      case ChatLogType.system:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              log.message,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        );
    }
  }
}
