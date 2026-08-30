import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:charts_dart/charts_dart.dart';

import '../api/api_config.dart';
import '../state/turn_transport.dart';
import 'chart_input.dart';
// Conditional-import pair: `fetch`+`ReadableStream` on web, `dart:io` on desktop.
import 'chat_stream.dart' if (dart.library.js_interop) 'chat_stream_web.dart';
import 'sse.dart';

/// Opens an SSE byte stream for [uri] with [headers]. The seam that lets tests
/// feed in-memory bytes instead of a real `fetch`/`dart:io` connection; the
/// production default is [openSseByteStream] (the conditional-import pair).
typedef SseByteSource =
    Stream<List<int>> Function(Uri uri, Map<String, String> headers);

/// Raised when the durable wire rejects a request (a non-2xx REST response, or a
/// missing token). Surfaces as a stream error the notifier turns into a terminal
/// [TurnError] after its reconnect budget.
class TurnTransportException implements Exception {
  final String message;
  const TurnTransportException(this.message);
  @override
  String toString() => message;
}

/// The real [TurnTransport]: the durable `/v1/ai` chat wire (adityas/ai/11).
///
/// Drives the canonical three-call contract:
///   1. `POST /v1/ai/conversations`             → `201 {conversation_id}` (lazy, cached)
///   2. `POST /v1/ai/conversations/{id}/turns`  → `202 {turn_id}` (Idempotency-Key required)
///   3. `GET  /v1/ai/turns/{turn_id}/stream`    → SSE; a `Last-Event-ID` header resumes.
///
/// Adapts the wire's SSE frames into the closed [TurnEvent] vocabulary through
/// [decodeTurnFrame] — the notifier never sees backend JSON. Resume is by
/// `Last-Event-ID` against the server's durable event log (I11): the *server*
/// persists the turn's events; this transport replays from an in-memory cursor
/// ([resume]). That cursor is NOT persisted client-side — resume survives a
/// widget unmount and a transient reconnect, but not an app relaunch (a durable
/// cross-relaunch cursor rides on adityas/ai/64).
///
/// **Chart-aware (adityas/ai/65):** when [TurnRequest.chart] is set, the open
/// chart's birth data rides along in the turn body as the backend's `ChartInput`
/// (`chart_facts` landed on the durable path in adityas/ai/63), so the model can
/// speak about the person's own activated beings. Absent ⇒ a chart-less turn.
class SseTurnTransport implements TurnTransport {
  SseTurnTransport({
    required Future<String?> Function({bool forceRefresh}) tokenProvider,
    String? baseUrl,
    http.Client? httpClient,
    SseByteSource? byteSource,
  }) : _token = tokenProvider,
       _baseUrl = baseUrl ?? apiBaseUrl,
       _http = httpClient ?? http.Client(),
       _byteSource = byteSource ?? openSseByteStream;

  final Future<String?> Function({bool forceRefresh}) _token;
  final String _baseUrl;
  final http.Client _http;
  final SseByteSource _byteSource;

  // The durable conversation this transport appends to, minted lazily and reused
  // for its lifetime. Reset on a user change ([resetConversation]) so a signed-in
  // user never appends to the previous user's conversation.
  String? _conversationId;

  // The in-flight (or most recent) turn — the target of [resume] and a future
  // server-side [cancel].
  String? _turnId;

  int _idempotencySeq = 0;

  @override
  Stream<TurnEvent> start(TurnRequest request) async* {
    final token = await _requireToken();
    final conversationId = await _ensureConversation(token);
    final turnId = await _createTurn(
      token,
      conversationId,
      request.text,
      request.chart,
    );
    _turnId = turnId;
    yield* _stream(token, turnId, lastEventId: null);
  }

  @override
  Stream<TurnEvent> resume(String cursor) async* {
    final turnId = _turnId;
    if (turnId == null) {
      throw const TurnTransportException('resume() before a turn was started');
    }
    final token = await _requireToken();
    yield* _stream(token, turnId, lastEventId: cursor.isEmpty ? null : cursor);
  }

  @override
  Future<void> cancel() async {
    // TODO(adityas/backend/54): server-side stop. The durable path has no cancel
    // route yet, so this is a no-op: the notifier keeps the stream open and
    // settles TurnCancelled on the server's real trailing usage/done, so billing
    // stays accurate even though the generation is not stopped early.
  }

  /// Reset the cached conversation (call on a user change). The next [start]
  /// mints a fresh durable conversation for the new user, so a turn never lands
  /// in a conversation the current token does not own.
  void resetConversation() {
    _conversationId = null;
    _turnId = null;
  }

