import 'dart:math';

import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'aditya_data.dart';
import 'chart_wheel_layout.dart';
import 'chart_wheel_painter.dart';

class ChartWheel extends StatefulWidget {
  final arrow.Chart chart;

  const ChartWheel({super.key, required this.chart});

  @override
  State<ChartWheel> createState() => _ChartWheelState();
}

class _ChartWheelState extends State<ChartWheel> {
  PlacedPlanet? _hoveredPlanet;
  PlacedCusp? _hoveredCusp;
  PlacedPlanet? _selectedPlanet;

  late int _ascSign;
  late List<PlacedPlanet> _planets;
  late List<PlacedCusp> _cusps;

  @override
  void initState() {
    super.initState();
    _computeLayout();
  }

  @override
  void didUpdateWidget(ChartWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chart != widget.chart) _computeLayout();
  }

  void _computeLayout() {
    _ascSign = widget.chart.cusp(1).sign;
    _cusps = _buildCusps();
    _planets = [];
  }

  List<PlacedCusp> _buildCusps() {
    return List.generate(12, (i) {
      final cusp = widget.chart.cusp(i + 1);
      return PlacedCusp(
        house: cusp.house,
        sign: cusp.sign,
        inSignDeg: cusp.longitude.inSignLongitude,
        angle: degreeToAngle(cusp.sign, cusp.longitude.inSignLongitude, _ascSign),
      );
    });
  }

  List<PlacedPlanet> _buildPlanets(double glyphAngularSize) {
    final grahas = widget.chart.grahas;

    // Group by sign.
    final bySign = <int, List<(int, arrow.Planet)>>{};
    for (var i = 0; i < grahas.length; i++) {
      final p = grahas[i];
      if (!defaultGrahas.contains(p.body.name)) continue;
      final sign = p.longitude.sign;
      (bySign[sign] ??= []).add((i, p));
    }

    final result = <PlacedPlanet>[];

    for (final entry in bySign.entries) {
      final sign = entry.key;
      final planets = entry.value;
      final degrees = planets.map((e) => e.$2.longitude.inSignLongitude).toList();

      final angles = resolvePlanetAngles(
        inSignDegrees: degrees,
        sign: sign,
        ascSign: _ascSign,
        glyphAngularSize: glyphAngularSize,
      );

      for (var i = 0; i < planets.length; i++) {
        final (_, p) = planets[i];
        result.add(PlacedPlanet(
          bodyName: p.body.name,
          sign: sign,
          inSignDeg: p.longitude.inSignLongitude,
          angle: angles[i],
          horaBeing: p.horaBeing.name,
          trimsamsaBeing: p.trimsamsaBeing.name,
          isRetrograde: p.isRetrograde,
        ));
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black;

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = min(constraints.maxWidth, constraints.maxHeight);
        final half = side / 2;
        final center = Offset(half, half);

        final planetGlyphSize = half * 0.065;
        final glyphAngularSize = planetGlyphSize / (half * planetMidRadius(1));

        // Compute planet positions based on current size.
        _planets = _buildPlanets(glyphAngularSize);

        return SizedBox(
          width: side,
          height: side,
          child: Stack(
            children: [
              // Geometric skeleton.
              Positioned.fill(
                child: CustomPaint(
                  painter: ChartWheelPainter(
                    color: color,
                    ascSign: _ascSign,
                    cusps: _cusps,
                  ),
                ),
              ),
              // Sign glyphs in outer ring.
              for (var s = 1; s <= 12; s++)
                _buildSignGlyph(s, half, center, color),
              // Planet glyphs.
              for (final planet in _planets)
                _buildPlanetGlyph(planet, half, center, color, planetGlyphSize),
              // Cusp hit regions.
              for (final cusp in _cusps)
                _buildCuspHitRegion(cusp, half, center, color),
              // Center info overlay.
              if (_hoveredPlanet != null || _hoveredCusp != null)
                _buildCenterInfo(half, center, color),
              // Being card overlay.
              if (_selectedPlanet != null) _buildBeingOverlay(color),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSignGlyph(
    int sign,
    double half,
    Offset center,
    Color color,
  ) {
    final angle = signMidAngle(sign, _ascSign);
    final radius = signMidRadius(half);
    final pos = polarToCartesian(angle, radius, center);
    final glyphSize = half * 0.10;
    final data = adityaSigns[sign]!;

    return Positioned(
      left: pos.dx - glyphSize / 2,
      top: pos.dy - glyphSize / 2,
      child: SizedBox(
        width: glyphSize,
        height: glyphSize,
        child: SvgPicture.asset(
          data.glyph,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        ),
      ),
    );
  }

  Widget _buildPlanetGlyph(
    PlacedPlanet planet,
    double half,
    Offset center,
    Color color,
    double glyphSize,
  ) {
    final radius = planetMidRadius(half);
    final pos = polarToCartesian(planet.angle, radius, center);
    final asset = planetGlyphs[planet.bodyName];

    if (asset == null) return const SizedBox.shrink();

    return Positioned(
      left: pos.dx - glyphSize / 2,
      top: pos.dy - glyphSize / 2,
      child: MouseRegion(
        onEnter: (_) => setState(() {
          _hoveredPlanet = planet;
          _hoveredCusp = null;
        }),
        onExit: (_) => setState(() => _hoveredPlanet = null),
        child: GestureDetector(
          onTap: () => setState(() => _selectedPlanet = planet),
          child: SizedBox(
            width: glyphSize,
            height: glyphSize,
            child: SvgPicture.asset(
              asset,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCuspHitRegion(
    PlacedCusp cusp,
    double half,
    Offset center,
    Color color,
  ) {
    final radius = half * (houseRingInner + 0.05);
    final pos = polarToCartesian(cusp.angle, radius, center);
    final hitSize = half * 0.06;

    return Positioned(
      left: pos.dx - hitSize / 2,
      top: pos.dy - hitSize / 2,
      child: MouseRegion(
        onEnter: (_) => setState(() {
          _hoveredCusp = cusp;
          _hoveredPlanet = null;
        }),
        onExit: (_) => setState(() => _hoveredCusp = null),
        child: SizedBox(width: hitSize, height: hitSize),
      ),
    );
  }

  Widget _buildCenterInfo(double half, Offset center, Color color) {
    final infoRadius = half * houseRingInner * 0.85;
    final fontSize = half * 0.038;

    List<String> lines;
    if (_hoveredPlanet case final p?) {
      final signName = adityaSigns[p.sign]?.name ?? '?';
      lines = [
        _capitalize(p.bodyName),
        "${p.longitudeLabel} $signName${p.isRetrograde ? ' (R)' : ''}",
        'Hora: ${p.horaBeing ?? '—'}',
        'Trimsamsa: ${p.trimsamsaBeing ?? '—'}',
      ];
    } else if (_hoveredCusp case final c?) {
      final signName = adityaSigns[c.sign]?.name ?? '?';
      lines = [
        'Cusp ${romanNumeral(c.house)}',
        '${c.longitudeLabel} $signName',
      ];
    } else {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: center.dx - infoRadius,
      top: center.dy - infoRadius,
      child: SizedBox(
        width: infoRadius * 2,
        height: infoRadius * 2,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final line in lines)
                Text(
                  line,
                  style: TextStyle(color: color, fontSize: fontSize),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBeingOverlay(Color color) {
    final planet = _selectedPlanet!;
    final signName = adityaSigns[planet.sign]?.name ?? '?';

    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _selectedPlanet = null),
        child: Container(
          color: Colors.black.withValues(alpha: 0.7),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _capitalize(planet.bodyName),
                          style: TextStyle(
                            color: color,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              setState(() => _selectedPlanet = null),
                          icon: Icon(Icons.close, color: color, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Placeholder for being image.
                    Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'Being image',
                          style: TextStyle(color: color.withValues(alpha: 0.3)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _infoRow('Position', '${planet.longitudeLabel} $signName', color),
                    _infoRow('Hora', planet.horaBeing ?? '—', color),
                    _infoRow('Trimsamsa', planet.trimsamsaBeing ?? '—', color),
                    if (planet.isRetrograde)
                      _infoRow('Motion', 'Retrograde', color),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 14)),
          Text(value, style: TextStyle(color: color, fontSize: 14)),
        ],
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
