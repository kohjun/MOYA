// lib/features/game/presentation/plugins/fantasy_wars/duel/fw_duel_minigames.dart
//
// FW 대결 전용 5종 미니게임 위젯.
// 각 게임은 onSubmit(Map) 콜백으로 서버 판정 규약에 맞는 데이터를 전달.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

typedef DuelSubmitCallback = void Function(Map<String, dynamic> result);

// ─────────────────────────────────────────────────────────────────────────────
// 1. 반응속도 (reaction_time)
//    Submit: { reactionMs: int }  낮을수록 유리 / 신호 전 탭 = 9999
// ─────────────────────────────────────────────────────────────────────────────

class ReactionTimeGame extends StatefulWidget {
  const ReactionTimeGame({super.key, required this.onSubmit});
  final DuelSubmitCallback onSubmit;

  @override
  State<ReactionTimeGame> createState() => _ReactionTimeGameState();
}

class _ReactionTimeGameState extends State<ReactionTimeGame>
    with SingleTickerProviderStateMixin {
  _RtPhase _phase = _RtPhase.ready;
  int _startMs = 0;
  int _reactionMs = 0;
  Timer? _signalTimer;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.18)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_pulseCtrl);
    _scheduleSignal();
  }

  void _scheduleSignal() {
    final delay = 1500 + Random().nextInt(2500);
    _signalTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted) return;
      setState(() {
        _phase = _RtPhase.signal;
        _startMs = DateTime.now().millisecondsSinceEpoch;
      });
      _pulseCtrl.repeat(reverse: true);
    });
  }

  void _onTap() {
    if (_phase == _RtPhase.done) return;

    if (_phase == _RtPhase.ready) {
      _signalTimer?.cancel();
      _pulseCtrl.stop();
      setState(() {
        _phase = _RtPhase.done;
        _reactionMs = 9999;
      });
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) widget.onSubmit({'reactionMs': 9999});
      });
      return;
    }

    if (_phase == _RtPhase.signal) {
      _reactionMs = DateTime.now().millisecondsSinceEpoch - _startMs;
      _pulseCtrl.stop();
      setState(() => _phase = _RtPhase.done);
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) widget.onSubmit({'reactionMs': _reactionMs});
      });
    }
  }

  @override
  void dispose() {
    _signalTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final String label;
    final String sub;
    final Color iconColor;

    switch (_phase) {
      case _RtPhase.ready:
        bg = const Color(0xFF1E293B);
        label = '신호를 기다려라!';
        sub = '신호 전에 탭하면 패널티';
        iconColor = Colors.white38;
      case _RtPhase.signal:
        bg = const Color(0xFF15803D);
        label = '지금!';
        sub = '최대한 빠르게 탭하라';
        iconColor = Colors.white;
      case _RtPhase.done:
        bg = const Color(0xFF1E1B4B);
        label = _reactionMs == 9999 ? '너무 빨랐다!' : '${_reactionMs}ms';
        sub = _reactionMs == 9999 ? '신호 전 탭 → 패널티' : '결과 대기 중...';
        iconColor = Colors.white54;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _onTap(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        color: bg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 신호 시 pulsing 아이콘
              ScaleTransition(
                scale: _phase == _RtPhase.signal ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
                child: Icon(
                  _phase == _RtPhase.signal ? Icons.flash_on : Icons.touch_app,
                  color: iconColor,
                  size: 72,
                ),
              ),
              const SizedBox(height: 20),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 120),
                style: TextStyle(
                  color: _phase == _RtPhase.signal ? Colors.white : Colors.white70,
                  fontSize: _phase == _RtPhase.signal ? 38 : 28,
                  fontWeight: FontWeight.bold,
                ),
                child: Text(label),
              ),
              const SizedBox(height: 8),
              Text(sub,
                  style: const TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RtPhase { ready, signal, done }

// ─────────────────────────────────────────────────────────────────────────────
// 2. 연타 (rapid_tap)
//    Submit: { tapCount: int, durationMs: int }  tapCount 높을수록 유리
// ─────────────────────────────────────────────────────────────────────────────

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
  int _count = 0;
  int _remainMs = 0;
  bool _started = false;
  bool _done = false;
  int _startMs = 0;
  Timer? _ticker;
  // ripple 효과
  late AnimationController _rippleCtrl;

  @override
  void initState() {
    super.initState();
    _remainMs = widget.durationSec * 1000;
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  void _onTap() {
    if (_done) return;
    if (!_started) {
      _started = true;
      _startMs = DateTime.now().millisecondsSinceEpoch;
      _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted) return;
        final elapsed = DateTime.now().millisecondsSinceEpoch - _startMs;
        final remain = widget.durationSec * 1000 - elapsed;
        if (remain <= 0) {
          _finish();
        } else {
          setState(() => _remainMs = remain.toInt());
        }
      });
    }
    _rippleCtrl.forward(from: 0);
    setState(() => _count++);
  }

  void _finish() {
    if (_done) return;
    _ticker?.cancel();
    final durationMs = DateTime.now().millisecondsSinceEpoch - _startMs;
    setState(() {
      _done = true;
      _remainMs = 0;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) widget.onSubmit({'tapCount': _count, 'durationMs': durationMs});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _rippleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sec = (_remainMs / 1000).toStringAsFixed(1);
    final progress = _started && widget.durationSec > 0
        ? (_remainMs / (widget.durationSec * 1000)).clamp(0.0, 1.0)
        : 1.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _onTap(),
      child: ColoredBox(
        color: const Color(0xFF1E1B4B),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 타이머 progress bar
            if (_started)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 50),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progress > 0.3 ? const Color(0xFF7C3AED) : Colors.redAccent,
                    ),
                    minHeight: 6,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              _done
                  ? '완료!'
                  : (!_started ? '탭해서 시작' : '$sec s'),
              style: TextStyle(
                  color: _done ? Colors.amber : Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              '$_count',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 80,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 20),
            // 탭 버튼 with ripple scale
            ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 0.88).animate(
                CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOut),
              ),
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: _done ? Colors.grey : const Color(0xFF7C3AED),
                  shape: BoxShape.circle,
                  boxShadow: _done
                      ? null
                      : [
                          BoxShadow(
                              color: const Color(0xFF7C3AED).withValues(alpha: 0.5),
                              blurRadius: 20,
                              spreadRadius: 4)
                        ],
                ),
                child: const Icon(Icons.touch_app, color: Colors.white, size: 72),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. 정밀타격 (precision)
