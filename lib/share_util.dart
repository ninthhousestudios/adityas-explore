import 'package:http/http.dart' as http;

import 'file_util.dart';
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

  await saveFileBytes(fileName, bytes, dialogTitle: 'Save share card');
  return null;
}
