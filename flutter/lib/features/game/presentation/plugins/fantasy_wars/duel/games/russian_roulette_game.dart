import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../providers/fantasy_wars_provider.dart';
import '../../fantasy_wars_design_tokens.dart';
import '../fw_duel_atoms.dart';

// 턴 기반 동기화 러시안 룰렛.
//
// 서버가 generateParams 시점에 6 발 약실 중 1발을 실탄으로 결정하고, 매 턴 actor 가
// { chamber, target: 'self' | 'opponent' } 액션을 보낸다. 서버가 검증 + 상태 전이 후
// 양 클라에 fw:duel:state broadcast → 이 위젯은 그 state 를 그대로 그린다.
//
// 클래식 룰:
//  - self miss → 같은 actor 의 턴 유지 (재시도 가능).
//  - opponent miss → 턴이 상대에게 넘어감.
//  - hit → 그 약실을 향한 target 이 패배.
class RussianRouletteGame extends ConsumerStatefulWidget {
  const RussianRouletteGame({
    super.key,
    required this.sessionId,
    required this.myId,
    required this.opponentId,
  });

  final String sessionId;
  final String myId;
  final String? opponentId;

  @override
  ConsumerState<RussianRouletteGame> createState() =>
      _RussianRouletteGameState();
}

class _RussianRouletteGameState extends ConsumerState<RussianRouletteGame>
    with SingleTickerProviderStateMixin {
  int? _selectedChamber;
  String _targetChoice = 'opponent';
  bool _submitting = false;
  int _lastHistoryLen = 0;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 6, end: -6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: -4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4, end: 0), weight: 1),
    ]).animate(_shakeController);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _pullTrigger(int chamber, String target) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final notifier = ref.read(fantasyWarsProvider(widget.sessionId).notifier);
    final response = await notifier.sendDuelAction({
      'chamber': chamber,
      'target': target,
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (response['ok'] != true) {
      // 서버 거부 (NOT_YOUR_TURN, CHAMBER_USED 등) — 선택 초기화.
      setState(() => _selectedChamber = null);
      final code = response['error'] as String? ?? 'ERROR';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('동작 거부됨 ($code)'),
          backgroundColor: FwColors.danger,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final duel = ref.watch(
      fantasyWarsProvider(widget.sessionId).select((s) => s.duel),
    );
    final params = duel.minigameParams ?? const <String, dynamic>{};
    final stateMap = (params['state'] is Map)
        ? Map<String, dynamic>.from(params['state'] as Map)
        : const <String, dynamic>{};

    final chamberCount = (params['chamberCount'] as num?)?.toInt() ?? 6;
    final firedRaw = stateMap['chambersFired'];
    final chambersFired = (firedRaw is List)
        ? firedRaw.map((e) => (e as num).toInt()).toSet()
        : <int>{};
    final currentTurn = stateMap['currentTurn'] as String?;
    final settled = stateMap['settled'] == true;
    final historyRaw = stateMap['history'];
    final history = (historyRaw is List)
        ? historyRaw.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : const <Map<String, dynamic>>[];

    final isMyTurn = currentTurn == widget.myId && !settled;

    // history 길이가 늘어나면 흔들림 + 햅틱.
    if (history.length != _lastHistoryLen) {
      _lastHistoryLen = history.length;
      if (history.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _shakeController.forward(from: 0);
          final last = history.last;
          if (last['hit'] == true) {
            HapticFeedback.heavyImpact();
          } else {
            HapticFeedback.lightImpact();
          }
        });
      }
    }

    return ColoredBox(
      color: const Color(0xFF1A1418),
      child: SafeArea(
        child: AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) => Transform.translate(
            offset: Offset(_shakeAnimation.value, 0),
            child: child,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                _Header(
                  isMyTurn: isMyTurn,
                  settled: settled,
                  history: history,
                  myId: widget.myId,
                ),
                const SizedBox(height: 14),
                FwMono(
                  text: '$chamberCount발 중 1발은 실탄 · '
                      '소진 ${chambersFired.length}/$chamberCount',
                  size: 10,
                  color: FwColors.danger,
                  letterSpacing: 1.4,
                ),
                const SizedBox(height: 16),
                _ChamberRow(
                  chamberCount: chamberCount,
                  chambersFired: chambersFired,
                  selectedChamber: _selectedChamber,
                  enabled: isMyTurn && !_submitting,
                  bulletReveal: settled ? _bulletFromHistory(history) : null,
                  onTap: (c) => setState(() => _selectedChamber = c),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 200,
                          height: 200,
                          child: CustomPaint(
                            painter: _RevolverCylinderPainter(
                              chamberCount: chamberCount,
                              chambersFired: chambersFired,
                              selectedChamber: _selectedChamber,
                              bulletReveal:
                                  settled ? _bulletFromHistory(history) : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _HistoryStrip(history: history, myId: widget.myId),
                      ],
                    ),
                  ),
                ),
                if (!settled) ...[
                  _TargetPicker(
                    value: _targetChoice,
                    enabled: isMyTurn && !_submitting,
                    onChanged: (v) => setState(() => _targetChoice = v),
                  ),
                  const SizedBox(height: 12),
                  _TriggerButton(
                    enabled:
                        isMyTurn && !_submitting && _selectedChamber != null,
                    label: _submitting
                        ? '판정 중…'
                        : (isMyTurn ? 'PULL THE TRIGGER · 발사' : '상대 차례 — 대기'),
                    onTap: () {
                      final c = _selectedChamber;
                      if (c == null) return;
                      _pullTrigger(c, _targetChoice);
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  const FwMono(
                    text: '결투 종결 · 결과 화면 대기',
                    size: 12,
                    color: FwColors.goldStrong,
                    letterSpacing: 1.2,
                    weight: FontWeight.w700,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static int? _bulletFromHistory(List<Map<String, dynamic>> history) {
    for (final h in history) {
      if (h['hit'] == true) {
        final c = h['chamber'];
        if (c is num) return c.toInt();
      }
    }
    return null;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isMyTurn,
    required this.settled,
    required this.history,
    required this.myId,
  });

  final bool isMyTurn;
  final bool settled;
  final List<Map<String, dynamic>> history;
  final String myId;

  @override
  Widget build(BuildContext context) {
    final String banner;
    final Color color;
    if (settled) {
      banner = 'GAME OVER · 결과 확인';
      color = FwColors.goldStrong;
    } else if (isMyTurn) {
      banner = 'YOUR TURN · 당신의 차례';
      color = FwColors.danger;
    } else {
      banner = 'OPPONENT TURN · 상대 차례';
      color = Colors.white.withValues(alpha: 0.55);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        FwPill(
          text: 'RUSSIAN ROULETTE',
          bg: Colors.white.withValues(alpha: 0.08),
          color: Colors.white,
        ),
        FwMono(
          text: banner,
          size: 11,
          color: color,
          letterSpacing: 1.2,
          weight: FontWeight.w700,
        ),
      ],
    );
  }
}

class _ChamberRow extends StatelessWidget {
  const _ChamberRow({
    required this.chamberCount,
    required this.chambersFired,
    required this.selectedChamber,
    required this.enabled,
    required this.onTap,
    this.bulletReveal,
  });

  final int chamberCount;
  final Set<int> chambersFired;
  final int? selectedChamber;
  final bool enabled;
  final ValueChanged<int> onTap;
  final int? bulletReveal;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(chamberCount, (i) {
        final chamber = i + 1;
        final fired = chambersFired.contains(chamber);
        final selected = selectedChamber == chamber;
        final isBullet = bulletReveal == chamber;
        Color bg;
        Color border;
        if (isBullet) {
          bg = FwColors.danger;
          border = Colors.white;
        } else if (fired) {
          bg = const Color(0xFF2A2026);
          border = const Color(0xFF4A3A42);
        } else if (selected) {
          bg = FwColors.danger;
          border = Colors.white;
        } else {
          bg = const Color(0xFF0F0A0D);
          border = const Color(0xFF6B5560);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: (enabled && !fired) ? () => onTap(chamber) : null,
              child: Opacity(
                opacity: fired ? 0.55 : 1.0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: border, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: fired
                      ? Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.7),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FwMono(
              text: '$chamber',
              size: 9,
              color: Colors.white.withValues(alpha: fired ? 0.4 : 0.7),
            ),
          ],
        );
      }),
    );
  }
}

