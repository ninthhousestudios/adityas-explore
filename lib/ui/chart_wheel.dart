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
  int? _hoveredSign;
  PlacedPlanet? _selectedPlanet;
  ({String name, String type, String planet})? _selectedBeing;

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

  List<PlacedPlanet> _buildPlanets(double half, double glyphSize) {
    final grahas = widget.chart.grahas;

    final filtered = <arrow.Planet>[];
    for (final p in grahas) {
      if (defaultGrahas.contains(p.body.name)) filtered.add(p);
    }

    final positions = resolvePlanetPositions(
      planets: filtered
          .map((p) => (sign: p.longitude.sign, inSignDeg: p.longitude.inSignLongitude))
          .toList(),
      ascSign: _ascSign,
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
        trimsamsaBeing: p.trimsamsaBeing.name,
        trimsamsaBeingType: p.trimsamsaBeing.type.name,
        isRetrograde: p.isRetrograde,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black;
    final backdropColor = isDark
        ? Colors.black.withValues(alpha: 0.5)
        : Colors.white.withValues(alpha: 0.5);

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = min(constraints.maxWidth, constraints.maxHeight);
        final half = side / 2;
        final center = Offset(half, half);
        final panelMargin = (constraints.maxWidth - side) / 2;

        final planetGlyphSize = half * 0.065;

        // Compute planet positions based on current size.
        _planets = _buildPlanets(half, planetGlyphSize);

        final wheel = SizedBox(
          width: side,
          height: side,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: ChartWheelPainter(
                    color: color,
                    backdropColor: backdropColor,
                    ascSign: _ascSign,
                    cusps: _cusps,
                  ),
                ),
              ),
              for (var s = 1; s <= 12; s++)
                _buildSignGlyph(s, half, center, color),
              for (final planet in _planets)
                _buildPlanetGlyph(planet, half, center, color, planetGlyphSize),
              for (final cusp in _cusps)
                _buildCuspHitRegion(cusp, half, center, color),
              _buildCenterInfo(half, center, color),
              if (_selectedPlanet != null || _selectedBeing != null)
                _buildBeingOverlay(color, isDark),
            ],
          ),
        );

        if (_planets.isEmpty || panelMargin < 80) return wheel;

        final panelWidth = panelMargin - 16;
        return SizedBox(
          width: constraints.maxWidth,
          height: side,
          child: Stack(
            children: [
              Positioned(
                left: panelMargin,
                top: 0,
                width: side,
                height: side,
                child: wheel,
              ),
              Positioned(
                left: 8,
                top: 0,
                width: panelWidth,
                child: _buildBeingPanel(
                  title: 'Hora',
                  entries: _planets.map((p) => (
                    planet: p.bodyName,
                    type: p.horaBeingType ?? '',
                    name: p.horaBeing ?? '',
                  )).toList(),
                  onTap: (e) => setState(() {
                    _selectedBeing = e;
                    _selectedPlanet = null;
                  }),
                  color: color,
                  backdropColor: backdropColor,
                  half: half,
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                width: panelWidth,
                child: _buildBeingPanel(
                  title: 'Trimsamsa',
                  entries: _planets.map((p) => (
                    planet: p.bodyName,
                    type: p.trimsamsaBeingType ?? '',
                    name: p.trimsamsaBeing ?? '',
                  )).toList(),
                  onTap: (e) {
                    final planet = _planets.firstWhere(
                      (p) => p.bodyName == e.planet,
                    );
                    setState(() {
                      _selectedPlanet = planet;
                      _selectedBeing = null;
                    });
                  },
                  color: color,
                  backdropColor: backdropColor,
                  half: half,
                ),
              ),
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
      child: MouseRegion(
        onEnter: (_) => setState(() {
          _hoveredSign = sign;
          _hoveredPlanet = null;
          _hoveredCusp = null;
        }),
        onExit: (_) => setState(() => _hoveredSign = null),
        child: SizedBox(
          width: glyphSize,
          height: glyphSize,
          child: SvgPicture.asset(
            data.glyph,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
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
    final radius = planet.radiusFraction * half;
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
          onTap: () => setState(() {
            if (_hoveredPlanet?.bodyName == planet.bodyName) {
              _selectedPlanet = planet;
              _selectedBeing = null;
            } else {
              _hoveredPlanet = planet;
              _hoveredCusp = null;
              _hoveredSign = null;
            }
          }),
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
    var showHint = false;
    if (_hoveredPlanet case final p?) {
      final signName = adityaSigns[p.sign]?.name ?? '?';
      lines = [
        _capitalize(p.bodyName),
        "${p.longitudeLabel} $signName${p.isRetrograde ? ' (R)' : ''}",
        'Hora: ${p.horaBeing ?? '—'}',
        'Trimsamsa: ${p.trimsamsaBeing ?? '—'}',
      ];
      showHint = true;
    } else if (_hoveredCusp case final c?) {
      final signName = adityaSigns[c.sign]?.name ?? '?';
      lines = [
        'Cusp ${romanNumeral(c.house)}',
        '${c.longitudeLabel} $signName',
      ];
    } else if (_hoveredSign case final s?) {
      lines = [adityaSigns[s]?.name ?? '?'];
    } else {
      lines = [];
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
              if (lines.isEmpty)
                Text(
                  'Tap a planet to learn\nwhich being it activates',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.35),
                    fontSize: fontSize * 0.9,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                )
              else ...[
                for (final line in lines)
                  Text(
                    line,
                    style: TextStyle(color: color, fontSize: fontSize),
                    textAlign: TextAlign.center,
                  ),
                if (showHint) ...[
                  SizedBox(height: fontSize * 0.5),
                  Text(
                    'tap to find out more',
                    style: TextStyle(
                      color: color.withValues(alpha: 0.4),
                      fontSize: fontSize * 0.8,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBeingPanel({
    required String title,
    required List<({String planet, String type, String name})> entries,
    required void Function(({String name, String type, String planet})) onTap,
    required Color color,
    required Color backdropColor,
    required double half,
  }) {
    final fontSize = half * 0.032;
    final dimColor = color.withValues(alpha: 0.6);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backdropColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: fontSize * 1.1,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'click to find out more',
            style: TextStyle(
              color: dimColor,
              fontSize: fontSize * 0.8,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 4),
          for (final e in entries)
            GestureDetector(
              onTap: () => onTap((name: e.name, type: e.type, planet: e.planet)),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _capitalize(e.planet),
                      style: TextStyle(color: dimColor, fontSize: fontSize),
                    ),
                    Text(
                      '  ${_capitalize(e.type)}',
                      style: TextStyle(color: dimColor, fontSize: fontSize),
                    ),
                    Text(
                      '  ${e.name}',
                      style: TextStyle(color: color, fontSize: fontSize),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBeingOverlay(Color color, bool isDark) {
    final cardBg = isDark ? const Color(0xF0151015) : const Color(0xF0F5F1EA);

    final String cardTitle;
    final List<Widget> infoRows;

    if (_selectedPlanet case final planet?) {
      final signName = adityaSigns[planet.sign]?.name ?? '?';
      cardTitle = _capitalize(planet.bodyName);
      infoRows = [
        _infoRow('Position', '${planet.longitudeLabel} $signName', color),
        _infoRow('Hora', planet.horaBeing ?? '—', color),
        _infoRow('Trimsamsa', planet.trimsamsaBeing ?? '—', color),
        if (planet.isRetrograde) _infoRow('Motion', 'Retrograde', color),
      ];
    } else if (_selectedBeing case final being?) {
      cardTitle = _capitalize(being.planet);
      infoRows = [
        _infoRow('Type', _capitalize(being.type), color),
        _infoRow('Being', being.name, color),
      ];
    } else {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cardBg,
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
                    cardTitle,
                    style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      _selectedPlanet = null;
                      _selectedBeing = null;
                    }),
                    icon: Icon(Icons.close, color: color, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
              ...infoRows,
            ],
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
