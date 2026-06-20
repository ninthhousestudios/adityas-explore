<explore>
Interactive birth chart explorer for 84beings.com. Flutter app targeting
web (primary) and Linux desktop. Calculates Vedic astrology charts
client-side using Arrow engine via FFI (desktop) or WASM (web).
</explore>

<stack>
Flutter, Dart. Key dependencies:
- arrow_core/arrow_swe/arrow_calc (git deps from ninthhousestudios/arjuna) — chart calculation engine
- charts_dart (git dep from ninthhousestudios/charts_dart) — ChartData model, file format parsers (TOML/CHTK/JHD), TomlChartFormat.encode for saving
- swisseph — Swiss Ephemeris bindings
- file_picker — open/save chart files (saveFile unimplemented on web; we use conditional imports in file_util.dart / file_util_web.dart)
- flutter_svg — glyph rendering
</stack>

<architecture>
lib/
  main.dart              — app shell, ExploreApp state, _openChart / _submitChart / _newChart
  chart_reader.dart      — dispatches .toml/.chtk/.jhd to charts_dart parsers
  file_util[_web].dart   — conditional import pair for platform-aware file save
  navigate[_web].dart    — conditional import pair for URL navigation
  astro/
    chart_calculator.dart — ChartData → arrow.Chart via EphemerisService
    jd.dart              — dateTimeToJdUt / jdUtToDateTime (Julian Day conversion)
    ephemeris_service.dart — abstract service, native isolate vs web worker
    swe*.dart            — Swiss Ephemeris init and compute
  ui/
    birth_form.dart      — birth data entry form (progressive disclosure card)
    chart_wheel.dart     — main chart rendering widget
    chart_wheel_layout.dart — planet/cusp layout engine
    chart_wheel_painter.dart — custom painter for chart rings
    being_content.dart   — being detail card data
    being_type_content.dart — being type popup content
    planet_content.dart  — planet popup content
    aditya_data.dart     — 12 Aditya name/color data
    theme.dart           — immersiveTheme() (dark) and lightTheme()
</architecture>

<conventions>
- Conditional imports for web vs native: use `import 'foo.dart' if (dart.library.js_interop) 'foo_web.dart'` pattern
- Card/panel styling: dark bg 0xF0151015, light bg 0xF0F5F1EA, border at 30% opacity of text color, borderRadius 16
- Brand accent colors: dark #D4A853, light #8B6F37
- ChartData.dateTime must be constructed with DateTime.utc() when building from form input — prevents double timezone conversion in dateTimeToJdUt (which calls .toUtc())
- No localization / i18n setup — English only for now
</conventions>

<key_docs>
- docs/chart-wheel.md — read before modifying chart_wheel*.dart
- docs/birth-entry.md — birth data entry spec
- docs/birth-data-validation.md — validation rules reference
- Parent project docs at /home/josh/adityas/docs/ (brand.md, aditya-system.md, vision.md)
</key_docs>

<running>
Web: `flutter run -d chrome`
Linux desktop: `flutter run -d linux`
Analyze: `flutter analyze lib/`
Ephemeris files in assets/ephe/, glyphs in assets/glyphs/.
</running>

<gotchas>
- file_picker saveFile() throws UnimplementedError on web — all file save logic goes through saveFileBytes() in file_util[_web].dart
- ChartData.utcDateTime getter returns a local-tagged DateTime (via subtract); if you then call .toUtc() you get double timezone offset. Always construct dateTime with DateTime.utc() for form-built ChartData.
- Arrow git deps pinned to a specific commit hash — update all four arrow_* deps together
- charts_dart tracks HEAD (no pinned ref) — be aware of upstream changes
</gotchas>
