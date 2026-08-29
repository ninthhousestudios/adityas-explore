import 'dart:convert';

import 'package:charts_dart/charts_dart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../api/api_config.dart';
import '../state/auth.dart';
import '../state/backend.dart';
// Conditional-import pair: `fetch`+`ReadableStream` on web, `dart:io` on desktop.
import 'chat_stream.dart' if (dart.library.js_interop) 'chat_stream_web.dart';
import 'sse.dart';

/// Supabase user ids allowed to use the wired skeleton chat client.
///
/// This mirrors the backend preview-path gate (`/v1/ai/preview/*`, adityas/ai/3
/// remounted by adityas/ai/51 — being_report ∪ gemini_test): the chat *panel* is
/// open to everyone (it doubles as the layout-mode stub), but the wired client
/// only talks to the backend for the allowlisted accounts below. Client-side this
/// is only a UX gate — the backend independently enforces the same allowlist, so
/// a determined non-allowlisted user gets a 403, not tokens.
const chatAllowlist = <String>{
  '01214259-228c-46a9-bb3d-e229c8c4cb3f', // josh@ninthhouse.studio
  '2e0010eb-0810-42f9-8c42-563342203813', // weburnalltimes@gmail.com (Josh, preview testing)
  'be96b3d3-5c64-40d2-ae77-73d6883d14a2', // info@lvbarat.com (Laura)
  '30cff75a-a431-4b48-bade-5528bc4e7f2f', // lorris
};

/// Accounts routed to the durable `/v1/ai` lane (backend gate: standalone
/// `ai_chat_allowlist`, adityas/ai/51). Everyone else on [chatAllowlist] stays
/// on the preview lane (`/v1/ai/preview`, gate: being_report ∪ gemini_test).
///
/// This is a subset of [chatAllowlist]: durable membership implies chat access.
/// At final cutover the preview lane is deleted and all accounts route to
/// `/v1/ai`.
const durableChatAllowlist = <String>{
  '01214259-228c-46a9-bb3d-e229c8c4cb3f', // josh@ninthhouse.studio
};

/// Backend base-path prefix for [userId]: the durable lane for
/// [durableChatAllowlist] members, the preview lane for everyone else. Selecting
/// per-account keeps a durable account off preview's gate (which would 403 it).
String chatPathPrefix(String userId) =>
    durableChatAllowlist.contains(userId) ? '/v1/ai' : '/v1/ai/preview';

/// True when the signed-in user may use the wired chat client.
final chatEnabledProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  return user != null && chatAllowlist.contains(user.id);
});

/// The chat client, wired to Supabase auth for bearer tokens. Rebuilt on auth
/// change so [SolarMirrorClient.basePath] tracks the signed-in account's lane;
/// stateless apart from its `http.Client`.
final solarMirrorClientProvider = Provider<SolarMirrorClient>((ref) {
  final user = ref.watch(authProvider);
  return SolarMirrorClient(
    tokenProvider: supabaseAccessToken,
    basePath: user == null ? '/v1/ai/preview' : chatPathPrefix(user.id),
  );
});

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
    this.basePath = '/v1/ai/preview',
    http.Client? httpClient,
  }) : _token = tokenProvider,
       _http = httpClient ?? http.Client();

  final Future<String?> Function({bool forceRefresh}) _token;
  final http.Client _http;

  /// Backend base-path prefix for this client's account — `/v1/ai` (durable) or
  /// `/v1/ai/preview` (preview). Chosen per signed-in account by
  /// [chatPathPrefix]; both lanes share the same route suffixes below.
  final String basePath;

  /// `POST {basePath}/conversations/{id}/turns` → the new turn's id.
  ///
  /// [conversationId] is accepted for URL parity but unused by the throwaway
  /// backend (no persistence yet).
  ///
  /// [chart], when supplied, is the currently-open chart's birth data. It rides
  /// along as the backend's `ChartInput` (adityas/explore/50 ↔ adityas/ai/35) so
  /// the harness can compute `chart_facts` and the model can speak about the
  /// person's own activated beings. Absent → a chart-less turn.
  Future<String> createTurn({
    required String conversationId,
    required String message,
    ChartData? chart,
  }) async {
    final token = await _token();
    if (token == null) throw const SolarMirrorException('Not signed in');
    final body = <String, dynamic>{'message': message};
    if (chart != null) body['chart'] = _chartInput(chart);
    final response = await _http.post(
      Uri.parse('$apiBaseUrl$basePath/conversations/$conversationId/turns'),
      headers: {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode != 202) {
      throw SolarMirrorException(_httpError(response));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['turn_id'] as String;
  }

  /// `GET {basePath}/turns/{turn_id}/stream` → the decoded event stream.
  ///
  /// Emits [ChatDelta]s live as the model streams, plus tool markers, and
  /// terminates on [ChatDone] (or [ChatError] followed by [ChatDone]).
  Stream<ChatEvent> streamTurn(String turnId) async* {
    final token = await _token();
    if (token == null) throw const SolarMirrorException('Not signed in');
    final uri = Uri.parse('$apiBaseUrl$basePath/turns/$turnId/stream');
    final headers = {
      'authorization': 'Bearer $token',
      'accept': 'text/event-stream',
    };
    try {
      await for (final event in parseSse(openSseByteStream(uri, headers))) {
        final decoded = _decode(event);
        if (decoded == null) continue;
        yield decoded;
        if (decoded is ChatDone) return;
      }
    } on SolarMirrorException {
      rethrow;
    } catch (e) {
      // Transport/parse failures arrive as HttpException (native) or Exception
      // (web), whose toString carries a type prefix and, on native, a
      // ", uri = …" tail. Rewrap so the panel shows just the message.
      throw SolarMirrorException(_cleanTransportError(e));
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

/// The open chart's civil birth data in the backend's `ChartInput` shape,
/// which mirrors `CalculateRequest` (adityas/ai/35). `date`/`time`/`utc_offset`/
/// `dst_offset` reuse charts_dart's canonical [ChartData.toJson] formatting
/// (`YYYY-MM-DD` / `HH:MM:SS`); `lat`/`lon` are flattened out of the nested
/// `location` object the backend doesn't accept here.
Map<String, dynamic> _chartInput(ChartData chart) {
  final json = chart.toJson();
  return {
    'date': json['date'],
    'time': json['time'],
    'lat': chart.birthLocation.latitude,
    'lon': chart.birthLocation.longitude,
    'utc_offset': json['utc_offset'],
    'dst_offset': json['dst_offset'],
  };
}

ChatEvent? _decode(SseFrame frame) {
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

/// Strips the leading `…Exception: ` type prefix and any trailing `, uri = …`
/// from a transport error's `toString`, leaving just the human message.
String _cleanTransportError(Object e) {
  var s = e.toString();
  final marker = s.indexOf('Exception: ');
  if (marker != -1) s = s.substring(marker + 'Exception: '.length);
  final uriTail = s.indexOf(', uri = ');
  if (uriTail != -1) s = s.substring(0, uriTail);
  return s;
}
