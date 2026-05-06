import 'dart:async';

import 'package:flutter/material.dart';

import '../../fantasy_wars_design_tokens.dart';
import '../fw_duel_atoms.dart';
import '../fw_duel_class_catalog.dart';
import 'duel_game_shared.dart';

class ReactionTimeGame extends StatefulWidget {
  const ReactionTimeGame({
    super.key,
    required this.onSubmit,
    required this.signalDelayMs,
  });

  final DuelSubmitCallback onSubmit;
  final int signalDelayMs;

  @override
  State<ReactionTimeGame> createState() => _ReactionTimeGameState();
}

class _ReactionTimeGameState extends State<ReactionTimeGame>
    with SingleTickerProviderStateMixin {
  final Stopwatch _stopwatch = Stopwatch();

  _ReactionPhase _phase = _ReactionPhase.ready;
  Timer? _signalTimer;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  int? _reactionMs;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pulseAnimation = Tween<double>(begin: 1, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _scheduleSignal();
  }

  void _scheduleSignal() {
    _signalTimer = Timer(
      Duration(milliseconds: widget.signalDelayMs),
      () {
        if (!mounted) {
          return;
        }
        _stopwatch
          ..reset()
          ..start();
        _pulseController.repeat(reverse: true);
        setState(() {
          _phase = _ReactionPhase.signal;
        });
      },
    );
  }

  void _submitFalseStart() {
    _signalTimer?.cancel();
    _pulseController.stop();
    setState(() {
      _phase = _ReactionPhase.done;
      _reactionMs = 9999;
    });
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        widget.onSubmit({'reactionMs': 9999});
      }
    });
  }

  void _submitReaction() {
    _stopwatch.stop();
    _pulseController.stop();
    final reactionMs = _stopwatch.elapsedMilliseconds;
    setState(() {
      _phase = _ReactionPhase.done;
      _reactionMs = reactionMs;
    });
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        widget.onSubmit({'reactionMs': reactionMs});
      }
    });
  }

  void _handleTap() {
    switch (_phase) {
      case _ReactionPhase.ready:
        _submitFalseStart();
        break;
      case _ReactionPhase.signal:
        _submitReaction();
        break;
      case _ReactionPhase.done:
        break;
    }
  }

  @override
  void dispose() {
    _signalTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFalseStart = _reactionMs == 9999;
    if (_phase == _ReactionPhase.ready) {
      return _buildWait();
    }
    if (_phase == _ReactionPhase.signal) {
      return _buildStrike(reactionMs: null);
    }
    return isFalseStart
        ? _buildEarly()
        : _buildStrike(reactionMs: _reactionMs);
  }

  // bg #1A1D26 + 거대 serif WAIT... + 단검 SVG opacity 0.3.
  Widget _buildWait() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _handleTap(),
      child: ColoredBox(
        color: const Color(0xFF1A1D26),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FwPill(
                      text: 'ASSASSIN',
                      bg: Colors.white.withValues(alpha: 0.08),
                      color: Colors.white.withValues(alpha: 0.7),
                      prefix: const FwClassEmblem(
                        kind: FwClassEmblemKind.dagger,
                        color: Colors.white,
                        size: 12,
                        stroke: 2,
                      ),
                    ),
                    FwMono(
                      text: 'SILENT · 신호 대기',
                      size: 11,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: 0.3,
                          child: SizedBox(
                            width: 140,
                            height: 60,
                            child: CustomPaint(
                              painter: _CrossedDaggersPainter(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FwSerifText(
                          text: 'WAIT...',
                          size: 56,
                          weight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.4),
                          letterSpacing: 4,
                        ),
                        const SizedBox(height: 14),
                        FwMono(
                          text: '신호가 오기 전에 누르면 패배',
                          size: 11,
                          color: Colors.white.withValues(alpha: 0.35),
                          letterSpacing: 1.6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // bg ink900 + radial gold glow + 거대 serif STRIKE! 92px white.
  Widget _buildStrike({int? reactionMs}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _handleTap(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: FwColors.ink900),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  FwColors.teamGold.withValues(alpha: 0.4),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.6],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: _phase == _ReactionPhase.signal
                        ? _pulseAnimation
                        : const AlwaysStoppedAnimation(1),
                    child: const FwSerifText(
                      text: 'STRIKE!',
                      size: 92,
                      weight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 4,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FwMono(
                    text: reactionMs == null
                        ? '화면을 즉시 탭하라'
                        : 'PERFECT · ${reactionMs}ms',
                    size: 12,
                    color: Colors.white,
                    letterSpacing: 1.6,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // bg #2A0B0B + 거대 serif TOO EARLY 64px white + warn 캡션.
  Widget _buildEarly() {
    return ColoredBox(
      color: const Color(0xFF2A0B0B),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FwSerifText(
                text: 'TOO EARLY',
                size: 64,
                weight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 2,
              ),
              const SizedBox(height: 10),
              const FwMono(
                text: '너무 성급했다 · 패배',
                size: 11,
                color: FwColors.danger,
                letterSpacing: 1.6,
              ),
              const SizedBox(height: 22),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(FwRadii.sm),
                ),
                child: FwMono(
                  text: '반응 시간: 신호 전 입력',
                  size: 11,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ReactionPhase { ready, signal, done }

class _CrossedDaggersPainter extends CustomPainter {
  _CrossedDaggersPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    // 좌측 단검 (M10 40h45l8-8 / M10 40h45l8 8) 140x80 viewBox scale.
    final scale = size.width / 140;
    final left = Path()
      ..moveTo(10 * scale, 40 * scale)
      ..lineTo(55 * scale, 40 * scale)
      ..lineTo(63 * scale, 32 * scale)
      ..moveTo(10 * scale, 40 * scale)
      ..lineTo(55 * scale, 40 * scale)
      ..lineTo(63 * scale, 48 * scale);
    canvas.drawPath(left, stroke);
    final right = Path()
      ..moveTo(130 * scale, 40 * scale)
      ..lineTo(85 * scale, 40 * scale)
      ..lineTo(77 * scale, 32 * scale)
      ..moveTo(130 * scale, 40 * scale)
      ..lineTo(85 * scale, 40 * scale)
      ..lineTo(77 * scale, 48 * scale);
    canvas.drawPath(right, stroke);
  }

  @override
  bool shouldRepaint(covariant _CrossedDaggersPainter old) => old.color != color;
}
