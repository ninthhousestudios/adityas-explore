import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class SavedChartSummary {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  SavedChartSummary({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  SavedChartSummary.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      createdAt = DateTime.parse(json['created_at'] as String),
      updatedAt = DateTime.parse(json['updated_at'] as String);
}

class ChartApiException implements Exception {
  final String message;
  final int statusCode;

  ChartApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}

/// The user's access entitlement, read from the backend DB — never from JWT
/// claims (a backend invariant; see the tier-1 notes § Content access levels).
///
/// A single `access_until` timestamp is the whole entitlement model: one-time
/// purchases (and a future opt-in subscription) extend it, and the chat gate
/// reads only this one field. `null` = no active access.
class Entitlement {
  final DateTime? accessUntil;

  const Entitlement({required this.accessUntil});
  const Entitlement.none() : accessUntil = null;

  Entitlement.fromJson(Map<String, dynamic> json)
    : accessUntil = json['access_until'] == null
          ? null
          : DateTime.parse(json['access_until'] as String);
}

/// Reads the current user's [Entitlement] from the backend.
///
/// An interface so the entitlement providers can be driven by a scripted fake
/// in headless tests (no network, no clock). The production implementation is
/// [ChartService.fetchEntitlement].
abstract interface class EntitlementClient {
  Future<Entitlement> fetchEntitlement();
}

/// Reads the coarse usage-headroom signal (adityas/ai/97) that drives the
/// near-ceiling notice: GET `/v1/ai/usage` → `{ used_pct: 0..100 }`.
///
/// An interface (mirrors [EntitlementClient]) so the usage provider is driven by
/// a scripted fake in headless tests. The percentage is a floored fraction of the
/// window budget — the wire deliberately carries NO dollar or token figure (the
/// no-meter invariant), and neither does this seam.
abstract interface class UsageClient {
  Future<int> fetchUsagePct();
}

typedef TokenProvider = Future<String?> Function({bool forceRefresh});

class ChartService implements EntitlementClient, UsageClient {
  final http.Client _client;
  final TokenProvider _tokenProvider;

  ChartService({required this._tokenProvider, http.Client? client})
    : _client = client ?? http.Client();

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  Future<http.Response> _request(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    var token = await _tokenProvider();
    if (token == null) {
      throw ChartApiException('Not authenticated', 401);
    }
    var response = await send(_headers(token));
    if (response.statusCode == 401) {
      token = await _tokenProvider(forceRefresh: true);
      if (token == null) {
        throw ChartApiException('Session expired', 401);
      }
      response = await send(_headers(token));
    }
    return response;
  }

  Future<List<SavedChartSummary>> list() async {
    final uri = Uri.parse('$apiBaseUrl/v1/charts');
    final response = await _request(
      (headers) => _client.get(uri, headers: headers),
    );

    if (response.statusCode != 200) {
      throw ChartApiException(_parseError(response), response.statusCode);
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => SavedChartSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> create(String name, String chartToml) async {
    final uri = Uri.parse('$apiBaseUrl/v1/charts');
    final response = await _request(
      (headers) => _client.post(
        uri,
        headers: headers,
        body: jsonEncode({'name': name, 'chart_toml': chartToml}),
      ),
    );

    if (response.statusCode != 201) {
      throw ChartApiException(_parseError(response), response.statusCode);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as String;
  }

  Future<String> fetchToml(String id) async {
    final uri = Uri.parse('$apiBaseUrl/v1/charts/$id');
    final response = await _request(
      (headers) => _client.get(uri, headers: headers),
    );

    if (response.statusCode != 200) {
      throw ChartApiException(_parseError(response), response.statusCode);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['chart_toml'] as String;
  }

  /// GET `/v1/entitlement` → the current user's [Entitlement].
  ///
  /// Reads `access_until` from the backend DB (never the JWT). Wire contract
  /// coordinated with adityas/backend; response shape is
  /// `{ "access_until": <RFC3339> | null }`.
  @override
  Future<Entitlement> fetchEntitlement() async {
    final uri = Uri.parse('$apiBaseUrl/v1/entitlement');
    final response = await _request(
      (headers) => _client.get(uri, headers: headers),
    );

    if (response.statusCode != 200) {
      throw ChartApiException(_parseError(response), response.statusCode);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Entitlement.fromJson(data);
  }

  /// GET `/v1/ai/usage` → the caller's floored usage percentage (adityas/ai/97).
  ///
  /// Response shape is `{ "used_pct": <int 0..100> }` — a ratio of the window
  /// budget, never the underlying micros/tokens. Drives the quiet near-ceiling
  /// notice; the hard at-ceiling signal stays the 402 on `POST .../turns`.
  @override
  Future<int> fetchUsagePct() async {
    final uri = Uri.parse('$apiBaseUrl/v1/ai/usage');
    final response = await _request(
      (headers) => _client.get(uri, headers: headers),
    );

    if (response.statusCode != 200) {
      throw ChartApiException(_parseError(response), response.statusCode);
    }

    final data = jsonDecode(response.body) as Map<String, Object?>;
    return data['used_pct'] as int;
  }

  String _parseError(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['error'] as String? ?? 'Request failed';
    } catch (_) {
      return 'Request failed (${response.statusCode})';
    }
  }
}
