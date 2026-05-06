import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../fantasy_wars_design_tokens.dart';

// ─── Layer 6.5: 결투/부활 타이머 배지 (84x96 우측 하단) ──────────────────────
// 외곽 84 / 내부 72 / danger 채움 / 중앙 흰 아이콘 / 하단 검정 캡슐 mono.
// CustomPainter 로 외곽에 progress 호 그리기.
class FwTimerBadge extends StatefulWidget {
  const FwTimerBadge({
    super.key,
    required this.expiresAtMs,
    required this.totalMs,
    required this.icon,
    required this.bottomOffset,
  });

  final int expiresAtMs;
  final int totalMs;
  final IconData icon;
  final double bottomOffset;

  @override
  State<FwTimerBadge> createState() => _FwTimerBadgeState();
}

class _FwTimerBadgeState extends State<FwTimerBadge>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  int _remainingMs = 0;

  @override
  void initState() {
    super.initState();
    _remainingMs =
        (widget.expiresAtMs - DateTime.now().millisecondsSinceEpoch)
            .clamp(0, widget.totalMs);
    _ticker = createTicker((_) {
      final next = (widget.expiresAtMs - DateTime.now().millisecondsSinceEpoch)
          .clamp(0, widget.totalMs);
      if (next != _remainingMs && mounted) {
        setState(() => _remainingMs = next);
      }
    })
      ..start();
  }

  @override
  void didUpdateWidget(covariant FwTimerBadge old) {
    super.didUpdateWidget(old);
    if (old.expiresAtMs != widget.expiresAtMs ||
        old.totalMs != widget.totalMs) {
      _remainingMs =
          (widget.expiresAtMs - DateTime.now().millisecondsSinceEpoch)
              .clamp(0, widget.totalMs);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        widget.totalMs > 0 ? _remainingMs / widget.totalMs : 0.0;
    final remainingSec = (_remainingMs / 1000).ceil();

    return Positioned(
      right: 16,
      bottom: widget.bottomOffset,
      child: SizedBox(
        width: 84,
        height: 96,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 외곽 progress 호
            Positioned.fill(
              top: 0,
              child: CustomPaint(
                painter: _TimerArcPainter(progress: progress),
              ),
            ),
            // 내부 빨간 원
            Positioned(
              top: 6,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: FwColors.danger,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: FwColors.danger.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(widget.icon, color: Colors.white, size: 30),
              ),
            ),
            // 하단 카운트다운 캡슐
            Positioned(
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(FwRadii.pill),
                ),
                child: Text(
                  '${remainingSec}s',
                  style: FwText.mono.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerArcPainter extends CustomPainter {
  _TimerArcPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    const radius = 42.0;
    final center = Offset(size.width / 2, radius + 2);
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    final bg = Paint()
      ..color = Colors.white.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, bg);

    final fg = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _TimerArcPainter old) =>
      old.progress != progress;
}

// ─── 부활 시도 버튼 (쿨타임 종료 후 노출) ────────────────────────────────────
// 펄스 애니메이션 + 탭 가능. 위치는 FwTimerBadge 와 동일하게 우측 하단.
class FwReviveButton extends StatefulWidget {
  const FwReviveButton({
    super.key,
    required this.bottomOffset,
    required this.chance,
    required this.onTap,
  });

  final double bottomOffset;
  final double chance;
  final VoidCallback onTap;

  @override
  State<FwReviveButton> createState() => _FwReviveButtonState();
}

class _FwReviveButtonState extends State<FwReviveButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = (widget.chance * 100).round();
    return Positioned(
      right: 16,
      bottom: widget.bottomOffset,
      child: SizedBox(
        width: 84,
        height: 96,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 6,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) {
                  final scale = 1.0 + 0.06 * _pulse.value;
                  final glow = 14.0 + 10.0 * _pulse.value;
                  return Transform.scale(
                    scale: scale,
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: widget.onTap,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: FwColors.accentHealth,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: FwColors.accentHealth
                                    .withValues(alpha: 0.55),
                                blurRadius: glow,
                                spreadRadius: 1,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.favorite_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(FwRadii.pill),
                ),
                child: Text(
                  '부활 $pct%',
                  style: FwText.mono.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
