import 'package:arrow_calc/arrow_calc.dart' as calc;
import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:arrow_options/arrow_options.dart' show Being;
import 'package:charts_dart/charts_dart.dart';

import 'chart_calculator.dart';

export 'package:arrow_core/arrow_core.dart'
    show TimeUncertainty, ExactTime, PeriodTime, UnknownTime;
export 'package:arrow_options/arrow_options.dart' show Being;

class BeingUncertainty {
  final Map<String, List<Being>> trimsamsaOptions;
  final Map<String, List<Being>> horaOptions;

  const BeingUncertainty({
    this.trimsamsaOptions = const {},
    this.horaOptions = const {},
  });

  bool isTrimsamsaUncertain(String planet) =>
      (trimsamsaOptions[planet]?.length ?? 0) > 1;

  bool isHoraUncertain(String planet) => (horaOptions[planet]?.length ?? 0) > 1;

  bool isUncertain(String planet) =>
      isTrimsamsaUncertain(planet) || isHoraUncertain(planet);

  List<Being> trimsamsaFor(String planet) =>
      trimsamsaOptions[planet] ?? const [];

  List<Being> horaFor(String planet) => horaOptions[planet] ?? const [];

  static const none = BeingUncertainty();
}

ChartData _withTime(ChartData original, DateTime dateTime) {
  return ChartData(
    name: original.name,
    dateTime: dateTime,
    birthLocation: original.birthLocation,
    utcOffsetHours: original.utcOffsetHours,
    dstOffsetHours: original.dstOffsetHours,
    roddenRating: original.roddenRating,
  );
}

Future<BeingUncertainty> computeBeingUncertainty({
  required ChartCalculator calculator,
  required ChartData chartData,
  required arrow.Chart primaryChart,
  required arrow.TimeUncertainty uncertainty,
}) async {
  if (uncertainty is arrow.ExactTime) return BeingUncertainty.none;

  final times = arrow.sampleTimes(chartData.dateTime, uncertainty);
  if (times.isEmpty) return BeingUncertainty.none;

  final charts = <arrow.Chart>[primaryChart];
  for (final time in times) {
    charts.add(await calculator.calculate(_withTime(chartData, time)));
  }

  final result = calc.computeBeingUncertainty(charts);

  return BeingUncertainty(
    trimsamsaOptions: {
      for (final e in result.trimsamsaOptions.entries) e.key.name: e.value,
    },
    horaOptions: {
      for (final e in result.horaOptions.entries) e.key.name: e.value,
    },
  );
}
