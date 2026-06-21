import 'dart:math';

import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../astro/being_uncertainty.dart';
import '../share_util.dart'
    if (dart.library.js_interop) '../share_util_web.dart';
import 'aditya_data.dart';
import 'being_content.dart';
import 'being_type_content.dart';
import 'chart_wheel_layout.dart';
import 'chart_wheel_painter.dart';
import 'planet_content.dart';

extension CapitalizeString on String {
  String toCapitalized() =>
      isNotEmpty ? '${this[0].toUpperCase()}${substring(1)}' : '';
}

class ChartWheel extends StatefulWidget {
  final arrow.Chart chart;
  final BeingUncertainty? uncertainty;

  const ChartWheel({super.key, required this.chart, this.uncertainty});

  @override
  State<ChartWheel> createState() => _ChartWheelState();
}

enum _UncertainKind { trimsamsa, hora }

sealed class _PopupState {}

class _BeingFromPlanet extends _PopupState {
  final PlacedPlanet planet;
  _BeingFromPlanet(this.planet);
}

class _BeingFromName extends _PopupState {
  final ({String name, String type, String planet, int sign}) being;
  _BeingFromName(this.being);
}

class _BeingTypePopupState extends _PopupState {
  final String type;
  _BeingTypePopupState(this.type);
}

class _PlanetPopupState extends _PopupState {
  final String planet;
  _PlanetPopupState(this.planet);
}

class _UncertaintyPopupState extends _PopupState {
  final String planet;
  final _UncertainKind kind;
  _UncertaintyPopupState(this.planet, this.kind);
}

class _ChartWheelState extends State<ChartWheel> {
  PlacedPlanet? _hoveredPlanet;
  PlacedCusp? _hoveredCusp;

  final List<_PopupState> _popupStack = [];
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

  void _closeOverlay() => setState(() => _popupStack.clear());

  void _openPopup(_PopupState state) => setState(() {
    _popupStack
      ..clear()
      ..add(state);
  });

  void _pushPopup(_PopupState state) => setState(() => _popupStack.add(state));

