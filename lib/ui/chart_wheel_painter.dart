import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'chart_wheel_layout.dart';
import 'tokens.dart';

class ChartWheelPainter extends CustomPainter {
  final ExploreTokens tokens;
  final int ascSign;
  final List<PlacedCusp> cusps;

  ChartWheelPainter({
    required this.tokens,
    required this.ascSign,
    required this.cusps,
  });

  Color get color => tokens.ink;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final half = min(size.width, size.height) / 2;

    // Semi-transparent backdrop so chart pops over background imagery.
    canvas.drawCircle(
      center,
      half * outerRingOuter,
      Paint()..color = tokens.wheelBackdrop,
    );

    // Per-ring warm fills give the concentric structure weight without leaning
    // on hairlines. Painted as true annuli (even-odd) so the center well keeps
    // showing the backdrop. Transparent in immersive mode, so these are no-ops
    // there and the backdrop-over-photo look is preserved.
    _fillRing(
      canvas,
      center,
      half,
      outerRingOuter,
      outerRingInner,
      tokens.ringOuterFill,
    );
    _fillRing(
      canvas,
      center,
      half,
      planetRingOuter,
      planetRingInner,
      tokens.ringPlanetFill,
    );
    _fillRing(
      canvas,
      center,
      half,
      houseRingOuter,
      houseRingInner,
      tokens.ringHouseFill,
    );

    final ringPaint = Paint()
      ..color = tokens.ringLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = tokens.ringStroke;

    final radialPaint = Paint()
      ..color = tokens.radialLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = tokens.radialStroke;

    // Concentric circles.
    canvas
      ..drawCircle(center, half * outerRingInner, ringPaint)
      ..drawCircle(center, half * planetRingInner, ringPaint)
      ..drawCircle(center, half * houseRingInner, ringPaint);

    // Outer edge.
    final outerEdgePaint = Paint()
      ..color = tokens.edgeLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = tokens.edgeStroke;
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

  /// Fills the annulus between [outerFrac] and [innerFrac] (fractions of
  /// [half]) with [fill]. No-op when [fill] is fully transparent.
  void _fillRing(
    Canvas canvas,
    Offset center,
    double half,
    double outerFrac,
    double innerFrac,
    Color fill,
  ) {
    if (fill.a == 0) return;
    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: half * outerFrac))
      ..addOval(Rect.fromCircle(center: center, radius: half * innerFrac))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = fill);
  }

  void _drawHouseLabels(Canvas canvas, Offset center, double half) {
    final textColor = color.withValues(alpha: 0.6);
    final cuspColor = color.withValues(alpha: 0.5);
    const arabicRadius = (houseRingOuter + houseRingInner) / 2 + 0.025;
    const romanRadius = (houseRingOuter + houseRingInner) / 2 - 0.025;

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
      tokens != oldDelegate.tokens ||
      ascSign != oldDelegate.ascSign ||
      cusps != oldDelegate.cusps;
}