class _TargetPicker extends StatelessWidget {
  const _TargetPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget choice(String key, String label) {
      final selected = value == key;
      return Expanded(
        child: GestureDetector(
          onTap: enabled ? () => onChanged(key) : null,
          child: Opacity(
            opacity: enabled ? 1.0 : 0.45,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? (key == 'self'
                        ? FwColors.danger.withValues(alpha: 0.85)
                        : FwColors.goldStrong.withValues(alpha: 0.85))
                    : const Color(0xFF1A1418),
                borderRadius: BorderRadius.circular(FwRadii.md),
                border: Border.all(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.18),
                  width: 1.4,
                ),
              ),
              alignment: Alignment.center,
              child: FwMono(
                text: label,
                size: 12,
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.7),
                weight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        choice('self', '내게 겨눔 · SELF'),
        const SizedBox(width: 10),
        choice('opponent', '상대에게 겨눔 · OPP'),
      ],
    );
  }
}

class _TriggerButton extends StatelessWidget {
  const _TriggerButton({
    required this.enabled,
    required this.label,
    required this.onTap,
  });

  final bool enabled;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FwRadii.md),
            border: Border.all(color: FwColors.danger, width: 1.5),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF3A1F22), Color(0xFF1A1418)],
            ),
          ),
          alignment: Alignment.center,
          child: FwMono(
            text: label,
            size: 13,
            color: FwColors.danger,
            weight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}

