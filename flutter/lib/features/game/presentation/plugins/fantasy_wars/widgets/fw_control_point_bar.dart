import 'package:flutter/material.dart';

import '../../../../providers/fantasy_wars_provider.dart';
import '../fantasy_wars_design_tokens.dart';
import '../fantasy_wars_hud.dart';

// ─── Layer 3: 점령지 5개를 한 줄에 모두 노출 + 탭 시 상세 패널 ─────────────
//
// 이전 구현(PageView 슬라이더) 은 화면 폭 전체를 차지해 지도 드래그/줌 제스처를
// 가로채는 문제가 있었다. 새 구조는 카드 5개를 가로 한 줄에 모두 보여주고
// (전체 폭의 일부만 차지), 탭 시 그 위에 상세 정보 패널을 띄운다.
class FwControlPointBar extends StatelessWidget {
  const FwControlPointBar({
    super.key,
    required this.controlPoints,
    required this.myGuildId,
    required this.guilds,
    required this.bottomOffset,
    required this.barHeight,
    required this.selectedControlPointId,
    required this.onFocusChanged,
    this.onDismiss,
  });

  final List<FwControlPoint> controlPoints;
  final String? myGuildId;
  final Map<String, FwGuildInfo> guilds;
  final double bottomOffset;
  // 칩 한 줄의 높이. 상세 카드는 칩 위로 올라가며 별도 공간을 차지한다.
  final double barHeight;
  final String? selectedControlPointId;
  final ValueChanged<FwControlPoint> onFocusChanged;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    if (controlPoints.isEmpty) {
      return const SizedBox.shrink();
    }

    FwControlPoint? selected;
    if (selectedControlPointId != null) {
      for (final cp in controlPoints) {
        if (cp.id == selectedControlPointId) {
          selected = cp;
          break;
        }
      }
    }

