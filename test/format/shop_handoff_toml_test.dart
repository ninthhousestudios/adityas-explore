import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:charts_dart/charts_dart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:explore/astro/being_uncertainty.dart';

// Contract for the `?birth=` hand-off: these are verbatim outputs of the site's
// `ChartFile.serializeToml` (site/public/js/chart-file.js) as the shop birth
// form's `buildChartToml` calls it. If that serializer changes shape,
// regenerate and re-run.

const _exact = '''
spec = "open-astrology-chart"
spec_version = 1

name = "Zoë \\"Z\\" Test"
rodden = "A"

[moment]
jd = 2447965.3645833335

[location]
lat = 40.7128
lon = -74.006
placename = "New York, NY, USA"

[civil]
date = "1990-03-14"
time = "16:45:00"
utc_offset = -5
dst_offset = 1
''';

// General time of day ("night"): period midpoint + Rodden C.
const _general = '''
spec = "open-astrology-chart"
spec_version = 1

name = "Ana"
rodden = "C"

[moment]
jd = 2452080.5416666665

[location]
lat = 51.5
lon = -0.12
placename = "London"

[civil]
date = "2001-06-20"
time = "03:00:00"
utc_offset = 1
dst_offset = 1
''';

// Time unknown: noon + Rodden X, no name.
const _unknown = '''
spec = "open-astrology-chart"
spec_version = 1

rodden = "X"

[moment]
jd = 2446371.7708333335

[location]
lat = 19.076
lon = 72.8777
placename = "Mumbai"

[civil]
date = "1985-11-02"
time = "12:00:00"
utc_offset = 5.5
''';

arrow.TimeUncertainty _uncertainty(ChartData c) =>
    roddenToUncertainty(c.roddenRating, c.dateTime.hour);

void main() {
  test('exact time → ExactTime', () {
    final chart = TomlChartFormat.parseString(_exact);
    expect(chart.name, 'Zoë "Z" Test');
    expect(chart.roddenRating, 'A');
    expect(chart.dateTime, DateTime.utc(1990, 3, 14, 16, 45));
    expect(chart.birthLocation.latitude, closeTo(40.7128, 1e-6));
    expect(chart.birthLocation.longitude, closeTo(-74.006, 1e-6));
    expect(_uncertainty(chart), isA<arrow.ExactTime>());
  });

  test('general time → PeriodTime for that period', () {
    final chart = TomlChartFormat.parseString(_general);
    expect(chart.roddenRating, 'C');
    final u = _uncertainty(chart);
    expect(u, isA<arrow.PeriodTime>());
    u as arrow.PeriodTime;
    expect((u.startHour, u.endHour), (0, 6));
  });

  test('unknown time → UnknownTime', () {
    final chart = TomlChartFormat.parseString(_unknown);
    expect(chart.roddenRating, 'X');
    expect(chart.dateTime, DateTime.utc(1985, 11, 2, 12));
    expect(_uncertainty(chart), isA<arrow.UnknownTime>());
  });
}
