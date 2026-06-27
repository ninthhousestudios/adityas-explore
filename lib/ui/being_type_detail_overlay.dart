import 'package:flutter/material.dart';

import 'being_type_content.dart';
import 'overlay_shell.dart';
import 'stable_asset_image.dart';

class BeingTypeDetailOverlay extends StatelessWidget {
  final Color color;
  final bool isDark;
  final String type;
  final Map<String, BeingTypeContent>? contentMap;
  final VoidCallback onClose;
  final VoidCallback? onBack;

  const BeingTypeDetailOverlay({
    super.key,
    required this.color,
    required this.isDark,
    required this.type,
    required this.contentMap,
    required this.onClose,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final content = contentMap?[type];
    final emblemPath = beingTypeEmblemPath(type);

    return OverlayShell(
      color: color,
      isDark: isDark,
      onClose: onClose,
      onBack: onBack,
      title: content != null ? '${content.type} — ${content.role}' : '',
      body: content == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  content.subtitle,
                  style: TextStyle(
                    color: isDark ? const Color(0xFFD4A855) : color,
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    fontWeight: isDark ? null : FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                StableAssetImage(path: emblemPath),
                const SizedBox(height: 16),
                Text(
                  content.description,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
    );
  }
}
