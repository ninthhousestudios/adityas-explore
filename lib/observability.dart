import 'package:sentry_flutter/sentry_flutter.dart';

/// Content-free observability for explore (I19).
///
/// Content-free is primarily *by construction*: the chat transport sends the
/// JWT in an `Authorization` header, never a query string (see
/// `lib/ai/chat_stream.dart` / `chat_stream_web.dart`), and no conversation
/// content is ever logged. [scrubSentryEvent] is the structural backstop — the
/// no-bodies policy enforced in one place rather than trusted to every call
/// site, mirroring the backend's `server::observability`.

/// Header names that must never leave the device in a Sentry payload. Matched
/// case-insensitively: bearer JWTs, session cookies, and provider API keys each
/// authenticate the caller or us — none of them is debugging signal.
const _sensitiveHeaders = <String>{
  'authorization',
  'proxy-authorization',
  'cookie',
  'set-cookie',
  'x-goog-api-key',
  'x-api-key',
};

/// Apply the content-free policy to Sentry options (I19, bug #4): never attach
/// PII or request/response bodies, and run [scrubSentryEvent] as a `beforeSend`
/// belt. Call from `SentryFlutter.init` alongside the app-specific
/// dsn/environment. The body-size default is already `never`; setting it here
/// makes the policy explicit and independent of a future default change.
void applyContentFreeSentryPolicy(SentryFlutterOptions options) {
  options
    ..sendDefaultPii = false
    ..maxRequestBodySize = MaxRequestBodySize.never
    ..beforeSend = scrubSentryEvent;
}

/// Strip request/response bodies, cookies, query strings, and auth-bearing
/// headers from an outgoing Sentry event — the belt behind the no-bodies policy
/// (I19). Method and URL are kept: debugging signal that carries no content.
SentryEvent? scrubSentryEvent(SentryEvent event, Hint hint) {
  final request = event.request;
  if (request != null) {
    event.request = SentryRequest(
      url: request.url,
      method: request.method,
      // Bodies, query strings, and cookies are deliberately dropped.
      headers: _withoutSensitiveHeaders(request.headers),
    );
  }
  return event;
}

Map<String, String> _withoutSensitiveHeaders(Map<String, String> headers) => {
  for (final entry in headers.entries)
    if (!_sensitiveHeaders.contains(entry.key.toLowerCase()))
      entry.key: entry.value,
};
