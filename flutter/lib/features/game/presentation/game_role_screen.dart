// lib/features/game/presentation/game_role_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/game_provider.dart';

class GameRoleScreen extends ConsumerStatefulWidget {
  const GameRoleScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<GameRoleScreen> createState() => _GameRoleScreenState();
}

class _GameRoleScreenState extends ConsumerState<GameRoleScreen> {
  bool _navigated = false;

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameProvider(widget.sessionId));

    // 역할 배정 후 3초 뒤 맵 화면으로 이동
    if (gameState.myRole != null && !_navigated) {
      _navigated = true;
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        // ignore: use_build_context_synchronously
        context.go('/map/${widget.sessionId}');
      });
    }

    final isImpostor = gameState.myRole?.isImpostor ?? false;
    final bgColor    = gameState.myRole == null
        ? const Color(0xFF1a1a2e)
        : isImpostor
            ? Colors.red.shade900
            : Colors.green.shade900;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: gameState.myRole == null
              ? _buildWaiting()
              : _buildRoleCard(isImpostor),
        ),
      ),
    );
  }

  Widget _buildWaiting() => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 24),
          Text(
            '게임 시작 대기 중...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );

  Widget _buildRoleCard(bool isImpostor) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isImpostor ? '😈' : '👨‍🚀',
            style: const TextStyle(fontSize: 80),
          ),
          const SizedBox(height: 24),
          Text(
            isImpostor ? '임포스터' : '크루원',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              isImpostor
                  ? '들키지 말고 크루원을 제거하라!'
                  : '미션을 완수하고 임포스터를 찾아라!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(height: 40),
          const Text(
            '잠시 후 맵 화면으로 이동합니다...',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      );
}
