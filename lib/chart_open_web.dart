import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'picked_chart.dart';

/// Web implementation of [pickChartFile] that hand-rolls the `<input type=file>`
/// element rather than going through file_picker's web plugin.
///
/// file_picker's web session is unreliable on iOS Safari: it removes the input
/// from the DOM immediately after `click()` and arms a window-`focus` "cancel"
/// timer, so a real selection resolves to `null` — the picker opens, you tap a
/// file, and nothing happens. Here the input stays attached and we resolve only
/// on its own `change` / `cancel` events, so a tapped file always comes back.
Future<PickedChart?> pickChartFile() async {
  final body = web.document.body;
  if (body == null) return null;

  final completer = Completer<PickedChart?>();

  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = chartExtensions.map((e) => '.$e').join(',')
    ..style.display = 'none';

  // iOS Safari only delivers `change` for an input attached to the DOM.
  body.appendChild(input);

  void finish(PickedChart? value) {
    if (!completer.isCompleted) completer.complete(value);
    input.remove();
  }

  input
    ..addEventListener(
      'change',
      ((web.Event _) {
        final files = input.files;
        final file = (files == null || files.length == 0)
            ? null
            : files.item(0);
        if (file == null) {
          finish(null);
          return;
        }
        final reader = web.FileReader();
        reader
          ..addEventListener(
            'loadend',
            ((web.Event _) {
              final buffer = (reader.result as JSArrayBuffer?)?.toDart;
              finish(
                buffer == null
                    ? null
                    : PickedChart(file.name, buffer.asUint8List()),
              );
            }).toJS,
          )
          ..addEventListener('error', ((web.Event _) => finish(null)).toJS)
          ..readAsArrayBuffer(file);
      }).toJS,
    )
    // `cancel` fires when the picker is dismissed without a choice (not emitted
    // by every browser; if absent the future stays pending, which is harmless).
    ..addEventListener('cancel', ((web.Event _) => finish(null)).toJS)
    ..click();

  return completer.future;
}
