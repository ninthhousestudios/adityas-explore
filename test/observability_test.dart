import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:explore/observability.dart';

/// The Sentry `beforeSend` belt behind the no-bodies policy (I19). Conversation
/// content, the assembled provider body, and the JWT are kept out of Sentry by
/// construction; this proves the structural backstop drops them even if request
/// context is attached.
void main() {
  test('scrubSentryEvent drops bodies, cookies, query, and auth headers', () {
    final event = SentryEvent(
      request: SentryRequest(
        url: 'https://api.84beings.com/v1/ai/preview/turns/x/stream',
        method: 'GET',
        queryString: 'access_token=leaked.jwt',
        data: '{"message":"my private reflection"}',
        headers: {
          'Authorization': 'Bearer leaked.jwt',
          'X-Goog-Api-Key': 'gemini-secret',
          'Content-Type': 'application/json',
          'x-request-id': 'abc-123',
        },
      ),
    );

    final scrubbed = scrubSentryEvent(event, Hint());
    final request = scrubbed!.request!;

    // No bodies, cookies, or query strings survive.
    expect(request.data, isNull);
    expect(request.queryString, isNull);
    expect(request.cookies, isNull);

    // Auth-bearing headers gone (case-insensitively); debugging headers kept.
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(request.headers.containsKey('X-Goog-Api-Key'), isFalse);
    expect(request.headers['Content-Type'], 'application/json');
    expect(request.headers['x-request-id'], 'abc-123');

    // Method + URL (no content) survive for debugging.
    expect(request.method, 'GET');
    expect(request.url, isNotNull);
  });

  test('scrubSentryEvent is a no-op without request context', () {
    final event = SentryEvent();
    expect(scrubSentryEvent(event, Hint())?.request, isNull);
  });

  test('applyContentFreeSentryPolicy sets the no-bodies policy', () {
    final options = SentryFlutterOptions();
    applyContentFreeSentryPolicy(options);

    expect(options.sendDefaultPii, isFalse);
    expect(options.maxRequestBodySize, MaxRequestBodySize.never);
    expect(options.beforeSend, isNotNull);
  });
}
