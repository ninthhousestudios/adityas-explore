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

/// Internal sentinel: an in-flight [SseTurnTransport.start] discovered that a
/// [adoptConversation]/[resetConversation] rotated the conversation out from
/// under it (the epoch changed). It unwinds the opening turn without writing any
/// conversation/turn state; [start] catches it and ends the stream silently.
/// Never surfaces to the notifier — the rotation path cancels the subscription
/// first (adityas/ai/86).
class _ConversationSuperseded implements Exception {
  const _ConversationSuperseded();
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

  // A Stop pressed while a turn is still opening (TurnConnecting) has no id to
  // target yet, so [cancel] latches the intent here and [start] fires it the
  // moment the id is minted. Without this, an early Stop reads a null [_turnId]
  // (no-op, turn keeps generating) or a stale previous id (cancels the wrong
  // turn) — the Stop-during-connecting race (adityas/ai/140). Reset at the top
  // of every [start] so it never carries across turns.
  bool _pendingCancel = false;

  int _idempotencySeq = 0;

  // True while [_conversationId] holds a *resumed* (adopted) thread rather than
  // a self-minted one. An adopted id that 404s on a turn must NOT be silently
  // re-minted — that would divorce the transport from the transcript the user is
  // looking at (adityas/ai/86) — so [_createTurn] fails instead of reminting.
  bool _adopted = false;

  // Rotation generation. [adoptConversation]/[resetConversation] bump it, and an
  // in-flight [start] that resumes past an await into a changed epoch abandons
  // itself before writing [_conversationId]/[_turnId]. This is what makes a
  // Resume or New-Chat fired mid-`start()` actually atomic: closing the stream
  // subscription cannot preempt the pre-yield body, but the epoch check can
  // (adityas/ai/86). The rotation path cancels the subscription first, so the
  // abandoning throw lands on a dead subscription and is dropped.
  int _epoch = 0;

  /// The server conversation subsequent turns append to: the adopted id after
  /// [adoptConversation], the minted id once [start] has created one, or null
  /// before any turn. The picker reads this to detect deleting the *active*
  /// thread even when it was minted this session (adityas/ai/86).
  @override
  String? get conversationId => _conversationId;

