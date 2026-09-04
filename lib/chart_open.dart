import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

import 'picked_chart.dart';

/// Opens the native file picker and returns the chosen chart file, or `null` if
/// the user cancels. (Native + desktop; the web override lives in
/// `chart_open_web.dart`.)
///
/// On iOS/Android the document picker filters by UTI / MIME type, and our
/// extensions ([chartExtensions]) aren't system-declared types — `FileType.custom`
/// makes those files render greyed-out / non-selectable (tap does nothing). So
/// on mobile we open with `FileType.any` and let `ChartReader` reject a
/// non-chart file by extension. Desktop keeps the extension filter, where it
/// works and pre-narrows the dialog.
Future<PickedChart?> pickChartFile() async {
  final mobile =
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
  final file = await FilePicker.pickFile(
    type: mobile ? FileType.any : FileType.custom,
    allowedExtensions: mobile ? null : chartExtensions,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return PickedChart(file.name, bytes);
}
