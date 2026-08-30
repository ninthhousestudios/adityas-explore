import 'dart:convert';

import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:charts_dart/charts_dart.dart';
import 'package:flutter/foundation.dart';

import '../astro/being_uncertainty.dart';
import '../file_util.dart';
import 'chart_pdf.dart';

/// Save [chartData] as a `.toml` file via the platform file picker.
///
/// The chart-persistence logic that used to sit inline in `_ExploreAppState`
/// (adityas/explore/56); the widget keeps only the thin callback + feedback.
Future<void> saveChartToml(ChartData chartData) async {
  final toml = TomlChartFormat.encode(chartData);
  final bytes = Uint8List.fromList(utf8.encode(toml));
  await saveFileBytes('${chartFileStem(chartData.name)}.toml', bytes);
}

/// Build the chart PDF and save it via the platform file picker.
Future<void> saveChartPdf({
  required arrow.Chart chart,
  String? chartName,
  BeingUncertainty? uncertainty,
}) async {
  final bytes = await buildChartPdf(
    chart: chart,
    chartName: chartName,
    uncertainty: uncertainty,
  );
  await saveFileBytes('${chartFileStem(chartName)}-chart.pdf', bytes);
}
