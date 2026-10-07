import 'package:web/web.dart' as html;

void navigateToUrl(String url) {
  html.window.location.href = url;
}

void openUrlNewTab(String url) {
  html.window.open(url, '_blank');
}

void reloadApp() {
  html.window.location.reload();
}

/// Read query parameter [name] and strip it from the address bar, so a value
/// that shouldn't linger (birth data in a hand-off link) stays out of
/// bookmarks, copied links, and reloads. History state is preserved — Flutter
/// keeps its own bookkeeping there.
String? takeQueryParam(String name) {
  final uri = Uri.parse(html.window.location.href);
  final value = uri.queryParameters[name];
  if (value == null) return null;
  final rest = Map.of(uri.queryParameters)..remove(name);
  final query = rest.isEmpty ? '' : '?${Uri(queryParameters: rest).query}';
  final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
  html.window.history.replaceState(
    html.window.history.state,
    '',
    '${uri.path}$query$fragment',
  );
  return value;
}
