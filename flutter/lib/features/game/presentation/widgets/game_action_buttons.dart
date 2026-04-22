// lib/features/game/presentation/widgets/game_action_buttons.dart
//
// 모드 플러그인과 game_main_screen에서 공유하는 버튼 위젯들

import 'package:flutter/material.dart';

/// 일반 액션 버튼 (사보타지, 미션, QR, 회의 소집 등)
class GameActionButton extends StatelessWidget {
  const GameActionButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? color : color.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

/// 킬/태그 버튼 (임포스터 전용, 큰 버튼)
class GameKillButton extends StatelessWidget {
  const GameKillButton({
    super.key,
    required this.label,
    required this.cooldown,
    required this.onTap,
  });

  final String label;
  final bool cooldown;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = cooldown
        ? const Color(0xFF7F1D1D).withValues(alpha: 0.55)
        : const Color(0xFF7F1D1D);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(36),
      child: InkWell(
        borderRadius: BorderRadius.circular(36),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// 위치 미션 수행 버튼 (전체 너비, 중앙 배치용)
class GamePillButton extends StatelessWidget {
  const GamePillButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}

/// 소형 정보 칩 (모드 플러그인에서 공통 사용)
class GameInfoChip extends StatelessWidget {
  const GameInfoChip({super.key, required this.label, this.accent = Colors.white});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
