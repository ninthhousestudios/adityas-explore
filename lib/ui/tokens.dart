import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Design-token set for the explorer, exposed as a [ThemeExtension] so token
/// lookup rides on the existing `Theme.of(context)` plumbing and the
/// MaterialApp theme swap.
///
/// Instances are `const`, so Dart canonicalizes them and `identical()` holds —
/// that is what lets [ChartWheelPainter.shouldRepaint] compare a single token
/// object instead of a handful of individual colour fields.
///
/// Values reproduce today's rendered colours EXACTLY, except the four
/// deliberate `docs/brand.md` drift corrections (see the task): the typo'd gold
/// collapses into [gold], the Material-blue light-mode link resolves to [gold],
/// and the three ad-hoc error reds / one ad-hoc success green collapse into
/// [error]/[errorBg]/[success].
@immutable
class ExploreTokens extends ThemeExtension<ExploreTokens> {
  // ---- Surfaces -----------------------------------------------------------
  /// Page canvas (brand Background). Note: the immersive [ThemeData] keeps a
  /// transparent scaffold so the background image shows; this is the value fed
  /// to the overridden `ColorScheme.surface`/`background`, not the scaffold.
  final Color canvas;

  /// Elevated surface (brand Surface).
  final Color surface;

  /// Frosted card/panel fill. Replaces the copy-pasted `0xF0151015` /
  /// `0xF0F5F1EA` pair at 7 sites.
  final Color cardBg;

  /// Semi-transparent disc painted behind the chart wheel so it pops over
  /// background imagery. Was `black@0.5 / white@0.5`.
  final Color wheelBackdrop;

  /// Drop-shadow / scrim colour under floating cards. Black at 50% (immersive)
  /// / 20% (light).
  final Color scrim;

  // ---- Ink ---------------------------------------------------------------
  /// Primary foreground — pure white (immersive) / black (light), at ~10 sites.
  /// Deliberately NOT the brand text ink, to preserve today's appearance; call
  /// sites keep their `.withValues(alpha:)` derivations off this.
  final Color ink;

  // ---- Accent ------------------------------------------------------------
  /// Brand gold accent — `#D4A853` (immersive) / `#8B6F37` (light). Collapses
  /// the copy-pasted gold pairs and the typo'd variant that drifted at 4 sites.
  final Color gold;

  /// Foreground on a gold-filled button — black (immersive) / white (light).
  final Color onGold;

  // ---- Being labels ------------------------------------------------------
  /// Being subtitle/reflection labels use gold in immersive mode but the
  /// being's own aditya colour in light mode. Encodes the theme half of that
  /// choice; the being colour is runtime data, so resolve via [beingLabel].
  final bool beingLabelUsesGold;

  /// Weight for being labels — normal/w400 (immersive, inherited) vs bold
  /// (light).
  final FontWeight beingLabelWeight;

  // ---- Status ------------------------------------------------------------
  /// Error text/foreground. Unifies the three ad-hoc error reds.
  final Color error;

  /// Error surface tint (error @ 20%).
  final Color errorBg;

  /// Success foreground. Unifies the one ad-hoc success green.
  final Color success;

  // ---- Wheel strokes -----------------------------------------------------
  /// Concentric ring stroke width (was hardcoded 1.0 in the painter).
  final double ringStroke;

  /// Radial sign-boundary line width (was 0.5).
  final double radialStroke;

  /// Outer edge stroke width (was 1.5).
  final double edgeStroke;

  // ---- Wheel fills (consumed by the upcoming light-mode pass) -------------
  /// Fill for the outer sign ring. Unused today (painter strokes only);
  /// transparent placeholder until the light-mode wheel work tunes it.
  final Color ringOuterFill;

  /// Fill for the planet ring.
  final Color ringPlanetFill;

  /// Fill for the house ring.
  final Color ringHouseFill;

  /// Ascendant marker colour.
  final Color ascMarker;

  const ExploreTokens({
    required this.canvas,
    required this.surface,
    required this.cardBg,
    required this.wheelBackdrop,
    required this.scrim,
    required this.ink,
    required this.gold,
    required this.onGold,
    required this.beingLabelUsesGold,
    required this.beingLabelWeight,
    required this.error,
    required this.errorBg,
    required this.success,
    required this.ringStroke,
    required this.radialStroke,
    required this.edgeStroke,
    required this.ringOuterFill,
    required this.ringPlanetFill,
    required this.ringHouseFill,
    required this.ascMarker,
  });

  /// Colour for a being subtitle/reflection label given the being's aditya
  /// [beingColor]. Replaces the per-theme gold-vs-being-colour ternary.
  Color beingLabel(Color beingColor) => beingLabelUsesGold ? gold : beingColor;

