import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import 'ui/aditya_data.dart';

const _baseUrl = 'https://api.84beings.com/static/share-cards';

String _cardUrl(int sign, String beingType) {
  final aditya = adityaSigns[sign]?.name.toLowerCase() ?? '';
  return '$_baseUrl/$aditya-$beingType.webp';
}

Future<String?> shareBeingCard({
  required int sign,
  required String beingType,
  required String beingName,
  required String planetName,
}) async {
  final url = _cardUrl(sign, beingType);
  final http.Response response;
  try {
    response = await http.get(Uri.parse(url));
  } catch (e) {
    return 'Network error: $e';
  }
  if (response.statusCode != 200) {
    return 'Failed to load card (${response.statusCode})';
  }

  final bytes = response.bodyBytes;
  final aditya = adityaSigns[sign]?.name.toLowerCase() ?? 'being';
  final fileName = '$aditya-$beingType.webp';

  await _saveFile(fileName, bytes);
  return null;
}

Future<void> _saveFile(String fileName, Uint8List bytes) async {
  final result = await FilePicker.platform.saveFile(
    dialogTitle: 'Save share card',
    fileName: fileName,
  );
  if (result == null) return;
  await File(result).writeAsBytes(bytes);
}
