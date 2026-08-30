import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web SSE byte source: streams the response body incrementally via `fetch` +
/// `ReadableStream`.
///
/// This is the whole point of bug #3 — `package:http`/`BrowserClient` buffers an
/// SSE response to completion instead of surfacing tokens live, so we drop to
/// the browser `fetch` API and pull chunks off the body reader by hand. Mirrors
/// [openSseByteStream] in chat_stream.dart; the shared SSE parser lives in
/// sse.dart (`parseSse`).
Stream<List<int>> openSseByteStream(
  Uri uri,
  Map<String, String> headers,
) async* {
  final jsHeaders = web.Headers();
  headers.forEach((name, value) => jsHeaders.append(name, value));

  final response = await web.window
      .fetch(
        uri.toString().toJS,
        web.RequestInit(method: 'GET', headers: jsHeaders),
      )
      .toDart;

  if (!response.ok) {
    final body = (await response.text().toDart).toDart;
    throw Exception('stream failed (${response.status}): ${body.trim()}');
  }

  final body = response.body;
  if (body == null) return;
  final reader = body.getReader() as web.ReadableStreamDefaultReader;
  try {
    while (true) {
      final chunk = await reader.read().toDart;
      if (chunk.done) break;
      final value = chunk.value;
      if (value == null) continue;
      yield (value as JSUint8Array).toDart;
    }
  } finally {
    // Abort the fetch if the Dart consumer cancels mid-stream.
    reader.cancel();
  }
}
