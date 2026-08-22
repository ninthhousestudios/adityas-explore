import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Sanitizes [rawName] into a filesystem-safe file stem for chart exports.
///
/// Falls back to `'chart'` when the name is null, empty, or reduces to nothing
/// usable, and strips leading dots. This guarantees a non-empty stem that never
/// begins with a `.` — a leading-dot name (e.g. `.toml`) is treated as an
/// extensionless dotfile by package:path, which trips file_picker's web save
/// guard ("The file name should include a valid file extension").
String chartFileStem(String? rawName) {
  final sanitized = (rawName ?? '')
      .replaceAll(RegExp(r'[^\w\-.]'), '_')
      .replaceAll(RegExp(r'^\.+'), '');
  return sanitized.isEmpty ? 'chart' : sanitized;
}

/// Saves [bytes] to a user-chosen location. Works on every platform: on
/// desktop it opens a save dialog and writes the file; on web it triggers a
/// browser download. Returns true unless the user cancels.
///
/// On web, [FilePicker.saveFile] always returns null (there is no cancel and no
/// path to report back), so a non-throwing call is treated as success.
Future<bool> saveFileBytes(
  String fileName,
  Uint8List bytes, {
  String dialogTitle = 'Save chart',
}) async {
  final uri = await FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    bytes: bytes,
  );
  return kIsWeb || uri != null;
}
