import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'chart_service.dart' show TokenProvider;

/// One row of the conversations picker (adityas/ai/86/87).
///
/// Content-free by design: a label, the last-active time, and a turn count — no
/// dollars or tokens (the no-meter invariant). [title] is null when the
/// conversation was minted by an old client that sent no title body.
class ConversationSummary {
  final String id;
  final String? title;

  /// Last-turn time — what the picker sorts on and shows as "active …".
  final DateTime updatedAt;
  final int turnCount;

  ConversationSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.turnCount,
  });

  ConversationSummary.fromJson(Map<String, Object?> json)
    : id = json['id'] as String,
      title = json['title'] as String?,
      updatedAt = DateTime.parse(json['updated_at'] as String),
      // Optional per the picker spec (adityas/ai/87); the current backend always
      // sends it, but a missing/null count degrades to 0 rather than blanking
      // the whole page.
      turnCount = (json['turn_count'] as num?)?.toInt() ?? 0;
}

/// One message of a loaded transcript. [fromUser] distinguishes the two roles
/// without leaking the backend's `role` enum into the client model.
class ConversationHistoryMessage {
  final bool fromUser;
  final String content;

  /// Server-assigned creation time — the axis the compaction seam is placed on
  /// (adityas/ai/121): the divider sits above the first message later than the
  /// conversation's `compacted_through` watermark.
  final DateTime createdAt;

  const ConversationHistoryMessage({
    required this.fromUser,
    required this.content,
    required this.createdAt,
  });

  ConversationHistoryMessage.fromJson(Map<String, Object?> json)
    : fromUser = json['role'] == 'user',
      content = json['content'] as String? ?? '',
      createdAt = DateTime.parse(json['created_at'] as String);
}

/// A conversation's decrypted transcript plus its label (adityas/ai/87). The
/// server unwrapped the per-conversation data key and returned plaintext over
/// TLS — this is a plain fetch+render, not client-side crypto.
class ConversationHistory {
  final String id;
  final String? title;
  final DateTime updatedAt;
  final List<ConversationHistoryMessage> messages;

  /// The compaction seam watermark (adityas/ai/119 contract): the `created_at`
  /// up to and including which older turns were condensed into a summary the
  /// model now sees in their place. `null` when nothing has been compacted (the
  /// field is omitted from the payload in that case). The full transcript is
  /// still returned — this only marks where the honesty divider goes.
  final DateTime? compactedThrough;

  ConversationHistory({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
    this.compactedThrough,
  });

  ConversationHistory.fromJson(Map<String, Object?> json)
    : id = json['id'] as String,
      title = json['title'] as String?,
      updatedAt = DateTime.parse(json['updated_at'] as String),
      compactedThrough = switch (json['compacted_through']) {
        final String s => DateTime.parse(s),
        _ => null,
      },
      messages = ((json['messages'] as List<Object?>?) ?? const [])
          .map(
            (e) =>
                ConversationHistoryMessage.fromJson(e as Map<String, Object?>),
          )
          .toList();
}

/// A page of the picker list: the rows plus the opaque keyset cursor to fetch
/// the next page (null when this was the last page).
class ConversationPage {
  final List<ConversationSummary> conversations;
  final String? nextCursor;

  const ConversationPage({required this.conversations, this.nextCursor});
}

class ConversationApiException implements Exception {
  final String message;
  final int statusCode;

  ConversationApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}

/// The durable-chat read/manage client the picker drives (adityas/ai/87
/// endpoints). Separate from [ChartService] — the two share only the
/// token-refresh idiom, and folding chat CRUD into the chart client would
/// couple two unrelated resource surfaces behind one type.
class ConversationService {
  final http.Client _client;
  final TokenProvider _tokenProvider;

  ConversationService({required this._tokenProvider, http.Client? client})
    : _client = client ?? http.Client();

