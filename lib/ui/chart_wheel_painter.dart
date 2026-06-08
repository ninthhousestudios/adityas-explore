import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'chart_wheel_layout.dart';

class ChartWheelPainter extends CustomPainter {
  final Color color;
  final Color backdropColor;
  final int ascSign;
  final List<PlacedCusp> cusps;

  ChartWheelPainter({
    required this.color,
    required this.backdropColor,
    required this.ascSign,
    required this.cusps,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final half = min(size.width, size.height) / 2;

    // Semi-transparent backdrop so chart pops over background imagery.
    canvas.drawCircle(
      center,
      half * outerRingOuter,
      Paint()..color = backdropColor,
    );

    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final radialPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Concentric circles.
    canvas.drawCircle(center, half * outerRingInner, ringPaint);
    canvas.drawCircle(center, half * planetRingInner, ringPaint);
    canvas.drawCircle(center, half * houseRingInner, ringPaint);

    // Outer edge.
    final outerEdgePaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, half * outerRingOuter, outerEdgePaint);

    // 12 radial lines at sign boundaries.
    for (var s = 1; s <= 12; s++) {
      final angle = signStartAngle(s, ascSign);
      final inner = polarToCartesian(angle, half * houseRingInner, center);
      final outer = polarToCartesian(angle, half * outerRingOuter, center);
      canvas.drawLine(inner, outer, radialPaint);
    }

    _drawHouseLabels(canvas, center, half);
  }

  void _drawHouseLabels(Canvas canvas, Offset center, double half) {
    final textColor = color.withValues(alpha: 0.6);
    final cuspColor = color.withValues(alpha: 0.5);
    final arabicRadius = (houseRingOuter + houseRingInner) / 2 + 0.025;
    final romanRadius = (houseRingOuter + houseRingInner) / 2 - 0.025;

    // Arabic whole-sign house numbers at sign midpoints.
    for (var i = 0; i < 12; i++) {
      final sign = ((ascSign - 1 + i) % 12) + 1;
      final houseNum = i + 1;
      final angle = signMidAngle(sign, ascSign);
      final pos = polarToCartesian(angle, half * arabicRadius, center);
      _drawText(canvas, '$houseNum', pos, textColor, half * 0.04);
    }

    // Roman numerals at actual cusp degree positions.
    for (final cusp in cusps) {
      final pos = polarToCartesian(cusp.angle, half * romanRadius, center);
      _drawText(canvas, romanNumeral(cusp.house), pos, cuspColor, half * 0.032);
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position,
    Color color,
    double fontSize,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, position - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(ChartWheelPainter oldDelegate) =>
      color != oldDelegate.color ||
      backdropColor != oldDelegate.backdropColor ||
      ascSign != oldDelegate.ascSign ||
      cusps != oldDelegate.cusps;
}
