import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../fantasy_wars_design_tokens.dart';
import 'fw_scale_tap_button.dart';

// ─── Layer 5: 좌측 하단 액션 도크 ───────────────────────────────────────────
// 점령 / 결투 / 던전 세 버튼 모두 항상 표시.
// 활성: opacity 1.0 + 컬러 ring + glow.
// 비활성: opacity 0.4 + 회색조. 탭하면 활성 조건을 toast 로 안내.
class FwActionDock extends StatelessWidget {
  const FwActionDock({
    super.key,
    required this.bottomOffset,
    required this.captureEnabled,
    required this.duelEnabled,
    required this.dungeonEnabled,
    required this.captureLabel,
    required this.onCapture,
    required this.onDuel,
    required this.onDungeon,
    required this.onShowDisabledReason,
    required this.captureDisabledReason,
    required this.duelDisabledReason,
    required this.dungeonDisabledReason,
  });

  final double bottomOffset;
  final bool captureEnabled;
  final bool duelEnabled;
  final bool dungeonEnabled;
  final String captureLabel;
  final VoidCallback onCapture;
  final VoidCallback onDuel;
  final VoidCallback onDungeon;
  final void Function(String reason) onShowDisabledReason;
  final String captureDisabledReason;
  final String duelDisabledReason;
  final String dungeonDisabledReason;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: FwSpace.x8,
      bottom: bottomOffset,
      // 액션 도크는 enabled 토글 / label 변화 등으로 자주 repaint 가 일어나도
      // 지도 PlatformView 영역까지 무효화되지 않도록 raster 캐시를 분리.
      // RepaintBoundary 는 Positioned 의 child 자리에 와야 Stack 의 ParentData
      // 계약을 깨지 않는다.
      child: RepaintBoundary(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionDockButton(
              icon: Icons.flag_rounded,
              label: captureLabel,
              iconColor: FwColors.teamRed,
              enabled: captureEnabled,
              onTap: onCapture,
              onDisabledTap: () => onShowDisabledReason(captureDisabledReason),
            ),
            const SizedBox(height: 10),
            _ActionDockButton(
              icon: Icons.sports_martial_arts_rounded,
              label: '결투 신청',
              iconColor: FwColors.danger,
              enabled: duelEnabled,
              onTap: onDuel,
              onDisabledTap: () => onShowDisabledReason(duelDisabledReason),
              highlightWhenEnabled: true,
            ),
            const SizedBox(height: 10),
            _ActionDockButton(
              icon: Icons.door_front_door_rounded,
              label: '던전 입장',
              iconColor: FwColors.ink700,
              enabled: dungeonEnabled,
              onTap: onDungeon,
              onDisabledTap: () => onShowDisabledReason(dungeonDisabledReason),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionDockButton extends StatelessWidget {
  const _ActionDockButton({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.enabled,
    required this.onTap,
    required this.onDisabledTap,
    this.highlightWhenEnabled = false,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onDisabledTap;
  // true 면 enabled 상태에서 iconColor 톤의 테두리 + soft glow 적용 (CTA 강조).
  final bool highlightWhenEnabled;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = enabled && highlightWhenEnabled;
    return FwScaleTapButton(
      onTap: () {
        if (enabled) {
          HapticFeedback.lightImpact();
          onTap();
        } else {
          HapticFeedback.selectionClick();
          onDisabledTap();
        }
      },
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: FwColors.cardSurface,
                borderRadius: BorderRadius.circular(FwRadii.md),
                boxShadow: isHighlighted
                    ? [
                        BoxShadow(
                          color: iconColor.withValues(alpha: 0.33),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : FwShadows.card,
                border: Border.all(
                  color: isHighlighted ? iconColor : FwColors.hairline,
                  width: isHighlighted ? 1.5 : 1,
                ),
              ),
              child: Icon(
                icon,
                color: enabled ? iconColor : FwColors.ink300,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: FwText.caption.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: enabled ? FwColors.ink900 : FwColors.ink500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
