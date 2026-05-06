import 'package:flutter/material.dart';

// 선택지 카드 우측 상단의 작은 배지 (예: '필수', '권장').
// soft fill (alpha 16%) + accent border (alpha 60%) + bold accent text.
class FwChoiceBadge extends StatelessWidget {
  const FwChoiceBadge({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