  Future<String> _requireToken() async {
    final token = await _token();
    if (token == null) throw const TurnTransportException('Not signed in');
    return token;
  }

  /// The durable conversation, minted on first use and cached thereafter.
  Future<String> _ensureConversation(String token) async {
    final cached = _conversationId;
    if (cached != null) return cached;
    final response = await _http.post(
      Uri.parse('$_baseUrl/v1/ai/conversations'),
      headers: _jsonHeaders(token),
    );
    if (response.statusCode != 201) {
      throw TurnTransportException(_httpError(response));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final id = data['conversation_id'] as String;
    _conversationId = id;
    return id;
  }

  /// POST the turn, returning its `turn_id`. A `404` means the cached
  /// conversation is stale (a user switch, or a server-side eviction): re-mint a
  /// fresh conversation and retry once.
  Future<String> _createTurn(
    String token,
    String conversationId,
    String message,
    ChartData? chart,
  ) async {
    final response = await _postTurn(token, conversationId, message, chart);
    if (response.statusCode == 404) {
      _conversationId = null;
      final fresh = await _ensureConversation(token);
      return _turnIdFrom(await _postTurn(token, fresh, message, chart));
    }
    return _turnIdFrom(response);
  }

  Future<http.Response> _postTurn(
    String token,
    String conversationId,
    String message,
    ChartData? chart,
  ) {
    final body = <String, dynamic>{'message': message};
    // The open chart rides along so the backend computes chart_facts (ai/63);
    // absent ⇒ a chart-less turn. Same ChartInput shape the preview lane posts.
    if (chart != null) body['chart'] = chartInputJson(chart);
    return _http.post(
      Uri.parse('$_baseUrl/v1/ai/conversations/$conversationId/turns'),
      headers: {
        ..._jsonHeaders(token),
        // Required by the durable path; a fresh key per turn (the notifier opens
        // a turn once — reconnects go through resume(), not a re-POST).
        'idempotency-key':
            'explore-${DateTime.now().microsecondsSinceEpoch}-${_idempotencySeq++}',
      },
      body: jsonEncode(body),
    );
  }

  String _turnIdFrom(http.Response response) {
    if (response.statusCode != 202) {
      throw TurnTransportException(_httpError(response));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['turn_id'] as String;
  }

  Stream<TurnEvent> _stream(
    String token,
    String turnId, {
    required String? lastEventId,
  }) async* {
    final uri = Uri.parse('$_baseUrl/v1/ai/turns/$turnId/stream');
    final headers = {
      'authorization': 'Bearer $token',
      'accept': 'text/event-stream',
      'last-event-id': ?lastEventId,
    };
    await for (final frame in parseSse(_byteSource(uri, headers))) {
      yield decodeTurnFrame(frame);
    }
  }

  Map<String, String> _jsonHeaders(String token) => {
    'authorization': 'Bearer $token',
    'content-type': 'application/json',
  };

  String _httpError(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['error'] as String? ?? 'Request failed';
    } catch (_) {
      return 'Request failed (${response.statusCode})';
    }
  }
}

/// Adapts one durable-wire [SseFrame] into the closed [TurnEvent] vocabulary.
///
/// An unrecognized `event:` name becomes an [UnknownEvent] — explore is a shipped
/// binary and must survive server event types it predates (the notifier ignores
/// them but still advances the cursor past them). The frame's `id:` is the
/// `Last-Event-ID` cursor; a frame without one carries the empty cursor.
TurnEvent decodeTurnFrame(SseFrame frame) {
  final id = frame.id ?? '';
  switch (frame.event) {
    case 'delta':
      return DeltaEvent(_stringField(frame.data, 'text'), id);
    case 'usage':
      return UsageEvent(_usageFrom(frame.data), id);
    case 'error':
      return ErrorEvent(_stringField(frame.data, 'message'), id);
    case 'done':
      return DoneEvent(id);
    default:
      return UnknownEvent(frame.event, id);
  }
}

/// The durable `usage` payload: `{promptTokens, outputTokens, totalTokens}`
/// (`engine.rs`). We keep the two components; [TurnUsage.totalTokens] re-derives
/// the sum.
TurnUsage _usageFrom(String data) {
  final map = _decodeObject(data);
  return TurnUsage(
    inputTokens: _intField(map, 'promptTokens'),
    outputTokens: _intField(map, 'outputTokens'),
  );
}

Map<String, dynamic> _decodeObject(String data) {
  try {
    final decoded = jsonDecode(data);
    return decoded is Map<String, dynamic> ? decoded : const {};
  } catch (_) {
    return const {};
  }
}

String _stringField(String data, String key) =>
    _decodeObject(data)[key]?.toString() ?? '';

int _intField(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
