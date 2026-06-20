import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:charts_dart/charts_dart.dart';

import '../ui/birth_form.dart' show TimePrecision, BirthPeriod;
import 'chart_calculator.dart';

class BeingOption {
  final String name;
  final String type;
  final int sign;

  const BeingOption({
    required this.name,
    required this.type,
    required this.sign,
  });

  @override
  bool operator ==(Object other) =>
      other is BeingOption && name == other.name && type == other.type;

  @override
  int get hashCode => Object.hash(name, type);
}

class BeingUncertainty {
  final Map<String, List<BeingOption>> trimsamsaOptions;
  final Map<String, List<BeingOption>> horaOptions;

  const BeingUncertainty({
    this.trimsamsaOptions = const {},
    this.horaOptions = const {},
  });

  bool isTrimsamsaUncertain(String planet) =>
      (trimsamsaOptions[planet]?.length ?? 0) > 1;

  bool isHoraUncertain(String planet) => (horaOptions[planet]?.length ?? 0) > 1;

  bool isUncertain(String planet) =>
      isTrimsamsaUncertain(planet) || isHoraUncertain(planet);

  List<BeingOption> trimsamsaFor(String planet) =>
      trimsamsaOptions[planet] ?? const [];

  List<BeingOption> horaFor(String planet) => horaOptions[planet] ?? const [];

  static const none = BeingUncertainty();
}

const _defaultGrahas = [
  'sun',
  'moon',
  'mars',
  'mercury',
  'jupiter',
  'venus',
  'saturn',
  'rahu',
  'ketu',
];

List<DateTime> _sampleTimes(
  ChartData chartData,
  TimePrecision precision,
  BirthPeriod? period,
) {
  final dt = chartData.dateTime;
  final year = dt.year;
  final month = dt.month;
  final day = dt.day;

  switch (precision) {
    case TimePrecision.exact:
      return [];
    case TimePrecision.general:
      final (startHour, endHour, endDayOffset) = switch (period!) {
        BirthPeriod.morning => (6, 12, 0),
        BirthPeriod.afternoon => (12, 18, 0),
        BirthPeriod.evening => (18, 0, 1),
        BirthPeriod.night => (0, 6, 0),
      };
      return [
        DateTime.utc(year, month, day, startHour),
        DateTime.utc(year, month, day + endDayOffset, endHour),
      ];
    case TimePrecision.unknown:
      return [
        for (var h = 0; h <= 24; h += 4)
          DateTime.utc(year, month, day + (h == 24 ? 1 : 0), h == 24 ? 0 : h),
      ];
  }
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
  required TimePrecision precision,
  BirthPeriod? period,
}) async {
  if (precision == TimePrecision.exact) return BeingUncertainty.none;

  final sampleTimes = _sampleTimes(chartData, precision, period);
  if (sampleTimes.isEmpty) return BeingUncertainty.none;

  final sampleCharts = <arrow.Chart>[];
  for (final time in sampleTimes) {
    final chart = await calculator.calculate(_withTime(chartData, time));
    sampleCharts.add(chart);
  }

  final allCharts = [primaryChart, ...sampleCharts];
  final trimsamsaResult = <String, List<BeingOption>>{};
  final horaResult = <String, List<BeingOption>>{};

  for (final name in _defaultGrahas) {
    final trimsamsaSet = <BeingOption>{};
    final horaSet = <BeingOption>{};

    for (final chart in allCharts) {
      final planet = chart.grahas.cast<arrow.Planet?>().firstWhere(
        (p) => p!.body.name == name,
        orElse: () => null,
      );
      if (planet != null) {
        trimsamsaSet.add(
          BeingOption(
            name: planet.trimsamsaBeing.name,
            type: planet.trimsamsaBeing.type.name,
            sign: planet.trimsamsaBeing.signNumber,
          ),
        );
        horaSet.add(
          BeingOption(
            name: planet.horaBeing.name,
            type: planet.horaBeing.type.name,
            sign: planet.horaBeing.signNumber,
          ),
        );
      }
    }

    if (trimsamsaSet.length > 1) {
      trimsamsaResult[name] = trimsamsaSet.toList();
    }
    if (horaSet.length > 1) {
      horaResult[name] = horaSet.toList();
    }
  }

  return BeingUncertainty(
    trimsamsaOptions: trimsamsaResult,
    horaOptions: horaResult,
  );
}
