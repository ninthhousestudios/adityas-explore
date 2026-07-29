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
      expect(chart.planets, hasLength(9));
      expect(chart.cusps, hasLength(12));
      // Sun on 2000-01-01 12:00 UT. The tolerance is deliberately tight: the
      // sidereal value for the same instant is ~256°, so a loose range would
      // pass through an ayanamsa or zodiac-mode flip — the exact regression
      // class this guard exists to catch on the next dependency bump.
      expect(chart.sun.longitude.eclipticLongitude, closeTo(280.369, 0.01));
    } finally {
      facade.dispose();
    }
  });
}
