import 'dart:math';
import 'dart:typed_data';

import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vector_math/vector_math_64.dart';

import '../ui/aditya_data.dart';
import '../ui/chart_wheel_layout.dart';

Future<Uint8List> buildChartPdf({
  required arrow.Chart chart,
  String? chartName,
}) async {
  final fontData = await rootBundle.load('assets/fonts/Inter.ttf');
  final font = pw.Font.ttf(fontData);
  final boldFont = pw.Font.ttf(fontData);

  final svgCache = <String, String>{};
  for (final entry in adityaSigns.entries) {
    svgCache[entry.value.glyph] = await rootBundle.loadString(
      entry.value.glyph,
    );
  }
  for (final entry in planetGlyphs.entries) {
    svgCache[entry.value] = await rootBundle.loadString(entry.value);
  }

  final ascSign = chart.cusp(1).sign;

  final cusps = List.generate(12, (i) {
    final c = chart.cusp(i + 1);
    return PlacedCusp(
      house: c.house,
      sign: c.longitude.sign,
      inSignDeg: c.longitude.inSignLongitude,
      angle: degreeToAngle(
        c.longitude.sign,
        c.longitude.inSignLongitude,
        ascSign,
      ),
    );
  });

  final doc = pw.Document();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) {
        final pageWidth = context.page.pageFormat.availableWidth;
        final wheelSize = min(pageWidth, 380.0);
        final half = wheelSize / 2;
        final glyphSize = half * 0.065;

        final planets = _buildPlanets(chart, ascSign, half, glyphSize);

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (chartName != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Text(
                  chartName,
                  style: pw.TextStyle(font: boldFont, fontSize: 16),
                ),
              ),
            pw.Center(
              child: pw.SizedBox(
                width: wheelSize,
                height: wheelSize,
                child: _WheelWidget(
                  planets: planets,
                  cusps: cusps,
                  ascSign: ascSign,
                  svgCache: svgCache,
                  font: font,
                ),
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _buildSoulStancesPanel(planets, font, boldFont),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(child: _buildBeingsPanel(planets, font, boldFont)),
              ],
            ),
            pw.Spacer(),
            pw.Text(
              '84beings.com',
              style: pw.TextStyle(
                font: font,
                fontSize: 8,
                color: PdfColors.grey600,
              ),
            ),
          ],
        );
      },
    ),
  );

  return doc.save();
}

List<PlacedPlanet> _buildPlanets(
  arrow.Chart chart,
  int ascSign,
  double half,
  double glyphSize,
) {
  final filtered = <arrow.Planet>[
    for (final p in chart.grahas)
      if (defaultGrahas.contains(p.body.name)) p,
  ];

  final positions = resolvePlanetPositions(
    planets: [
      for (final p in filtered)
        (sign: p.longitude.sign, inSignDeg: p.longitude.inSignLongitude),
    ],
    ascSign: ascSign,
    half: half,
    glyphSize: glyphSize,
  );

  return List.generate(filtered.length, (i) {
    final p = filtered[i];
    return PlacedPlanet(
      bodyName: p.body.name,
      sign: p.longitude.sign,
      inSignDeg: p.longitude.inSignLongitude,
      angle: positions[i].angle,
      radiusFraction: positions[i].radiusFraction,
      horaBeing: p.horaBeing.name,
      horaBeingType: p.horaBeing.type.name,
      horaBeingSign: p.horaBeing.signNumber,
      trimsamsaBeing: p.trimsamsaBeing.name,
      trimsamsaBeingType: p.trimsamsaBeing.type.name,
      trimsamsaBeingSign: p.trimsamsaBeing.signNumber,
      isRetrograde: p.isRetrograde,
    );
  });
}

class _WheelWidget extends pw.Widget {
  final List<PlacedPlanet> planets;
  final List<PlacedCusp> cusps;
  final int ascSign;
  final Map<String, String> svgCache;
  final pw.Font font;

  _WheelWidget({
    required this.planets,
    required this.cusps,
    required this.ascSign,
    required this.svgCache,
    required this.font,
  });

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    final s = min(constraints.maxWidth, constraints.maxHeight);
    box = PdfRect(0, 0, s, s);
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    final canvas = context.canvas;
    final pdfFont = font.getFont(context);
    final s = box!.width;
    final half = s / 2;
    final cx = box!.left + half;
    final cy = box!.bottom + half;

