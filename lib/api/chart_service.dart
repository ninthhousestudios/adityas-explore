import 'dart:convert';

import 'package:http/http.dart' as http;

const _defaultBaseUrl = 'https://api.84beings.com';

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

typedef TokenProvider = Future<String?> Function({bool forceRefresh});

class ChartService {
  static final String _baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  final http.Client _client;
  final TokenProvider _tokenProvider;

  ChartService({required TokenProvider tokenProvider, http.Client? client})
    : _tokenProvider = tokenProvider,
      _client = client ?? http.Client();

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
    final uri = Uri.parse('$_baseUrl/v1/charts');
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
    final uri = Uri.parse('$_baseUrl/v1/charts');
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
    final uri = Uri.parse('$_baseUrl/v1/charts/$id');
    final response = await _request(
      (headers) => _client.get(uri, headers: headers),
    );

    if (response.statusCode != 200) {
      throw ChartApiException(_parseError(response), response.statusCode);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['chart_toml'] as String;
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