  void _popPopup() => setState(() {
    if (_popupStack.isNotEmpty) _popupStack.removeLast();
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
        angle: degreeToAngle(
          cusp.sign,
          cusp.longitude.inSignLongitude,
          _ascSign,
        ),
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
          .map(
            (p) => (
              sign: p.longitude.sign,
              inSignDeg: p.longitude.inSignLongitude,
            ),
          )
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
            clipBehavior: Clip.none,
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
              if (_popupStack.isNotEmpty)
                switch (_popupStack.last) {
                  _BeingFromPlanet(:final planet) => _buildBeingOverlay(
                    color,
                    isDark,
                    planet: planet,
                  ),
                  _BeingFromName(:final being) => _buildBeingOverlay(
                    color,
                    isDark,
                    being: being,
                  ),
                  _BeingTypePopupState(:final type) => _buildBeingTypeOverlay(
                    color,
                    isDark,
                    type,
                  ),
                  _PlanetPopupState(:final planet) => _buildPlanetOverlay(
                    color,
                    isDark,
                    planet,
                  ),
                  _UncertaintyPopupState(:final planet, :final kind) =>
                    _buildUncertaintyChooser(color, isDark, planet, kind),
                },
            ],
          ),
        );

        if (_planets.isEmpty || panelMargin < 80) return wheel;

        final panelWidth = panelMargin - 16;
        return SizedBox(
          width: constraints.maxWidth,
          height: side,
          child: Stack(
            clipBehavior: Clip.none,
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

  Widget _buildSignGlyph(int sign, double half, Offset center, Color color) {
    final angle = signMidAngle(sign, _ascSign);
    final radius = signMidRadius(half);
    final data = adityaSigns[sign]!;
    final name = data.name.toUpperCase();
    final fontSize = half * 0.052;
    final naturalSpacing = fontSize * 0.85 / radius;
    final maxSpan = 0.85 * pi / 6;
    final totalNatural = name.length > 1
        ? (name.length - 1) * naturalSpacing
        : 0.0;
    final spacing = name.length > 1
        ? (totalNatural > maxSpan
              ? maxSpan / (name.length - 1)
              : naturalSpacing)
        : 0.0;
    final totalSpan = (name.length - 1) * spacing;
    final startAngle = angle - totalSpan / 2;

    void onTap() => _openPopup(
      _BeingFromName((name: data.name, type: 'aditya', planet: '', sign: sign)),
    );

    return Positioned.fill(
      child: Stack(
        children: [
          for (var i = 0; i < name.length; i++)
            _buildArcLetter(
              name[i],
              startAngle + i * spacing,
              radius,
              center,
              color,
              fontSize,
              onTap,
            ),
        ],
      ),
    );
  }

  Widget _buildArcLetter(
    String letter,
    double angle,
    double radius,
    Offset center,
    Color color,
    double fontSize,
    VoidCallback onTap,
  ) {
    final pos = polarToCartesian(angle, radius, center);
    final boxSize = fontSize * 1.2;
    return Positioned(
      left: pos.dx - boxSize / 2,
      top: pos.dy - boxSize / 2,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Transform.rotate(
            angle: angle + pi / 2,
            child: SizedBox(
              width: boxSize,
              height: boxSize,
              child: Center(
                child: Text(
                  letter,
                  style: TextStyle(
                    color: color,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
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
          onTap: () {
            if (_hoveredPlanet?.bodyName == planet.bodyName) {
              final u = widget.uncertainty;
              final uncertain = u?.isUncertain(planet.bodyName) ?? false;
              if (uncertain) {
                final kind = u!.isTrimsamsaUncertain(planet.bodyName)
                    ? _UncertainKind.trimsamsa
                    : _UncertainKind.hora;
                _openPopup(_UncertaintyPopupState(planet.bodyName, kind));
              } else {
                _openPopup(_BeingFromPlanet(planet));
              }
            } else {
              setState(() {
                _hoveredPlanet = planet;
                _hoveredCusp = null;
              });
            }
          },
          child: SizedBox(
            width: glyphSize,
            height: glyphSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SvgPicture.asset(
                  asset,
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                ),
                if (widget.uncertainty?.isUncertain(planet.bodyName) ?? false)
                  Positioned(
                    right: -glyphSize * 0.15,
                    bottom: 0,
                    child: Text(
                      '~',
                      style: TextStyle(
                        color: color.withValues(alpha: 0.7),
                        fontSize: glyphSize * 0.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
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
        'Soul Stance: ${(p.horaBeingType ?? '').toCapitalized()} • ${p.horaBeing ?? '—'}',
        'Being: ${p.trimsamsaBeing ?? '—'}',
      ];
      showHint = true;
    } else if (_hoveredCusp case final c?) {
      final signName = adityaSigns[c.sign]?.name ?? '?';
      lines = [
        'Cusp ${romanNumeral(c.house)}',
        '${c.longitudeLabel} $signName',
      ];
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
                  'Tap any glyph or name to learn more',
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

    final adityaPlanets = _planets
        .where((p) => p.horaBeingType == 'aditya')
        .toList();
    final nagaPlanets = _planets
        .where((p) => p.horaBeingType == 'naga')
        .toList();

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
            GestureDetector(
              onTap: () => _openPopup(_BeingTypePopupState('aditya')),
              behavior: HitTestBehavior.opaque,
              child: Text(
                'Aditya Stance',
                style: TextStyle(
                  color: color,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
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
            GestureDetector(
              onTap: () => _openPopup(_BeingTypePopupState('naga')),
              behavior: HitTestBehavior.opaque,
              child: Text(
                'Naga Stance',
                style: TextStyle(
                  color: color,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
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
            onTap: () => _openPopup(_PlanetPopupState(p.bodyName)),
            behavior: HitTestBehavior.opaque,
            child: Text(
              _capitalize(p.bodyName),
              style: TextStyle(color: dimColor, fontSize: fontSize),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              final horaUncertain =
                  widget.uncertainty?.isHoraUncertain(p.bodyName) ?? false;
              if (horaUncertain) {
                _openPopup(
                  _UncertaintyPopupState(p.bodyName, _UncertainKind.hora),
                );
              } else {
                _openPopup(
                  _BeingFromName((
                    name: p.horaBeing ?? '',
                    type: p.horaBeingType ?? '',
                    planet: p.bodyName,
                    sign: p.horaBeingSign ?? 0,
                  )),
                );
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Text(
              '${p.horaBeing ?? ''}'
              '${(widget.uncertainty?.isHoraUncertain(p.bodyName) ?? false) ? ' ~' : ''}',
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
                    onTap: () => _openPopup(_PlanetPopupState(p.bodyName)),
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      _capitalize(p.bodyName),
                      style: TextStyle(color: dimColor, fontSize: fontSize),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _openPopup(
                      _BeingTypePopupState(p.trimsamsaBeingType ?? ''),
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      '  ${_capitalize(p.trimsamsaBeingType ?? '')}',
                      style: TextStyle(color: dimColor, fontSize: fontSize),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      final uncertain =
                          widget.uncertainty?.isTrimsamsaUncertain(
                            p.bodyName,
                          ) ??
                          false;
                      if (uncertain) {
                        _openPopup(
                          _UncertaintyPopupState(
                            p.bodyName,
                            _UncertainKind.trimsamsa,
                          ),
                        );
                      } else {
                        _openPopup(_BeingFromPlanet(p));
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      '  ${p.trimsamsaBeing ?? ''}'
                      '${(widget.uncertainty?.isTrimsamsaUncertain(p.bodyName) ?? false) ? ' ~' : ''}',
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

  Widget _buildBeingOverlay(
    Color color,
    bool isDark, {
    PlacedPlanet? planet,
    ({String name, String type, String planet, int sign})? being,
  }) {
    final cardBg = isDark ? const Color(0xF0151015) : const Color(0xF0F5F1EA);
    final dimColor = color.withValues(alpha: 0.6);

    int beingSign;
    String beingType;
    String planetName;
    List<Widget> infoRows;

    String beingName;

    if (planet case final planet?) {
      planetName = planet.bodyName;
      beingSign = planet.trimsamsaBeingSign ?? 0;
      beingType = planet.trimsamsaBeingType ?? '';
      beingName = planet.trimsamsaBeing ?? '';
      final signName = adityaSigns[planet.sign]?.name ?? '?';
      infoRows = [
        _infoRow('Position', '${planet.longitudeLabel} $signName', color),
        _tappableInfoRow(
          'Type',
          _capitalize(beingType),
          color,
          () => _pushPopup(_BeingTypePopupState(beingType)),
        ),
        _soulStanceRow(
          planet.horaBeingType ?? '',
          planet.horaBeing ?? '',
          planet.bodyName,
          planet.horaBeingSign ?? 0,
          color,
        ),
        if (planet.isRetrograde) _infoRow('Motion', 'Retrograde', color),
      ];
    } else if (being case final being?) {
      planetName = being.planet;
      beingSign = being.sign;
      beingType = being.type;
      beingName = being.name;
      infoRows = [
        _tappableInfoRow(
          'Type',
          _capitalize(being.type),
          color,
          () => _pushPopup(_BeingTypePopupState(being.type)),
        ),
      ];
    } else {
      return const SizedBox.shrink();
    }

    final content = _beingContent?[(beingSign, beingType)];
    final imagePath = beingImagePath(beingSign, beingType);
    final glyphPath = beingTypeGlyphPath(beingType);
    final planetGlyph = planetName.isNotEmpty ? planetGlyphs[planetName] : null;
    final headerTitle = planetName.isNotEmpty
        ? '${_capitalize(planetName)} — $beingName'
        : beingName.isNotEmpty
        ? beingName
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
                            if (_popupStack.length > 1) ...[
                              IconButton(
                                onPressed: _popPopup,
                                icon: Icon(
                                  Icons.arrow_back,
                                  color: color,
                                  size: 20,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (planetGlyph != null) ...[
                              SvgPicture.asset(
                                planetGlyph,
                                width: 28,
                                height: 28,
                                colorFilter: ColorFilter.mode(
                                  color,
                                  BlendMode.srcIn,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ] else if (glyphPath != null) ...[
                              ColorFiltered(
                                colorFilter: ColorFilter.mode(
                                  color,
                                  BlendMode.srcIn,
                                ),
                                child: Image.asset(
                                  glyphPath,
                                  width: 28,
                                  height: 28,
                                ),
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
                              const SizedBox(height: 12),
                              Center(
                                child: _ShareBeingButton(
                                  sign: beingSign,
                                  beingType: beingType,
                                  beingName: beingName,
                                  planetName: planetName,
                                  color: color,
                                  isDark: isDark,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (glyphPath != null)
                                Center(
                                  child: ColorFiltered(
                                    colorFilter: ColorFilter.mode(
                                      color,
                                      BlendMode.srcIn,
                                    ),
                                    child: Image.asset(
                                      glyphPath,
                                      width: 56,
                                      height: 56,
                                    ),
                                  ),
                                ),
                              if (content != null) ...[
                                const SizedBox(height: 16),
                                Center(
                                  child: Text(
                                    content.subtitle,
                                    style: TextStyle(
                                      color: isDark
                                          ? const Color(0xFFD4A855)
                                          : color,
                                      fontSize: 16,
                                      fontStyle: FontStyle.italic,
                                      fontWeight: isDark
                                          ? null
                                          : FontWeight.bold,
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
                                        color: isDark
                                            ? const Color(0xFFD4A855)
                                            : color,
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

  Widget _buildUncertaintyChooser(
    Color color,
    bool isDark,
    String planetName,
    _UncertainKind uncertainKind,
  ) {
    final uncertainty = widget.uncertainty;
    if (uncertainty == null) return const SizedBox.shrink();

    final options = uncertainKind == _UncertainKind.hora
        ? uncertainty.horaFor(planetName)
        : uncertainty.trimsamsaFor(planetName);
    if (options.isEmpty) return const SizedBox.shrink();

    final label = uncertainKind == _UncertainKind.hora
        ? 'soul stance'
        : 'being';

    final cardBg = isDark ? const Color(0xF0151015) : const Color(0xF0F5F1EA);
    final dimColor = color.withValues(alpha: 0.6);
    final accentColor = isDark
        ? const Color(0xFFD4A853)
        : const Color(0xFF8B6F37);

    return Positioned.fill(
      child: GestureDetector(
        onTap: _closeOverlay,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_popupStack.length > 1) ...[
                        GestureDetector(
                          onTap: _popPopup,
                          child: Icon(Icons.arrow_back, size: 18, color: color),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          'Your ${_capitalize(planetName)} $label could be:',
                          style: TextStyle(
                            color: color,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _closeOverlay,
                        child: Icon(Icons.close, size: 18, color: dimColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final option in options) ...[
                    GestureDetector(
                      onTap: () => _pushPopup(
                        _BeingFromName((
                          name: option.name,
                          type: option.type,
                          planet: planetName,
                          sign: option.sign,
                        )),
                      ),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Text(
                              '▸  ',
                              style: TextStyle(
                                color: accentColor,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              option.name,
                              style: TextStyle(
                                color: color,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '  ${_capitalize(option.type)} of '
                              '${adityaName(option.sign) ?? '?'}',
                              style: TextStyle(color: dimColor, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Tap a being to learn more.',
                    style: TextStyle(
                      color: dimColor,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
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

  Widget _buildBeingTypeOverlay(Color color, bool isDark, String type) {
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
                            if (_popupStack.length > 1) ...[
                              IconButton(
                                onPressed: _popPopup,
                                icon: Icon(
                                  Icons.arrow_back,
                                  color: color,
                                  size: 20,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 8),
                            ],
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

  Widget _buildPlanetOverlay(Color color, bool isDark, String planetName) {
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
                            if (_popupStack.length > 1) ...[
                              IconButton(
                                onPressed: _popPopup,
                                icon: Icon(
                                  Icons.arrow_back,
                                  color: color,
                                  size: 20,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (glyphPath != null) ...[
                              SvgPicture.asset(
                                glyphPath,
                                width: 28,
                                height: 28,
                                colorFilter: ColorFilter.mode(
                                  color,
                                  BlendMode.srcIn,
                                ),
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

  Widget _tappableInfoRow(
    String label,
    String value,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: TextStyle(color: color, fontSize: 14)),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward,
                  color: color.withValues(alpha: 0.4),
                  size: 14,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _soulStanceRow(
    String horaType,
    String horaName,
    String planetName,
    int horaSign,
    Color color,
  ) {
    final dimColor = color.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Soul Stance', style: TextStyle(color: dimColor, fontSize: 14)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _pushPopup(_BeingTypePopupState(horaType)),
                behavior: HitTestBehavior.opaque,
                child: Text(
                  _capitalize(horaType),
                  style: TextStyle(color: color, fontSize: 14),
                ),
              ),
              Text(' — ', style: TextStyle(color: dimColor, fontSize: 14)),
              GestureDetector(
                onTap: () => _pushPopup(
                  _BeingFromName((
                    name: horaName,
                    type: horaType,
                    planet: planetName,
                    sign: horaSign,
                  )),
                ),
                behavior: HitTestBehavior.opaque,
                child: Text(
                  horaName,
                  style: TextStyle(color: color, fontSize: 14),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward,
                color: color.withValues(alpha: 0.4),
                size: 14,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 14),
          ),
          Text(value, style: TextStyle(color: color, fontSize: 14)),
        ],
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _ShareBeingButton extends StatefulWidget {
  final int sign;
  final String beingType;
  final String beingName;
  final String planetName;
  final Color color;
  final bool isDark;

  const _ShareBeingButton({
    required this.sign,
    required this.beingType,
    required this.beingName,
    required this.planetName,
    required this.color,
    required this.isDark,
  });

  @override
  State<_ShareBeingButton> createState() => _ShareBeingButtonState();
}

class _ShareBeingButtonState extends State<_ShareBeingButton> {
  bool _loading = false;

  Future<void> _share() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await shareBeingCard(
        sign: widget.sign,
        beingType: widget.beingType,
        beingName: widget.beingName,
        planetName: widget.planetName,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isDark
        ? const Color(0xFFD4A853)
        : const Color(0xFF8B6F37);
    return GestureDetector(
      onTap: _share,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_loading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: accent),
            )
          else
            Icon(Icons.share, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            _loading ? 'Sharing...' : 'Share my Being',
            style: TextStyle(
              color: accent,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
