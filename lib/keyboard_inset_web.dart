import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Flip to `true` to overlay the raw viewport readout, the RED/GREEN reference
/// lines, and a live correction slider for on-device tuning. Ship it `false`.
const bool _kDebugKeyboardInset = false;

// --- Empirical browser-chrome correction ------------------------------------
//
// `window.visualViewport` reports the *visible* viewport, whose bottom edge sits
// ABOVE the real keyboard by a browser-reserved band that the keyboard draws
// over (the iOS input-accessory bar; Android browser chrome). No web API reports
// the keyboard's true top, so after anchoring to the visual-viewport bottom we
// subtract a per-engine constant to close that band.
//
// Biased to leave a hair of gap rather than risk the composer sliding behind the
// keys: the band shrinks in some states (e.g. iOS with no accessory row), and a
// small gap looks fine while overlap is broken.
//
// Tuned on-device 2026-09-04 with the debug slider — iPhone + Android both landed
// at 110 (Brave on a Pixel-class Android; iPhone 11 Pro Max simulator, iOS 26.3).
// Kept as separate named constants so each device class can diverge on retune. No
// real iPhone available, so the WebKit (iPhone) value is fitted on the simulator
// and may need a nudge on real hardware (the accessory-bar band can differ).
//
// iPad is its OWN bucket, not iPhone: its WebKit keyboard has a smaller (or no)
// accessory-bar band and reports the visual viewport more faithfully, so the
// iPhone 110 overshoots and drops the composer *behind* the keys. 20 landed the
// composer just above the keys on the iPad 11"/13" simulators (no real iPad
// available); may need a nudge on real hardware.
//
// RETUNE HERE when these drift: set `_kDebugKeyboardInset = true`, drag the
// slider until the composer sits just above the keys on each device, read the
// value off the HUD, and copy it back.
const double _kChromeCorrectionBlink = 110;
const double _kChromeCorrectionWebKit = 110;
const double _kChromeCorrectionIPad = 20;

/// Per-device correction for the current browser (logical px). iOS is always
/// WebKit regardless of the browser badge; iPad gets its own value; everything
/// else we treat as Blink.
double _engineChromeCorrection() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  // iPadOS masquerades as desktop Safari ("macintosh") but exposes touch points.
  final isIPad =
      ua.contains('ipad') ||
      (ua.contains('macintosh') && web.window.navigator.maxTouchPoints > 1);
  if (isIPad) return _kChromeCorrectionIPad;
  final isIPhone = ua.contains('iphone') || ua.contains('ipod');
  return isIPhone ? _kChromeCorrectionWebKit : _kChromeCorrectionBlink;
}

/// Web implementation of [keyboardInsetBuilder]: measures the soft keyboard's
/// overlap of Flutter's canvas from `window.visualViewport` and rebuilds
/// [builder] whenever it changes.
///
/// Flutter web keeps its canvas pinned to the layout viewport at full height
/// when the mobile keyboard opens (the keyboard overlays it) and reports an
/// unreliable `viewInsets.bottom`, so neither `Scaffold` resize nor
/// `MediaQuery.viewInsets` gives a usable inset.
///
/// The visual viewport is the browser's source of truth for the *visible* area.
/// The keyboard's top edge, measured from the top of the layout viewport, is
/// `visualViewport.offsetTop + visualViewport.height`. Flutter's canvas fills
/// that same layout viewport, so the visible-area overlap of the canvas is:
///
///   base = `flutterCanvasHeight - (offsetTop + visualViewport.height)`
///
/// We reference Flutter's *own* reported height (`MediaQuery.sizeOf(context)
/// .height`, in logical px == CSS px on web) rather than `window.innerHeight`,
/// which on iOS tracks the visual viewport and is off by a per-device constant.
///
/// `base` lands the composer at the visual-viewport bottom, which is a touch
/// above the real keyboard; a per-engine [_engineChromeCorrection] closes the
/// remaining browser-chrome band. See the correction notes above.
Widget keyboardInsetBuilder({
  required Widget Function(BuildContext context, double inset) builder,
}) => _WebKeyboardInset(builder: builder);

class _WebKeyboardInset extends StatefulWidget {
  final Widget Function(BuildContext context, double inset) builder;

  const _WebKeyboardInset({required this.builder});

  @override
  State<_WebKeyboardInset> createState() => _WebKeyboardInsetState();
}

class _WebKeyboardInsetState extends State<_WebKeyboardInset> {
  /// Bottom edge of the visual viewport in layout-viewport CSS px
  /// (`offsetTop + height`) — i.e. the keyboard's top edge. Null until the first
  /// viewport event; treated as "no keyboard".
  double? _vvBottom;

