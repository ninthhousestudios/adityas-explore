import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Web implementation of [keyboardInsetBuilder]: measures the soft keyboard's
/// overlap of the layout viewport from `window.visualViewport` and rebuilds
/// [builder] whenever it changes.
///
/// Flutter web keeps its canvas at full height when the mobile keyboard opens
/// (the keyboard overlays it) and reports an unreliable `viewInsets.bottom`, so
/// neither `Scaffold` resize nor `MediaQuery` gives a usable inset. The visual
/// viewport is the browser's source of truth: `innerHeight - visualViewport
/// .height - offsetTop` is exactly how much of the bottom the keyboard covers.
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
  double _inset = 0;
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
    final overlap =
        web.window.innerHeight - viewport.height - viewport.offsetTop;
    final next = overlap < 0 ? 0.0 : overlap.toDouble();
    // Ignore sub-pixel churn (visualViewport fires a stream of scroll events).
    if ((next - _inset).abs() > 1) setState(() => _inset = next);
  }

  @override
  void dispose() {
    _viewport
      ?..removeEventListener('resize', _listener)
      ..removeEventListener('scroll', _listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _inset);
}
