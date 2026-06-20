import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:charts_dart/charts_dart.dart';

import '../ui/birth_form.dart' show TimePrecision, BirthPeriod;
import 'chart_calculator.dart';

class PlanetBeingOption {
  final String horaBeing;
  final String horaBeingType;
  final int horaBeingSign;
  final String trimsamsaBeing;
  final String trimsamsaBeingType;
  final int trimsamsaBeingSign;

  const PlanetBeingOption({
    required this.horaBeing,
    required this.horaBeingType,
    required this.horaBeingSign,
    required this.trimsamsaBeing,
    required this.trimsamsaBeingType,
    required this.trimsamsaBeingSign,
  });

  String get _key => '$horaBeing|$trimsamsaBeing';

  @override
  bool operator ==(Object other) =>
      other is PlanetBeingOption && _key == other._key;

  @override
  int get hashCode => _key.hashCode;
}

class BeingUncertainty {
  final Map<String, List<PlanetBeingOption>> planetOptions;

  const BeingUncertainty(this.planetOptions);

  bool isUncertain(String planetName) =>
      (planetOptions[planetName]?.length ?? 0) > 1;

  List<PlanetBeingOption> optionsFor(String planetName) =>
      planetOptions[planetName] ?? const [];

  static const none = BeingUncertainty({});
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

PlanetBeingOption _extractOption(arrow.Planet planet) {
  return PlanetBeingOption(
    horaBeing: planet.horaBeing.name,
    horaBeingType: planet.horaBeing.type.name,
    horaBeingSign: planet.horaBeing.signNumber,
    trimsamsaBeing: planet.trimsamsaBeing.name,
    trimsamsaBeingType: planet.trimsamsaBeing.type.name,
    trimsamsaBeingSign: planet.trimsamsaBeing.signNumber,
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
  final result = <String, List<PlanetBeingOption>>{};

  for (final name in _defaultGrahas) {
    final options = <PlanetBeingOption>{};
    for (final chart in allCharts) {
      final planet = chart.grahas.cast<arrow.Planet?>().firstWhere(
        (p) => p!.body.name == name,
        orElse: () => null,
      );
      if (planet != null) {
        options.add(_extractOption(planet));
      }
    }
    if (options.length > 1) {
      result[name] = options.toList();
    }
  }

  return BeingUncertainty(result);
}