  /// Live correction while the debug slider is up; seeded from the baked
  /// per-engine constant. Unused when [_kDebugKeyboardInset] is false.
  double _correction = _engineChromeCorrection();

  late final JSFunction _listener;

  web.VisualViewport? get _viewport => web.window.visualViewport;

  @override
  void initState() {
    super.initState();
    _listener = ((web.Event _) => _update()).toJS;
    _viewport
      ?..addEventListener('resize', _listener)
      ..addEventListener('scroll', _listener);
  }

  void _update() {
    final viewport = _viewport;
    if (viewport == null) return;
    final next = viewport.offsetTop + viewport.height;
    final prev = _vvBottom;
    // Ignore sub-pixel churn (visualViewport fires a stream of scroll events).
    if (prev == null || (next - prev).abs() > 1) {
      setState(() => _vvBottom = next.toDouble());
    }
  }

  @override
  void dispose() {
    _viewport
      ?..removeEventListener('resize', _listener)
      ..removeEventListener('scroll', _listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewH = MediaQuery.sizeOf(context).height;
    final vvBottom = _vvBottom;
    final correction = _kDebugKeyboardInset
        ? _correction
        : _engineChromeCorrection();

    // Anchor at the visual-viewport bottom, then pull down by the chrome band.
    // Clamped so the keyboard-closed state (base ~0) and an over-large
    // correction can never yield a negative lift.
    final base = vvBottom == null ? 0.0 : (viewH - vvBottom);
    final inset = base <= 0 ? 0.0 : (base - correction).clamp(0.0, viewH);

    final child = widget.builder(context, inset);
    if (!_kDebugKeyboardInset) return child;

    final mq = MediaQuery.of(context);
    return Stack(
      children: [
        child,
        // RED line = body's own bottom (bottom: 0). GREEN line = composer target
        // (bottom: inset). Drag the slider until GREEN rests just above the keys.
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: ColoredBox(
              color: Color(0xFFFF0000),
              child: SizedBox(height: 2),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: inset,
          child: const IgnorePointer(
            child: ColoredBox(
              color: Color(0xFF00FF00),
              child: SizedBox(height: 2),
            ),
          ),
        ),
        _KeyboardInsetHud(
          flutterHeight: viewH,
          base: base,
          correction: correction,
          inset: inset,
          viewInsetsBottom: mq.viewInsets.bottom,
          dpr: mq.devicePixelRatio,
        ),
        // Correction tuner, pinned top so the keyboard never covers it.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: _CorrectionSlider(
              value: _correction,
              onChanged: (v) => setState(() => _correction = v),
            ),
          ),
        ),
      ],
    );
  }
}

/// Debug-only slider for dialing [_WebKeyboardInsetState._correction] live.
class _CorrectionSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _CorrectionSlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xCC000000),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Text(
              'corr ${value.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Color(0xFFFFEB3B),
                fontSize: 12,
                decoration: TextDecoration.none,
              ),
            ),
            Expanded(
              child: Slider(value: value, max: 220, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}

/// On-screen readout of the raw viewport numbers, for on-device tuning. Renders
/// only when [_kDebugKeyboardInset] is set.
class _KeyboardInsetHud extends StatelessWidget {
  final double flutterHeight;
  final double base;
  final double correction;
  final double inset;
  final double viewInsetsBottom;
  final double dpr;

  const _KeyboardInsetHud({
    required this.flutterHeight,
    required this.base,
    required this.correction,
    required this.inset,
    required this.viewInsetsBottom,
    required this.dpr,
  });

  @override
  Widget build(BuildContext context) {
    final vv = web.window.visualViewport;
    final innerH = web.window.innerHeight;
    final vvH = vv?.height ?? -1;
    final vvTop = vv?.offsetTop ?? -1;
    String n(num v) => v.toStringAsFixed(1);

    return Positioned(
      left: 8,
      bottom: inset + 8,
      child: IgnorePointer(
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Color(0xFFFFEB3B),
            fontSize: 11,
            height: 1.3,
            decoration: TextDecoration.none,
            fontFamilyFallback: ['monospace'],
          ),
          child: ColoredBox(
            color: const Color(0xCC000000),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('flutter H : ${n(flutterHeight)}'),
                  Text('innerH    : ${n(innerH)}'),
                  Text('vv.height : ${n(vvH)}'),
                  Text('vv.top    : ${n(vvTop)}'),
                  Text('viewIns.b : ${n(viewInsetsBottom)}'),
                  Text('dpr       : ${n(dpr)}'),
                  Text('base      : ${n(base)}'),
                  Text('corr      : ${n(correction)}'),
                  Text('INSET     : ${n(inset)}'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
