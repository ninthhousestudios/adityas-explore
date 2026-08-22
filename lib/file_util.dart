import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Saves [bytes] to a user-chosen location. Works on every platform: on
/// desktop it opens a save dialog and writes the file; on web it triggers a
/// browser download. Returns true unless the user cancels.
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
  return uri != null;
}
