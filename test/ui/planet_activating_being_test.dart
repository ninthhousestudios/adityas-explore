import 'package:arrow_core/arrow_core.dart';
import 'package:arrow_options/arrow_options.dart';
import 'package:arrow_swe/arrow_swe.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:explore/ui/aditya_data.dart';
import 'package:explore/ui/being_slug.dart';

/// [planetActivatingBeing] is the `show_being` seam's placement lookup: given a
/// being `(sign, type)`, does a *displayed* planet in the open chart activate it
/// on its Trimsamsa? Driven off a real computed chart so the arrow field wiring
/// (Trimsamsa being sign/type) is exercised, not mocked.
void main() {
  late Chart chart;

  setUpAll(() {
    final facade = SweFacade.create(ephePath: 'assets/ephe');
    try {
      // 2000-01-01 12:00 UT, London — the same fixed instant as swe_smoke_test.
      final snap = facade.calcAll(
        2451545.0,
        const Location(latitude: 51.5074, longitude: -0.1278),
        const SweConfig(),
      );
      chart = Chart(snap, const CalcConfig());
    } finally {
      facade.dispose();
    }
  });

  test('finds a displayed planet whose Trimsamsa is the being', () {
    final graha = chart.grahas.firstWhere(
      (p) => defaultGrahas.contains(p.body.name),
    );
    final being = graha.trimsamsaBeing;

    final placed = planetActivatingBeing(
      chart,
      being.signNumber,
      being.type.name,
    );

    expect(placed, isNotNull);
    // The returned placement carries this being (first match wins if two
    // planets share it, so assert the being, not a specific body).
    expect(placed!.trimsamsaBeingSign, being.signNumber);
    expect(placed.trimsamsaBeingType, being.type.name);
    // A real body from the chart, and its Soul Stance (Hora being) came along.
    expect(defaultGrahas, contains(placed.bodyName));
    expect(placed.horaBeing, isNotNull);
  });

  test('returns null for a being no displayed planet activates', () {
    final present = {
      for (final p in chart.grahas)
        if (defaultGrahas.contains(p.body.name))
          '${p.trimsamsaBeing.signNumber}-${p.trimsamsaBeing.type.name}',
    };
    const types = [
      'rishi',
      'yaksha',
      'rakshasa',
      'gandharva',
      'apsara',
      'naga',
      'aditya',
    ];
    int? freeSign;
    String? freeType;
    outer:
    for (var sign = 1; sign <= 12; sign++) {
      for (final type in types) {
        if (!present.contains('$sign-$type')) {
          freeSign = sign;
          freeType = type;
          break outer;
        }
      }
    }
    expect(freeSign, isNotNull, reason: 'a chart cannot fill all 84 beings');

    expect(planetActivatingBeing(chart, freeSign!, freeType!), isNull);
  });
}
