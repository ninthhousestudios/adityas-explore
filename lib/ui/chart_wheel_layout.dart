import 'dart:math';
import 'dart:ui';

// Ring radii as fractions of the widget half-size.
const outerRingOuter = 1.0;
const outerRingInner = 0.82;
const planetRingOuter = 0.82;
const planetRingInner = 0.56;
const houseRingOuter = 0.56;
const houseRingInner = 0.46;

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

/// Resolve planet placement within a sign to prevent overlaps
/// and keep glyphs inside sign boundaries.
List<double> resolvePlanetAngles({
  required List<double> inSignDegrees,
  required int sign,
  required int ascSign,
  required double glyphAngularSize,
}) {
  if (inSignDegrees.isEmpty) return [];

  final signStart = signStartAngle(sign, ascSign);
  final signSpan = pi / 6; // 30°
  final halfGlyph = glyphAngularSize / 2;

  // Counterclockwise: sign goes from signStart (high angle) to signStart - signSpan (low angle).
  final rangeMax = signStart - halfGlyph;
  final rangeMin = signStart - signSpan + halfGlyph;

  if (inSignDegrees.length == 1) {
    final raw = degreeToAngle(sign, inSignDegrees[0], ascSign);
    return [raw.clamp(rangeMin, rangeMax)];
  }

  // Index + sort by degree ascending (= angle descending).
  final indexed =
      List.generate(inSignDegrees.length, (i) => (i, inSignDegrees[i]));
  indexed.sort((a, b) => a.$2.compareTo(b.$2));

  // Try natural placement with boundary clamping.
  final natural = indexed.map((e) {
    final raw = degreeToAngle(sign, e.$2, ascSign);
    return raw.clamp(rangeMin, rangeMax);
  }).toList();

  // natural is in descending angle order (low degree = high angle).
  // Sort ascending for overlap check.
  final ascending = List.of(natural)..sort();
  if (_noOverlaps(ascending, glyphAngularSize)) {
    final result = List<double>.filled(inSignDegrees.length, 0);
    for (var i = 0; i < indexed.length; i++) {
      result[indexed[i].$1] = natural[i];
    }
    return result;
  }

  // Even spread across the sign, preserving degree order.
  // Lowest degree gets highest angle (rangeMax), highest degree gets rangeMin.
  final count = indexed.length;
  final step = count > 1 ? (rangeMax - rangeMin) / (count - 1) : 0.0;

  final result = List<double>.filled(inSignDegrees.length, 0);
  for (var i = 0; i < count; i++) {
    result[indexed[i].$1] = rangeMax - i * step;
  }
  return result;
}

bool _noOverlaps(List<double> sortedAngles, double minSeparation) {
  for (var i = 1; i < sortedAngles.length; i++) {
    if ((sortedAngles[i] - sortedAngles[i - 1]).abs() < minSeparation) {
      return false;
    }
  }
  return true;
}

/// Data for a placed planet on the wheel.
class PlacedPlanet {
  final String bodyName;
  final int sign;
  final double inSignDeg;
  final double angle;
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
