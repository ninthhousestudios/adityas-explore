import 'dart:math';
import 'dart:ui';

// Ring radii as fractions of the widget half-size.
const outerRingOuter = 1.0;
const outerRingInner = 0.82;
const planetRingOuter = 0.82;
const planetRingInner = 0.46;
const houseRingOuter = 0.46;
const houseRingInner = 0.36;

double signMidRadius(double halfSize) =>
    halfSize * (outerRingOuter + outerRingInner) / 2;
double planetMidRadius(double halfSize) =>
    halfSize * (planetRingOuter + planetRingInner) / 2;
double houseMidRadius(double halfSize) =>
    halfSize * (houseRingOuter + houseRingInner) / 2;

/// Screen angle (radians) where a sign's 0° boundary starts.
/// Signs increase counterclockwise. The 0° edge of a sign is its
/// clockwise boundary (higher screen angle).
double signStartAngle(int signNumber, int ascSign) {
  final offset = signNumber - ascSign;
  return pi + pi / 12 - offset * (pi / 6);
}

/// Screen angle for a specific ecliptic position within a sign.
/// Degrees increase counterclockwise (decreasing screen angle).
double degreeToAngle(int sign, double inSignDeg, int ascSign) {
  final signStart = signStartAngle(sign, ascSign);
  return signStart - inSignDeg / 30.0 * (pi / 6);
}

/// Midpoint angle for a given sign.
double signMidAngle(int signNumber, int ascSign) {
  return signStartAngle(signNumber, ascSign) - pi / 12;
}

Offset polarToCartesian(double angle, double radius, Offset center) {
  return Offset(
    center.dx + radius * cos(angle),
    center.dy + radius * sin(angle),
  );
}

/// Force-directed planet placement. Planets can spread both radially
/// and angularly within the planet band, staying inside their sign
/// sector with padding from boundary lines.
/// Ported from gandiva/renderers/western_wheel.py.
List<({double angle, double radiusFraction})> resolvePlanetPositions({
  required List<({int sign, double inSignDeg})> planets,
  required int ascSign,
  required double half,
  required double glyphSize,
}) {
  if (planets.isEmpty) return [];

  final cx = half;
  final cy = half;
  final rMid = half * (planetRingOuter + planetRingInner) / 2;
  final pad = glyphSize / 2 + 4;
  final rMin = half * planetRingInner + pad;
  final rMax = half * planetRingOuter - pad;
  final minDist = glyphSize * 0.95;
  final marginDeg = pad / (2 * pi * ((rMin + rMax) / 2)) * 360;

  // [x, y, sign, trueInSignDeg]
  final items = List.generate(planets.length, (i) {
    final p = planets[i];
    final a = degreeToAngle(p.sign, p.inSignDeg, ascSign);
    return [
      cx + rMid * cos(a) + (i % 3 - 1) * 0.5,
      cy + rMid * sin(a) + (i ~/ 3 % 3 - 1) * 0.5,
      p.sign.toDouble(),
      p.inSignDeg,
    ];
  });

  for (var iter = 0; iter < 200; iter++) {
    var moved = false;

    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        final dx = items[j][0] - items[i][0];
        final dy = items[j][1] - items[i][1];
        final dist = sqrt(dx * dx + dy * dy);
        if (dist < minDist) {
          double nx, ny;
          if (dist < 0.01) {
            final a = (i - j) * pi / max(items.length, 1);
            nx = cos(a);
            ny = sin(a);
          } else {
            nx = dx / dist;
            ny = dy / dist;
          }
          final push = (minDist - dist) / 2 + 0.3;
          items[i][0] -= nx * push;
          items[i][1] -= ny * push;
          items[j][0] += nx * push;
          items[j][1] += ny * push;
          moved = true;
        }
      }
    }

    for (final item in items) {
      final dxC = item[0] - cx;
      final dyC = item[1] - cy;
      final r = sqrt(dxC * dxC + dyC * dyC);
      if (r < 1) continue;

      final targetR = r + (rMid - r) * 0.02;
      final clampedR = targetR.clamp(rMin, rMax);

      final signNum = item[2].toInt();
      final trueDeg = item[3];
      final signStart = signStartAngle(signNum, ascSign);

      // Recover current in-sign degree from screen position.
      var angleDiff = signStart - atan2(dyC, dxC);
      while (angleDiff > pi) {
        angleDiff -= 2 * pi;
      }
      while (angleDiff < -pi) {
        angleDiff += 2 * pi;
      }
      final currentDeg = angleDiff * 180 / pi;

      final drift = currentDeg - trueDeg;
      final springDeg = currentDeg - drift * 0.008;
      final clampedDeg = springDeg.clamp(marginDeg, 30 - marginDeg);

      final clampedAngle = degreeToAngle(signNum, clampedDeg, ascSign);
      item[0] = cx + clampedR * cos(clampedAngle);
      item[1] = cy + clampedR * sin(clampedAngle);
    }

    if (!moved) break;
  }

  return items.map((item) {
    final dxC = item[0] - cx;
    final dyC = item[1] - cy;
    final r = sqrt(dxC * dxC + dyC * dyC);
    return (angle: atan2(dyC, dxC), radiusFraction: r / half);
  }).toList();
}

/// Data for a placed planet on the wheel.
class PlacedPlanet {
  final String bodyName;
  final int sign;
  final double inSignDeg;
  final double angle;
  final double radiusFraction;
  final String? horaBeing;
  final String? horaBeingType;
  final String? trimsamsaBeing;
  final String? trimsamsaBeingType;
  final bool isRetrograde;

  const PlacedPlanet({
    required this.bodyName,
    required this.sign,
    required this.inSignDeg,
    required this.angle,
    required this.radiusFraction,
    this.horaBeing,
    this.horaBeingType,
    this.trimsamsaBeing,
    this.trimsamsaBeingType,
    this.isRetrograde = false,
  });

  String get longitudeLabel {
    final deg = inSignDeg.floor();
    final arcMin = ((inSignDeg - deg) * 60).floor();
    return "$deg°$arcMin'";
  }
}

/// Data for a placed cusp on the wheel.
class PlacedCusp {
  final int house;
  final int sign;
  final double inSignDeg;
  final double angle;

  const PlacedCusp({
    required this.house,
    required this.sign,
    required this.inSignDeg,
    required this.angle,
  });

  String get longitudeLabel {
    final deg = inSignDeg.floor();
    final arcMin = ((inSignDeg - deg) * 60).floor();
    return "$deg°$arcMin'";
  }
}

const _romanNumerals = [
  '', 'I', 'II', 'III', 'IV', 'V', 'VI',
  'VII', 'VIII', 'IX', 'X', 'XI', 'XII',
];

String romanNumeral(int n) => _romanNumerals[n.clamp(0, 12)];
