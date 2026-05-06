import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../fantasy_wars_design_tokens.dart';
import '../fw_duel_atoms.dart';
import '../fw_duel_class_catalog.dart';
import 'duel_game_shared.dart';

class RapidTapGame extends StatefulWidget {
  const RapidTapGame({
    super.key,
    required this.onSubmit,
    this.durationSec = 5,
  });

  final DuelSubmitCallback onSubmit;
  final int durationSec;

  @override
  State<RapidTapGame> createState() => _RapidTapGameState();
}

class _RapidTapGameState extends State<RapidTapGame>
    with SingleTickerProviderStateMixin {
  int _tapCount = 0;
  int _remainingMs = 0;
  int _startedAtMs = 0;
  bool _started = false;
  bool _submitted = false;

  Timer? _ticker;
  late final AnimationController _tapAnimationController;

  @override
  void initState() {
    super.initState();
    _remainingMs = widget.durationSec * 1000;
    _tapAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
  }

  void _startIfNeeded() {
    if (_started) {
      return;
    }

    _started = true;
    _startedAtMs = DateTime.now().millisecondsSinceEpoch;
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - _startedAtMs;
      final remaining = widget.durationSec * 1000 - elapsed;
      if (!mounted) {
        return;
      }
      if (remaining <= 0) {
        _finish();
        return;
      }
      setState(() {
        _remainingMs = remaining;
      });
    });
  }

  void _handleTap() {
    if (_submitted) {
      return;
    }

    _startIfNeeded();
    _tapAnimationController.forward(from: 0);
    setState(() {
      _tapCount += 1;
    });
  }

  void _finish() {
    if (_submitted) {
      return;
    }

    _ticker?.cancel();
    _submitted = true;
    final durationMs = _started
        ? DateTime.now().millisecondsSinceEpoch - _startedAtMs
        : widget.durationSec * 1000;
    setState(() {
      _remainingMs = 0;
    });
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (mounted) {
        widget.onSubmit({
          'tapCount': _tapCount,
          'durationMs': max(durationMs, 1),
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tapAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = FwDuelClasses.of(FwDuelClass.warrior).accent;
    final progress = widget.durationSec == 0
        ? 0.0
        : (_remainingMs / (widget.durationSec * 1000))
            .clamp(0.0, 1.0)
            .toDouble();
    final elapsedSec = _started
        ? ((widget.durationSec * 1000 - _remainingMs) / 1000).clamp(0.001, 10.0)
        : 0.001;
    final tps = _started ? (_tapCount / elapsedSec) : 0;
    final berserk = tps >= 8;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _handleTap(),
      child: ColoredBox(
        color: const Color(0xFFF5EFEC),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FwMono(
                          text: '나',
                          size: 9.5,
                          color: FwColors.ink500,
                          letterSpacing: 1.4,
                        ),
                        Text(
                          '$_tapCount',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontFamilyFallback: const [
                              'RobotoMono',
                              'Menlo',
                              'Consolas',
                            ],
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                            color: accent,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FwMono(
                          text: '상대',
                          size: 9.5,
                          color: FwColors.ink500,
                          letterSpacing: 1.4,
                        ),
                        Text(
                          '?',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontFamilyFallback: [
                              'RobotoMono',
                              'Menlo',
                              'Consolas',
                            ],
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                            color: FwColors.ink700,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const FwMono(text: 'TIME', size: 10, color: FwColors.ink500),
                    FwMono(
                      text:
                          '${(_remainingMs / 1000).toStringAsFixed(1)}s',
                      size: 10,
                      color: accent,
                      weight: FontWeight.w700,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(FwRadii.pill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: FwColors.line2,
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Stack(
                    children: [
                      // Tap zone with radial gradient and slash decorations.
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: FwColors.hairline),
                            gradient: const RadialGradient(
                              colors: [FwColors.cardSurface, Color(0xFFECDFD9)],
                              stops: [0.0, 1.0],
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: CustomPaint(
                              painter: _WarriorSlashPainter(accent: accent),
                            ),
                          ),
                        ),
                      ),
                      if (berserk)
                        Positioned(
                          top: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: FwPill(
                              text: 'BERSERK · 8 TPS',
                              bg: accent,
                              color: Colors.white,
                              prefix: const Text(
                                '⚡',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: FwMono(
                            text: _started
                                ? 'TAP ANYWHERE · 검을 휘둘러라'
                                : 'TAP ANYWHERE · 시작하려면 탭',
                            size: 11,
                            color: FwColors.ink500,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                      if (_submitted)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: Colors.black.withValues(alpha: 0.45),
                            ),
                            child: const Center(
                              child: Text(
                                '결과를 전송하는 중',
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WarriorSlashPainter extends CustomPainter {
  _WarriorSlashPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    // dummy silhouette (opacity 0.18)
    final body = Paint()..color = FwColors.ink900.withValues(alpha: 0.18);
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy - 60), width: 44, height: 52),
      body,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy - 4), width: 60, height: 90),
        const Radius.circular(14),
      ),
      body,
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx - 8, cy + 70), width: 10, height: 40),
      body,
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx + 8, cy + 70), width: 10, height: 40),
      body,
    );
    // 4 slash lines
    final accentSlash = Paint()
      ..color = accent.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final inkSlash = Paint()
      ..color = FwColors.ink900.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.10, size.height * 0.20),
      Offset(size.width * 0.55, size.height * 0.10),
      accentSlash,
    );
    canvas.drawLine(
      Offset(size.width * 0.18, size.height * 0.55),
      Offset(size.width * 0.62, size.height * 0.46),
      inkSlash,
    );
    canvas.drawLine(
      Offset(size.width * 0.30, size.height * 0.78),
      Offset(size.width * 0.72, size.height * 0.62),
      accentSlash..strokeWidth = 2,
    );
    canvas.drawLine(
      Offset(size.width * 0.55, size.height * 0.18),
      Offset(size.width * 0.92, size.height * 0.34),
      inkSlash..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _WarriorSlashPainter old) => old.accent != accent;
}
