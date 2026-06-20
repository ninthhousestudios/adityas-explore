import 'dart:typed_data';

import 'package:charts_dart/charts_dart.dart';

class ChartReader {
  static ChartData read(String fileName, Uint8List bytes) {
    final ext = fileName.toLowerCase();
    if (ext.endsWith('.chtk')) {
      return ChtkFormat.parseBytes(bytes);
    }
    if (ext.endsWith('.toml')) {
      final content = String.fromCharCodes(bytes);
      return TomlChartFormat.parseString(content, fileName: fileName);
    }
    if (ext.endsWith('.jhd')) {
      final content = String.fromCharCodes(bytes);
      return JhdFormat.parseString(content, fileName: fileName);
    }
    throw UnsupportedError('Unknown chart format: $fileName');
  }
}