    return Positioned(
      left: 8,
      right: 8,
      bottom: bottomOffset,
      // 점령지 카드의 진행률/봉쇄 표시는 빈번히 변하지만 다른 HUD 와 독립적이라
      // 부모 rebuild 가 trans-paint 로 번지지 않도록 raster 캐시를 분리한다.
      child: RepaintBoundary(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 상세 카드는 선택 시에만 표시되고 칩 위로 부드럽게 펼쳐진다.
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.bottomCenter,
              child: selected == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _ControlPointDetailCard(
                        cp: selected,
                        myGuildId: myGuildId,
                        guilds: guilds,
                        onClose: onDismiss,
                      ),
                    ),
            ),
            SizedBox(
              height: barHeight,
              child: Row(
                children: [
                  for (final cp in controlPoints)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _ControlPointChip(
                          cp: cp,
                          myGuildId: myGuildId,
                          isSelected: cp.id == selectedControlPointId,
                          onTap: () => onFocusChanged(cp),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 칩: 항상 5개 노출. 좁은 폭에 핵심 상태(점령/봉쇄/중립)만 색으로 전달.
class _ControlPointChip extends StatelessWidget {
  const _ControlPointChip({
    required this.cp,
    required this.myGuildId,
    required this.isSelected,
    required this.onTap,
  });

  final FwControlPoint cp;
  final String? myGuildId;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final owned = cp.capturedBy != null;
    final isMine = cp.capturedBy == myGuildId;
    final ownerColor = guildColor(cp.capturedBy);
    final capturingColor = guildColor(cp.capturingGuild);

    Color accent;
    if (cp.isBlockaded) {
      accent = const Color(0xFFEF4444);
    } else if (owned) {
      accent = ownerColor;
    } else if (cp.capturingGuild != null) {
      accent = capturingColor;
    } else {
      accent = const Color(0xFF94A3B8);
    }

    final captureRatio = (cp.captureProgress / 100).clamp(0.0, 1.0);
    final showCaptureBar = !cp.isBlockaded &&
        (cp.capturingGuild != null || cp.captureProgress > 0 || owned);

    final borderColor =
        isSelected ? accent : (isMine ? FwColors.teamGold : FwColors.hairline);
    final borderWidth = isSelected ? 2.0 : (isMine ? 1.5 : 1.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FwRadii.sm),
        child: Container(
          decoration: BoxDecoration(
            color: FwColors.cardSurface,
            borderRadius: BorderRadius.circular(FwRadii.sm),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: isSelected ? FwShadows.card : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_rounded, size: 12, color: accent),
                  if (isMine) ...[
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.star_rounded,
                      size: 10,
                      color: FwColors.teamGold,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                cp.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: FwText.caption.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: FwColors.ink700,
                ),
              ),
              const SizedBox(height: 3),
              if (cp.isBlockaded)
                _ChipPill(
                  // 봉쇄 잔여 시간을 칩에서 바로 읽을 수 있게 mm:ss 표기. 만료 직전엔
                  // 곧 풀린다는 인상을 주기 위해 0초도 그대로 표시한다.
                  label: _formatBlockadeRemainingShort(cp.blockadeExpiresAt),
                  color: const Color(0xFF991B1B),
                  bg: const Color(0xFFFEE2E2),
                )
              else if (showCaptureBar)
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 3,
                    child: Stack(
                      children: [
                        Container(color: FwColors.line2),
                        FractionallySizedBox(
                          widthFactor: owned ? 1.0 : captureRatio,
                          child: Container(color: accent),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipPill extends StatelessWidget {
  const _ChipPill({
    required this.label,
    required this.color,
    required this.bg,
  });

  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}

// 상세 카드: 칩 탭 시 그 위로 펼쳐진다. 우상단 × 닫기 버튼 제공.
class _ControlPointDetailCard extends StatelessWidget {
  const _ControlPointDetailCard({
    required this.cp,
    required this.myGuildId,
    required this.guilds,
    required this.onClose,
  });

  final FwControlPoint cp;
  final String? myGuildId;
  final Map<String, FwGuildInfo> guilds;
  final VoidCallback? onClose;

  String _guildLabel(String? guildId) {
    if (guildId == null) return '중립';
    return guilds[guildId]?.displayName ?? guildId;
  }

  @override
  Widget build(BuildContext context) {
    final owned = cp.capturedBy != null;
    final isMine = cp.capturedBy == myGuildId;
    final ownerColor = guildColor(cp.capturedBy);
    final capturingColor = guildColor(cp.capturingGuild);
    final hasCoords = cp.lat != null && cp.lng != null;

    final Color accent;
    final String stateLabel;
    final Color pillBg;
    final Color pillText;

    if (cp.isBlockaded) {
      accent = const Color(0xFFEF4444);
      stateLabel = '봉쇄';
      pillBg = const Color(0xFFFEE2E2);
      pillText = const Color(0xFF991B1B);
    } else if (owned) {
      accent = ownerColor;
      stateLabel = isMine ? '아군 점령' : '점령됨';
      pillBg = ownerColor.withValues(alpha: 0.18);
      pillText = _darken(ownerColor, 0.25);
    } else if (cp.capturingGuild != null) {
      accent = capturingColor;
      stateLabel = '점령 중';
      pillBg = capturingColor.withValues(alpha: 0.18);
      pillText = _darken(capturingColor, 0.25);
    } else {
      accent = const Color(0xFF94A3B8);
      stateLabel = '중립';
      pillBg = const Color(0xFFF1F5F9);
      pillText = const Color(0xFF475569);
    }

    final readyRatio = cp.requiredCount > 0
        ? (cp.readyCount / cp.requiredCount).clamp(0.0, 1.0)
        : 0.0;
    final captureRatio = (cp.captureProgress / 100).clamp(0.0, 1.0);
    final showCaptureBar = !cp.isBlockaded &&
        (cp.capturingGuild != null || cp.captureProgress > 0 || owned);
    final blockadeRemaining = _blockadeRemaining(cp);

    return Container(
      decoration: BoxDecoration(
        color: FwColors.cardSurface,
        borderRadius: BorderRadius.circular(FwRadii.md),
        border: Border.all(
          color: isMine ? FwColors.teamGold : FwColors.hairline,
          width: isMine ? 2 : 1,
        ),
        boxShadow: FwShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FwRadii.md),
        child: Row(
          children: [
            SizedBox(
              width: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: accent.withValues(alpha: 0.28)),
                  if (cp.requiredCount > 0)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: readyRatio,
                        child: Container(color: accent),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_rounded, size: 16, color: accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            cp.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FwText.title.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isMine)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: FwColors.teamGold,
                            ),
                          ),
                        if (hasCoords)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.center_focus_strong_rounded,
                              size: 12,
                              color: FwColors.ink500,
                            ),
                          ),
                        const SizedBox(width: 6),
                        _StatePill(
                          label: stateLabel,
                          bg: pillBg,
                          text: pillText,
                        ),
                        if (onClose != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: InkWell(
                              onTap: onClose,
                              borderRadius: BorderRadius.circular(999),
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: FwColors.ink500,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _OwnerCapturingRow(
                      ownerLabel: owned ? _guildLabel(cp.capturedBy) : '중립',
                      ownerColor: owned ? ownerColor : FwColors.ink500,
                      capturingLabel: cp.capturingGuild != null
                          ? _guildLabel(cp.capturingGuild)
                          : null,
                      capturingColor: capturingColor,
                      readyCount: cp.readyCount,
                      requiredCount: cp.requiredCount,
                    ),
                    const SizedBox(height: 6),
                    if (cp.isBlockaded)
                      _BlockadeRow(
                        actorLabel: cp.blockadedBy != null
                            ? _guildLabel(cp.blockadedBy)
                            : null,
                        remaining: blockadeRemaining,
                      )
                    else if (showCaptureBar)
                      _CaptureProgressBar(
                        ratio: owned ? 1.0 : captureRatio,
                        color: accent,
                        labelText: owned
                            ? '점령 완료'
                            : '점령 ${(captureRatio * 100).round()}%',
                      )
                    else
                      const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Duration? _blockadeRemaining(FwControlPoint cp) {
    final exp = cp.blockadeExpiresAt;
    if (exp == null) return null;
    final ms = exp - DateTime.now().millisecondsSinceEpoch;
    if (ms <= 0) return Duration.zero;
    return Duration(milliseconds: ms);
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({
    required this.label,
    required this.bg,
    required this.text,
  });

  final String label;
  final Color bg;
  final Color text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}

class _OwnerCapturingRow extends StatelessWidget {
  const _OwnerCapturingRow({
    required this.ownerLabel,
    required this.ownerColor,
    required this.capturingLabel,
    required this.capturingColor,
    required this.readyCount,
    required this.requiredCount,
  });

  final String ownerLabel;
  final Color ownerColor;
  final String? capturingLabel;
  final Color capturingColor;
  final int readyCount;
  final int requiredCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.flag_rounded, size: 12, color: FwColors.ink500),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            ownerLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FwText.caption.copyWith(
              color: ownerColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (capturingLabel != null) ...[
          const SizedBox(width: 6),
          Icon(Icons.swap_horiz_rounded, size: 12, color: capturingColor),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              capturingLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FwText.caption.copyWith(
                color: capturingColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const Spacer(),
        if (requiredCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: FwColors.line2,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.group_rounded,
                    size: 11, color: FwColors.ink500),
                const SizedBox(width: 3),
                Text(
                  '$readyCount/$requiredCount',
                  style: FwText.mono.copyWith(color: FwColors.ink700),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CaptureProgressBar extends StatelessWidget {
  const _CaptureProgressBar({
    required this.ratio,
    required this.color,
    required this.labelText,
  });

  final double ratio;
  final Color color;
  final String labelText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(height: 6, color: FwColors.line2),
              FractionallySizedBox(
                widthFactor: ratio,
                child: Container(height: 6, color: color),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          labelText,
          style: FwText.caption.copyWith(
            color: FwColors.ink500,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _BlockadeRow extends StatelessWidget {
  const _BlockadeRow({required this.actorLabel, required this.remaining});

  final String? actorLabel;
  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    final remainingText = _formatDuration(remaining);
    return Row(
      children: [
        const Icon(Icons.block_rounded, size: 13, color: Color(0xFFB91C1C)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            actorLabel != null ? '$actorLabel 봉쇄' : '봉쇄 중',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FwText.caption.copyWith(
              color: const Color(0xFF991B1B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (remainingText != null) ...[
          const Spacer(),
          Text(
            '잔여 $remainingText',
            style: FwText.mono.copyWith(color: const Color(0xFF991B1B)),
          ),
        ],
      ],
    );
  }

  static String? _formatDuration(Duration? d) {
    if (d == null) return null;
    final totalSec = d.inSeconds;
    if (totalSec <= 0) return '00:00';
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

Color _darken(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}

// 칩 안 봉쇄 pill 에 들어갈 짧은 잔여 시간 라벨. 만료 시각이 없거나 이미 지난
// 경우엔 '봉쇄' 텍스트만 노출해 풀리기 직전 깜박임을 줄인다.
String _formatBlockadeRemainingShort(int? expiresAt) {
  if (expiresAt == null) return '봉쇄';
  final ms = expiresAt - DateTime.now().millisecondsSinceEpoch;
  if (ms <= 0) return '봉쇄';
  final totalSec = (ms / 1000).ceil();
  if (totalSec >= 60) {
    return '봉쇄 ${(totalSec / 60).ceil()}m';
  }
  return '봉쇄 ${totalSec}s';
}
