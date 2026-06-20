import 'dart:convert';

import 'package:http/http.dart' as http;

const _defaultBaseUrl = 'https://api.84beings.com';

class PlaceAutocompleteResult {
  final String placeId;
  final String description;

  const PlaceAutocompleteResult({
    required this.placeId,
    required this.description,
  });

  factory PlaceAutocompleteResult.fromJson(Map<String, dynamic> json) {
    return PlaceAutocompleteResult(
      placeId: json['place_id'] as String,
      description: json['description'] as String,
    );
  }
}

class PlaceResolveResult {
  final double lat;
  final double lon;
  final String timezone;
  final double utcOffsetHours;
  final double dstOffsetHours;
  final String formattedAddress;

  const PlaceResolveResult({
    required this.lat,
    required this.lon,
    required this.timezone,
    required this.utcOffsetHours,
    required this.dstOffsetHours,
    required this.formattedAddress,
  });

  factory PlaceResolveResult.fromJson(Map<String, dynamic> json) {
    return PlaceResolveResult(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      timezone: json['timezone'] as String,
      utcOffsetHours: (json['utc_offset_hours'] as num).toDouble(),
      dstOffsetHours: (json['dst_offset_hours'] as num).toDouble(),
      formattedAddress: json['formatted_address'] as String,
    );
  }
}

class PlacesApiException implements Exception {
  final String message;
  final int statusCode;

  const PlacesApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}

class PlacesService {
  static final String _baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  final http.Client _client;

  PlacesService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<PlaceAutocompleteResult>> autocomplete(String query) async {
    final uri = Uri.parse(
      '$_baseUrl/v1/places/autocomplete',
    ).replace(queryParameters: {'q': query});

    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      final error = _parseError(response);
      throw PlacesApiException(error, response.statusCode);
    }

    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => PlaceAutocompleteResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PlaceResolveResult> resolve(String placeId, {int? timestamp}) async {
    final params = <String, String>{'place_id': placeId};
    if (timestamp != null) params['timestamp'] = timestamp.toString();

    final uri = Uri.parse(
      '$_baseUrl/v1/places/resolve',
    ).replace(queryParameters: params);

    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      final error = _parseError(response);
      throw PlacesApiException(error, response.statusCode);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return PlaceResolveResult.fromJson(data);
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
