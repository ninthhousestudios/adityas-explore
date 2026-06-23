import 'package:flutter/material.dart';

import '../astro/being_uncertainty.dart';
import 'chart_wheel_layout.dart';
import 'popup_state.dart';

class SoulStancesPanel extends StatelessWidget {
  final List<PlacedPlanet> planets;
  final BeingUncertainty? uncertainty;
  final Color color;
  final Color backdropColor;
  final double fontSize;
  final ValueChanged<PopupState> onOpen;

  const SoulStancesPanel({
    super.key,
    required this.planets,
    this.uncertainty,
    required this.color,
    required this.backdropColor,
    required this.fontSize,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final dimColor = color.withValues(alpha: 0.6);

    final adityaPlanets = planets
        .where((p) => p.horaBeingType == 'aditya')
        .toList();
    final nagaPlanets = planets
        .where((p) => p.horaBeingType == 'naga')
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backdropColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Soul Stances of Your Planets',
            style: TextStyle(
              color: color,
              fontSize: fontSize * 1.1,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (adityaPlanets.isNotEmpty) ...[
            GestureDetector(
              onTap: () => onOpen(BeingTypePopup('aditya')),
              behavior: HitTestBehavior.opaque,
              child: Text(
                'Aditya Stance',
                style: TextStyle(
                  color: color,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              'These planets call you to express your love in the world.',
              style: TextStyle(
                color: dimColor,
                fontSize: fontSize * 0.8,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 2),
            for (final p in adityaPlanets) _buildStanceRow(p, dimColor),
            const SizedBox(height: 8),
          ],
          if (nagaPlanets.isNotEmpty) ...[
            GestureDetector(
              onTap: () => onOpen(BeingTypePopup('naga')),
              behavior: HitTestBehavior.opaque,
              child: Text(
                'Naga Stance',
                style: TextStyle(
                  color: color,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              'These planets call you to dig deep into yourself.',
              style: TextStyle(
                color: dimColor,
                fontSize: fontSize * 0.8,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 2),
            for (final p in nagaPlanets) _buildStanceRow(p, dimColor),
          ],
        ],
      ),
    );
  }

  Widget _buildStanceRow(PlacedPlanet p, Color dimColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => onOpen(PlanetPopup(p.bodyName)),
            behavior: HitTestBehavior.opaque,
            child: Text(
              _capitalize(p.bodyName),
              style: TextStyle(color: dimColor, fontSize: fontSize),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              final horaUncertain =
                  uncertainty?.isHoraUncertain(p.bodyName) ?? false;
              if (horaUncertain) {
                onOpen(UncertaintyPopup(p.bodyName, UncertainKind.hora));
              } else {
                onOpen(
                  BeingFromName((
                    name: p.horaBeing ?? '',
                    type: p.horaBeingType ?? '',
                    planet: p.bodyName,
                    sign: p.horaBeingSign ?? 0,
                  )),
                );
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Text(
              '${p.horaBeing ?? ''}'
              '${(uncertainty?.isHoraUncertain(p.bodyName) ?? false) ? ' ~' : ''}',
              style: TextStyle(color: color, fontSize: fontSize),
            ),
          ),
        ],
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