//    Submit: { distances: [double], totalDistance: double }  낮을수록 유리
// ─────────────────────────────────────────────────────────────────────────────

class PrecisionGame extends StatefulWidget {
  const PrecisionGame({
    super.key,
    required this.onSubmit,
    this.shots = 3,
  });
  final DuelSubmitCallback onSubmit;
  final int shots;

  @override
  State<PrecisionGame> createState() => _PrecisionGameState();
}

class _PrecisionGameState extends State<PrecisionGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final List<double> _distances = [];
  final List<Offset> _hits = []; // 탭 위치 표시용
  Offset _targetPos = Offset.zero;
  Size _area = Size.zero;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _placeTarget(Size size) {
    _area = size;
    _targetPos = Offset(
      40 + _rng.nextDouble() * (size.width - 80),
      80 + _rng.nextDouble() * (size.height - 160),
    );
  }

  void _onTap(TapDownDetails details) {
    if (_distances.length >= widget.shots) return;
    final pos = details.localPosition;
    final d = (pos - _targetPos).distance;
    _distances.add(d);
    _hits.add(pos);
    if (_distances.length < widget.shots) {
      setState(() => _placeTarget(_area));
    } else {
      final total = _distances.fold<double>(0, (a, b) => a + b);
      setState(() {});
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) widget.onSubmit({'distances': _distances, 'totalDistance': total});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0F172A),
      child: LayoutBuilder(builder: (_, bc) {
        if (_area == Size.zero) _placeTarget(bc.biggest);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _distances.length < widget.shots ? _onTap : null,
          child: Stack(
            children: [
              // HUD
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    '${_distances.length}/${widget.shots}발  — 표적을 탭하라',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              ),
              // 이전 탭 hit 마커
              for (final h in _hits)
                Positioned(
                  left: h.dx - 6,
                  top: h.dy - 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.orangeAccent,
                    ),
                  ),
                ),
              // 타겟 (애니메이션)
              AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) {
                  final pulse = 0.8 + 0.2 * _ctrl.value;
                  final r = 32.0 * pulse;
                  return Positioned(
                    left: _targetPos.dx - r,
                    top: _targetPos.dy - r,
                    child: IgnorePointer(
                      child: Container(
                        width: r * 2,
                        height: r * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.redAccent, width: 2.5),
                          color: Colors.red.withValues(alpha: 0.15),
                        ),
                        child: const Icon(Icons.add, color: Colors.redAccent, size: 22),
                      ),
                    ),
                  );
                },
              ),
              if (_distances.length >= widget.shots)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.6),
                    child: const Center(
                      child: Text('결과 대기 중...',
                          style: TextStyle(color: Colors.white70, fontSize: 15)),
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. 러시안룰렛 (russian_roulette)
//    Submit: { chamber: int (1-6) }  서버가 seed로 탄환 위치 결정
// ─────────────────────────────────────────────────────────────────────────────

class RussianRouletteGame extends StatefulWidget {
  const RussianRouletteGame({super.key, required this.onSubmit});
  final DuelSubmitCallback onSubmit;

  @override
  State<RussianRouletteGame> createState() => _RussianRouletteGameState();
}

class _RussianRouletteGameState extends State<RussianRouletteGame>
    with SingleTickerProviderStateMixin {
  int? _selected;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 6, end: -6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: -4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4, end: 0), weight: 1),
    ]).animate(_shakeCtrl);
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _pick(int chamber) {
    if (_selected != null) return;
    setState(() => _selected = chamber);
    _shakeCtrl.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) widget.onSubmit({'chamber': chamber});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF1A1018),
      child: Center(
        child: AnimatedBuilder(
          animation: _shakeAnim,
          builder: (_, child) {
            return Transform.translate(
              offset: Offset(_shakeAnim.value, 0),
              child: child,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('탄창을 선택하라',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('6개 중 1개에 탄환이 있다',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
              const SizedBox(height: 36),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: List.generate(6, (i) {
                  final num = i + 1;
                  final isPicked = _selected == num;
                  return GestureDetector(
                    onTap: () => _pick(num),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isPicked
                            ? const Color(0xFF7F1D1D)
                            : const Color(0xFF374151),
                        border: Border.all(
                          color: isPicked ? Colors.red : Colors.white24,
                          width: 2,
                        ),
                        boxShadow: isPicked
                            ? [
                                BoxShadow(
                                    color: Colors.red.withValues(alpha: 0.6),
                                    blurRadius: 18,
                                    spreadRadius: 4)
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '$num',
                          style: TextStyle(
                              color: isPicked ? Colors.red.shade200 : Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              if (_selected != null) ...[
                const SizedBox(height: 24),
                const Text('결과 대기 중...',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. 스피드 블랙잭 (speed_blackjack)
//    Submit: { finalScore: int }  ≤21에서 높을수록 유리, bust → 0
// ─────────────────────────────────────────────────────────────────────────────

class SpeedBlackjackGame extends StatefulWidget {
  const SpeedBlackjackGame({
    super.key,
    required this.onSubmit,
    required this.initialHand,
    this.timeoutSec = 15,
  });
  final DuelSubmitCallback onSubmit;
  final List<int> initialHand;
  final int timeoutSec;

  @override
  State<SpeedBlackjackGame> createState() => _SpeedBlackjackGameState();
}

class _SpeedBlackjackGameState extends State<SpeedBlackjackGame>
    with SingleTickerProviderStateMixin {
  late List<int> _hand;
  late int _remainSec;
  bool _done = false;
  Timer? _timer;
  final _rng = Random();

  // 새 카드 슬라이드인 + bust 시 화면 흔들림
  late AnimationController _bustCtrl;
  late Animation<double> _bustAnim;
  bool _showNewCard = false;

  static const _deck = [2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 10, 10, 11];

  int get _score {
    int total = _hand.fold(0, (a, b) => a + b);
    int aces = _hand.where((c) => c == 11).length;
    while (total > 21 && aces > 0) {
      total -= 10;
      aces--;
    }
    return total;
  }

  bool get _isBust => _score > 21;

  @override
  void initState() {
    super.initState();
    _hand = List<int>.from(widget.initialHand);
    _remainSec = widget.timeoutSec;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remainSec--);
      if (_remainSec <= 0) _stand();
    });
    _bustCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _bustAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 8, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: 0), weight: 1),
    ]).animate(_bustCtrl);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bustCtrl.dispose();
    super.dispose();
  }

  void _hit() {
    if (_done) return;
    final card = _deck[_rng.nextInt(_deck.length)];
    setState(() {
      _hand.add(card);
      _showNewCard = true;
    });
    // 잠시 후 new card 표시 제거
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showNewCard = false);
    });
    if (_isBust) {
      _bustCtrl.forward(from: 0);
      Future.delayed(const Duration(milliseconds: 500), _stand);
    }
  }

  void _stand() {
    if (_done) return;
    _timer?.cancel();
    final score = _isBust ? 0 : _score;
    setState(() => _done = true);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) widget.onSubmit({'finalScore': score});
    });
  }

  String _cardLabel(int v) => v == 11 ? 'A' : '$v';

  Widget _buildCard(int v, {bool isNew = false}) {
    return AnimatedSlide(
      offset: isNew ? Offset.zero : Offset.zero,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: isNew ? -30.0 : 0.0, end: 0.0),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        builder: (_, dy, child) => Transform.translate(
          offset: Offset(0, dy),
          child: Opacity(opacity: isNew ? (1 + dy / 30).clamp(0.0, 1.0) : 1.0, child: child),
        ),
        child: Container(
          width: 48,
          height: 68,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: isNew ? Colors.amber.withValues(alpha: 0.6) : Colors.black38,
                blurRadius: isNew ? 12 : 4,
              )
            ],
          ),
          child: Center(
            child: Text(
              _cardLabel(v),
              style: TextStyle(
                color: (v == 11) ? Colors.red : Colors.black87,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bustAnim,
      builder: (_, child) => Transform.translate(
        offset: Offset(_bustAnim.value, 0),
        child: child,
      ),
      child: ColoredBox(
        color: const Color(0xFF064E3B),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer, color: Colors.white38, size: 16),
                const SizedBox(width: 4),
                Text('$_remainSec s',
                    style: TextStyle(
                      color: _remainSec <= 5 ? Colors.redAccent : Colors.white54,
                      fontSize: 14,
                      fontWeight: _remainSec <= 5 ? FontWeight.bold : FontWeight.normal,
                    )),
              ],
            ),
            const SizedBox(height: 16),
            const Text('블랙잭',
                style: TextStyle(
                    color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (int i = 0; i < _hand.length; i++)
                  _buildCard(_hand[i], isNew: _showNewCard && i == _hand.length - 1),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _isBust ? 'BUST!' : '합계: ${_score}',
              style: TextStyle(
                color: _isBust ? Colors.redAccent : Colors.amber,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 28),
            if (!_done)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _hit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    ),
                    child: const Text('힛', style: TextStyle(fontSize: 17)),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: _stand,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF374151),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    ),
                    child: const Text('스탠드', style: TextStyle(fontSize: 17)),
                  ),
                ],
              )
            else
              const Text('결과 대기 중...',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
