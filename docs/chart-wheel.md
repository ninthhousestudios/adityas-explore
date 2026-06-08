# Chart Wheel Renderer

Technical reference for the chart wheel in the explore app. Read this before
modifying any `lib/ui/chart_wheel*` files.

## Architecture

The chart wheel is a hybrid: `CustomPainter` draws the geometric skeleton
(circles, radial lines, house labels) while sign and planet glyphs are
positioned `SvgPicture` widgets in a `Stack`. This gives free hit-testing
and hover detection on glyphs via standard Flutter gesture widgets.

```
lib/ui/
  chart_wheel.dart            — ChartWheel StatefulWidget, orchestrates everything
  chart_wheel_painter.dart    — CustomPainter: circles, radials, cusp/house labels
  chart_wheel_layout.dart     — Pure math: angles, radii, planet collision resolution
  aditya_data.dart            — Sign 1–12 → Aditya name/glyph, planet body → glyph
```

## Ring geometry (outside → inside)

| Ring        | Radius fraction | Content                                    |
|-------------|----------------|--------------------------------------------|
| Outer       | 0.82 – 1.0    | Aditya sign glyph SVGs (one per 30° segment) |
| Planet      | 0.56 – 0.82   | Planet glyph SVGs placed by degree          |
| House       | 0.36 – 0.56   | Roman numerals (Campanus cusps) + arabic whole-sign numbers |
| Center      | 0 – 0.36      | Empty; shows hover info when hovering a planet/cusp |

## Rotation and direction

- Signs increase **counterclockwise**
- The ascendant sign (containing cusp 1) is centered at 9 o'clock (π radians)
- Degrees within a sign increase counterclockwise (0° at the clockwise edge)
- All angle math is in `chart_wheel_layout.dart`; key functions:
  - `signStartAngle(signNumber, ascSign)` → clockwise boundary of a sign
  - `degreeToAngle(sign, inSignDeg, ascSign)` → screen angle for a position
  - `signMidAngle(signNumber, ascSign)` → center of a sign's arc

## Planet placement

Planets are placed at their ecliptic degree via `degreeToAngle`, then run
through `resolvePlanetAngles` which enforces two hard constraints:

1. Every glyph must be entirely inside its sign's angular boundaries
2. No two glyphs may overlap

If natural placement violates either constraint, planets are spread evenly
across the sign's 30° span, preserving degree order where possible.

## Glyph assets

**Sign glyphs** (`assets/glyphs/*.svg`): 12 Aditya glyphs from Sunflare.
Hardcoded stroke `#e0d8c8`, overridden at render time via `ColorFilter.mode`.

**Planet glyphs** (`assets/glyphs/planets/*.svg`): 14 glyphs extracted from
`gandiva/glyphs.py` (AstroDraw/AstroChart MIT-licensed path data) via
`tools/extract_glyphs.py`. Square viewBoxes, proportional stroke widths.
All 14 are in assets; only the 9 Vedic grahas render by default
(`defaultGrahas` in `aditya_data.dart`).

To regenerate planet SVGs after modifying the extraction script:
```
python3 tools/extract_glyphs.py
```

## Arrow API surface used

`Chart` from `package:arrow_core`:
- `.grahas` → `List<Planet>` (9 Vedic: Sun–Saturn + Rahu + Ketu)
- `.cusp(n)` → `Cusp` (1-based, 12 total)
- Each `Planet` has: `.body.name`, `.longitude.sign` (int 1–12, circle-aware),
  `.longitude.inSignLongitude` (0–30), `.isRetrograde`, `.horaBeing.name`,
  `.trimsamsaBeing.name`
- Each `Cusp` has: `.house` (1–12), `.longitude.sign`, `.longitude.inSignLongitude`
- `.sign` is circle-aware — always use it instead of computing from raw longitude
- Cusps do NOT have horaBeing/trimsamsaBeing (only SkyObject subclasses do)

## Interactions

- **Hover planet** → center circle shows: name, in-sign longitude, horaBeing, trimsamsaBeing
- **Hover cusp** → center circle shows: cusp number, in-sign longitude
- **Tap planet** → being card (scaffolded; no overlay/backdrop, just the card)

## Theme

Reads `Theme.of(context).brightness`. Single color for all rendering:
- Immersive (dark): white
- Light: black

SVGs get `ColorFilter.mode(color, BlendMode.srcIn)`.

## Aditya sign mapping

| Sign | Aditya    | Glyph file    |
|------|-----------|---------------|
| 1    | Dhata     | dhata.svg     |
| 2    | Aryama    | aryama.svg    |
| 3    | Mitra     | mitra.svg     |
| 4    | Varuna    | varuna.svg    |
| 5    | Indra     | indra.svg     |
| 6    | Vivasvan  | vivasvan.svg  |
| 7    | Tvashta   | tvashta.svg   |
| 8    | Vishnu    | vishnu.svg    |
| 9    | Amshu     | amzu.svg      |
| 10   | Bhaga     | bhaga.svg     |
| 11   | Pusha     | pushan.svg    |
| 12   | Parjanya  | parjanya.svg  |

Note filename discrepancies for signs 9 and 11 (inherited from Sunflare).
