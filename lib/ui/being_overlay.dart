import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../share_util.dart'
    if (dart.library.js_interop) '../share_util_web.dart';
import 'aditya_data.dart';
import 'being_content.dart';
import 'chart_wheel_layout.dart';

({Widget? leading, String title})? beingOverlayHeader({
  required Color color,
  PlacedPlanet? planet,
  ({String name, String type, String planet, int sign})? being,
}) {
  final String planetName;
  final int beingSign;
  final String beingType;
  final String beingName;

  if (planet != null) {
    planetName = planet.bodyName;
    beingSign = planet.trimsamsaBeingSign ?? 0;
    beingType = planet.trimsamsaBeingType ?? '';
    beingName = planet.trimsamsaBeing ?? '';
  } else if (being != null) {
    planetName = being.planet;
    beingSign = being.sign;
    beingType = being.type;
    beingName = being.name;
  } else {
    return null;
  }

  final planetGlyph = planetName.isNotEmpty ? planetGlyphs[planetName] : null;
  final glyphPath = beingTypeGlyphPath(beingType);

  final Widget? leading;
  if (planetGlyph != null) {
    leading = SvgPicture.asset(
      planetGlyph,
      width: 28,
      height: 28,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  } else if (glyphPath != null) {
    leading = ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: Image.asset(glyphPath, width: 28, height: 28),
    );
  } else {
    leading = null;
  }

  final title = planetName.isNotEmpty
      ? '${_capitalize(planetName)} — $beingName'
      : beingName.isNotEmpty
      ? beingName
      : adityaName(beingSign) ?? '';

  return (leading: leading, title: title);
}

class BeingOverlayBody extends StatelessWidget {
  final Color color;
  final bool isDark;
  final PlacedPlanet? planet;
  final ({String name, String type, String planet, int sign})? being;
  final Map<(int, String), BeingContent>? beingContent;
  final void Function(String type) onPushBeingType;
  final void Function(({String name, String type, String planet, int sign}))
  onPushBeing;

  const BeingOverlayBody({
    super.key,
    required this.color,
    required this.isDark,
    this.planet,
    this.being,
    this.beingContent,
    required this.onPushBeingType,
    required this.onPushBeing,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = _resolveData();
    if (resolved == null) return const SizedBox.shrink();

    final (:planetName, :beingSign, :beingType, :beingName, :infoRows) =
        resolved;

    final content = beingContent?[(beingSign, beingType)];
    final imagePath = beingImagePath(beingSign, beingType);
    final glyphPath = beingTypeGlyphPath(beingType);
    final dimColor = color.withValues(alpha: 0.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...infoRows,
        const SizedBox(height: 16),
        if (imagePath.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              imagePath,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                height: 160,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'Image not found',
                    style: TextStyle(color: dimColor),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Center(
          child: _ShareBeingButton(
            sign: beingSign,
            beingType: beingType,
            beingName: beingName,
            planetName: planetName,
            color: color,
            isDark: isDark,
          ),
        ),
        const SizedBox(height: 16),
        if (glyphPath != null)
          Center(
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              child: Image.asset(glyphPath, width: 56, height: 56),
            ),
          ),
        if (content != null) ...[
          const SizedBox(height: 16),
          Center(
            child: Text(
              content.subtitle,
              style: TextStyle(
                color: isDark ? const Color(0xFFD4A855) : color,
                fontSize: 16,
                fontStyle: FontStyle.italic,
                fontWeight: isDark ? null : FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content.description,
            style: TextStyle(
              color: color.withValues(alpha: 0.85),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          if (content.reflections.isNotEmpty) ...[
            const SizedBox(height: 20),
            Center(
              child: Text(
                'Reflection',
                style: TextStyle(
                  color: isDark ? const Color(0xFFD4A855) : color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              content.reflections,
              style: TextStyle(
                color: color.withValues(alpha: 0.85),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ],
      ],
    );
  }

  ({
    String planetName,
    int beingSign,
    String beingType,
    String beingName,
    List<Widget> infoRows,
  })?
  _resolveData() {
    if (planet case final planet?) {
      final beingType = planet.trimsamsaBeingType ?? '';
      return (
        planetName: planet.bodyName,
        beingSign: planet.trimsamsaBeingSign ?? 0,
        beingType: beingType,
        beingName: planet.trimsamsaBeing ?? '',
        infoRows: [
          _infoRow(
            'Position',
            '${planet.longitudeLabel} ${adityaSigns[planet.sign]?.name ?? '?'}',
          ),
          _tappableInfoRow(
            'Type',
            _capitalize(beingType),
            () => onPushBeingType(beingType),
          ),
          _soulStanceRow(
            planet.horaBeingType ?? '',
            planet.horaBeing ?? '',
            planet.bodyName,
            planet.horaBeingSign ?? 0,
          ),
          if (planet.isRetrograde) _infoRow('Motion', 'Retrograde'),
        ],
      );
    } else if (being case final being?) {
      return (
        planetName: being.planet,
        beingSign: being.sign,
        beingType: being.type,
        beingName: being.name,
        infoRows: [
          _tappableInfoRow(
            'Type',
            _capitalize(being.type),
            () => onPushBeingType(being.type),
          ),
        ],
      );
    }
    return null;
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 14),
          ),
          Text(value, style: TextStyle(color: color, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _tappableInfoRow(String label, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: TextStyle(color: color, fontSize: 14)),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward,
                  color: color.withValues(alpha: 0.4),
                  size: 14,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _soulStanceRow(
    String horaType,
    String horaName,
    String planetName,
    int horaSign,
  ) {
    final dimColor = color.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Soul Stance', style: TextStyle(color: dimColor, fontSize: 14)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => onPushBeingType(horaType),
                behavior: HitTestBehavior.opaque,
                child: Text(
                  _capitalize(horaType),
                  style: TextStyle(color: color, fontSize: 14),
                ),
              ),
              Text(' — ', style: TextStyle(color: dimColor, fontSize: 14)),
              GestureDetector(
                onTap: () => onPushBeing((
                  name: horaName,
                  type: horaType,
                  planet: planetName,
                  sign: horaSign,
                )),
                behavior: HitTestBehavior.opaque,
                child: Text(
                  horaName,
                  style: TextStyle(color: color, fontSize: 14),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward,
                color: color.withValues(alpha: 0.4),
                size: 14,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

class _ShareBeingButton extends StatefulWidget {
  final int sign;
  final String beingType;
  final String beingName;
  final String planetName;
  final Color color;
  final bool isDark;

  const _ShareBeingButton({
    required this.sign,
    required this.beingType,
    required this.beingName,
    required this.planetName,
    required this.color,
    required this.isDark,
  });

  @override
  State<_ShareBeingButton> createState() => _ShareBeingButtonState();
}

class _ShareBeingButtonState extends State<_ShareBeingButton> {
  bool _loading = false;
  String? _error;

  Future<void> _share() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final error = await shareBeingCard(
        sign: widget.sign,
        beingType: widget.beingType,
        beingName: widget.beingName,
        planetName: widget.planetName,
      );
      if (mounted && error != null) setState(() => _error = error);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isDark
        ? const Color(0xFFD4A853)
        : const Color(0xFF8B6F37);
    final errorColor = Colors.red.shade300;
    return GestureDetector(
      onTap: _share,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: accent,
                  ),
                )
              else
                Icon(Icons.share, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                _loading ? 'Sharing...' : 'Share my Being',
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!, style: TextStyle(color: errorColor, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}
