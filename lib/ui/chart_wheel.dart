import 'dart:math';

import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'aditya_data.dart';
import 'being_content.dart';
import 'being_type_content.dart';
import 'chart_wheel_layout.dart';
import 'chart_wheel_painter.dart';
import 'planet_content.dart';

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
  ({String name, String type, String planet, int sign})? _selectedBeing;
  String? _selectedBeingType;
  String? _selectedPlanetInfo;
  Map<(int, String), BeingContent>? _beingContent;
  Map<String, BeingTypeContent>? _beingTypeContent;
  Map<String, PlanetContent>? _planetContent;

  late int _ascSign;
  late List<PlacedPlanet> _planets;
  late List<PlacedCusp> _cusps;

  @override
  void initState() {
    super.initState();
    _computeLayout();
    _loadContent();
  }

  Future<void> _loadContent() async {
    final results = await Future.wait([
      loadBeingContent(),
      loadBeingTypeContent(),
      loadPlanetContent(),
    ]);
    if (mounted) {
      setState(() {
        _beingContent = results[0] as Map<(int, String), BeingContent>;
        _beingTypeContent = results[1] as Map<String, BeingTypeContent>;
        _planetContent = results[2] as Map<String, PlanetContent>;
      });
    }
  }

  void _closeOverlay() => setState(() {
    _selectedPlanet = null;
    _selectedBeing = null;
    _selectedBeingType = null;
    _selectedPlanetInfo = null;
  });

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
        horaBeingSign: p.horaBeing.signNumber,
        trimsamsaBeing: p.trimsamsaBeing.name,
        trimsamsaBeingType: p.trimsamsaBeing.type.name,
        trimsamsaBeingSign: p.trimsamsaBeing.signNumber,
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
              if (_selectedBeingType != null)
                _buildBeingTypeOverlay(color, isDark),
              if (_selectedPlanetInfo != null)
                _buildPlanetOverlay(color, isDark),
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
                child: _buildSoulStancesPanel(
                  color: color,
                  backdropColor: backdropColor,
                  half: half,
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                width: panelWidth,
                child: _buildBeingsPanel(
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
        child: GestureDetector(
          onTap: () => setState(() {
            _selectedBeing = (
              name: data.name,
              type: 'aditya',
              planet: '',
              sign: sign,
            );
            _selectedPlanet = null;
          }),
          child: SizedBox(
            width: glyphSize,
            height: glyphSize,
            child: SvgPicture.asset(
              data.glyph,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
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

  Widget _buildSoulStancesPanel({
    required Color color,
    required Color backdropColor,
    required double half,
  }) {
    final fontSize = half * 0.032;
    final dimColor = color.withValues(alpha: 0.6);

    final adityaPlanets =
        _planets.where((p) => p.horaBeingType == 'aditya').toList();
    final nagaPlanets =
        _planets.where((p) => p.horaBeingType == 'naga').toList();

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
            'Soul Stances of Your Planets',
            style: TextStyle(
              color: color,
              fontSize: fontSize * 1.1,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (adityaPlanets.isNotEmpty) ...[
            Text(
              'Aditya Stance',
              style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'These planets call you to express your love in the world.',
              style: TextStyle(
                color: dimColor,
                fontSize: fontSize * 0.8,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 2),
            for (final p in adityaPlanets)
              _buildStanceRow(p, fontSize, color, dimColor),
            const SizedBox(height: 8),
          ],
          if (nagaPlanets.isNotEmpty) ...[
            Text(
              'Naga Stance',
              style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'These planets call you to dig deep into yourself.',
              style: TextStyle(
                color: dimColor,
                fontSize: fontSize * 0.8,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 2),
            for (final p in nagaPlanets)
              _buildStanceRow(p, fontSize, color, dimColor),
          ],
        ],
      ),
    );
  }

  Widget _buildStanceRow(
    PlacedPlanet p,
    double fontSize,
    Color color,
    Color dimColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() {
              _selectedPlanetInfo = p.bodyName;
              _selectedPlanet = null;
              _selectedBeing = null;
              _selectedBeingType = null;
            }),
            behavior: HitTestBehavior.opaque,
            child: Text(
              _capitalize(p.bodyName),
              style: TextStyle(color: dimColor, fontSize: fontSize),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() {
              _selectedBeing = (
                name: p.horaBeing ?? '',
                type: p.horaBeingType ?? '',
                planet: p.bodyName,
                sign: p.horaBeingSign ?? 0,
              );
              _selectedPlanet = null;
              _selectedBeingType = null;
              _selectedPlanetInfo = null;
            }),
            behavior: HitTestBehavior.opaque,
            child: Text(
              p.horaBeing ?? '',
              style: TextStyle(color: color, fontSize: fontSize),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeingsPanel({
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
            'Your Beings',
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
          for (final p in _planets)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedPlanetInfo = p.bodyName;
                      _selectedPlanet = null;
                      _selectedBeing = null;
                      _selectedBeingType = null;
                    }),
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      _capitalize(p.bodyName),
                      style: TextStyle(color: dimColor, fontSize: fontSize),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedBeingType = p.trimsamsaBeingType;
                      _selectedPlanet = null;
                      _selectedBeing = null;
                      _selectedPlanetInfo = null;
                    }),
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      '  ${_capitalize(p.trimsamsaBeingType ?? '')}',
                      style: TextStyle(color: dimColor, fontSize: fontSize),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedPlanet = p;
                      _selectedBeing = null;
                      _selectedBeingType = null;
                      _selectedPlanetInfo = null;
                    }),
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      '  ${p.trimsamsaBeing ?? ''}',
                      style: TextStyle(color: color, fontSize: fontSize),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBeingOverlay(Color color, bool isDark) {
    final cardBg = isDark ? const Color(0xF0151015) : const Color(0xF0F5F1EA);
    final dimColor = color.withValues(alpha: 0.6);

    int beingSign;
    String beingType;
    String planetName;
    List<Widget> infoRows;

    if (_selectedPlanet case final planet?) {
      planetName = planet.bodyName;
      beingSign = planet.trimsamsaBeingSign ?? 0;
      beingType = planet.trimsamsaBeingType ?? '';
      final signName = adityaSigns[planet.sign]?.name ?? '?';
      infoRows = [
        _infoRow('Position', '${planet.longitudeLabel} $signName', color),
        _tappableInfoRow(
          'Hora', planet.horaBeing ?? '—', color,
          () => setState(() {
            _selectedBeing = (
              name: planet.horaBeing ?? '',
              type: planet.horaBeingType ?? '',
              planet: planet.bodyName,
              sign: planet.horaBeingSign ?? 0,
            );
            _selectedPlanet = null;
            _selectedBeingType = null;
            _selectedPlanetInfo = null;
          }),
        ),
        _infoRow('Trimsamsa', planet.trimsamsaBeing ?? '—', color),
        if (planet.isRetrograde) _infoRow('Motion', 'Retrograde', color),
      ];
    } else if (_selectedBeing case final being?) {
      planetName = being.planet;
      beingSign = being.sign;
      beingType = being.type;
      infoRows = [
        _infoRow('Type', _capitalize(being.type), color),
        _infoRow('Being', being.name, color),
      ];
    } else {
      return const SizedBox.shrink();
    }

    final content = _beingContent?[(beingSign, beingType)];
    final imagePath = beingImagePath(beingSign, beingType);
    final glyphPath = adityaGlyphPath(beingSign);
    final planetGlyph = planetName.isNotEmpty ? planetGlyphs[planetName] : null;
    final headerGlyph = planetGlyph ?? glyphPath;
    final headerTitle = planetName.isNotEmpty
        ? _capitalize(planetName)
        : adityaName(beingSign) ?? '';

    return Positioned.fill(
      child: GestureDetector(
        onTap: _closeOverlay,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(44, 24, 44, 0),
                        child: Row(
                          children: [
                            if (headerGlyph != null) ...[
                              SvgPicture.asset(
                                headerGlyph,
                                width: 28,
                                height: 28,
                                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                headerTitle,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _closeOverlay,
                              icon: Icon(Icons.close, color: color, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(44, 0, 44, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...infoRows,
                        const SizedBox(height: 16),
                        if (imagePath.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              imagePath,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                height: 160,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    'Image not found',
                                    style: TextStyle(color: dimColor),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        if (glyphPath != null)
                          Center(
                            child: SvgPicture.asset(
                              glyphPath,
                              width: 28,
                              height: 28,
                              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                            ),
                          ),
                        if (content != null) ...[
                          const SizedBox(height: 16),
                          Center(
                            child: Text(
                              content.subtitle,
                              style: TextStyle(
                                color: isDark ? const Color(0xFFD4A855) : color,
                                fontSize: 16,
                                fontStyle: FontStyle.italic,
                                fontWeight: isDark ? null : FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            content.description,
                            style: TextStyle(
                              color: color.withValues(alpha: 0.85),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          if (content.reflections.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Center(
                              child: Text(
                                'Reflection',
                                style: TextStyle(
                                  color: isDark ? const Color(0xFFD4A855) : color,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              content.reflections,
                              style: TextStyle(
                                color: color.withValues(alpha: 0.85),
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBeingTypeOverlay(Color color, bool isDark) {
    final type = _selectedBeingType;
    if (type == null) return const SizedBox.shrink();

    final content = _beingTypeContent?[type];
    if (content == null) return const SizedBox.shrink();

    final cardBg = isDark ? const Color(0xF0151015) : const Color(0xF0F5F1EA);
    final emblemPath = beingTypeEmblemPath(type);

    return Positioned.fill(
      child: GestureDetector(
        onTap: _closeOverlay,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(44, 24, 44, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${content.type} — ${content.role}',
                                style: TextStyle(
                                  color: color,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _closeOverlay,
                              icon: Icon(Icons.close, color: color, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(44, 0, 44, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                content.subtitle,
                                style: TextStyle(
                                  color: isDark
                                      ? const Color(0xFFD4A855)
                                      : color,
                                  fontSize: 16,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: isDark ? null : FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.asset(
                                  emblemPath,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                content.description,
                                style: TextStyle(
                                  color: color.withValues(alpha: 0.85),
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanetOverlay(Color color, bool isDark) {
    final planetName = _selectedPlanetInfo;
    if (planetName == null) return const SizedBox.shrink();

    final content = _planetContent?[planetName];
    if (content == null) return const SizedBox.shrink();

    final cardBg = isDark ? const Color(0xF0151015) : const Color(0xF0F5F1EA);
    final glyphPath = planetGlyphs[planetName];
    final imagePath = planetImagePath(planetName);

    return Positioned.fill(
      child: GestureDetector(
        onTap: _closeOverlay,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(44, 24, 44, 0),
                        child: Row(
                          children: [
                            if (glyphPath != null) ...[
                              SvgPicture.asset(
                                glyphPath,
                                width: 28,
                                height: 28,
                                colorFilter: ColorFilter.mode(
                                    color, BlendMode.srcIn),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                content.name,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _closeOverlay,
                              icon: Icon(Icons.close, color: color, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(44, 0, 44, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                content.description,
                                style: TextStyle(
                                  color: color.withValues(alpha: 0.85),
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.asset(
                                  imagePath,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tappableInfoRow(String label, String value, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 14)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: TextStyle(color: color, fontSize: 14)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward, color: color.withValues(alpha: 0.4), size: 14),
              ],
            ),
          ],
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
