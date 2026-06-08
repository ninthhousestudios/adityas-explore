import 'package:toml/toml.dart';

import 'chart_data.dart';

class TomlChartFormat {
  static ChartData parse(String content, {String? fileName}) {
    final doc = TomlDocument.parse(content);
    final map = doc.toMap();
    if (map['spec'] == 'open-astrology-chart') {
      return _readSpec(map, fileName: fileName);
    }
    return _readLegacy(map, fileName: fileName);
  }

  static ChartData _readSpec(Map<String, dynamic> map, {String? fileName}) {
    final moment = map['moment'] as Map<String, dynamic>? ?? {};
    final location = map['location'] as Map<String, dynamic>? ?? {};
    final civil = map['civil'] as Map<String, dynamic>? ?? {};

    final utcOffset = (civil['utc_offset'] as num?)?.toDouble() ?? 0.0;
    final dstOffset = (civil['dst_offset'] as num?)?.toDouble() ?? 0.0;
    final totalOffset = utcOffset + dstOffset;

    double? julianDay;
    DateTime localDt;

    final jdRaw = moment['jd'];
    if (jdRaw != null) {
      julianDay = (jdRaw as num).toDouble();
      final utcDt = _jdToDateTime(julianDay);
      localDt = utcDt.add(Duration(minutes: (totalOffset * 60).round()));
    } else {
      final date = civil['date'] as String?;
      final time = civil['time'] as String?;
      if (date == null || time == null) {
        throw FormatException(
            'Neither [moment].jd nor [civil].date+time present');
      }
      final dp = date.split('-');
      final tp = time.split(':');
      localDt = DateTime.utc(
        int.parse(dp[0]),
        int.parse(dp[1]),
        int.parse(dp[2]),
        int.parse(tp[0]),
        int.parse(tp[1]),
        tp.length > 2 ? int.parse(tp[2]) : 0,
      );
    }

    String name = (map['name'] ?? '').toString();
    if (name.isEmpty && fileName != null) {
      name = fileName.replaceAll(RegExp(r'\.toml$', caseSensitive: false), '');
    }

    Gender? gender;
    final rawGender = map['gender'];
    if (rawGender != null) {
      gender = switch (rawGender.toString().toLowerCase()) {
        'male' || 'm' => Gender.male,
        'female' || 'f' => Gender.female,
        'unknown' => Gender.unknown,
        _ => null,
      };
    }

    final lat = (location['lat'] as num?)?.toDouble() ?? 0.0;
    final lon = (location['lon'] as num?)?.toDouble() ?? 0.0;
    final alt = (location['alt'] as num?)?.toDouble();
    final placename = (location['placename'] ?? '').toString();
    final country = (location['country'] ?? '').toString();

    final rodden = map['rodden'] as String?;
    final rawTags = map['tags'];
    final tags =
        rawTags is List ? rawTags.map((e) => e.toString()).toList() : null;
    final notes = map['notes'] as String?;

    final extra = <String, dynamic>{};
    if (alt != null) extra['altitude'] = alt;
    final timezone = civil['timezone'] as String?;
    if (timezone != null) extra['timezone'] = timezone;

    return ChartData(
      name: name,
      dateTime: localDt,
      birthLocation: GeoLocation(
        city: placename,
        country: country,
        latitude: lat,
        longitude: lon,
      ),
      utcOffsetHours: utcOffset,
      dstOffsetHours: dstOffset,
      gender: gender,
      roddenRating: rodden,
      tags: tags,
      notes: notes,
      julianDay: julianDay,
      extra: extra,
    );
  }

  static ChartData _readLegacy(Map<String, dynamic> map, {String? fileName}) {
    final timeJD = map['timeJD'] as Map<String, dynamic>? ?? {};
    final location = map['location'] as Map<String, dynamic>? ?? {};

    final jd = (timeJD['jd'] as num?)?.toDouble() ?? 0.0;
    final utcOffset = (timeJD['utcoffset'] as num?)?.toDouble() ?? 0.0;

    final utcDt = _jdToDateTime(jd);
    final localDt = utcDt.add(Duration(minutes: (utcOffset * 60).round()));

    String name;
    final rawName = map['name'];
    if (rawName is List) {
      name = rawName.map((e) => e.toString()).join(' ').trim();
    } else {
      name = (rawName ?? fileName ?? 'Unknown').toString();
    }

    Gender? gender;
    final rawGender = map['gender'];
    if (rawGender != null) {
      gender = switch (rawGender.toString().toLowerCase()) {
        'male' || 'm' => Gender.male,
        'female' || 'f' => Gender.female,
        _ => null,
      };
    }

    var country = (map['country'] ?? '').toString();
    var placename = (location['placename'] ?? '').toString();

    if (country.isEmpty && placename.contains(',')) {
      final parts = placename.split(',').map((s) => s.trim()).toList();
      if (parts.length >= 3) {
        country = parts.last;
        placename = parts.sublist(0, parts.length - 1).join(', ');
      }
    }

    final lat = (location['lat'] as num?)?.toDouble() ?? 0.0;
    final lon = (location['long'] as num?)?.toDouble() ?? 0.0;
    final alt = (location['alt'] as num?)?.toDouble();

    final extra = <String, dynamic>{};
    if (alt != null) extra['altitude'] = alt;
    final icao = location['icao'];
    if (icao != null) extra['icao'] = icao.toString();

    return ChartData(
      name: name,
      dateTime: localDt,
      birthLocation: GeoLocation(
        city: placename,
        country: country,
        latitude: lat,
        longitude: lon,
      ),
      utcOffsetHours: utcOffset,
      gender: gender,
      julianDay: jd,
      extra: extra,
    );
  }

  static DateTime _jdToDateTime(double jd) {
    final z = (jd + 0.5).floor();
    final f = jd + 0.5 - z;
    final alpha = ((z - 1867216.25) / 36524.25).floor();
    final a = z + 1 + alpha - (alpha ~/ 4);
    final b = a + 1524;
    final c = ((b - 122.1) / 365.25).floor();
    final d = (365.25 * c).floor();
    final e = ((b - d) / 30.6001).floor();

    final day = b - d - (30.6001 * e).floor();
    final month = e < 14 ? e - 1 : e - 13;
    final year = month > 2 ? c - 4716 : c - 4715;

    final totalSeconds = (f * 86400.0).round();
    final hour = totalSeconds ~/ 3600;
    final minute = (totalSeconds % 3600) ~/ 60;
    final second = totalSeconds % 60;

    return DateTime.utc(year, month, day, hour, minute, second);
  }
}