    _drawRings(canvas, cx, cy, half);
    _drawRadials(canvas, cx, cy, half);
    _drawHouseLabels(canvas, cx, cy, half, pdfFont);
    _drawSignNames(canvas, cx, cy, half, pdfFont);
    _drawPlanetGlyphs(context, cx, cy, half);
  }

  void _drawRings(PdfGraphics canvas, double cx, double cy, double half) {
    canvas
      ..setFillColor(PdfColors.white)
      ..drawEllipse(cx, cy, half * outerRingOuter, half * outerRingOuter)
      ..fillPath();

    canvas
      ..setStrokeColor(PdfColors.black)
      ..setLineWidth(1.5)
      ..drawEllipse(cx, cy, half * outerRingOuter, half * outerRingOuter)
      ..strokePath();

    canvas
      ..setStrokeColor(const PdfColor.fromInt(0xFF808080))
      ..setLineWidth(0.75);
    for (final r in [outerRingInner, planetRingInner, houseRingInner]) {
      canvas
        ..drawEllipse(cx, cy, half * r, half * r)
        ..strokePath();
    }
  }

  void _drawRadials(PdfGraphics canvas, double cx, double cy, double half) {
    canvas
      ..setStrokeColor(const PdfColor.fromInt(0xFFB0B0B0))
      ..setLineWidth(0.5);

    for (var s = 1; s <= 12; s++) {
      final angle = signStartAngle(s, ascSign);
      final inner = _polar(angle, half * houseRingInner, cx, cy);
      final outer = _polar(angle, half * outerRingOuter, cx, cy);
      canvas
        ..drawLine(inner.x, inner.y, outer.x, outer.y)
        ..strokePath();
    }
  }

  void _drawHouseLabels(
    PdfGraphics canvas,
    double cx,
    double cy,
    double half,
    PdfFont pdfFont,
  ) {
    final fontSize = half * 0.04;
    const arabicRadius = (houseRingOuter + houseRingInner) / 2 + 0.025;
    const romanRadius = (houseRingOuter + houseRingInner) / 2 - 0.025;

    for (var i = 0; i < 12; i++) {
      final signNum = ((ascSign - 1 + i) % 12) + 1;
      final houseNum = i + 1;
      final angle = signMidAngle(signNum, ascSign);
      final pos = _polar(angle, half * arabicRadius, cx, cy);
      _drawCenteredText(
        canvas,
        pdfFont,
        '$houseNum',
        pos.x,
        pos.y,
        fontSize,
        color: const PdfColor.fromInt(0xFF606060),
      );
    }

    for (final cusp in cusps) {
      final pos = _polar(cusp.angle, half * romanRadius, cx, cy);
      _drawCenteredText(
        canvas,
        pdfFont,
        romanNumeral(cusp.house),
        pos.x,
        pos.y,
        fontSize * 0.8,
        color: const PdfColor.fromInt(0xFF808080),
      );
    }
  }

  void _drawSignNames(
    PdfGraphics canvas,
    double cx,
    double cy,
    double half,
    PdfFont pdfFont,
  ) {
    final fontSize = half * 0.052;
    final radius = signMidRadius(half);

    for (var s = 1; s <= 12; s++) {
      final data = adityaSigns[s]!;
      final name = data.name.toUpperCase();
      final charWidth = fontSize * 0.6;
      final spacing = min(
        charWidth,
        0.85 * (pi / 6) * radius / max(name.length - 1, 1),
      );
      final totalSpan = (name.length - 1) * spacing;
      final midAngle = signMidAngle(s, ascSign);

      for (var i = 0; i < name.length; i++) {
        final charAngle =
            midAngle + totalSpan / (2 * radius) - i * spacing / radius;
        final pos = _polar(charAngle, radius, cx, cy);

        canvas
          ..saveContext()
          ..setTransform(
            Matrix4.identity()
              ..translateByDouble(pos.x, pos.y, 0, 1)
              ..rotateZ(charAngle - pi / 2),
          );

        _drawCenteredText(canvas, pdfFont, name[i], 0, 0, fontSize);

        canvas.restoreContext();
      }
    }
  }

  void _drawPlanetGlyphs(
    pw.Context context,
    double cx,
    double cy,
    double half,
  ) {
    final glyphSize = half * 0.065;

    for (final planet in planets) {
      final asset = planetGlyphs[planet.bodyName];
      if (asset == null) continue;
      final svgStr = svgCache[asset];
      if (svgStr == null) continue;

      final radius = planet.radiusFraction * half;
      final pos = _polar(planet.angle, radius, cx, cy);

      final svgImage = pw.SvgImage(
        svg: svgStr,
        width: glyphSize,
        height: glyphSize,
        colorFilter: const PdfColor.fromInt(0xFF000000),
      );

      svgImage.layout(
        context,
        pw.BoxConstraints.tightFor(width: glyphSize, height: glyphSize),
      );
      svgImage.box = PdfRect(
        pos.x - glyphSize / 2,
        pos.y - glyphSize / 2,
        glyphSize,
        glyphSize,
      );
      svgImage.paint(context);
    }
  }

  PdfPoint _polar(double angle, double radius, double cx, double cy) =>
      PdfPoint(cx + radius * cos(angle), cy + radius * sin(angle));

  void _drawCenteredText(
    PdfGraphics canvas,
    PdfFont pdfFont,
    String text,
    double x,
    double y,
    double fontSize, {
    PdfColor color = PdfColors.black,
  }) {
    final metrics = pdfFont.stringMetrics(text);
    final w = metrics.advanceWidth * fontSize;
    final h = fontSize;

    canvas
      ..setFillColor(color)
      ..drawString(pdfFont, fontSize, text, x - w / 2, y - h / 2);
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

pw.Widget _buildSoulStancesPanel(
  List<PlacedPlanet> planets,
  pw.Font font,
  pw.Font boldFont,
) {
  final adityaPlanets = planets
      .where((p) => p.horaBeingType == 'aditya')
      .toList();
  final nagaPlanets = planets.where((p) => p.horaBeingType == 'naga').toList();

  return pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Soul Stances of Your Planets',
          style: pw.TextStyle(font: boldFont, fontSize: 10),
        ),
        pw.SizedBox(height: 6),
        if (adityaPlanets.isNotEmpty) ...[
          pw.Text(
            'Aditya Stance',
            style: pw.TextStyle(font: boldFont, fontSize: 9),
          ),
          pw.Text(
            'These planets call you to express your love in the world.',
            style: pw.TextStyle(
              font: font,
              fontSize: 7,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 2),
          for (final p in adityaPlanets)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1),
              child: pw.Row(
                children: [
                  pw.Text(
                    _capitalize(p.bodyName),
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Text(
                    p.horaBeing ?? '',
                    style: pw.TextStyle(font: font, fontSize: 8),
                  ),
                ],
              ),
            ),
          pw.SizedBox(height: 6),
        ],
        if (nagaPlanets.isNotEmpty) ...[
          pw.Text(
            'Naga Stance',
            style: pw.TextStyle(font: boldFont, fontSize: 9),
          ),
          pw.Text(
            'These planets call you to dig deep into yourself.',
            style: pw.TextStyle(
              font: font,
              fontSize: 7,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 2),
          for (final p in nagaPlanets)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1),
              child: pw.Row(
                children: [
                  pw.Text(
                    _capitalize(p.bodyName),
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Text(
                    p.horaBeing ?? '',
                    style: pw.TextStyle(font: font, fontSize: 8),
                  ),
                ],
              ),
            ),
        ],
      ],
    ),
  );
}

pw.Widget _buildBeingsPanel(
  List<PlacedPlanet> planets,
  pw.Font font,
  pw.Font boldFont,
) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Your Beings',
          style: pw.TextStyle(font: boldFont, fontSize: 10),
        ),
        pw.SizedBox(height: 6),
        for (final p in planets)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1),
            child: pw.Row(
              children: [
                pw.Text(
                  _capitalize(p.bodyName),
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  '  ${_capitalize(p.trimsamsaBeingType ?? '')}',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  '  ${p.trimsamsaBeing ?? ''}',
                  style: pw.TextStyle(font: font, fontSize: 8),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
