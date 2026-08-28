import 'package:flutter/material.dart';

import 'being_type_content.dart';
import 'overlay_shell.dart';
import 'stable_asset_image.dart';
import 'tokens.dart';

class BeingTypeDetailOverlay extends StatelessWidget {
  final Color color;
  final String type;
  final Map<String, BeingTypeContent>? contentMap;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  final FloatingConfig? floating;

  const BeingTypeDetailOverlay({
    super.key,
    required this.color,
    required this.type,
    required this.contentMap,
    required this.onClose,
    this.onBack,
    this.floating,
  });

  @override
  Widget build(BuildContext context) {
    final content = contentMap?[type];
    final emblemPath = beingTypeEmblemPath(type);
    final t = context.tokens;

    return OverlayShell(
      color: color,
      onClose: onClose,
      onBack: onBack,
      floating: floating,
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
                    color: t.beingLabel(color),
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    fontWeight: t.beingLabelWeight,
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
