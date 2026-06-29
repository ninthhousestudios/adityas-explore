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

class ChartService {
  static final String _baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  final http.Client _client;

  ChartService({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  Future<List<SavedChartSummary>> list(String token) async {
    final uri = Uri.parse('$_baseUrl/v1/charts');
    final response = await _client.get(uri, headers: _headers(token));

    if (response.statusCode != 200) {
      throw ChartApiException(_parseError(response), response.statusCode);
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => SavedChartSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> create(String token, String name, String chartToml) async {
    final uri = Uri.parse('$_baseUrl/v1/charts');
    final response = await _client.post(
      uri,
      headers: _headers(token),
      body: jsonEncode({'name': name, 'chart_toml': chartToml}),
    );

    if (response.statusCode != 201) {
      throw ChartApiException(_parseError(response), response.statusCode);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as String;
  }

  Future<String> fetchToml(String token, String id) async {
    final uri = Uri.parse('$_baseUrl/v1/charts/$id');
    final response = await _client.get(uri, headers: _headers(token));

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