  static const immersive = ExploreTokens(
    canvas: Color(0xFF110E14),
    surface: Color(0xFF1A1520),
    cardBg: Color(0xF0151015),
    wheelBackdrop: Color(0x80000000),
    scrim: Color(0x80000000),
    ink: Color(0xFFFFFFFF),
    gold: Color(0xFFD4A853),
    onGold: Color(0xFF000000),
    beingLabelUsesGold: true,
    beingLabelWeight: FontWeight.normal,
    error: Color(0xFFE57373),
    errorBg: Color(0x33E57373),
    success: Color(0xFF4CAF50),
    ringStroke: 1.0,
    radialStroke: 0.5,
    edgeStroke: 1.5,
    ringOuterFill: Color(0x00000000),
    ringPlanetFill: Color(0x00000000),
    ringHouseFill: Color(0x00000000),
    ascMarker: Color(0xFFD4A853),
  );

  static const light = ExploreTokens(
    canvas: Color(0xFFF5F1EA),
    surface: Color(0xFFFFFFFF),
    cardBg: Color(0xF0F5F1EA),
    wheelBackdrop: Color(0x80FFFFFF),
    scrim: Color(0x33000000),
    ink: Color(0xFF000000),
    gold: Color(0xFF8B6F37),
    onGold: Color(0xFFFFFFFF),
    beingLabelUsesGold: false,
    beingLabelWeight: FontWeight.bold,
    error: Color(0xFFE57373),
    errorBg: Color(0x33E57373),
    success: Color(0xFF4CAF50),
    ringStroke: 1.0,
    radialStroke: 0.5,
    edgeStroke: 1.5,
    ringOuterFill: Color(0xFFFFFFFF),
    ringPlanetFill: Color(0xFFF7F3EC),
    ringHouseFill: Color(0xFFEFEAE1),
    ascMarker: Color(0xFF8B6F37),
  );

  @override
  ExploreTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? cardBg,
    Color? wheelBackdrop,
    Color? scrim,
    Color? ink,
    Color? gold,
    Color? onGold,
    bool? beingLabelUsesGold,
    FontWeight? beingLabelWeight,
    Color? error,
    Color? errorBg,
    Color? success,
    double? ringStroke,
    double? radialStroke,
    double? edgeStroke,
    Color? ringOuterFill,
    Color? ringPlanetFill,
    Color? ringHouseFill,
    Color? ascMarker,
  }) {
    return ExploreTokens(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      cardBg: cardBg ?? this.cardBg,
      wheelBackdrop: wheelBackdrop ?? this.wheelBackdrop,
      scrim: scrim ?? this.scrim,
      ink: ink ?? this.ink,
      gold: gold ?? this.gold,
      onGold: onGold ?? this.onGold,
      beingLabelUsesGold: beingLabelUsesGold ?? this.beingLabelUsesGold,
      beingLabelWeight: beingLabelWeight ?? this.beingLabelWeight,
      error: error ?? this.error,
      errorBg: errorBg ?? this.errorBg,
      success: success ?? this.success,
      ringStroke: ringStroke ?? this.ringStroke,
      radialStroke: radialStroke ?? this.radialStroke,
      edgeStroke: edgeStroke ?? this.edgeStroke,
      ringOuterFill: ringOuterFill ?? this.ringOuterFill,
      ringPlanetFill: ringPlanetFill ?? this.ringPlanetFill,
      ringHouseFill: ringHouseFill ?? this.ringHouseFill,
      ascMarker: ascMarker ?? this.ascMarker,
    );
  }

  /// Snap rather than crossfade: the theme swap is a deliberate, instant user
  /// action, and the snap preserves the const-identity fast path that
  /// [ChartWheelPainter.shouldRepaint] relies on. A per-field `Color.lerp`
  /// crossfade is an upgrade for later, not a blocker.
  @override
  ExploreTokens lerp(ThemeExtension<ExploreTokens>? other, double t) {
    if (other is! ExploreTokens) return this;
    return t < 0.5 ? this : other;
  }
}

/// Token lookup with a non-null fallback (the house Dart rules forbid `!`).
extension ExploreThemeX on BuildContext {
  ExploreTokens get tokens =>
      Theme.of(this).extension<ExploreTokens>() ?? ExploreTokens.immersive;
}

/// Theme selection, replacing the persisted `bool useLight`.
enum ExploreTheme { immersive, light }

/// SharedPreferences key for the new enum-valued preference.
const String kThemePrefKey = 'exploreTheme';

/// Legacy `bool` key, read once for migration then left in place.
const String kLegacyUseLightKey = 'useLight';

/// Reads the persisted theme, migrating a pre-existing `useLight` bool on first
/// run so an upgrading user who had light mode still lands in light mode.
ExploreTheme readThemePreference(SharedPreferences prefs) {
  final stored = prefs.getString(kThemePrefKey);
  if (stored != null) {
    return ExploreTheme.values.firstWhere(
      (t) => t.name == stored,
      orElse: () => ExploreTheme.immersive,
    );
  }
  // First run since the enum migration: translate the legacy bool once.
  final legacy = prefs.getBool(kLegacyUseLightKey);
  final migrated = legacy == true ? ExploreTheme.light : ExploreTheme.immersive;
  prefs.setString(kThemePrefKey, migrated.name);
  return migrated;
}

/// Persists [theme] under [kThemePrefKey].
Future<void> writeThemePreference(SharedPreferences prefs, ExploreTheme theme) {
  return prefs.setString(kThemePrefKey, theme.name);
}
