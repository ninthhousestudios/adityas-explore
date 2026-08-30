import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:charts_dart/charts_dart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../astro/being_uncertainty.dart';
import '../astro/chart_calculator.dart';

/// The chart currently open in the explorer and its calculation status.
///
/// [chartData] is the input (birth data), set synchronously the moment a chart
/// is opened/submitted and kept through calculation — the chat turn reads it
/// mid-flight (adityas/ai/65). [chart] and [uncertainty] are the async-derived
/// results, populated together when calculation finishes.
class ChartState {
  final ChartData? chartData;
  final arrow.Chart? chart;
  final BeingUncertainty? uncertainty;
  final bool calculating;

  const ChartState({
    this.chartData,
    this.chart,
    this.uncertainty,
    this.calculating = false,
  });

  bool get hasChart => chartData != null;
}

/// Owns the open chart's full lifecycle: input, calculation, results. Replaces
/// the setState fields that used to live on `_ExploreAppState` (adityas/explore/55).
///
/// The widget is a consumer, not the source of truth. Asset precaching stays in
/// the widget (it needs a BuildContext) via a ref.listen on this controller.
class ChartController extends Notifier<ChartState> {
  /// Last-write-wins guard. Bumped on every [submit]/[clear]; each run captures
  /// it and drops its results if a newer run has since started — so a slow
  /// open/submit can't land a stale chart over a newer one.
  int _token = 0;

  @override
  ChartState build() => const ChartState();

  /// Calculate and render [chartData]. Sets the input synchronously (so readers
  /// see it during the async work), then computes the chart and being
  /// uncertainty. Silently returns if superseded; rethrows real errors for the
  /// current run so the caller can surface them.
  Future<void> submit(
    ChartData chartData,
    arrow.TimeUncertainty timeUncertainty,
  ) async {
    final calculator = ref.read(chartCalculatorProvider);
    if (calculator == null) {
      // Invariant: the UI is gated on boot completing before any submit is
      // reachable, so a null calculator means a programming error, not a
      // recoverable state.
      throw StateError('ChartController.submit called before boot completed');
    }

    final token = ++_token;
    state = ChartState(chartData: chartData, calculating: true);
    try {
      final chart = await calculator.calculate(chartData);
      if (token != _token) return;
      final uncertainty = await computeBeingUncertainty(
        calculator: calculator,
        chartData: chartData,
        primaryChart: chart,
        uncertainty: timeUncertainty,
      );
      if (token != _token) return;
      state = ChartState(
        chartData: chartData,
        chart: chart,
        uncertainty: uncertainty,
      );
    } catch (_) {
      if (token != _token) return;
      state = ChartState(chartData: chartData);
      rethrow;
    }
  }

  /// Clear the open chart (New Chart). Bumps the token so an in-flight [submit]
  /// can't repopulate after the clear.
  void clear() {
    _token++;
    state = const ChartState();
  }
}

final chartControllerProvider = NotifierProvider<ChartController, ChartState>(
  ChartController.new,
);

/// The ChartCalculator, built asynchronously during boot and pushed here by the
/// root widget once ready. Null until boot completes; [ChartController.submit]
/// reads it at call time (always post-boot in the real UI path).
final chartCalculatorProvider =
    NotifierProvider<CalculatorHolder, ChartCalculator?>(CalculatorHolder.new);

class CalculatorHolder extends Notifier<ChartCalculator?> {
  @override
  ChartCalculator? build() => null;

  void set(ChartCalculator calculator) => state = calculator;
}

/// The birth data of the open chart, or null when none is open. A pure view of
/// [chartControllerProvider] — the chat turn reads this to attach the open chart
/// to a durable turn (adityas/ai/65).
final activeChartProvider = Provider<ChartData?>(
  (ref) => ref.watch(chartControllerProvider).chartData,
);
