import 'dart:math';

import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../astro/being_uncertainty.dart';
import '../navigate.dart' if (dart.library.js_interop) '../navigate_web.dart';
import 'aditya_data.dart';
import 'being_overlay.dart';
import 'being_type_detail_overlay.dart';
import 'beings_panel.dart';
import 'overlay_shell.dart';
import 'being_content.dart';
import 'being_type_content.dart';
import 'chart_wheel_layout.dart';
import 'chart_wheel_painter.dart';
import 'planet_content.dart';
import 'planet_detail_overlay.dart';
import 'popup_state.dart';
import 'soul_stances_panel.dart';
import 'mobile_chart_buttons.dart';
import 'uncertainty_chooser.dart';
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
            ],
          ),
        );

        final isMobile = _planets.isEmpty || panelMargin < 80;

        if (isMobile) {
          return Stack(
            children: [
              Center(child: wheel),
              if (_planets.isNotEmpty && _popupStack.isEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: MobileChartButtons(
                    color: color,
                    backdropColor: backdropColor,
                    onSoulStances: () => _openPopup(SoulStancesPopup()),
                    onYourBeings: () => _openPopup(YourBeingsPopup()),
                  ),
                ),
              if (_popupStack.isNotEmpty) _buildOverlay(color, isDark),
            ],
          );
        }

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
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    wheel,
                    if (_popupStack.isNotEmpty) _buildOverlay(color, isDark),
                  ],
                ),
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
                    _ShopCta(
                      color: color,
                      backdropColor: backdropColor,
                      fontSize: half * 0.032,
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
    final scaledSize = MediaQuery.textScalerOf(context).scale(fontSize);
    final naturalSpacing = scaledSize * 0.85 / radius;
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
    final scaledSize = MediaQuery.textScalerOf(context).scale(fontSize);
    final boxSize = scaledSize * 1.2;
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

  Widget _buildOverlay(Color color, bool isDark) {
    final canGoBack = _popupStack.length > 1;
    final onBack = canGoBack ? _popPopup : null;

    return switch (_popupStack.last) {
      BeingFromPlanet(:final planet) => _buildBeingShell(
        color,
        isDark,
        planet: planet,
        onBack: onBack,
      ),
      BeingFromName(:final being) => _buildBeingShell(
        color,
        isDark,
        being: being,
        onBack: onBack,
      ),
      BeingTypePopup(:final type) => BeingTypeDetailOverlay(
        color: color,
        isDark: isDark,
        type: type,
        contentMap: _beingTypeContent,
        onClose: _closeOverlay,
        onBack: onBack,
      ),
      PlanetPopup(:final planet) => PlanetDetailOverlay(
        color: color,
        isDark: isDark,
        planetName: planet,
        contentMap: _planetContent,
        onClose: _closeOverlay,
        onBack: onBack,
      ),
      UncertaintyPopup(:final planet, :final kind) => UncertaintyChooser(
        color: color,
        isDark: isDark,
        planetName: planet,
        kind: kind,
        options: kind == UncertainKind.hora
            ? (widget.uncertainty?.horaFor(planet) ?? const [])
            : (widget.uncertainty?.trimsamsaFor(planet) ?? const []),
        canGoBack: canGoBack,
        onClose: _closeOverlay,
        onBack: onBack,
        onPush: _pushPopup,
      ),
      SoulStancesPopup() => _buildMobilePanelOverlay(
        color: color,
        isDark: isDark,
        child: SoulStancesPanel(
          planets: _planets,
          uncertainty: widget.uncertainty,
          color: color,
          backdropColor: Colors.transparent,
          fontSize: 16,
          onOpen: _pushPopup,
        ),
      ),
      YourBeingsPopup() => _buildMobilePanelOverlay(
        color: color,
        isDark: isDark,
        child: BeingsPanel(
          planets: _planets,
          uncertainty: widget.uncertainty,
          color: color,
          backdropColor: Colors.transparent,
          fontSize: 16,
          onOpen: _pushPopup,
        ),
      ),
    };
  }

  Widget _buildMobilePanelOverlay({
    required Color color,
    required bool isDark,
    required Widget child,
  }) {
    final cardBg = isDark ? const Color(0xF0151015) : const Color(0xF0F5F1EA);
    return GestureDetector(
      onTap: _closeOverlay,
      behavior: HitTestBehavior.opaque,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: _closeOverlay,
                      icon: Icon(Icons.close, color: color, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: child,
                  ),
                ),
              ],
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
    BeingRef? being,
    VoidCallback? onBack,
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
      onBack: onBack,
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

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _ShopCta extends StatelessWidget {
  final Color color;
  final Color backdropColor;
  final double fontSize;

  const _ShopCta({
    required this.color,
    required this.backdropColor,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => openUrlNewTab('https://84beings.com/shop/'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: backdropColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color),
          ),
          child: Text(
            'Shop in-depth reports',
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
