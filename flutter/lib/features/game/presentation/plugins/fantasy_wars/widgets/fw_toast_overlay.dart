import 'package:flutter/material.dart';

import '../fantasy_wars_design_tokens.dart';

// ─── Layer 7: 토스트 오버레이 (시스템 이벤트, fade in/out) ───────────────
class FwToastOverlay extends StatefulWidget {
  const FwToastOverlay({
    super.key,
    required this.message,
    required this.kind,
  });

  final String message;
  final String kind;

  @override
  State<FwToastOverlay> createState() => _FwToastOverlayState();
}

class _FwToastOverlayState extends State<FwToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void didUpdateWidget(covariant FwToastOverlay old) {
    super.didUpdateWidget(old);
    if (old.message != widget.message) {
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final color = switch (widget.kind) {
      'capture' => FwColors.okStrong,
      'combat' || 'duel' => FwColors.dangerStrong,
      'skill' => FwColors.infoStrong,
      'revive' => const Color(0xFF38BDF8),
      'match' => FwColors.goldStrong,
      _ => Colors.black87,
    };
    final icon = switch (widget.kind) {
      'capture' => Icons.flag_rounded,
      'combat' => Icons.local_fire_department_rounded,
      'duel' => Icons.sports_martial_arts_rounded,
      'skill' => Icons.auto_fix_high_rounded,
      'revive' => Icons.favorite_rounded,
      'match' => Icons.emoji_events_rounded,
      _ => Icons.notifications_rounded,
    };
    return Positioned(
      top: topInset + 96,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _opacity,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: FwColors.goldStrong.withValues(alpha: 0.6)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x88000000),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
