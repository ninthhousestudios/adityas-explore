import 'package:arrow_core/arrow_core.dart';
import 'package:arrow_options/arrow_options.dart';
import 'package:arrow_swe/arrow_swe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('swisseph_rs 0.3.1 + arrow compute a chart', () {
    final facade = SweFacade.create(ephePath: 'assets/ephe');
    try {
      // 2000-01-01 12:00 UT, London.
      final snap = facade.calcAll(
        2451545.0,
        const Location(latitude: 51.5074, longitude: -0.1278),
        const SweConfig(),
      );
      final chart = Chart(snap, const CalcConfig());
      expect(chart.planets, isNotEmpty);
      expect(chart.cusps, isNotEmpty);
      // Sun on 2000-01-01 12:00 UT sits ~280° tropical / ~256° sidereal.
      expect(chart.sun.longitude.eclipticLongitude, inInclusiveRange(250, 285));
    } finally {
      facade.dispose();
    }
  });
}
