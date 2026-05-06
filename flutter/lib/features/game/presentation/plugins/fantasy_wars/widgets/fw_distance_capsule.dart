import 'package:flutter/material.dart';

import '../fantasy_wars_design_tokens.dart';

// 지도 마커용 거리 라벨 캡슐. NOverlayImage.fromWidget 으로 비트맵화하여 사용.
class FwDistanceCapsule extends StatelessWidget {
  const FwDistanceCapsule({super.key, required this.distanceMeters});

  final double distanceMeters;

  @override
  Widget build(BuildContext context) {
    final label = distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(1)}km'
        : '${distanceMeters.round()}m';
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: FwColors.cardSurface,
          borderRadius: BorderRadius.circular(FwRadii.pill),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: FwText.mono.copyWith(color: FwColors.ink900),
        ),
      ),
    );
  }
}
