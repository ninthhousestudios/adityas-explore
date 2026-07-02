import 'package:web/web.dart' as html;

void navigateToUrl(String url) {
  html.window.location.href = url;
}

void openUrlNewTab(String url) {
  html.window.open(url, '_blank');
}
