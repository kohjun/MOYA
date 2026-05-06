import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../fantasy_wars_design_tokens.dart';
import '../fw_duel_atoms.dart';
import '../fw_duel_class_catalog.dart';
import 'duel_game_shared.dart';

class PrecisionGame extends StatefulWidget {
  const PrecisionGame({
    super.key,
    required this.onSubmit,
    required this.targets,
  });

  final DuelSubmitCallback onSubmit;
  final List<Offset> targets;

  @override
  State<PrecisionGame> createState() => _PrecisionGameState();
}

class _PrecisionGameState extends State<PrecisionGame>
    with SingleTickerProviderStateMixin {
  final List<Map<String, double>> _submittedHits = [];
  final List<Offset> _hitMarkers = [];

  late final AnimationController _pulseController;
  Size _canvasSize = Size.zero;

  Offset get _currentTarget {
    if (widget.targets.isEmpty) {
      return Offset.zero;
    }
    final lastIndex = widget.targets.length - 1;
    final targetIndex = min(_submittedHits.length, lastIndex);
    return widget.targets[targetIndex];
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  void _handleTap(TapDownDetails details) {
    if (_submittedHits.length >= widget.targets.length || _canvasSize == Size.zero) {
      return;
    }

    final localPosition = details.localPosition;
    final normalizedX =
        (localPosition.dx / _canvasSize.width).clamp(0.0, 1.0).toDouble();
    final normalizedY =
        (localPosition.dy / _canvasSize.height).clamp(0.0, 1.0).toDouble();

    setState(() {
      _submittedHits.add({'x': normalizedX, 'y': normalizedY});
      _hitMarkers.add(localPosition);
    });

    if (_submittedHits.length == widget.targets.length) {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          widget.onSubmit({'hits': _submittedHits});
        }
      });
    }
  }

  Offset _toCanvasOffset(Offset normalized) {
    return Offset(
      normalized.dx * _canvasSize.width,
      normalized.dy * _canvasSize.height,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = FwDuelClasses.of(FwDuelClass.archer).accent;
    final soft = FwDuelClasses.of(FwDuelClass.archer).soft;
    return ColoredBox(
      color: const Color(0xFFEAEFE7),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FwPill(
                    text: 'ARCHER',
                    bg: FwColors.cardSurface,
                    color: FwColors.ink700,
                    prefix: FwClassEmblem(
                      kind: FwClassEmblemKind.bow,
                      color: accent,
                      size: 12,
                      stroke: 2,
                    ),
                  ),
                  FwMono(
                    text:
                        '${min(_submittedHits.length + 1, widget.targets.length)} / ${widget.targets.length} 발',
                    size: 11,
                    color: FwColors.ink500,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: FwColors.cardSurface,
                  borderRadius: BorderRadius.circular(FwRadii.md),
                  border: Border.all(color: FwColors.hairline),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const FwMono(
                      text: 'TARGET',
                      size: 10,
                      color: FwColors.ink500,
                      letterSpacing: 1.4,
                    ),
                    FwMono(
                      text: '정중앙에 가까울수록 우위',
                      size: 11,
                      color: accent,
                      weight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _canvasSize = constraints.biggest;
                    final targetPosition = _toCanvasOffset(_currentTarget);
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: _handleTap,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ColoredBox(color: soft),
                            ),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _ArcherTargetRingsPainter(
                                  accent: accent,
                                  soft: soft,
                                ),
                              ),
                            ),
                            for (final marker in _hitMarkers)
                              Positioned(
                                left: marker.dx - 6,
                                top: marker.dy - 6,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: accent,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                final radius =
                                    28 + (_pulseController.value * 10);
                                return Positioned(
                                  left: targetPosition.dx - radius,
                                  top: targetPosition.dy - radius,
                                  child: IgnorePointer(
                                    child: Container(
                                      width: radius * 2,
                                      height: radius * 2,
                                      decoration: BoxDecoration(
                                        color:
                                            accent.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: accent,
                                          width: 2.5,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.add,
                                        color: accent,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            if (_submittedHits.length ==
                                widget.targets.length)
                              Positioned.fill(
                                child: ColoredBox(
                                  color:
                                      Colors.black.withValues(alpha: 0.55),
                                  child: const Center(
                                    child: Text(
                                      '결과를 전송하는 중',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArcherTargetRingsPainter extends CustomPainter {
  _ArcherTargetRingsPainter({required this.accent, required this.soft});

  final Color accent;
  final Color soft;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = min(size.width, size.height) * 0.42;
    final radii = <double>[maxR, maxR * 0.78, maxR * 0.56, maxR * 0.34, 6];
    for (var i = 0; i < radii.length; i++) {
      final paint = Paint()
        ..color = i.isOdd ? FwColors.cardSurface : soft
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radii[i], paint);
      final stroke = Paint()
        ..color = accent.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(center, radii[i], stroke);
    }
    final bullseye = Paint()..color = accent;
    canvas.drawCircle(center, 4, bullseye);
  }

  @override
  bool shouldRepaint(covariant _ArcherTargetRingsPainter old) =>
      old.accent != accent || old.soft != soft;
}
