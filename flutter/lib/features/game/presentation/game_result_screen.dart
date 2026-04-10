// lib/features/game/presentation/game_result_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class GameResultScreen extends ConsumerWidget {
  const GameResultScreen({
    super.key,
    required this.sessionId,
    required this.winner,
  });
  final String sessionId;
  final String winner; // 'crew' | 'impostor'

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCrewWin = winner == 'crew';

    return Scaffold(
      backgroundColor: isCrewWin ? Colors.blue.shade900 : Colors.red.shade900,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isCrewWin ? '🎉' : '😈',
                style: const TextStyle(fontSize: 80),
              ),
              const SizedBox(height: 24),
              Text(
                isCrewWin ? '크루원 승리!' : '임포스터 승리!',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () => context.go('/'),
                child: const Text('로비로 돌아가기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
