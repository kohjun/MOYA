import 'package:flutter/material.dart';

import '../fantasy_wars_design_tokens.dart';

/// Fantasy Wars 화면 우상단에 작게 띄우는 음성 상태 칩.
///
/// - 마이크 on/off 아이콘 + 현재 voice channel 라벨
/// - `isSelfSpeaking == true` 일 때 외곽 ring + 작은 dot 으로 발화 표시
/// - `isReady == false` 면 opacity 낮추고 탭 비활성
///
/// 펄스 애니메이션이나 큰 시각 효과는 의도적으로 생략 — 마커 영역의
/// speaking ring 과 시각적 충돌 없이 보조 표시 역할만.
class FwVoiceChip extends StatelessWidget {
  const FwVoiceChip({
    super.key,
    required this.isMuted,
    required this.isSelfSpeaking,
    required this.isReady,
    required this.channelLabel,
    required this.channelColor,
    required this.onTap,
  });

  final bool isMuted;
  final bool isSelfSpeaking;
  final bool isReady;
  final String channelLabel;
  final Color channelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = isMuted ? FwColors.danger : FwColors.ink900;
    final iconData =
        isMuted ? Icons.mic_off_rounded : Icons.mic_rounded;
    final ringActive = isSelfSpeaking && !isMuted && isReady;

    return Opacity(
      opacity: isReady ? 1.0 : 0.5,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(FwRadii.pill),
        child: InkWell(
          onTap: isReady ? onTap : null,
          borderRadius: BorderRadius.circular(FwRadii.pill),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: FwColors.cardSurface,
              borderRadius: BorderRadius.circular(FwRadii.pill),
              border: Border.all(
                color: ringActive ? channelColor : FwColors.hairline,
                width: ringActive ? 2 : 1,
              ),
              boxShadow: ringActive
                  ? [
                      BoxShadow(
                        color: channelColor.withValues(alpha: 0.45),
                        blurRadius: 6,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : FwShadows.card,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(iconData, color: iconColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  channelLabel,
                  style: FwText.caption.copyWith(
                    color: channelColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (ringActive) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: channelColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
