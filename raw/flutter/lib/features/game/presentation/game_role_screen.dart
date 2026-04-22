// lib/features/game/presentation/game_role_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/game_models.dart';
import '../providers/game_provider.dart';

class GameRoleScreen extends ConsumerStatefulWidget {
  const GameRoleScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<GameRoleScreen> createState() => _GameRoleScreenState();
}

class _GameRoleScreenState extends ConsumerState<GameRoleScreen> {
  // 한 번 예약되면 절대 다시 예약하지 않음
  bool _returnScheduled = false;

  @override
  void initState() {
    super.initState();
    // 화면이 마운트될 때 이미 역할이 배정된 상태라면 즉시 복귀 타이머 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final role = ref.read(gameProvider(widget.sessionId)).myRole;
      if (role != null) _scheduleReturn();
    });
  }

  void _scheduleReturn() {
    if (_returnScheduled) return;
    _returnScheduled = true;
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        // ignore: use_build_context_synchronously
        context.go('/game/${widget.sessionId}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameProvider(widget.sessionId));

    // 역할이 배정되면 복귀 타이머 시작 (build 안에서는 예약만, 실제 로직은 _scheduleReturn)
    ref.listen<AmongUsGameState>(
      gameProvider(widget.sessionId),
      (_, next) {
        if (next.myRole != null) _scheduleReturn();
      },
    );

    final isImpostor = gameState.myRole?.isImpostor ?? false;
    final bgColor = gameState.myRole == null
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
            isImpostor ? '임포스터' : '크루원',
            style: TextStyle(
              color: isImpostor ? Colors.red.shade200 : Colors.green.shade200,
              fontSize: 64,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 24),
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
