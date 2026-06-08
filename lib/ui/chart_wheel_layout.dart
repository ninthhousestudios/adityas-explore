import 'dart:math';
import 'dart:ui';

// Ring radii as fractions of the widget half-size.
const outerRingOuter = 1.0;
const outerRingInner = 0.82;
const planetRingOuter = 0.82;
const planetRingInner = 0.56;
const houseRingOuter = 0.56;
const houseRingInner = 0.36;

double signMidRadius(double halfSize) =>
    halfSize * (outerRingOuter + outerRingInner) / 2;
double planetMidRadius(double halfSize) =>
    halfSize * (planetRingOuter + planetRingInner) / 2;
double houseMidRadius(double halfSize) =>
    halfSize * (houseRingOuter + houseRingInner) / 2;

/// Screen angle (radians) where a sign's 0° boundary starts.
/// Sign with ascSign is centered at π (9 o'clock).
double signStartAngle(int signNumber, int ascSign) {
  final offset = signNumber - ascSign;
  // Each sign spans 2π/12 = π/6 radians.
  // Sign ascSign starts at π - π/12 (so its midpoint is at π).
  return pi - pi / 12 + offset * (pi / 6);
}

/// Screen angle for a specific ecliptic position.
double degreeToAngle(int sign, double inSignDeg, int ascSign) {
  final signStart = signStartAngle(sign, ascSign);
  // 30° of sign maps to π/6 radians. Degrees increase clockwise.
  return signStart + inSignDeg / 30.0 * (pi / 6);
}

/// Midpoint angle for a given sign.
double signMidAngle(int signNumber, int ascSign) {
  return signStartAngle(signNumber, ascSign) + pi / 12;
}

Offset polarToCartesian(double angle, double radius, Offset center) {
  return Offset(
    center.dx + radius * cos(angle),
    center.dy + radius * sin(angle),
  );
}

/// Resolve planet placement within a sign to prevent overlaps.
/// Returns list of resolved angles, maintaining input order.
List<double> resolvePlanetAngles({
  required List<double> inSignDegrees,
  required int sign,
  required int ascSign,
  required double glyphAngularSize,
}) {
  if (inSignDegrees.isEmpty) return [];
  if (inSignDegrees.length == 1) {
    return [degreeToAngle(sign, inSignDegrees[0], ascSign)];
  }

  final signStart = signStartAngle(sign, ascSign);
  final signSpan = pi / 6; // 30°
  final padding = glyphAngularSize * 0.15;

  // Create indexed entries and sort by degree.
  final indexed =
      List.generate(inSignDegrees.length, (i) => (i, inSignDegrees[i]));
  indexed.sort((a, b) => a.$2.compareTo(b.$2));

  // Try natural placement first.
  final natural =
      indexed.map((e) => signStart + e.$2 / 30.0 * signSpan).toList();

  if (_noOverlaps(natural, glyphAngularSize)) {
    // Reorder back to original indices.
    final result = List<double>.filled(inSignDegrees.length, 0);
    for (var i = 0; i < indexed.length; i++) {
      result[indexed[i].$1] = natural[i];
    }
    return result;
  }

  // Even spread across the sign.
  final totalNeeded = indexed.length * (glyphAngularSize + padding) - padding;
  final startOffset = (signSpan - totalNeeded) / 2;
  final step = glyphAngularSize + padding;

  final result = List<double>.filled(inSignDegrees.length, 0);
  for (var i = 0; i < indexed.length; i++) {
    final angle = signStart +
        max(0, startOffset) +
        i * step +
        glyphAngularSize / 2;
    result[indexed[i].$1] = angle.clamp(
      signStart + glyphAngularSize / 2,
      signStart + signSpan - glyphAngularSize / 2,
    );
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
  final String? trimsamsaBeing;
  final bool isRetrograde;

  const PlacedPlanet({
    required this.bodyName,
    required this.sign,
    required this.inSignDeg,
    required this.angle,
    this.horaBeing,
    this.trimsamsaBeing,
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
