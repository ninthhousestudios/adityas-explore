import 'package:charts_dart/charts_dart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The chart currently open in the explorer, or null when none is open.
///
/// Bridges the imperatively-managed open chart in the root widget's `State`
/// (`_ExploreAppState._chartData`) into the provider graph so the chat notifier
/// can attach it to a durable turn (adityas/ai/65). The root widget is the sole
/// writer, pushing via [set] on every open/submit/new-chart transition; the
/// chat turn is the reader.
final activeChartProvider = NotifierProvider<ActiveChartNotifier, ChartData?>(
  ActiveChartNotifier.new,
);

class ActiveChartNotifier extends Notifier<ChartData?> {
  @override
  ChartData? build() => null;

  void set(ChartData? chart) => state = chart;
}
