import 'dart:math';

import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:charts_dart/charts_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../astro/being_uncertainty.dart';
import '../navigate.dart' if (dart.library.js_interop) '../navigate_web.dart';
import '../state/overlay.dart';
import 'aditya_data.dart';
import 'being_overlay.dart';
import 'being_type_detail_overlay.dart';
import 'beings_panel.dart';
import 'chat_panel.dart';
import 'overlay_shell.dart';
import 'being_content.dart';
import 'being_type_content.dart';
import 'chart_wheel_layout.dart';
import 'chart_wheel_painter.dart';
import 'layout_state.dart';
import 'planet_content.dart';
import 'planet_detail_overlay.dart';
import 'popup_state.dart';
import 'soul_stances_panel.dart';
import 'mobile_chart_buttons.dart';
import 'tokens.dart';
import 'uncertainty_chooser.dart';
import 'waitlist_cta.dart';

extension CapitalizeString on String {
  String toCapitalized() =>
      isNotEmpty ? '${this[0].toUpperCase()}${substring(1)}' : '';
}

class ChartWheel extends ConsumerStatefulWidget {
  final arrow.Chart chart;

  /// The raw birth data behind [chart], carried so the chat panel can send it
  /// with each turn (the computed [chart] has lost the civil date/time/offsets).
  final ChartData? chartData;
  final BeingUncertainty? uncertainty;
  final bool waitlistSigned;
  final VoidCallback onWaitlistSigned;

  const ChartWheel({
    super.key,
    required this.chart,
    this.chartData,
    this.uncertainty,
    this.waitlistSigned = false,
    required this.onWaitlistSigned,
  });

  @override
  ConsumerState<ChartWheel> createState() => _ChartWheelState();
}

