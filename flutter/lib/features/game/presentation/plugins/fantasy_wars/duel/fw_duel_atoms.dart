import 'package:flutter/material.dart';

import '../fantasy_wars_design_tokens.dart';
import 'fw_duel_class_catalog.dart';

// 결투 화면 공용 프리미티브 (shared.jsx 의 atoms 이식).
//
// 디자인 의도: 6 종 미니게임의 VS/Brief/Play/Result 화면에서 반복되는
// "엠블럼·뱃지·카드·필·mono·eyebrow·serif" 표현을 토큰 한 군데에서 일관 적용.
// 폰트 자산을 추가하지 않으므로 serif 는 플랫폼 기본 + Pretendard fallback.

// ─── 1. ClassEmblem ──────────────────────────────────────────────────────────
// SVG 6종을 CustomPainter 1개로 분기. JSX path 값을 그대로 옮겨 24×24 viewBox.
class FwClassEmblem extends StatelessWidget {
  const FwClassEmblem({
    super.key,
    required this.kind,
    this.color = FwColors.ink900,
    this.size = 28,
    this.stroke = 1.8,
  });

  final FwClassEmblemKind kind;
  final Color color;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _FwClassEmblemPainter(
          kind: kind,
          color: color,
          stroke: stroke,
        ),
      ),
    );
  }
}

class _FwClassEmblemPainter extends CustomPainter {
  _FwClassEmblemPainter({
    required this.kind,
    required this.color,
    required this.stroke,
  });

  final FwClassEmblemKind kind;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.scale(scale);

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (kind) {
      case FwClassEmblemKind.sword:
        // M19 3l-9 9 / M14 3h5v5
        final blade = Path()
          ..moveTo(19, 3)
          ..relativeLineTo(-9, 9);
        canvas.drawPath(blade, strokePaint);
        final tip = Path()
          ..moveTo(14, 3)
          ..relativeLineTo(5, 0)
          ..relativeLineTo(0, 5);
        canvas.drawPath(tip, strokePaint);
        // M5 19l3-3 2 2-3 3-2 1 0-3z (hilt diamond)
        final hilt = Path()
          ..moveTo(5, 19)
          ..relativeLineTo(3, -3)
          ..relativeLineTo(2, 2)
          ..relativeLineTo(-3, 3)
          ..relativeLineTo(-2, 1)
          ..close();
        canvas.drawPath(hilt, strokePaint);
        // M10 14l-1 1 (cross-guard tick)
        final tick = Path()
          ..moveTo(10, 14)
          ..relativeLineTo(-1, 1);
        canvas.drawPath(tick, strokePaint);
        break;

      case FwClassEmblemKind.bow:
        // M5 3c6 4 6 14 0 18 (bow curve)
        final curve = Path()
          ..moveTo(5, 3)
          ..cubicTo(11, 7, 11, 17, 5, 21);
        canvas.drawPath(curve, strokePaint);
        // M5 3l14 14 / M19 17l1-3-3 0 (string + arrowhead)
        final arrow = Path()
          ..moveTo(5, 3)
          ..lineTo(19, 17);
        canvas.drawPath(arrow, strokePaint);
        final head = Path()
          ..moveTo(19, 17)
          ..relativeLineTo(1, -3)
          ..relativeLineTo(-3, 0);
        canvas.drawPath(head, strokePaint);
        break;

      case FwClassEmblemKind.rune:
        // M12 3l8 5v8l-8 5-8-5V8l8-5z (hexagonal frame)
        final frame = Path()
          ..moveTo(12, 3)
          ..relativeLineTo(8, 5)
          ..relativeLineTo(0, 8)
          ..relativeLineTo(-8, 5)
          ..relativeLineTo(-8, -5)
          ..lineTo(4, 8)
          ..close();
        canvas.drawPath(frame, strokePaint);
        // M12 8v8 / M9 11h6 (inner cross)
        final inner = Path()
          ..moveTo(12, 8)
          ..relativeLineTo(0, 8)
          ..moveTo(9, 11)
          ..relativeLineTo(6, 0);
        canvas.drawPath(inner, strokePaint);
        break;

      case FwClassEmblemKind.chalice:
        // M6 4h12l-1 5a5 5 0 01-10 0L6 4z (cup)
        final cup = Path()
          ..moveTo(6, 4)
          ..relativeLineTo(12, 0)
          ..relativeLineTo(-1, 5)
          ..arcToPoint(
            const Offset(7, 9),
            radius: const Radius.circular(5),
            largeArc: false,
            clockwise: false,
          )
          ..close();
        canvas.drawPath(cup, strokePaint);
        // M12 14v5 / M9 19h6 (stem + base)
        final stem = Path()
          ..moveTo(12, 14)
          ..relativeLineTo(0, 5)
          ..moveTo(9, 19)
          ..relativeLineTo(6, 0);
        canvas.drawPath(stem, strokePaint);
        break;

      case FwClassEmblemKind.dagger:
        // M12 3l3 11h-6l3-11z (blade triangle)
        final blade = Path()
          ..moveTo(12, 3)
          ..relativeLineTo(3, 11)
          ..relativeLineTo(-6, 0)
          ..close();
        canvas.drawPath(blade, strokePaint);
        // M9 14h6 / M12 14v5 / M10 21h4 (cross-guard, hilt, pommel)
        final guard = Path()
          ..moveTo(9, 14)
          ..relativeLineTo(6, 0)
          ..moveTo(12, 14)
          ..relativeLineTo(0, 5)
          ..moveTo(10, 21)
          ..relativeLineTo(4, 0);
        canvas.drawPath(guard, strokePaint);
        break;

      case FwClassEmblemKind.banner:
        // M5 3v18 / M5 4h12l-2 4 2 4H5 (pole + flag with notch)
        final pole = Path()
          ..moveTo(5, 3)
          ..relativeLineTo(0, 18);
        canvas.drawPath(pole, strokePaint);
        final flag = Path()
          ..moveTo(5, 4)
          ..relativeLineTo(12, 0)
          ..relativeLineTo(-2, 4)
          ..relativeLineTo(2, 4)
          ..lineTo(5, 12);
        canvas.drawPath(flag, strokePaint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _FwClassEmblemPainter old) =>
      old.kind != kind || old.color != color || old.stroke != stroke;
}

// ─── 2. ClassBadge ───────────────────────────────────────────────────────────
// 라운드 박스(soft 배경 + accent 테두리) + 엠블럼. withName=true 면 이름/영문 라벨 추가.
class FwClassBadge extends StatelessWidget {
  const FwClassBadge({
    super.key,
    required this.klass,
    this.size = 36,
    this.withName = false,
  });

