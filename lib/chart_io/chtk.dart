import 'dart:typed_data';

import 'chart_data.dart';

class ChtkFormat {
  static ChartData parse(Uint8List bytes) {
    final content = _decodeUtf16Le(bytes);
    final lines =
        content.split(RegExp(r'\r?\n')).map((l) => l.trim()).toList();

    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }

    final name = lines[0];
    final year = int.parse(lines[1]);
    final month = int.parse(lines[2]);
    final day = int.parse(lines[3]);
    final hour = int.parse(lines[4]);
    final minute = int.parse(lines[5]);
    final second = int.parse(lines[6]);
    final genderCode = int.tryParse(lines[7]) ?? 0;
    final country = lines[8];
    final city = lines[9];
    final longitude = _parseDms(lines[10]);
    final latitude = _parseDms(lines[11]);
    final utcOffset = _parseUtcOffset(lines[12]);

    var dstOffset = 0.0;
    var idx = 13;
    if (idx < lines.length) {
      final maybeFlag = int.tryParse(lines[idx]);
      if (maybeFlag != null) {
        dstOffset = 0.0;
        idx++;
      }
    }

    final noteLines = <String>[];
    while (idx < lines.length && lines[idx] != '~end of notes~') {
      if (lines[idx].isNotEmpty) noteLines.add(lines[idx]);
      idx++;
    }
    if (idx < lines.length) idx++;

    while (idx < lines.length && lines[idx] != '~end of muhurtas~') {
      idx++;
    }
    if (idx < lines.length) idx++;

    GeoLocation? currentLoc;
    double? currentUtcOffset;
    if (idx + 5 < lines.length) {
      idx++; // muhurta count
      idx++; // location preset name
      final curCountry = idx < lines.length ? lines[idx++] : '';
      final curCity = idx < lines.length ? lines[idx++] : '';
      final curLon = idx < lines.length ? _parseDms(lines[idx++]) : 0.0;
      final curLat = idx < lines.length ? _parseDms(lines[idx++]) : 0.0;
      final curOffset =
          idx < lines.length ? _parseUtcOffset(lines[idx++]) : 0.0;
      currentLoc = GeoLocation(
        city: curCity,
        country: curCountry,
        latitude: curLat,
        longitude: curLon,
      );
      currentUtcOffset = curOffset;
    }

    return ChartData(
      name: name,
      dateTime: DateTime.utc(year, month, day, hour, minute, second),
      birthLocation: GeoLocation(
        city: city,
        country: country,
        latitude: latitude,
        longitude: longitude,
      ),
      utcOffsetHours: utcOffset,
      dstOffsetHours: dstOffset,
      gender: genderCode == 2
          ? Gender.female
          : genderCode == 1
              ? Gender.male
              : null,
      notes: noteLines.isNotEmpty ? noteLines.join('\n') : null,
      currentLocation: currentLoc,
      currentUtcOffsetHours: currentUtcOffset,
    );
  }

  static double _parseDms(String s) {
    s = s.trim();
    final match = RegExp(r"(\d+)([NESW])(\d+)'(\d+(?:\.\d+)?)")
        .firstMatch(s.toUpperCase());
    if (match == null) return 0.0;
    final deg = int.parse(match.group(1)!);
    final dir = match.group(2)!;
    final min = int.parse(match.group(3)!);
    final sec = double.parse(match.group(4)!);
    var val = deg + min / 60.0 + sec / 3600.0;
    if (dir == 'W' || dir == 'S') val = -val;
    return val;
  }

  static double _parseUtcOffset(String s) {
    s = s.trim();
    if (s == 'UTC' || s == '0') return 0.0;
    final negative = s.startsWith('-');
    s = s.replaceFirst(RegExp(r'^[+-]'), '');
    final parts = s.split(':');
    var hours = double.tryParse(parts[0]) ?? 0.0;
    if (parts.length > 1) hours += (double.tryParse(parts[1]) ?? 0.0) / 60;
    if (parts.length > 2) hours += (double.tryParse(parts[2]) ?? 0.0) / 3600;
    // Kala stores offset negated
    return negative ? hours : -hours;
  }

  static String _decodeUtf16Le(Uint8List bytes) {
    var start = 0;
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      start = 2;
    }
    final buf = StringBuffer();
    for (var i = start; i + 1 < bytes.length; i += 2) {
      final code = bytes[i] | (bytes[i + 1] << 8);
      buf.writeCharCode(code);
    }
    return buf.toString();
  }
}
