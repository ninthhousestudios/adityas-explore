import 'dart:typed_data';

/// A chart file chosen by the user via [pickChartFile]: its display [name]
/// (which `ChartReader.read` dispatches on by extension) and raw [bytes].
class PickedChart {
  final String name;
  final Uint8List bytes;

  const PickedChart(this.name, this.bytes);
}

/// The chart file extensions the picker offers, without the leading dot.
const List<String> chartExtensions = ['toml', 'chtk', 'jhd'];