  @override
  Stream<TurnEvent> start(TurnRequest request) async* {
    final epoch = _epoch;
    // A fresh turn has no id and no carried-over Stop intent yet. Clear the
    // previous turn's id so a Stop pressed while this one connects can't target
    // it, and drop any stale pending-cancel (adityas/ai/140).
    _turnId = null;
    _pendingCancel = false;
    final String token;
    final String conversationId;
    final String turnId;
    try {
      token = await _requireToken();
      conversationId = await _ensureConversation(
        token,
        epoch,
        title: request.conversationTitle,
      );
      turnId = await _createTurn(
        token,
        conversationId,
        request.text,
        request.chart,
        request.conversationTitle,
        epoch,
      );
    } on _ConversationSuperseded {
      // A Resume / New-Chat / user-change rotated the conversation while this
      // turn was opening. Abandon silently — the notifier has already moved on,
      // and its subscription to this stream was cancelled first.
      return;
    }
    if (_epoch != epoch) return;
    _turnId = turnId;
    if (_pendingCancel) {
      // A Stop pressed while this turn was still opening latched the intent;
      // fire it now for the exact id, then still stream so the terminal
      // error → usage → done flows to the notifier (adityas/ai/140).
      _pendingCancel = false;
      await _postCancel(turnId);
    }
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
  Future<bool> cancel() async {
    final turnId = _turnId;
    if (turnId == null) {
      // The turn is still opening (TurnConnecting): its id isn't known yet, so
      // latch the Stop intent for [start] to fire once the id is minted. A bare
      // return here would leave the turn generating; POSTing against a stale
      // previous id would cancel the wrong turn (adityas/ai/140). The stop is
      // queued, not failed, so report it in effect (adityas/ai/141).
      _pendingCancel = true;
      return true;
    }
    return _postCancel(turnId);
  }

  // Server-side stop (adityas/backend/54, contract in adityas/ai/94): POST the
  // cancel and report whether the stop is in effect. The actual stop is NOT the
  // 202 — it arrives over the turn's already-open SSE stream as the terminal
  // `error "generation was cancelled" → usage → done`, which the notifier is
  // holding the stream open to receive (and which settles the non-refunding
  // billing). The 202 only acks; a 404 means the turn is already gone (finished,
  // evicted, or not this user's) — nothing to stop either way, so both are
  // success. Every OTHER outcome — a non-202/404 status, a signed-out token, or a
  // transport throw — means the stop did NOT reach the server: the turn may still
  // be generating over the open stream, so report false rather than silently
  // claiming success. The caller keeps that live stream visible instead of
  // asserting a cancellation that never happened (adityas/ai/141).
  Future<bool> _postCancel(String turnId) async {
    try {
      final token = await _token();
      if (token == null) return false; // signed out — could not authorize
      final response = await _http.post(
        Uri.parse('$_baseUrl/v1/ai/turns/$turnId/cancel'),
        headers: {'authorization': 'Bearer $token'},
      );
      return response.statusCode == 202 || response.statusCode == 404;
    } catch (_) {
      // The stop never reached the server (network down, etc.).
      return false;
    }
  }

  /// Reset the cached conversation (call on a user change, or New Chat). The
  /// next [start] mints a fresh durable conversation for the new user, so a turn
  /// never lands in a conversation the current token does not own.
  @override
  void resetConversation() {
    _conversationId = null;
    _turnId = null;
    _adopted = false;
    _epoch++;
  }

  /// Adopt an existing server conversation (Resume, adityas/ai/86): subsequent
  /// turns append to [id] rather than a freshly-minted thread. Clears the turn
  /// cursor so a stale [resume] can't target the previous conversation's turn.
  @override
  void adoptConversation(String id) {
    _conversationId = id;
    _turnId = null;
    _adopted = true;
    _epoch++;
  }

  Future<String> _requireToken() async {
    final token = await _token();
    if (token == null) throw const TurnTransportException('Not signed in');
    return token;
  }

  /// The durable conversation, minted on first use and cached thereafter. When
  /// this call mints it, [title] (the client-composed `{chart · date}` label)
  /// rides in the create body; the backend accepts an optional title there. A
  /// cached conversation ignores it — a title is a creation-time snapshot.
  Future<String> _ensureConversation(
    String token,
    int epoch, {
    String? title,
  }) async {
    final cached = _conversationId;
    if (cached != null) return cached;
    // A rotation landed during a prior await (e.g. token fetch): don't POST a
    // ghost conversation the caller has already abandoned.
    if (_epoch != epoch) throw const _ConversationSuperseded();
    final response = await _http.post(
      Uri.parse('$_baseUrl/v1/ai/conversations'),
      headers: _jsonHeaders(token),
      body: title == null ? null : jsonEncode({'title': title}),
    );
    if (_epoch != epoch) throw const _ConversationSuperseded();
    if (response.statusCode != 201) {
      throw _httpError(response);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final id = data['conversation_id'] as String;
    _conversationId = id;
    _adopted = false; // self-minted and owned by this transport
    return id;
  }

  /// POST the turn, returning its `turn_id`. A `404` on a *self-minted*
  /// conversation means it went stale (a user switch, or a server-side
  /// eviction): re-mint a fresh conversation and retry once. A `404` on an
  /// *adopted* (resumed) conversation is fatal — reminting would silently start
  /// a new thread divorced from the transcript on screen (adityas/ai/86), so the
  /// turn fails instead.
  Future<String> _createTurn(
    String token,
    String conversationId,
    String message,
    ChartData? chart,
    String? title,
    int epoch,
  ) async {
    final response = await _postTurn(token, conversationId, message, chart);
    if (_epoch != epoch) throw const _ConversationSuperseded();
    if (response.statusCode == 404) {
      if (_adopted) {
        throw _httpError(response);
      }
      _conversationId = null;
      final fresh = await _ensureConversation(token, epoch, title: title);
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
      throw _httpError(response);
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

  /// Turn a non-2xx REST response into a status-carrying exception. The
  /// [statusCode] is what lets the notifier branch a deliberate gate (403/402/
  /// 428) apart from a generic failure — always route rejections through here.
  TurnTransportException _httpError(http.Response response) {
    String message;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      message = body['error'] as String? ?? 'Request failed';
    } catch (_) {
      message = 'Request failed (${response.statusCode})';
    }
    return TurnTransportException(message, statusCode: response.statusCode);
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
    case 'tool_start':
      // `{name, args}` — args is the tool's own JSON object (e.g. show_being's
      // `{slug}`), passed through for the notifier's show_being dispatch.
      return ToolStartEvent(
        _stringField(frame.data, 'name'),
        id,
        args: _objectField(frame.data, 'args'),
      );
    case 'tool_end':
      // `{name}` only — the args ride on tool_start.
      return ToolEndEvent(_stringField(frame.data, 'name'), id);
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

/// A nested JSON object field (e.g. a tool call's `args`), or null when absent
/// or not an object.
Map<String, Object?>? _objectField(String data, String key) {
  final value = _decodeObject(data)[key];
  return value is Map<String, Object?> ? value : null;
}

int _intField(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