  final FwDuelClass klass;
  final double size;
  final bool withName;

  @override
  Widget build(BuildContext context) {
    final data = FwDuelClasses.of(klass);
    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: data.soft,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: data.accent.withValues(alpha: 0.13)),
      ),
      alignment: Alignment.center,
      child: FwClassEmblem(
        kind: data.icon,
        color: data.accent,
        size: size * 0.55,
      ),
    );

    if (!withName) return tile;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        tile,
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.name,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: FwColors.ink900,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            FwMono(
              text: data.en.toUpperCase(),
              size: 9.5,
              color: FwColors.ink500,
              letterSpacing: 1.2,
            ),
          ],
        ),
      ],
    );
  }
}

// ─── 3. FwCard ───────────────────────────────────────────────────────────────
// 흰 surface + soft 그림자 + 14px radius (디자인 default).
class FwCard extends StatelessWidget {
  const FwCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = FwRadii.md,
    this.color = FwColors.cardSurface,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: FwShadows.card,
        border: border ??
            Border.all(color: const Color(0x0D1F2630)), // ~0.05 alpha
      ),
      child: child,
    );
  }
}

// ─── 4. FwPill ───────────────────────────────────────────────────────────────
// 라운드 풀 칩. mono=true 면 JetBrains Mono fallback 적용.
class FwPill extends StatelessWidget {
  const FwPill({
    super.key,
    required this.text,
    this.bg = FwColors.line2,
    this.color = FwColors.ink700,
    this.mono = true,
    this.prefix,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    this.fontSize = 10.5,
    this.letterSpacing,
  });

  final String text;
  final Color bg;
  final Color color;
  final bool mono;
  final Widget? prefix;
  final EdgeInsetsGeometry padding;
  final double fontSize;
  final double? letterSpacing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(FwRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prefix != null) ...[
            prefix!,
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontFamily: mono ? 'monospace' : 'Pretendard',
              fontFamilyFallback: mono
                  ? const ['RobotoMono', 'Menlo', 'Consolas']
                  : null,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: letterSpacing ?? (mono ? 0.4 : 0),
              fontFeatures: mono
                  ? const [FontFeature.tabularFigures()]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 5. FwMono ───────────────────────────────────────────────────────────────
// mono 텍스트 헬퍼 (수치/라벨/EYEBROW 본체).
class FwMono extends StatelessWidget {
  const FwMono({
    super.key,
    required this.text,
    this.size = 11,
    this.weight = FontWeight.w500,
    this.color = FwColors.ink500,
    this.letterSpacing = 0.2,
    this.uppercase = false,
    this.textAlign,
  });

  final String text;
  final double size;
  final FontWeight weight;
  final Color color;
  final double letterSpacing;
  final bool uppercase;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      uppercase ? text.toUpperCase() : text,
      textAlign: textAlign,
      style: TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['RobotoMono', 'Menlo', 'Consolas'],
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: 1.25,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

// ─── 6. FwEyebrow ────────────────────────────────────────────────────────────
// UPPERCASE mono 10px / letter-spacing 1.6.
class FwEyebrow extends StatelessWidget {
  const FwEyebrow({
    super.key,
    required this.text,
    this.color = FwColors.ink500,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FwMono(
      text: text,
      size: 10,
      weight: FontWeight.w600,
      color: color,
      letterSpacing: 1.6,
      uppercase: true,
    );
  }
}

// ─── 7. FwSerifText ──────────────────────────────────────────────────────────
// VS 110px / 카운트다운 92px / 결과 스탬프 / 편지 카드 이탤릭 대사용.
// 별도 폰트 자산 없이 플랫폼 기본 serif + Pretendard fallback.
class FwSerifText extends StatelessWidget {
  const FwSerifText({
    super.key,
    required this.text,
    this.size = 28,
    this.weight = FontWeight.w700,
    this.color = FwColors.ink900,
    this.letterSpacing = -0.3,
    this.italic = false,
    this.height = 1.1,
    this.textAlign,
  });

  final String text;
  final double size;
  final FontWeight weight;
  final Color color;
  final double letterSpacing;
  final bool italic;
  final double height;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      style: TextStyle(
        fontFamily: 'serif',
        fontFamilyFallback: const ['Pretendard', 'Noto Serif KR'],
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      ),
    );
  }
}
