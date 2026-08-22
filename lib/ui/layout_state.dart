import 'package:flutter/foundation.dart';

/// Identifies a persistent, dockable panel in the desktop layout.
///
/// Persistent panels dock and reflow with the [LayoutMode], can be toggled
/// on/off, and never overlap each other. Contrast the transient popups
/// (being / planet / being-type detail) which float above everything and are
/// z-ordered — those live in `_ChartWheelState._popupStack`, not here.
///
/// See docs/layout-modes.md.
enum PanelId {
  /// Soul Stances (Hora). Left gutter in explore mode.
  soulStances,

  /// Your Beings. Right gutter in explore mode.
  yourBeings,

  /// Shop + Waitlist call-to-action stack. Right gutter, below Your Beings.
  ctas,

  /// AI chat. Stubbed in this foundation and hidden in explore mode; docks a
  /// column in `conversation` mode (later feature).
  chat,
}

/// A docked region a persistent panel can occupy.
///
/// Explore mode uses the two side gutters flanking the centered square chart.
/// `conversation` mode will add a docked chat column (adityas/explore task 2).
enum PanelDock { leftGutter, rightGutter }

/// Named desktop layout presets. The chart's size/position and where panels
/// dock are functions of the mode, so transitions can be animated — layout is
/// data, not hand-placed `Positioned` widgets.
///
/// This foundation implements only [explore]. [conversation] and [focus] land
/// with the reflow work (adityas/explore task 2). See docs/layout-modes.md.
enum LayoutMode {
  /// Chart centered, persistent panels docked in the gutters. Today's layout.
  explore,

  /// Chart shrinks and shifts aside; chat claims a docked column; info panels
  /// collapse to toggle-to-overlay.
  conversation,

  /// Chart only; all persistent panels hidden. Clean-read escape hatch.
  focus,
}

/// The desktop layout as data: the current [mode] plus which persistent panels
/// are visible. Immutable — `_ChartWheelState` holds one instance and swaps it
/// via `setState`. Placement is derived from this each build, never stored.
@immutable
class LayoutState {
  const LayoutState({required this.mode, required this.visiblePanels});

  /// Today's default: explore mode, everything but the stubbed chat visible.
  const LayoutState.explore()
    : mode = LayoutMode.explore,
      visiblePanels = const {
        PanelId.soulStances,
        PanelId.yourBeings,
        PanelId.ctas,
      };

  /// Persistent panels the user may show/hide directly. Chat is excluded — it
  /// is stubbed and driven by the mode, not a user toggle.
  static const List<PanelId> toggleable = [
    PanelId.soulStances,
    PanelId.yourBeings,
    PanelId.ctas,
  ];

  final LayoutMode mode;
  final Set<PanelId> visiblePanels;

  bool isVisible(PanelId id) => visiblePanels.contains(id);

  /// Returns a copy with [id] shown or hidden. The visibility set is copied, so
  /// the original state stays immutable.
  LayoutState withPanelVisible(PanelId id, bool visible) {
    final next = {...visiblePanels};
    if (visible) {
      next.add(id);
    } else {
      next.remove(id);
    }
    return copyWith(visiblePanels: next);
  }

  LayoutState copyWith({LayoutMode? mode, Set<PanelId>? visiblePanels}) =>
      LayoutState(
        mode: mode ?? this.mode,
        visiblePanels: visiblePanels ?? this.visiblePanels,
      );
}

/// Human-readable label for a layout mode, for the mode-selection affordance.
String layoutModeLabel(LayoutMode mode) => switch (mode) {
  LayoutMode.explore => 'Explore',
  LayoutMode.conversation => 'Chat',
  LayoutMode.focus => 'Focus',
};

/// Human-readable label for a persistent panel, for the visibility affordance.
String panelLabel(PanelId id) => switch (id) {
  PanelId.soulStances => 'Soul Stances',
  PanelId.yourBeings => 'Your Beings',
  PanelId.ctas => 'Shop & Waitlist',
  PanelId.chat => 'Chat',
};

/// Dock assignment for a persistent panel in explore mode.
///
/// This is the "layout is data" seam: `build` groups the visible panels by
/// dock and stacks each dock's column, instead of hand-placing `Positioned`
/// widgets. Task 2 makes this mode-dependent (a resolver keyed on
/// [LayoutMode]); for now it encodes today's gutter layout exactly.
PanelDock exploreDock(PanelId id) => switch (id) {
  PanelId.soulStances => PanelDock.leftGutter,
  PanelId.yourBeings || PanelId.ctas || PanelId.chat => PanelDock.rightGutter,
};