  Map<String, String> _headers(String token, {String? accept}) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
    'Accept': ?accept,
  };

  /// Sends an authed request, force-refreshing the token once on a 401 (mirrors
  /// [ChartService]'s retry; kept local because the two throw different
  /// exception types).
  Future<http.Response> _request(
    Future<http.Response> Function(String token) send,
  ) async {
    var token = await _tokenProvider();
    if (token == null) throw ConversationApiException('Not authenticated', 401);
    var response = await send(token);
    if (response.statusCode == 401) {
      token = await _tokenProvider(forceRefresh: true);
      if (token == null) throw ConversationApiException('Session expired', 401);
      response = await send(token);
    }
    return response;
  }

  /// GET `/v1/ai/conversations` — one recent-first page.
  Future<ConversationPage> list({String? cursor, int limit = 50}) async {
    final uri = Uri.parse(
      '$apiBaseUrl/v1/ai/conversations',
    ).replace(queryParameters: {'limit': '$limit', 'cursor': ?cursor});
    final response = await _request(
      (token) => _client.get(uri, headers: _headers(token)),
    );
    if (response.statusCode != 200) {
      throw ConversationApiException(
        _parseError(response),
        response.statusCode,
      );
    }
    try {
      final data = jsonDecode(response.body) as Map<String, Object?>;
      final rows = ((data['conversations'] as List<Object?>?) ?? const [])
          .map((e) => ConversationSummary.fromJson(e as Map<String, Object?>))
          .toList();
      return ConversationPage(
        conversations: rows,
        nextCursor: data['next_cursor'] as String?,
      );
    } on Object {
      // A shape mismatch (wrong endpoint, renamed field) surfaces as a typed,
      // expected error the picker already handles — never a raw CastError.
      throw ConversationApiException(
        'Malformed conversations response',
        response.statusCode,
      );
    }
  }

  /// GET `/v1/ai/conversations/{id}` — the decrypted transcript for Resume.
  Future<ConversationHistory> fetch(String id) async {
    final uri = Uri.parse('$apiBaseUrl/v1/ai/conversations/$id');
    final response = await _request(
      (token) => _client.get(uri, headers: _headers(token)),
    );
    if (response.statusCode != 200) {
      throw ConversationApiException(
        _parseError(response),
        response.statusCode,
      );
    }
    try {
      return ConversationHistory.fromJson(
        jsonDecode(response.body) as Map<String, Object?>,
      );
    } on Object {
      throw ConversationApiException(
        'Malformed conversation transcript',
        response.statusCode,
      );
    }
  }

  /// PATCH `/v1/ai/conversations/{id}` — set the user-editable title.
  Future<void> rename(String id, String title) async {
    final uri = Uri.parse('$apiBaseUrl/v1/ai/conversations/$id');
    final response = await _request(
      (token) => _client.patch(
        uri,
        headers: _headers(token),
        body: jsonEncode({'title': title}),
      ),
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw ConversationApiException(
        _parseError(response),
        response.statusCode,
      );
    }
  }

  /// DELETE `/v1/ai/conversations/{id}` — irreversible crypto-shred.
  Future<void> delete(String id) async {
    final uri = Uri.parse('$apiBaseUrl/v1/ai/conversations/$id');
    final response = await _request(
      (token) => _client.delete(uri, headers: _headers(token)),
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw ConversationApiException(
        _parseError(response),
        response.statusCode,
      );
    }
  }

  /// GET `/v1/ai/conversations/{id}/export.pdf` — the branded keepsake PDF
  /// bytes (adityas/ai/88). Fetched with the auth header rather than opened in a
  /// new tab (a bare browser GET would carry no bearer token → 401), then handed
  /// to the platform save path.
  Future<Uint8List> exportPdf(String id) async {
    final uri = Uri.parse('$apiBaseUrl/v1/ai/conversations/$id/export.pdf');
    final response = await _request(
      (token) =>
          _client.get(uri, headers: _headers(token, accept: 'application/pdf')),
    );
    if (response.statusCode != 200) {
      throw ConversationApiException(
        _parseError(response),
        response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  String _parseError(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, Object?>;
      return body['error'] as String? ?? 'Request failed';
    } catch (_) {
      return 'Request failed (${response.statusCode})';
    }
  }
}
