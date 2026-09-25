import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Custom Brand Mark for Fadhkur (فذكر)
/// Concept: Minimalist open Quran with acoustic recitation soundwave arc.
/// Supports both regular brand mark and live radio broadcast variant.
class FadhkurBrandMark extends StatelessWidget {
  final double size;
  final bool isRadio;
  final Color? primaryColor;
  final Color? secondaryColor;
  final Color? accentColor;

  const FadhkurBrandMark({
    super.key,
    this.size = 48,
    this.isRadio = false,
    this.primaryColor,
    this.secondaryColor,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pColor = primaryColor ?? const Color(0xFF243B6B);
    final sColor = secondaryColor ?? const Color(0xFF2E9E9E);
    final aColor = accentColor ?? const Color(0xFFC77955);

    return Semantics(
      label: 'شعار فذكر',
      child: CustomPaint(
        size: Size(size, size),
        painter: _BrandMarkPainter(
          primaryColor: pColor,
          secondaryColor: sColor,
          accentColor: aColor,
          isRadio: isRadio,
          isDark: theme.brightness == Brightness.dark,
        ),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final bool isRadio;
  final bool isDark;

  _BrandMarkPainter({
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.isRadio,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;

    // 1. Background Shield
    final bgPaint = Paint()
      ..color = isDark ? const Color(0xFF162746) : primaryColor
      ..style = PaintingStyle.fill;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, s, s),
      Radius.circular(s * 0.22),
    );
    canvas.drawRRect(rrect, bgPaint);

    // 2. Recitation Soundwave Arc (Teal & Copper)
    final arcPaintTeal = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.035
      ..strokeCap = StrokeCap.round;

    final arcPaintCopper = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.03
      ..strokeCap = StrokeCap.round;

    // Outer recitation arc
    final outerArcPath = Path();
    outerArcPath.addArc(
      Rect.fromCircle(center: Offset(s * 0.5, s * 0.44), radius: s * 0.22),
      math.pi * 1.15,
      math.pi * 0.7,
    );
    canvas.drawPath(outerArcPath, arcPaintTeal);

    // Inner recitation arc
    final innerArcPath = Path();
    innerArcPath.addArc(
      Rect.fromCircle(center: Offset(s * 0.5, s * 0.46), radius: s * 0.14),
      math.pi * 1.18,
      math.pi * 0.64,
    );
    canvas.drawPath(innerArcPath, arcPaintCopper);

    // Live Radio pulses
    if (isRadio) {
      final radioPulsePaint = Paint()
        ..color = secondaryColor.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.025
        ..strokeCap = StrokeCap.round;
      final radioArc = Path();
      radioArc.addArc(
        Rect.fromCircle(center: Offset(s * 0.5, s * 0.42), radius: s * 0.30),
        math.pi * 1.12,
        math.pi * 0.76,
      );
      canvas.drawPath(radioArc, radioPulsePaint);
    }

    // 3. Open Holy Quran (Pages)
    final leftPagePath = Path();
    leftPagePath.moveTo(s * 0.48, s * 0.52);
    leftPagePath.quadraticBezierTo(s * 0.38, s * 0.48, s * 0.28, s * 0.51);
    leftPagePath.lineTo(s * 0.28, s * 0.70);
    leftPagePath.quadraticBezierTo(s * 0.38, s * 0.67, s * 0.48, s * 0.72);
    leftPagePath.close();

    final rightPagePath = Path();
    rightPagePath.moveTo(s * 0.52, s * 0.52);
    rightPagePath.quadraticBezierTo(s * 0.62, s * 0.48, s * 0.72, s * 0.51);
    rightPagePath.lineTo(s * 0.72, s * 0.70);
    rightPagePath.quadraticBezierTo(s * 0.62, s * 0.67, s * 0.52, s * 0.72);
    rightPagePath.close();

    final leftPagePaint = Paint()
      ..color = const Color(0xFFF8F6F1)
      ..style = PaintingStyle.fill;
    final rightPagePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawPath(leftPagePath, leftPagePaint);
    canvas.drawPath(rightPagePath, rightPagePaint);

    // 4. Wooden Rihal Stand (Interlocking base)
    final standPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.038
      ..strokeCap = StrokeCap.round;

    // Cross legs
    canvas.drawLine(Offset(s * 0.38, s * 0.72), Offset(s * 0.62, s * 0.83), standPaint);
    canvas.drawLine(Offset(s * 0.62, s * 0.72), Offset(s * 0.38, s * 0.83), standPaint);
    // Base stabilizer
    canvas.drawLine(Offset(s * 0.32, s * 0.81), Offset(s * 0.68, s * 0.81), standPaint);

    // 5. Bookmark Ribbon
    final ribbonPaint = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.024
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(s * 0.50, s * 0.53), Offset(s * 0.50, s * 0.76), ribbonPaint);
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter oldDelegate) {
    return oldDelegate.isRadio != isRadio ||
        oldDelegate.isDark != isDark ||
        oldDelegate.primaryColor != primaryColor;
  }
}
