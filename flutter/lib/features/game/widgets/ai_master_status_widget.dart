import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ai_master_provider.dart';

class AiMasterStatusWidget extends ConsumerWidget {
  const AiMasterStatusWidget({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiMasterProvider(sessionId));

    return switch (state.phase) {
      AiMasterPhase.ok => const SizedBox.shrink(),
      AiMasterPhase.retrying => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.amber),
              ),
              SizedBox(width: 6),
              Text('AI 마스터 재연결 중...',
                  style: TextStyle(fontSize: 12, color: Colors.amber)),
            ],
          ),
        ),
      AiMasterPhase.failed => GestureDetector(
          onTap: () => ref.read(aiMasterProvider(sessionId).notifier).retry(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.shade900.withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_outlined, size: 14, color: Colors.white),
                SizedBox(width: 6),
                Text('AI 마스터 실패  다시 시도',
                    style: TextStyle(fontSize: 12, color: Colors.white)),
                SizedBox(width: 4),
                Icon(Icons.refresh, size: 12, color: Colors.white),
              ],
            ),
          ),
        ),
    };
  }
}
