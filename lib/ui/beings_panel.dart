import 'package:flutter/material.dart';

import '../astro/being_uncertainty.dart';
import 'chart_wheel_layout.dart';
import 'popup_state.dart';

class BeingsPanel extends StatelessWidget {
  final List<PlacedPlanet> planets;
  final BeingUncertainty? uncertainty;
  final Color color;
  final Color backdropColor;
  final double fontSize;
  final ValueChanged<PopupState> onOpen;

  const BeingsPanel({
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
            'Your Beings',
            style: TextStyle(
              color: color,
              fontSize: fontSize * 1.1,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'click to find out more',
            style: TextStyle(
              color: dimColor,
              fontSize: fontSize * 0.8,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 4),
          for (final p in planets)
            Padding(
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
                  GestureDetector(
                    onTap: () =>
                        onOpen(BeingTypePopup(p.trimsamsaBeingType ?? '')),
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      '  ${_capitalize(p.trimsamsaBeingType ?? '')}',
                      style: TextStyle(color: dimColor, fontSize: fontSize),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      final uncertain =
                          uncertainty?.isTrimsamsaUncertain(p.bodyName) ??
                          false;
                      if (uncertain) {
                        onOpen(
                          UncertaintyPopup(p.bodyName, UncertainKind.trimsamsa),
                        );
                      } else {
                        onOpen(BeingFromPlanet(p));
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      '  ${p.trimsamsaBeing ?? ''}'
                      '${(uncertainty?.isTrimsamsaUncertain(p.bodyName) ?? false) ? ' ~' : ''}',
                      style: TextStyle(color: color, fontSize: fontSize),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
