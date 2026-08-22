import 'dart:math';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/popup_state.dart';

/// The transient overlay layer, lifted out of `_ChartWheelState` widget state.
///
/// This is the "transient" half of the two-layer desktop model
/// (docs/layout-modes.md § "Two layers, two behaviors"): popups float, overlap,
/// drag, resize, and z-order *above* the persistent docked panels — this move
/// changes only *where the transient stack lives*, not that rule. It used to be
/// `_ChartWheelState._popupStack` / `_popupRect`; it was lifted here so the chat
/// tool-call path (`show_being`) can drive it with no `BuildContext`
/// (docs/chat-state-architecture.md § Overlay ripple).
///
/// keepAlive (app-lifetime, like `authProvider`): a plain [NotifierProvider] is
/// not autoDispose. It is *not* auth-scoped — popups are chart content, not user
/// data — so nothing resets it on sign-out. It is reset when the chart view
/// tears down: `_ChartWheelState.dispose` calls [OverlayController.close], which
/// reproduces the old lifecycle (the stack lived exactly as long as the
/// chart-wheel State).

/// An immutable snapshot of the overlay layer.
class OverlayLayer {
  /// The drill-down stack; the last element is the popup on screen. Empty means
  /// nothing is shown.
  final List<PopupState> stack;

  /// Desktop floating-window geometry. `null` means the user hasn't moved or
  /// resized it, so it renders at a centered default (see [overlayWindowRect]).
  /// Reset when a fresh root popup opens or all close, but preserved across
  /// drill-down (push/pop) so the window stays put. The floating window is the
  /// desktop concern only — mobile stays a modal.
  final Rect? rect;

  const OverlayLayer({this.stack = const [], this.rect});

  /// The popup on screen, or `null` when nothing is shown.
  PopupState? get top => stack.isEmpty ? null : stack.last;

  bool get isEmpty => stack.isEmpty;
  bool get isNotEmpty => stack.isNotEmpty;

  /// Drill-down depth; `> 1` means a back affordance is warranted.
  int get depth => stack.length;
}

final overlayControllerProvider =
    NotifierProvider<OverlayController, OverlayLayer>(OverlayController.new);

class OverlayController extends Notifier<OverlayLayer> {
  @override
  OverlayLayer build() => const OverlayLayer();

  /// Open a fresh root popup, replacing any existing stack and resetting the
  /// floating-window geometry to its centered default.
  void open(PopupState popup) => state = OverlayLayer(stack: [popup]);

  /// Drill down one level, preserving the window geometry so it stays put.
  void push(PopupState popup) =>
      state = OverlayLayer(stack: [...state.stack, popup], rect: state.rect);

  /// Go back one level; a no-op when the stack is empty.
  void pop() {
    if (state.stack.isEmpty) return;
    state = OverlayLayer(
      stack: state.stack.sublist(0, state.stack.length - 1),
      rect: state.rect,
    );
  }

  /// Close the whole overlay and reset the geometry.
  void close() => state = const OverlayLayer();

  /// The `show_being` tool-call seam: open a being popup with no `BuildContext`.
  ///
  /// This is the entry point the chat stream handler drives — a Notifier holds
  /// `ref`, so it reaches this without callback-threading through the widget
  /// tree. It is the reason the stack was lifted out of `_ChartWheelState`
  /// (docs/chat-state-architecture.md § Overlay ripple). The handler resolves
  /// the tool's being identifier to a [BeingRef] and calls this; wiring the
  /// dispatch is blocked on the transport carrying tool arguments (see
  /// `ToolEndEvent` in lib/state/turn_transport.dart) and the chat PRD.
  void showBeing(BeingRef being) => open(BeingFromName(being));

  /// Move the floating window by [delta], clamped to the [areaW]×[areaH] area.
  void drag(Offset delta, double areaW, double areaH) {
    final r = overlayWindowRect(state.rect, areaW, areaH);
    state = OverlayLayer(
      stack: state.stack,
      rect: _clampPopupRect(r.shift(delta), areaW, areaH),
    );
  }

  /// Resize the floating window, center-anchored: the box grows/shrinks
  /// symmetrically about its center, so it stays where it opened instead of
  /// drifting by its top-left. The handle is at the bottom-right, so the corner
  /// moves by [delta] while the opposite corner mirrors it — hence the 2× on the
  /// size to keep the handle tracking the cursor.
  void resize(Offset delta, double areaW, double areaH) {
    final r = overlayWindowRect(state.rect, areaW, areaH);
    final w = (r.width + 2 * delta.dx)
        .clamp(_kPopupMinW, max(_kPopupMinW, areaW))
        .toDouble();
    final h = (r.height + 2 * delta.dy)
        .clamp(_kPopupMinH, max(_kPopupMinH, areaH))
        .toDouble();
    state = OverlayLayer(
      stack: state.stack,
      rect: _clampPopupRect(
        Rect.fromCenter(center: r.center, width: w, height: h),
        areaW,
        areaH,
      ),
    );
  }
}

// --- Floating popup geometry (desktop transient layer) ---------------------
//
// Pure geometry: kept out of the widget so drag/resize state and its math live
// together. [overlayWindowRect] is used by the chart-wheel build to resolve the
// stored rect (or a centered default) into an on-screen rect each frame.

const double _kPopupMinW = 300;
const double _kPopupMinH = 220;
const double _kPopupDefaultW = 460;
const double _kPopupDefaultH = 560;

/// The floating window rect for a desktop area of [areaW]×[areaH]: the [stored]
/// geometry, or a centered default when null, always clamped on-screen so a
/// viewport resize can't strand it.
Rect overlayWindowRect(Rect? stored, double areaW, double areaH) {
  final r = stored ?? _defaultPopupRect(areaW, areaH);
  return _clampPopupRect(r, areaW, areaH);
}

Rect _defaultPopupRect(double areaW, double areaH) {
  final w = min(_kPopupDefaultW, areaW - 32);
  final h = min(_kPopupDefaultH, areaH - 32);
  return Rect.fromLTWH((areaW - w) / 2, (areaH - h) / 2, w, h);
}

Rect _clampPopupRect(Rect r, double areaW, double areaH) {
  final w = r.width.clamp(_kPopupMinW, max(_kPopupMinW, areaW)).toDouble();
  final h = r.height.clamp(_kPopupMinH, max(_kPopupMinH, areaH)).toDouble();
  final left = r.left.clamp(0.0, max(0.0, areaW - w)).toDouble();
  final top = r.top.clamp(0.0, max(0.0, areaH - h)).toDouble();
  return Rect.fromLTWH(left, top, w, h);
}
