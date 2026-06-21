import 'package:http/http.dart' as http;

const _defaultBaseUrl = 'https://api.84beings.com';

class WaitlistService {
  static final String _baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  final http.Client _client;

  WaitlistService({http.Client? client}) : _client = client ?? http.Client();

  Future<String?> signup(String email) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/v1/waitlist'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'email': email.trim(),
          'source': 'explore-cta',
          'locale': 'en',
          'website': '',
        },
      );
      if (response.statusCode >= 200 && response.statusCode < 400) {
        return null;
      }
      return 'Something went wrong. Please try again.';
    } catch (_) {
      return 'Network error. Please check your connection.';
    }
  }
}