class _ChartWheelState extends ConsumerState<ChartWheel>
    with SingleTickerProviderStateMixin {
  PlacedPlanet? _hoveredPlanet;
  PlacedCusp? _hoveredCusp;

  /// Desktop layout as data: which persistent panels are visible + the mode.
  /// `build` derives panel placement from this instead of hardcoded
  /// `Positioned` blocks. See docs/layout-modes.md.
  LayoutState _layout = const LayoutState.explore();

  /// The mode we are animating *away from*. `build` lerps the chart/panel
  /// geometry from `_prevMode` to `_layout.mode` by `_modeAnim.value`, so a
  /// mode switch choreographs the chart resize/recenter and panel reflow.
  LayoutMode _prevMode = LayoutMode.explore;
  late final AnimationController _modeAnim;

  /// Captured in [initState] so [dispose] can reset the overlay without reading
  /// `ref` during teardown (unsafe once the element is deactivated — Riverpod
  /// throws a StateError). Safe to hold because `overlayControllerProvider` is
  /// keepAlive, so this notifier instance is stable for the State's lifetime.
  late final OverlayController _overlayController;

  Map<(int, String), BeingContent>? _beingContent;
  Map<String, BeingTypeContent>? _beingTypeContent;
  Map<String, PlanetContent>? _planetContent;

  late int _ascSign;
  late List<PlacedPlanet> _planets;
  late List<PlacedCusp> _cusps;

  @override
  void initState() {
    super.initState();
    _overlayController = ref.read(overlayControllerProvider.notifier);
    _modeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      value: 1,
    )..addListener(() => setState(() {}));
    _computeLayout();
    _loadContent();
  }

  @override
  void dispose() {
    // The overlay now lives in a keepAlive provider, not this State. Reset it
    // when the chart view tears down (chart → null / app teardown) so a stale
    // popup can't leak onto the next chart — reproducing the old lifecycle
    // where the stack lived exactly as long as this State. Mode switches don't
    // unmount ChartWheel, so this only fires on a genuine chart teardown.
    // Use the cached notifier, not `ref` — reading `ref` in dispose is unsafe.
    _overlayController.close();
    _modeAnim.dispose();
    super.dispose();
  }

  /// Switches the desktop layout mode, animating the transition. Idempotent.
  void _setMode(LayoutMode mode) {
    if (_layout.mode == mode) return;
    setState(() {
      _prevMode = _layout.mode;
      _layout = _layout.copyWith(mode: mode);
    });
    _modeAnim.forward(from: 0);
  }

  /// Shows or hides a persistent panel. Panels reflow in the gutters from the
  /// updated visibility set (see `_dockedPanels`). Exposed to the user via the
  /// bottom-bar panels menu and each panel's hover close button.
  void _setPanelVisible(PanelId id, bool visible) =>
      setState(() => _layout = _layout.withPanelVisible(id, visible));

  void _togglePanel(PanelId id) => _setPanelVisible(id, !_layout.isVisible(id));

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

  // The transient popup stack + floating-window geometry now live in
  // overlayControllerProvider (lib/state/overlay.dart) so the chat tool-call
  // path can drive them with no BuildContext. These stay as thin forwarders so
  // the panel/wheel callback sites (onOpen / onPush / onClose) are unchanged.
  void _closeOverlay() => ref.read(overlayControllerProvider.notifier).close();

  void _openPopup(PopupState popup) =>
      ref.read(overlayControllerProvider.notifier).open(popup);

  void _pushPopup(PopupState popup) =>
      ref.read(overlayControllerProvider.notifier).push(popup);

  void _popPopup() => ref.read(overlayControllerProvider.notifier).pop();

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
    final tokens = context.tokens;
    final color = tokens.ink;
    final backdropColor = tokens.wheelBackdrop;

    // The transient popup layer, watched at the top of build so any open/push/
    // pop/drag/resize rebuilds the wheel (LayoutBuilder is a nested closure, so
    // the watch stays here, not inside it).
    final overlay = ref.watch(overlayControllerProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = min(constraints.maxWidth, constraints.maxHeight);
        final panelMargin = (constraints.maxWidth - side) / 2;

        // Mobile means no room for side gutters, or an empty chart. Derive it
        // without building the wheel — `_planets.isEmpty` used to stand in for
        // the empty-chart case, but reading it forced a throwaway `_buildWheel`
        // purely for its side effect. `_planets.isEmpty` ⟺ no graha survives the
        // `defaultGrahas` filter, so check that directly.
        final hasPlanets = widget.chart.grahas.any(
          (p) => defaultGrahas.contains(p.body.name),
        );
        final isMobile = !hasPlanets || panelMargin < 80;

        if (isMobile) {
          // Explore-size wheel; `_buildWheel` also populates `_planets`, which
          // the mobile buttons below read.
          final wheel = _buildWheel(side, tokens);
          return Stack(
            children: [
              Center(child: wheel),
              if (_planets.isNotEmpty && overlay.isEmpty)
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
              if (overlay.isNotEmpty) _buildOverlay(overlay, color),
            ],
          );
        }

        // The desktop layout is a function of the mode: lerp the geometry from
        // the mode we're leaving to the mode we're entering. When idle,
        // `_modeAnim.value == 1` so `g` is exactly the current mode's geometry.
        final w = constraints.maxWidth;
        final t = Curves.easeInOut.transform(_modeAnim.value);
        final g = _ModeGeometry.lerp(
          _geometryFor(_prevMode, w, side),
          _geometryFor(_layout.mode, w, side),
          t,
        );

        // Panels keep their explore-mode gutter geometry and simply fade with
        // the mode (they only show in explore); the chart is what reflows.
        final panelWidth = panelMargin - 16;
        final panelFontSize = (side / 2) * 0.032;
        final chartWheel = _buildWheel(g.chartSide, tokens);
        return SizedBox(
          width: w,
          height: side,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: g.chartLeft,
                top: g.chartTop,
                width: g.chartSide,
                height: g.chartSide,
                child: chartWheel,
              ),
              if (g.panelsOpacity > 0.01)
                for (final dock in PanelDock.values)
                  if (_dockedPanels(dock).isNotEmpty)
                    Positioned(
                      left: dock == PanelDock.leftGutter ? 8 : null,
                      right: dock == PanelDock.rightGutter ? 8 : null,
                      top: 0,
                      width: panelWidth,
                      child: IgnorePointer(
                        ignoring: g.panelsOpacity < 0.99,
                        child: Opacity(
                          opacity: g.panelsOpacity,
                          child: _buildGutter(
                            context,
                            dock,
                            color: color,
                            backdropColor: backdropColor,
                            fontSize: panelFontSize,
                          ),
                        ),
                      ),
                    ),
              if (g.chatOpacity > 0.01)
                Positioned(
                  left: g.chatLeft,
                  top: g.chatTop,
                  width: g.chatWidth,
                  height: g.chatHeight,
                  child: IgnorePointer(
                    ignoring: g.chatOpacity < 0.99,
                    child: Opacity(
                      opacity: g.chatOpacity,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                        child: ChatPanel(
                          color: color,
                          backdropColor: backdropColor,
                          fontSize: panelFontSize,
                          chartData: widget.chartData,
                        ),
                      ),
                    ),
                  ),
                ),
              // Bottom-left settings gear: tucks the (currently dev-facing)
              // panel-visibility and layout-mode controls behind a single
              // affordance — Panels (show/hide each persistent panel) and Mode
              // (explore/chat/focus) as submenus. See docs/layout-modes.md
              // § foundation item 4.
              Positioned(
                left: 8,
                bottom: 8,
                child: _SettingsMenu(
                  layout: _layout,
                  color: color,
                  backdropColor: backdropColor,
                  onTogglePanel: _togglePanel,
                  onSelectMode: _setMode,
                ),
              ),
              // Transient popup layer floats above everything, over the whole
              // desktop area (not confined to the chart square). Draggable +
              // resizable — see docs/layout-modes.md.
              if (overlay.isNotEmpty)
                _buildOverlay(
                  overlay,
                  color,
                  floating: FloatingConfig(
                    rect: overlayWindowRect(overlay.rect, w, side),
                    onDrag: (d) => ref
                        .read(overlayControllerProvider.notifier)
                        .drag(d, w, side),
                    onResize: (d) => ref
                        .read(overlayControllerProvider.notifier)
                        .resize(d, w, side),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Builds the chart wheel sized to [wheelSide]. Recomputes `_planets` for
  /// that size (positions scale with the wheel) as a side effect; panels read
  /// `_planets` afterwards but only for being-type data, not positions.
  Widget _buildWheel(double wheelSide, ExploreTokens tokens) {
    final color = tokens.ink;
    final half = wheelSide / 2;
    final center = Offset(half, half);
    final glyphSize = half * 0.065;
    _planets = _buildPlanets(half, glyphSize);
    return SizedBox(
      width: wheelSide,
      height: wheelSide,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: ChartWheelPainter(
                tokens: tokens,
                ascSign: _ascSign,
                cusps: _cusps,
              ),
            ),
          ),
          for (var s = 1; s <= 12; s++) _buildSignGlyph(s, half, center, color),
          for (final planet in _planets)
            _buildPlanetGlyph(planet, half, center, color, glyphSize),
          for (final cusp in _cusps)
            _buildCuspHitRegion(cusp, half, center, color),
          _buildCenterInfo(half, center, color),
        ],
      ),
    );
  }

  /// Derives the chart + chat geometry for [mode] within a `w`×`boxH` desktop
  /// area (`boxH` is the explore square's side, the outer box's height). This
  /// is the "layout is data" seam: transitions animate because placement is a
  /// pure function of the mode, not hand-placed `Positioned` widgets.
  _ModeGeometry _geometryFor(LayoutMode mode, double w, double boxH) {
    switch (mode) {
      case LayoutMode.explore:
      case LayoutMode.focus:
        final s = min(w, boxH);
        return _ModeGeometry(
          chartLeft: (w - s) / 2,
          chartTop: 0,
          chartSide: s,
          chatLeft: w,
          chatTop: 0,
          chatWidth: _chatColumnWidth(w),
          chatHeight: boxH,
          panelsOpacity: mode == LayoutMode.explore ? 1 : 0,
          chatOpacity: 0,
        );
      case LayoutMode.conversation:
        final chatW = _chatColumnWidth(w);
        const gap = 16.0;
        final leftRegion = w - chatW - gap;
        final s = min(leftRegion, boxH);
        return _ModeGeometry(
          chartLeft: (leftRegion - s) / 2,
          chartTop: (boxH - s) / 2,
          chartSide: s,
          chatLeft: w - chatW,
          chatTop: 0,
          chatWidth: chatW,
          chatHeight: boxH,
          panelsOpacity: 0,
          chatOpacity: 1,
        );
    }
  }

  /// Docked chat-column width: ~30% of the viewport, clamped to a readable band.
  double _chatColumnWidth(double w) => (w * 0.3).clamp(300.0, 460.0);

  /// Visible persistent panels assigned to [dock], in enum order.
  List<PanelId> _dockedPanels(PanelDock dock) => [
    for (final id in PanelId.values)
      if (_layout.isVisible(id) && exploreDock(id) == dock) id,
  ];

  /// Stacks the visible panels of one gutter into a column.
  ///
  /// The left gutter stretches its (single) panel to the full gutter width —
  /// matching the pre-refactor `Positioned(width: panelWidth)`. The right
  /// gutter centers and shrink-wraps each panel, as its stacked column did.
  Widget _buildGutter(
    BuildContext context,
    PanelDock dock, {
    required Color color,
    required Color backdropColor,
    required double fontSize,
  }) {
    final panels = _dockedPanels(dock);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: dock == PanelDock.leftGutter
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < panels.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          // Right-click is a secondary power-user shortcut only (the bottom-bar
          // menu is the primary path — docs/layout-modes.md § foundation 4).
          GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onSecondaryTapDown: (d) =>
                _showPanelContextMenu(context, panels[i], d.globalPosition),
            child: _ClosablePanel(
              color: color,
              backdropColor: backdropColor,
              label: panelLabel(panels[i]),
              onClose: () => _setPanelVisible(panels[i], false),
              child: _buildPanel(
                panels[i],
                color: color,
                backdropColor: backdropColor,
                fontSize: fontSize,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Secondary-only right-click menu on a persistent panel: "Hide" the panel
  /// under the cursor, then a checklist mirroring the bottom-bar panels menu.
  ///
  /// Desktop only by design. On web the browser's native context menu wins, so
  /// this never fires — not a bug. The only override is the global
  /// `BrowserContextMenu.disableContextMenu()`, which would suppress the native
  /// menu app-wide (copy, inspect, open-image) for a secondary power-user
  /// shortcut — a bad trade. Web keeps the primary affordances (the bottom-bar
  /// Panels menu + hover close), which cover panel visibility fully.
  Future<void> _showPanelContextMenu(
    BuildContext context,
    PanelId panel,
    Offset globalPos,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final tokens = context.tokens;
    final color = tokens.ink;
    final selected = await showMenu<(_PanelMenuKind, PanelId)>(
      context: context,
      color: tokens.wheelBackdrop,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: (_PanelMenuKind.hideThis, panel),
          child: Text(
            'Hide ${panelLabel(panel)}',
            style: TextStyle(color: color),
          ),
        ),
        const PopupMenuDivider(),
        for (final id in LayoutState.toggleable)
          CheckedPopupMenuItem(
            value: (_PanelMenuKind.toggle, id),
            checked: _layout.isVisible(id),
            child: Text(panelLabel(id), style: TextStyle(color: color)),
          ),
      ],
    );
    if (selected == null) return;
    final (kind, id) = selected;
    switch (kind) {
      case _PanelMenuKind.hideThis:
        _setPanelVisible(id, false);
      case _PanelMenuKind.toggle:
        _togglePanel(id);
    }
  }

  /// Builds the widget for one persistent panel.
  Widget _buildPanel(
    PanelId id, {
    required Color color,
    required Color backdropColor,
    required double fontSize,
  }) {
    switch (id) {
      case PanelId.soulStances:
        return SoulStancesPanel(
          planets: _planets,
          uncertainty: widget.uncertainty,
          color: color,
          backdropColor: backdropColor,
          fontSize: fontSize,
          onOpen: _openPopup,
        );
      case PanelId.yourBeings:
        return BeingsPanel(
          planets: _planets,
          uncertainty: widget.uncertainty,
          color: color,
          backdropColor: backdropColor,
          fontSize: fontSize,
          onOpen: _openPopup,
        );
      case PanelId.ctas:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ShopCta(
              color: color,
              backdropColor: backdropColor,
              fontSize: fontSize,
            ),
            const SizedBox(height: 8),
            WaitlistCta(
              color: color,
              backdropColor: backdropColor,
              fontSize: fontSize,
              signed: widget.waitlistSigned,
              onSigned: widget.onWaitlistSigned,
            ),
          ],
        );
      case PanelId.chat:
        // Stub: chat docks in conversation mode (adityas/explore task 2);
        // hidden in explore, so this is never reached today.
        return const SizedBox.shrink();
    }
  }

  Widget _buildSignGlyph(int sign, double half, Offset center, Color color) {
    final angle = signMidAngle(sign, _ascSign);
    final radius = signMidRadius(half);
    final data = adityaSigns[sign]!;
    final name = data.name.toUpperCase();
    final fontSize = half * 0.052;
    final scaledSize = MediaQuery.textScalerOf(context).scale(fontSize);
    final naturalSpacing = scaledSize * 0.85 / radius;
    const maxSpan = 0.85 * pi / 6;
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
                    fontFamily: context.tokens.serifFamily,
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

  /// Builds the top popup. When [floating] is supplied (desktop) the three
  /// detail popups render as a draggable + resizable window; the uncertainty
  /// chooser and mobile panel sheets stay modal regardless.
  Widget _buildOverlay(
    OverlayLayer overlay,
    Color color, {
    FloatingConfig? floating,
  }) {
    final top = overlay.top;
    if (top == null) return const SizedBox.shrink();
    final canGoBack = overlay.depth > 1;
    final onBack = canGoBack ? _popPopup : null;

    return switch (top) {
      BeingFromPlanet(:final planet) => _buildBeingShell(
        color,
        planet: planet,
        onBack: onBack,
        floating: floating,
      ),
      BeingFromName(:final being) => _buildBeingShell(
        color,
        being: being,
        onBack: onBack,
        floating: floating,
      ),
      BeingTypePopup(:final type) => BeingTypeDetailOverlay(
        color: color,
        type: type,
        contentMap: _beingTypeContent,
        onClose: _closeOverlay,
        onBack: onBack,
        floating: floating,
      ),
      PlanetPopup(:final planet) => PlanetDetailOverlay(
        color: color,
        planetName: planet,
        contentMap: _planetContent,
        onClose: _closeOverlay,
        onBack: onBack,
        floating: floating,
      ),
      UncertaintyPopup(:final planet, :final kind) => UncertaintyChooser(
        color: color,
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
    required Widget child,
  }) {
    final cardBg = context.tokens.cardBg;
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
    Color color, {
    PlacedPlanet? planet,
    BeingRef? being,
    VoidCallback? onBack,
    FloatingConfig? floating,
  }) {
    final header = beingOverlayHeader(
      color: color,
      planet: planet,
      being: being,
    );
    return OverlayShell(
      color: color,
      onClose: _closeOverlay,
      onBack: onBack,
      floating: floating,
      headerLeading: header?.leading,
      title: header?.title ?? '',
      body: BeingOverlayBody(
        color: color,
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

/// The chart + chat placement for one desktop layout mode, as plain numbers so
/// a mode transition can be animated by lerping between two of these.
@immutable
class _ModeGeometry {
  const _ModeGeometry({
    required this.chartLeft,
    required this.chartTop,
    required this.chartSide,
    required this.chatLeft,
    required this.chatTop,
    required this.chatWidth,
    required this.chatHeight,
    required this.panelsOpacity,
    required this.chatOpacity,
  });

  final double chartLeft;
  final double chartTop;
  final double chartSide;
  final double chatLeft;
  final double chatTop;
  final double chatWidth;
  final double chatHeight;

  /// Opacity of the docked info panels (1 in explore, 0 otherwise).
  final double panelsOpacity;

  /// Opacity of the docked chat column (1 in conversation, 0 otherwise).
  final double chatOpacity;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static _ModeGeometry lerp(_ModeGeometry a, _ModeGeometry b, double t) =>
      _ModeGeometry(
        chartLeft: _lerp(a.chartLeft, b.chartLeft, t),
        chartTop: _lerp(a.chartTop, b.chartTop, t),
        chartSide: _lerp(a.chartSide, b.chartSide, t),
        chatLeft: _lerp(a.chatLeft, b.chatLeft, t),
        chatTop: _lerp(a.chatTop, b.chatTop, t),
        chatWidth: _lerp(a.chatWidth, b.chatWidth, t),
        chatHeight: _lerp(a.chatHeight, b.chatHeight, t),
        panelsOpacity: _lerp(a.panelsOpacity, b.panelsOpacity, t),
        chatOpacity: _lerp(a.chatOpacity, b.chatOpacity, t),
      );
}

/// What a right-click panel menu item does: hide the right-clicked panel, or
/// toggle a named one (mirroring the settings-menu checklist).
enum _PanelMenuKind { hideThis, toggle }

/// Bottom-left settings gear. Tucks the (currently dev-facing) layout controls
/// behind one affordance: a `Panels` submenu (show/hide each persistent panel,
/// so a user who closed every panel can restore them — the primary visibility
/// affordance, right-click being only a secondary shortcut) and a `Mode`
/// submenu (explore/chat/focus). Checkmark = active. See docs/layout-modes.md
/// § foundation item 4.
class _SettingsMenu extends StatelessWidget {
  final LayoutState layout;
  final Color color;
  final Color backdropColor;
  final ValueChanged<PanelId> onTogglePanel;
  final ValueChanged<LayoutMode> onSelectMode;

  const _SettingsMenu({
    required this.layout,
    required this.color,
    required this.backdropColor,
    required this.onTogglePanel,
    required this.onSelectMode,
  });

  @override
  Widget build(BuildContext context) {
    // Match the old bottom-bar pills: brand backdrop, faint border, rounded
    // corners (card convention, radius 16) on the popup, and a softly rounded
    // hover highlight on each row.
    final menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(backdropColor),
      side: WidgetStatePropertyAll(
        BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
    );
    // Submenus open *upward* from the bottom-left corner: bottomEnd alignment
    // places the panel's origin at the parent row's bottom, and the negative
    // dy raises it by roughly its own height so the last item (e.g. Focus)
    // lands level with its parent row (Mode) instead of the whole flyout
    // flipping to float above it. The dy magnitude ≈ a 3-item panel's height;
    // it's the nudge knob if the bottom item sits a touch high or low.
    final submenuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(backdropColor),
      side: WidgetStatePropertyAll(
        BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
      alignment: AlignmentDirectional.bottomEnd,
    );
    const submenuOffset = Offset(6, -138);
    final buttonStyle = ButtonStyle(
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      overlayColor: WidgetStatePropertyAll(color.withValues(alpha: 0.1)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );
    return MenuAnchor(
      style: menuStyle,
      menuChildren: [
        SubmenuButton(
          style: buttonStyle,
          menuStyle: submenuStyle,
          alignmentOffset: submenuOffset,
          leadingIcon: Icon(
            Icons.view_sidebar_outlined,
            size: 18,
            color: color,
          ),
          menuChildren: [
            for (final id in LayoutState.toggleable)
              _checkItem(
                label: panelLabel(id),
                active: layout.isVisible(id),
                onPressed: () => onTogglePanel(id),
                buttonStyle: buttonStyle,
              ),
          ],
          child: Text('Panels', style: TextStyle(color: color)),
        ),
        SubmenuButton(
          style: buttonStyle,
          menuStyle: submenuStyle,
          alignmentOffset: submenuOffset,
          leadingIcon: Icon(Icons.dashboard_outlined, size: 18, color: color),
          menuChildren: [
            for (final m in LayoutMode.values)
              _checkItem(
                label: layoutModeLabel(m),
                active: m == layout.mode,
                onPressed: () => onSelectMode(m),
                buttonStyle: buttonStyle,
              ),
          ],
          child: Text('Mode', style: TextStyle(color: color)),
        ),
      ],
      builder: (context, controller, child) => Tooltip(
        message: 'Settings',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: backdropColor,
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Icon(Icons.settings_outlined, size: 18, color: color),
            ),
          ),
        ),
      ),
    );
  }

  MenuItemButton _checkItem({
    required String label,
    required bool active,
    required VoidCallback onPressed,
    required ButtonStyle buttonStyle,
  }) {
    return MenuItemButton(
      onPressed: onPressed,
      style: buttonStyle,
      leadingIcon: Icon(active ? Icons.check : null, size: 18, color: color),
      child: Text(label, style: TextStyle(color: color)),
    );
  }
}

/// Wraps a persistent panel with a hover-revealed close (X) button in its top
/// corner, so each panel can be dismissed in place. Reappears via [_SettingsMenu].
class _ClosablePanel extends StatefulWidget {
  final Widget child;
  final Color color;
  final Color backdropColor;
  final String label;
  final VoidCallback onClose;

  const _ClosablePanel({
    required this.child,
    required this.color,
    required this.backdropColor,
    required this.label,
    required this.onClose,
  });

  @override
  State<_ClosablePanel> createState() => _ClosablePanelState();
}

class _ClosablePanelState extends State<_ClosablePanel> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          Positioned(
            top: 4,
            right: 4,
            child: IgnorePointer(
              ignoring: !_hover,
              child: AnimatedOpacity(
                opacity: _hover ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: Tooltip(
                  message: 'Hide ${widget.label}',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: widget.onClose,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: widget.backdropColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: widget.color.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: widget.color.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
