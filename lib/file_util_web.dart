import 'dart:typed_data';

Future<void> writeBytesToPath(String path, Uint8List bytes) async {
  // On web, FilePicker.saveFile handles the download via the bytes param.
}
