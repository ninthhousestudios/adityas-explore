import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../api/api_config.dart';
import '../state/auth.dart';
import '../state/backend.dart';
// Conditional-import pair: `fetch`+`ReadableStream` on web, `dart:io` on desktop.
import 'chat_stream.dart' if (dart.library.js_interop) 'chat_stream_web.dart';

/// Supabase user ids allowed to use the wired skeleton chat client.
///
/// This mirrors the backend `BEING_REPORT_ALLOWLIST` gate (adityas/ai/3): the
/// chat *panel* is open to everyone (it doubles as the layout-mode stub), but
/// the wired client only talks to the backend for Josh + Laura. Client-side this
/// is only a UX gate — the backend independently enforces the same allowlist, so
/// a determined non-allowlisted user gets a 403, not tokens.
const chatAllowlist = <String>{
  '01214259-228c-46a9-bb3d-e229c8c4cb3f', // josh@ninthhouse.studio
  'be96b3d3-5c64-40d2-ae77-73d6883d14a2', // info@lvbarat.com
};

/// True when the signed-in user may use the wired chat client.
final chatEnabledProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  return user != null && chatAllowlist.contains(user.id);
});

/// The chat client, wired to Supabase auth for bearer tokens. keepAlive — it is
/// stateless apart from its `http.Client`.
final solarMirrorClientProvider = Provider<SolarMirrorClient>(
  (ref) => SolarMirrorClient(tokenProvider: supabaseAccessToken),
);

/// Raised when the backend rejects a turn (non-202 POST or an SSE `error`).
class SolarMirrorException implements Exception {
  final String message;
  const SolarMirrorException(this.message);
  @override
  String toString() => message;
}

/// A typed event decoded from the backend's turn SSE stream.
sealed class ChatEvent {
  const ChatEvent();
}

/// A chunk of assistant text to append to the in-flight message.
class ChatDelta extends ChatEvent {
  final String text;
  const ChatDelta(this.text);
}

/// The model started a knowledge tool call (e.g. `get_being`).
class ChatToolStart extends ChatEvent {
  final String name;
  const ChatToolStart(this.name);
}

/// A knowledge tool call returned.
class ChatToolEnd extends ChatEvent {
  final String name;
  const ChatToolEnd(this.name);
}

/// The generation failed; carries the backend's message.
class ChatError extends ChatEvent {
  final String message;
  const ChatError(this.message);
}

/// Terminal event — the turn is complete.
class ChatDone extends ChatEvent {
  const ChatDone();
}

/// Throwaway walking-skeleton client for the Solar Mirror chat (adityas/ai/4).
///
/// Drives the two-call durable-generation contract: [createTurn] POSTs the
/// message and gets a `turn_id` back immediately; [streamTurn] attaches to that
/// turn's SSE stream and decodes it into [ChatEvent]s. No history, no resume, no
/// persistence — a restart or a panel close loses the conversation.
class SolarMirrorClient {
  SolarMirrorClient({
    required Future<String?> Function({bool forceRefresh}) tokenProvider,
    http.Client? httpClient,
  }) : _token = tokenProvider,
       _http = httpClient ?? http.Client();

  final Future<String?> Function({bool forceRefresh}) _token;
  final http.Client _http;

  /// `POST /v1/ai/conversations/{id}/turns` → the new turn's id.
  ///
  /// [conversationId] is accepted for URL parity but unused by the throwaway
  /// backend (no persistence yet).
  Future<String> createTurn({
    required String conversationId,
    required String message,
  }) async {
    final token = await _token();
    if (token == null) throw const SolarMirrorException('Not signed in');
    final response = await _http.post(
      Uri.parse('$apiBaseUrl/v1/ai/conversations/$conversationId/turns'),
      headers: {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      },
      body: jsonEncode({'message': message}),
    );
    if (response.statusCode != 202) {
      throw SolarMirrorException(_httpError(response));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['turn_id'] as String;
  }

  /// `GET /v1/ai/turns/{turn_id}/stream` → the decoded event stream.
  ///
  /// Emits [ChatDelta]s live as the model streams, plus tool markers, and
  /// terminates on [ChatDone] (or [ChatError] followed by [ChatDone]).
  Stream<ChatEvent> streamTurn(String turnId) async* {
    final token = await _token();
    if (token == null) throw const SolarMirrorException('Not signed in');
    final uri = Uri.parse('$apiBaseUrl/v1/ai/turns/$turnId/stream');
    final headers = {
      'authorization': 'Bearer $token',
      'accept': 'text/event-stream',
    };
    await for (final event in _parseSse(openSseByteStream(uri, headers))) {
      final decoded = _decode(event);
      if (decoded == null) continue;
      yield decoded;
      if (decoded is ChatDone) return;
    }
  }

  String _httpError(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['error'] as String? ?? 'Request failed';
    } catch (_) {
      return 'Request failed (${response.statusCode})';
    }
  }
}

/// One SSE frame: its `event:` name and the accumulated `data:` payload.
class _SseFrame {
  final String event;
  final String data;
  const _SseFrame(this.event, this.data);
}

/// Parses a raw SSE byte stream into [_SseFrame]s. Handles multi-line `data:`,
/// leading-space trimming, comment/keep-alive lines (`:`), and a frame left
/// unterminated when the stream closes. Chunk boundaries are handled by the
/// UTF-8 decoder + line splitter.
Stream<_SseFrame> _parseSse(Stream<List<int>> bytes) async* {
  var event = 'message';
  final data = StringBuffer();
  var hasData = false;

  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (hasData) yield _SseFrame(event, data.toString());
      event = 'message';
      data.clear();
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
    }
  }
  if (hasData) yield _SseFrame(event, data.toString());
}

ChatEvent? _decode(_SseFrame frame) {
  switch (frame.event) {
    case 'delta':
      return ChatDelta(_field(frame.data, 'text'));
    case 'tool_start':
      return ChatToolStart(_field(frame.data, 'name'));
    case 'tool_end':
      return ChatToolEnd(_field(frame.data, 'name'));
    case 'error':
      return ChatError(_field(frame.data, 'message'));
    case 'done':
      return const ChatDone();
    default:
      return null; // usage, keep-alive, or anything unrecognized
  }
}

String _field(String data, String key) {
  try {
    final map = jsonDecode(data) as Map<String, dynamic>;
    return map[key]?.toString() ?? '';
  } catch (_) {
    return '';
  }
}
