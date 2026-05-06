import 'package:flutter/material.dart';

// 탭하면 살짝 (0.94×) 축소되는 버튼 래퍼.
// AnimatedScale 만 사용 — vsync / dispose 불필요.
class FwScaleTapButton extends StatefulWidget {
  const FwScaleTapButton({
    super.key,
    required this.child,
    this.onTap,
  });

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<FwScaleTapButton> createState() => _FwScaleTapButtonState();
}

class _FwScaleTapButtonState extends State<FwScaleTapButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:
          widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: widget.child,
      ),
    );
  }
}
