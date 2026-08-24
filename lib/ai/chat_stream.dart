import 'dart:convert';
import 'dart:io';

/// Native (`dart:io`) SSE byte source for the walking-skeleton chat client.
///
/// Opens a GET to [uri] with [headers] and yields the raw response body as it
/// arrives. This is the desktop half of a conditional-import pair; its web twin
/// ([chat_stream_web.dart]) streams via `fetch`+`ReadableStream` to dodge the
/// `package:http`/`BrowserClient` buffering bug (adityas/ai bug #3). Both only
/// supply bytes — the shared SSE parser lives in [SolarMirrorClient].
Stream<List<int>> openSseByteStream(
  Uri uri,
  Map<String, String> headers,
) async* {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    headers.forEach((name, value) => request.headers.set(name, value));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      final body = await response.transform(utf8.decoder).join();
      throw HttpException(
        'stream failed (${response.statusCode}): ${body.trim()}',
        uri: uri,
      );
    }
    yield* response;
  } finally {
    client.close();
  }
}
