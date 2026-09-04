import 'package:flutter/widgets.dart';

/// Rebuilds [builder] with the current soft-keyboard inset in logical pixels.
///
/// This is the native/desktop implementation: it always reports `0`, because
/// there the `Scaffold`'s `resizeToAvoidBottomInset` already lifts content above
/// the keyboard. The web override (`keyboard_inset_web.dart`) measures the real
/// keyboard overlap from `window.visualViewport`, since Flutter web's
/// `viewInsets.bottom` is unreliable on mobile browsers. Callers pair the web
/// value with `resizeToAvoidBottomInset: false` (web only) so the inset is
/// applied exactly once.
Widget keyboardInsetBuilder({
  required Widget Function(BuildContext context, double inset) builder,
}) => Builder(builder: (context) => builder(context, 0));
