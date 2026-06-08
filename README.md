[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

# Adityas Explore

Interactive birth chart explorer for the Aditya system — a non-standard Vedic
framework derived from the Srimad Bhagavatam. Renders a circular chart wheel
with Aditya sign glyphs, planet positions, Campanus house cusps, and
tap-to-reveal being cards (Hora and Trimsamsa).

Built with Flutter (desktop + web). The Arrow calculation engine runs
client-side (Dart/WASM for web, native FFI for desktop).

## Running

```
flutter run -d chrome    # web
flutter run -d linux     # desktop
```

Load a `.chtk` or `.toml` chart file from the settings menu.

