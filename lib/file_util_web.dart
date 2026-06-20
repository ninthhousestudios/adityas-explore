import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as html;

Future<bool> saveFileBytes(String fileName, Uint8List bytes) async {
  final blob = html.Blob([bytes.toJS].toJS);
  final url = html.URL.createObjectURL(blob);
  html.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..click();
  html.URL.revokeObjectURL(url);
  return true;
}
