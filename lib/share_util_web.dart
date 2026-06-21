import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as html;

import 'ui/aditya_data.dart';

const _baseUrl = 'https://84beings.com/static/share-cards';

String _cardUrl(int sign, String beingType) {
  final aditya = adityaSigns[sign]?.name.toLowerCase() ?? '';
  return '$_baseUrl/$aditya-$beingType.webp';
}

Future<void> shareBeingCard({
  required int sign,
  required String beingType,
  required String beingName,
  required String planetName,
}) async {
  final url = _cardUrl(sign, beingType);
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) return;

  final bytes = response.bodyBytes;
  final aditya = adityaSigns[sign]?.name.toLowerCase() ?? 'being';
  final fileName = '$aditya-$beingType.webp';
  final shareText = planetName.isNotEmpty
      ? 'My ${_capitalize(planetName)} is $beingName — 84beings.com'
      : '$beingName — 84beings.com';

  try {
    final nav = html.window.navigator as JSObject;
    if (nav.has('share') && nav.has('canShare')) {
      final file = html.File(
        [bytes.toJS].toJS,
        fileName,
        html.FilePropertyBag(type: 'image/webp'),
      );
      final shareData = html.ShareData(files: [file].toJS, text: shareText);
      if (html.window.navigator.canShare(shareData)) {
        await html.window.navigator.share(shareData).toDart;
        return;
      }
    }
  } catch (_) {}
  _download(fileName, bytes);
}

void _download(String fileName, Uint8List bytes) {
  final blob = html.Blob([bytes.toJS].toJS);
  final url = html.URL.createObjectURL(blob);
  html.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..click();
  html.URL.revokeObjectURL(url);
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
