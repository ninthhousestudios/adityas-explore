import 'dart:typed_data';

import 'chart_data.dart';
import 'chtk.dart';
import 'toml_chart.dart';

class ChartReader {
  static const supportedExtensions = ['.toml', '.chtk'];

  static ChartData read(String fileName, Uint8List bytes) {
    final ext = fileName.toLowerCase();
    if (ext.endsWith('.chtk')) {
      return ChtkFormat.parse(bytes);
    }
    if (ext.endsWith('.toml')) {
      final content = String.fromCharCodes(bytes);
      return TomlChartFormat.parse(content, fileName: fileName);
    }
    throw UnsupportedError('Unknown chart format: $fileName');
  }
}
