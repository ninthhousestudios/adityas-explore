import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'aditya_data.dart';
import 'overlay_shell.dart';
import 'planet_content.dart';
import 'stable_asset_image.dart';

class PlanetDetailOverlay extends StatelessWidget {
  final Color color;
  final bool isDark;
  final String planetName;
  final Map<String, PlanetContent>? contentMap;
  final VoidCallback onClose;
  final VoidCallback? onBack;

  const PlanetDetailOverlay({
    super.key,
    required this.color,
    required this.isDark,
    required this.planetName,
    required this.contentMap,
    required this.onClose,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final content = contentMap?[planetName];
    final glyphPath = planetGlyphs[planetName];
    final imagePath = planetImagePath(planetName);

    return OverlayShell(
      color: color,
      isDark: isDark,
      onClose: onClose,
      onBack: onBack,
      headerLeading: glyphPath != null
          ? SvgPicture.asset(
              glyphPath,
              width: 28,
              height: 28,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            )
          : null,
      title: content?.name ?? '',
      body: content == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  content.description,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                StableAssetImage(path: imagePath),
              ],
            ),
    );
  }
}
