import 'dart:async';

import 'package:flutter/material.dart';

import '../fantasy_wars_design_tokens.dart';

// ─── Layer 2: 우측 전장 정보 패널 (기본 접힘 / 토글 시 확장) ──────────────────
// 던전 / 성유물 보유자 / 추적 대상 / BLE 시그널 / 결투 로그를 한 카드에 모아
// 표시한다. expanded=false 일 때는 헤더만, true 일 때는 행 단위로 펼친다.
//
// 위치는 호출자(우측 utility rail)가 책임진다 — 더 이상 자체 Positioned 로
// 우상단을 점유하지 않는다. Log/나가기/Voice chip/AI/BLE 와 같이 한 컬럼 안에
// 정렬되도록 호출자가 maxWidth 를 ConstrainedBox 로 제한한다.
class FwBattlePanel extends StatelessWidget {
  const FwBattlePanel({
    super.key,
    required this.dungeonLabel,
    required this.relicHolderLabel,
    required this.trackedTargetLabel,
    required this.bleSummary,
    required this.telemetryLabel,
    required this.recentDuelLogs,
    required this.expanded,
    required this.onToggle,
    this.maxExpandedHeight,
    this.gameExpiresAtMs,
  });

  final String dungeonLabel;
  final String? relicHolderLabel;
  final String? trackedTargetLabel;
  final String? bleSummary;
  final String? telemetryLabel;
  final List<String> recentDuelLogs;
  final bool expanded;
  final VoidCallback onToggle;
  // 세션 만료 epoch (ms). null 이면 남은 게임 시간 행을 숨긴다. 1초 단위로
  // 자체 갱신하므로 호출자는 한 번만 넘기면 된다.
  final int? gameExpiresAtMs;
  // expanded 본문이 화면을 너무 길게 덮지 않도록 호출자가 cap 을 넘긴다.
  // 내부 Column 은 maxHeight 안에서 SingleChildScrollView 로 스크롤한다.
  final double? maxExpandedHeight;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topRight,
      curve: Curves.easeOutCubic,
      child: expanded ? _expandedPanel(context) : _collapsedHeader(),
    );
  }

  Widget _collapsedHeader() {
    // AnimatedSize 는 child 에게 unbounded constraints 를 전달한다. Container 의
    // BoxConstraints(maxWidth) 만으론 width 의 tight lower-bound 가 없어 안의
    // Row + Expanded 가 width 를 분배하지 못하고 일부 RenderBox 가 layout 을 건너
    // 뛰어 paint 시 hasSize assertion 이 매 프레임 실패한다. SizedBox 로 폭을
    // 220 으로 고정해 tight constraint 를 강제.
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(FwRadii.lg),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(FwRadii.lg),
        child: SizedBox(
          width: 220,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: FwColors.cardSurface,
              borderRadius: BorderRadius.circular(FwRadii.lg),
              boxShadow: FwShadows.card,
              border: Border.all(color: FwColors.hairline),
            ),
            child: Row(
              children: [
                const Icon(Icons.explore_outlined,
                    color: FwColors.ink700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child:
                      Text('전장 정보', style: FwText.title.copyWith(fontSize: 14)),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: FwColors.ink500, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _expandedPanel(BuildContext context) {
    final cap =
        maxExpandedHeight ?? (MediaQuery.of(context).size.height * 0.55);
    // _collapsedHeader 와 동일 — AnimatedSize 의 unbounded constraints 아래에서
    // Row + Expanded / Wrap / SingleChildScrollView 가 안전히 layout 되도록
    // SizedBox 로 폭을 220 에 고정. 높이는 cap 으로만 제한.
    return SizedBox(
      width: 220,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: cap),
        child: Container(
          decoration: BoxDecoration(
            color: FwColors.cardSurface,
            borderRadius: BorderRadius.circular(FwRadii.lg),
            boxShadow: FwShadows.popover,
            border: Border.all(color: FwColors.hairline),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(FwRadii.lg),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: onToggle,
                    borderRadius: BorderRadius.circular(FwRadii.sm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.explore_outlined,
                              color: FwColors.ink700, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('전장 정보',
                                style: FwText.title.copyWith(fontSize: 14)),
                          ),
                          const Icon(Icons.keyboard_arrow_up_rounded,
                              color: FwColors.ink500, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: FwColors.hairline),
                  const SizedBox(height: 10),
                  if (gameExpiresAtMs != null) ...[
                    // RepaintBoundary 로 1초 ticker setState 가 AnimatedSize / 우측
                    // utility rail 까지 전파되지 않도록 격리. mono 라벨은 `M:SS` 와
                    // `H:MM:SS` 사이에서 폭이 변하므로 행 자체는 자연 폭, 값만 mono.
                    RepaintBoundary(
                      child: _GameRemainingTicker(
                        expiresAtMs: gameExpiresAtMs!,
                        builder: (context, label) => _BattlePanelRow(
                          icon: Icons.timer_outlined,
                          iconColor: FwColors.ink700,
                          label: '남은 게임 시간',
                          value: label,
                          valueColor: FwColors.ink900,
                          mono: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (bleSummary != null)
                    _BattlePanelRow(
                      icon: Icons.bluetooth,
                      iconColor: FwColors.ink700,
                      label: 'BLE 연결',
                      value: bleSummary!,
                      valueColor: FwColors.ink900,
                      mono: true,
                    ),
                  if (telemetryLabel != null) ...[
                    const SizedBox(height: 8),
                    _BattlePanelRow(
                      icon: Icons.satellite_alt_outlined,
                      iconColor: FwColors.ink500,
                      label: '시그널',
                      value: telemetryLabel!,
                      valueColor: FwColors.ink700,
                      mono: true,
                    ),
                  ],
                  const SizedBox(height: 8),
                  _BattlePanelRow(
                    icon: Icons.shield_outlined,
                    iconColor: FwColors.teamRed,
                    label: '던전',
                    value: dungeonLabel,
                    valueColor: FwColors.ink900,
                  ),
                  if (relicHolderLabel != null) ...[
                    const SizedBox(height: 8),
                    _BattlePanelRow(
                      icon: Icons.diamond_outlined,
                      iconColor: FwColors.teamGold,
                      label: '성유물',
                      value: relicHolderLabel!,
                      valueColor: FwColors.teamBlue,
                    ),
                  ],
                  if (trackedTargetLabel != null) ...[
                    const SizedBox(height: 8),
                    _BattlePanelRow(
                      icon: Icons.location_on_outlined,
                      iconColor: FwColors.teamBlue,
                      label: '추적 대상',
                      value: trackedTargetLabel!,
                      valueColor: FwColors.teamBlue,
                    ),
                  ],
                  if (recentDuelLogs.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: FwColors.hairline),
                    const SizedBox(height: 10),
                    Text('결투 판정 로그',
                        style:
                            FwText.label.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    for (final log in recentDuelLogs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          log,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FwText.caption,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 남은 게임 시간을 1초 단위로 갱신하는 작은 위젯. 부모 패널 전체를 매초
// rebuild 하지 않도록 자기 subtree 만 setState 한다. label 형식은
// `H:MM:SS` (1시간 미만이면 `M:SS`).
class _GameRemainingTicker extends StatefulWidget {
  const _GameRemainingTicker({
    required this.expiresAtMs,
    required this.builder,
  });

  final int expiresAtMs;
  final Widget Function(BuildContext context, String label) builder;

  @override
  State<_GameRemainingTicker> createState() => _GameRemainingTickerState();
}

class _GameRemainingTickerState extends State<_GameRemainingTicker> {
  Timer? _timer;
  late int _remainingSec;

  @override
  void initState() {
    super.initState();
    _remainingSec = _computeRemainingSec(widget.expiresAtMs);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = _computeRemainingSec(widget.expiresAtMs);
      if (next != _remainingSec) {
        setState(() => _remainingSec = next);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _GameRemainingTicker old) {
    super.didUpdateWidget(old);
    if (old.expiresAtMs != widget.expiresAtMs) {
      _remainingSec = _computeRemainingSec(widget.expiresAtMs);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static int _computeRemainingSec(int expiresAtMs) {
    final ms = expiresAtMs - DateTime.now().millisecondsSinceEpoch;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _formatRemaining(_remainingSec));
  }
}

String _formatRemaining(int totalSec) {
  if (totalSec <= 0) return '종료';
  final h = totalSec ~/ 3600;
  final m = (totalSec % 3600) ~/ 60;
  final s = totalSec % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) {
    return '$h:$mm:$ss';
  }
  return '$mm:$ss';
}

class _BattlePanelRow extends StatelessWidget {
  const _BattlePanelRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.valueColor,
    this.mono = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color valueColor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FwText.label.copyWith(color: FwColors.ink700),
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: mono
                ? FwText.mono.copyWith(color: valueColor)
                : FwText.label.copyWith(
                    color: valueColor,
                    fontWeight: FontWeight.w600,
                  ),
          ),
        ),
      ],
    );
  }
}
