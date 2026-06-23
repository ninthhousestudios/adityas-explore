import 'dart:math';

import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../astro/being_uncertainty.dart';
import 'aditya_data.dart';
import 'being_overlay.dart';
import 'beings_panel.dart';
import 'overlay_shell.dart';
import 'being_content.dart';
import 'being_type_content.dart';
import 'chart_wheel_layout.dart';
import 'chart_wheel_painter.dart';
import 'planet_content.dart';
import 'popup_state.dart';
import 'soul_stances_panel.dart';
import 'waitlist_cta.dart';

extension CapitalizeString on String {
  String toCapitalized() =>
      isNotEmpty ? '${this[0].toUpperCase()}${substring(1)}' : '';
}

class ChartWheel extends StatefulWidget {
  final arrow.Chart chart;
  final BeingUncertainty? uncertainty;
  final bool waitlistSigned;
  final VoidCallback onWaitlistSigned;

  const ChartWheel({
    super.key,
    required this.chart,
    this.uncertainty,
    this.waitlistSigned = false,
    required this.onWaitlistSigned,
  });

  @override
  State<ChartWheel> createState() => _ChartWheelState();
}

class _ChartWheelState extends State<ChartWheel> {
  PlacedPlanet? _hoveredPlanet;
  PlacedCusp? _hoveredCusp;

  final List<PopupState> _popupStack = [];
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
      for (final type in _beingTypeContent!.keys) {
        precacheImage(AssetImage(beingTypeEmblemPath(type)), context);
      }
    }
  }

  void _closeOverlay() => setState(() => _popupStack.clear());

  void _openPopup(PopupState state) => setState(() {
    _popupStack
      ..clear()
      ..add(state);
  });

  void _pushPopup(PopupState state) => setState(() => _popupStack.add(state));

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
                  BeingFromPlanet(:final planet) => _buildBeingShell(
                    color,
                    isDark,
                    planet: planet,
                  ),
                  BeingFromName(:final being) => _buildBeingShell(
                    color,
                    isDark,
                    being: being,
                  ),
                  BeingTypePopup(:final type) => _buildBeingTypeOverlay(
                    color,
                    isDark,
                    type,
                  ),
                  PlanetPopup(:final planet) => _buildPlanetOverlay(
                    color,
                    isDark,
                    planet,
                  ),
                  UncertaintyPopup(:final planet, :final kind) =>
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
                child: SoulStancesPanel(
                  planets: _planets,
                  uncertainty: widget.uncertainty,
                  color: color,
                  backdropColor: backdropColor,
                  fontSize: half * 0.032,
                  onOpen: _openPopup,
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                width: panelWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BeingsPanel(
                      planets: _planets,
                      uncertainty: widget.uncertainty,
                      color: color,
                      backdropColor: backdropColor,
                      fontSize: half * 0.032,
                      onOpen: _openPopup,
                    ),
                    const SizedBox(height: 8),
                    WaitlistCta(
                      color: color,
                      backdropColor: backdropColor,
                      fontSize: half * 0.032,
                      signed: widget.waitlistSigned,
                      onSigned: widget.onWaitlistSigned,
                    ),
                  ],
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
      BeingFromName((name: data.name, type: 'aditya', planet: '', sign: sign)),
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
                    ? UncertainKind.trimsamsa
                    : UncertainKind.hora;
                _openPopup(UncertaintyPopup(planet.bodyName, kind));
              } else {
                _openPopup(BeingFromPlanet(planet));
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

  Widget _buildUncertaintyChooser(
    Color color,
    bool isDark,
    String planetName,
    UncertainKind uncertainKind,
  ) {
    final uncertainty = widget.uncertainty;
    if (uncertainty == null) return const SizedBox.shrink();

    final options = uncertainKind == UncertainKind.hora
        ? uncertainty.horaFor(planetName)
        : uncertainty.trimsamsaFor(planetName);
    if (options.isEmpty) return const SizedBox.shrink();

    final label = uncertainKind == UncertainKind.hora ? 'soul stance' : 'being';

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
                        BeingFromName((
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

  Widget _buildBeingShell(
    Color color,
    bool isDark, {
    PlacedPlanet? planet,
    ({String name, String type, String planet, int sign})? being,
  }) {
    final header = beingOverlayHeader(
      color: color,
      planet: planet,
      being: being,
    );
    return OverlayShell(
      color: color,
      isDark: isDark,
      onClose: _closeOverlay,
      onBack: _popupStack.length > 1 ? _popPopup : null,
      headerLeading: header?.leading,
      title: header?.title ?? '',
      body: BeingOverlayBody(
        color: color,
        isDark: isDark,
        planet: planet,
        being: being,
        beingContent: _beingContent,
        onPushBeingType: (t) => _pushPopup(BeingTypePopup(t)),
        onPushBeing: (b) => _pushPopup(BeingFromName(b)),
      ),
    );
  }

  Widget _buildBeingTypeOverlay(Color color, bool isDark, String type) {
    final content = _beingTypeContent?[type];
    final emblemPath = beingTypeEmblemPath(type);

    return OverlayShell(
      color: color,
      isDark: isDark,
      onClose: _closeOverlay,
      onBack: _popupStack.length > 1 ? _popPopup : null,
      title: content != null ? '${content.type} — ${content.role}' : '',
      body: content == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  content.subtitle,
                  style: TextStyle(
                    color: isDark ? const Color(0xFFD4A855) : color,
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
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
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
    );
  }

  Widget _buildPlanetOverlay(Color color, bool isDark, String planetName) {
    final content = _planetContent?[planetName];
    final glyphPath = planetGlyphs[planetName];
    final imagePath = planetImagePath(planetName);

    return OverlayShell(
      color: color,
      isDark: isDark,
      onClose: _closeOverlay,
      onBack: _popupStack.length > 1 ? _popPopup : null,
      headerLeading: glyphPath != null
          ? SvgPicture.asset(
              glyphPath,
              width: 28,
              height: 28,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            )
          : null,
      title: content?.name ?? '',
      body: content == null
          ? const SizedBox.shrink()
          : Column(
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
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