class _HistoryStrip extends StatelessWidget {
  const _HistoryStrip({required this.history, required this.myId});

  final List<Map<String, dynamic>> history;
  final String myId;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const FwMono(
        text: '약실 한 칸을 골라 방아쇠를 당겨라',
        size: 11,
        color: FwColors.danger,
        letterSpacing: 1.4,
      );
    }
    final last = history.last;
    final actor = last['actor'] as String?;
    final target = last['target'] as String?;
    final chamber = last['chamber'] as num?;
    final hit = last['hit'] == true;
    final actorLabel = actor == myId ? '나' : '상대';
    final targetLabel = target == myId ? '나' : '상대';
    final verb = hit ? '명중!' : '공포탄';
    return FwMono(
      text: '$actorLabel → $targetLabel · '
          '약실 ${chamber?.toInt() ?? '?'} · $verb',
      size: 11,
      color: hit ? Colors.white : Colors.white.withValues(alpha: 0.55),
      letterSpacing: 1.0,
      weight: hit ? FontWeight.w800 : FontWeight.w600,
    );
  }
}

class _RevolverCylinderPainter extends CustomPainter {
  _RevolverCylinderPainter({
    required this.chamberCount,
    required this.chambersFired,
    required this.selectedChamber,
    this.bulletReveal,
  });

  final int chamberCount;
  final Set<int> chambersFired;
  final int? selectedChamber;
  final int? bulletReveal;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width * 0.45;
    canvas.drawCircle(
      center,
      outerR,
      Paint()..color = const Color(0xFF2A2026),
    );
    canvas.drawCircle(
      center,
      outerR,
      Paint()
        ..color = const Color(0xFF5A4751)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      center,
      outerR * 0.92,
      Paint()
        ..color = const Color(0xFF3D2F37)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final perAngle = 360 / chamberCount;
    for (var i = 0; i < chamberCount; i++) {
      final a = (i * perAngle - 90) * pi / 180;
      final cx = center.dx + cos(a) * outerR * 0.6;
      final cy = center.dy + sin(a) * outerR * 0.6;
      final chamber = i + 1;
      final isFired = chambersFired.contains(chamber);
      final isSelected = selectedChamber == chamber;
      final isBullet = bulletReveal == chamber;

      Color outer = const Color(0xFF0F0A0D);
      Color inner = const Color(0xFF1A1418);
      if (isBullet) {
        outer = FwColors.danger.withValues(alpha: 0.85);
        inner = FwColors.danger;
      } else if (isFired) {
        outer = const Color(0xFF1A1418);
        inner = const Color(0xFF2A2026);
      } else if (isSelected) {
        outer = FwColors.danger.withValues(alpha: 0.7);
        inner = FwColors.danger;
      }

      canvas.drawCircle(Offset(cx, cy), 20, Paint()..color = outer);
      canvas.drawCircle(
        Offset(cx, cy),
        20,
        Paint()
          ..color = const Color(0xFF6B5560)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(Offset(cx, cy), 12, Paint()..color = inner);
    }

    canvas.drawCircle(
      center,
      14,
      Paint()..color = const Color(0xFF5A4751),
    );
    canvas.drawCircle(
      center,
      6,
      Paint()..color = const Color(0xFF0F0A0D),
    );
  }

  @override
  bool shouldRepaint(covariant _RevolverCylinderPainter old) =>
      old.selectedChamber != selectedChamber ||
      old.chambersFired.length != chambersFired.length ||
      old.bulletReveal != bulletReveal ||
      old.chamberCount != chamberCount;
}
