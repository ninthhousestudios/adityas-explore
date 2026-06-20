import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> saveFileBytes(String fileName, Uint8List bytes) async {
  final result = await FilePicker.platform.saveFile(
    dialogTitle: 'Save chart',
    fileName: fileName,
  );
  if (result == null) return false;
  await File(result).writeAsBytes(bytes);
  return true;
}
