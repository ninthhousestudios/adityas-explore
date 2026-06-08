import 'package:arrow_core/arrow_core.dart';
import 'package:arrow_options/arrow_options.dart';
import 'package:flutter/foundation.dart';

import '../chart_io/chart_data.dart';
import 'ephemeris_service.dart';
import 'jd.dart';
import 'swe.dart';
import 'swe_compute.dart';

const _sweConfig = SweConfig();
const _calcConfig = CalcConfig();

class _CalcArgs {
  final String? ephePath;
  final double jd;
  final Location location;
  const _CalcArgs(this.ephePath, this.jd, this.location);
}

Chart _computeChart(_CalcArgs args) {
  return runWithSwe(args.ephePath, (facade) {
    final snap = facade.calcAll(args.jd, args.location, _sweConfig);
    return Chart(snap, _calcConfig);
  });
}

class ChartCalculator {
  final EphemerisService _service;

  ChartCalculator(this._service);

  Future<Chart> calculate(ChartData data) async {
    final jd = data.julianDay ?? dateTimeToJdUt(data.utcDateTime);
    final location = Location(
      latitude: data.birthLocation.latitude,
      longitude: data.birthLocation.longitude,
    );

    final chart = await _service.chart(
      _computeChart,
      _CalcArgs(currentSweEphePath, jd, location),
      debugName: 'chart(${data.name})',
    );

    _logChart(chart, data.name);
    return chart;
  }

  static void _logChart(Chart chart, String name) {
    final buf = StringBuffer();
    buf.writeln('=== Chart: $name ===');
    buf.writeln('Circle: ${chart.config.circle.name}');
    buf.writeln('');

    buf.writeln('--- Planets ---');
    for (final planet in chart.planets) {
      final lon = planet.longitude;
      buf.writeln(
        '${planet.body.name.padRight(8)} '
        '${lon.eclipticLongitude.toStringAsFixed(4).padLeft(10)}° '
        'sign=${lon.sign.toString().padLeft(2)} '
        '${lon.inSignLongitude.toStringAsFixed(2).padLeft(6)}° '
        '${planet.isRetrograde ? "R" : " "} '
        'hora=${planet.horaBeing.name} '
        'trimsamsa=${planet.trimsamsaBeing.name}',
      );
    }

    buf.writeln('');
    buf.writeln('--- Houses ---');
    for (final cusp in chart.cusps) {
      final lon = cusp.longitude;
      buf.writeln(
        'H${cusp.house.toString().padLeft(2)} '
        '${lon.eclipticLongitude.toStringAsFixed(4).padLeft(10)}° '
        'sign=${lon.sign.toString().padLeft(2)} '
        '${lon.inSignLongitude.toStringAsFixed(2).padLeft(6)}°',
      );
    }

    buf.writeln('=== End Chart ===');
    debugPrint(buf.toString());
  }
}
