import 'dart:convert';

/// Shared Server-Sent-Events framing for the chat wire.
///
/// Both the throwaway preview client ([SolarMirrorClient]) and the durable
/// [SseTurnTransport] speak SSE, so the multi-line-`data:` / comment /
/// unterminated-frame rules live here once rather than in two copies. The byte
/// source itself is the conditional-import pair (chat_stream.dart /
/// chat_stream_web.dart); this only frames the bytes into [SseFrame]s.

/// One SSE frame: its `event:` name, accumulated `data:` payload, and `id:` — the
/// `Last-Event-ID` cursor, `null` on a frame that carries none (the preview wire
/// sends no ids; the durable wire tags every event with its log index).
class SseFrame {
  final String event;
  final String data;
  final String? id;

  const SseFrame(this.event, this.data, this.id);
}

/// Frames a raw SSE byte stream. Handles multi-line `data:`, `id:`, leading-space
/// trimming, comment/keep-alive lines (`:`), and a frame left unterminated when
/// the stream closes. Chunk boundaries are handled by the UTF-8 decoder + line
/// splitter.
Stream<SseFrame> parseSse(Stream<List<int>> bytes) async* {
  var event = 'message';
  final data = StringBuffer();
  String? id;
  var hasData = false;

  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (hasData) yield SseFrame(event, data.toString(), id);
      event = 'message';
      data.clear();
      id = null;
      hasData = false;
      continue;
    }
    if (line.startsWith(':')) continue; // comment / keep-alive ping
    final colon = line.indexOf(':');
    final field = colon == -1 ? line : line.substring(0, colon);
    var value = colon == -1 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        event = value;
      case 'data':
        if (hasData) data.write('\n');
        data.write(value);
        hasData = true;
      case 'id':
        id = value;
    }
  }
  if (hasData) yield SseFrame(event, data.toString(), id);
}
