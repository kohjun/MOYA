import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../providers/fantasy_wars_models.dart';
import '../fantasy_wars_design_tokens.dart';

// ─── 점령 진행 HUD ─────────────────────────────────────────────────────
// 사용자가 자기 길드 깃발로 점령을 시작하면 화면 하단에 30s 짜리 진행 카드가
// 노출된다. 서버는 fw:capture_started 시점에만 startedAt + durationSec 을 emit
// 하므로 클라가 자체 ticker 로 (now - startedAt) / (duration*1000) 비율을 계산한다.
//
// 부모 widget rebuild 와 분리하기 위해 자체 stateful + RepaintBoundary 로 감싸
// 200ms ticker setState 가 HUD 외부 위젯 트리에 전파되지 않도록 했다.
//
// 점령 영역 이탈 / 적 방해 / 완료 시 상위 widget 이 visibility 분기를 끊으면
// 자동 dispose. (cp.capturingGuild != myGuildId || captureStartedAt == null)

class FwCaptureProgressOverlay extends StatefulWidget {
  const FwCaptureProgressOverlay({
    super.key,
    required this.controlPoint,
  });

  final FwControlPoint controlPoint;

  @override
  State<FwCaptureProgressOverlay> createState() =>
      _FwCaptureProgressOverlayState();
}

class _FwCaptureProgressOverlayState extends State<FwCaptureProgressOverlay> {
  Timer? _ticker;
  double _progress = 0;
  int _remainSec = 0;

  @override
  void initState() {
    super.initState();
    _recompute();
    // 200ms — 30s 바를 약 150 프레임으로 채워 부드럽게. 1s ticker 는 stutter.
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      _recompute();
    });
  }

  @override
  void didUpdateWidget(covariant FwCaptureProgressOverlay old) {
    super.didUpdateWidget(old);
    if (old.controlPoint.captureStartedAt !=
            widget.controlPoint.captureStartedAt ||
        old.controlPoint.captureDurationSec !=
            widget.controlPoint.captureDurationSec) {
      _recompute();
    }
  }

  void _recompute() {
    final startedAt = widget.controlPoint.captureStartedAt;
    final durationSec = widget.controlPoint.captureDurationSec ?? 30;
    if (startedAt == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = (now - startedAt).clamp(0, durationSec * 1000);
    final ratio = elapsedMs / (durationSec * 1000);
    final remainMs = (durationSec * 1000) - elapsedMs;
    final remainSec = (remainMs / 1000).ceil().clamp(0, durationSec);
    if ((ratio - _progress).abs() > 0.001 || remainSec != _remainSec) {
      setState(() {
        _progress = ratio.clamp(0.0, 1.0).toDouble();
        _remainSec = remainSec;
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cp = widget.controlPoint;
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: FwColors.cardSurface,
          borderRadius: BorderRadius.circular(FwRadii.lg),
          boxShadow: FwShadows.popover,
          border: Border.all(color: FwColors.teamGold, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.flag_circle_rounded,
                    color: FwColors.teamGold, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '점령 중 · ${cp.displayName}',
                    style: FwText.title.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: FwColors.ink900,
                    ),
                  ),
                ),
                Text(
                  '$_remainSec초',
                  style: FwText.mono.copyWith(
                    fontSize: 12,
                    color: FwColors.danger,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Container(color: FwColors.line2),
                    FractionallySizedBox(
                      widthFactor: _progress,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [FwColors.teamGold, Color(0xFFEAB308)],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '구역을 벗어나면 점령이 취소됩니다',
              style: FwText.caption.copyWith(color: FwColors.ink500),
            ),
          ],
        ),
      ),
    );
  }
}
