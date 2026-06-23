import 'package:flutter/material.dart';

import '../astro/being_uncertainty.dart';
import 'being_content.dart';
import 'popup_state.dart';

class UncertaintyChooser extends StatelessWidget {
  final Color color;
  final bool isDark;
  final String planetName;
  final UncertainKind kind;
  final List<Being> options;
  final bool canGoBack;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  final ValueChanged<PopupState> onPush;

  const UncertaintyChooser({
    super.key,
    required this.color,
    required this.isDark,
    required this.planetName,
    required this.kind,
    required this.options,
    required this.canGoBack,
    required this.onClose,
    this.onBack,
    required this.onPush,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();

    final label = kind == UncertainKind.hora ? 'soul stance' : 'being';
    final cardBg = isDark ? const Color(0xF0151015) : const Color(0xF0F5F1EA);
    final dimColor = color.withValues(alpha: 0.6);
    final accentColor = isDark
        ? const Color(0xFFD4A853)
        : const Color(0xFF8B6F37);

    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (canGoBack) ...[
                        GestureDetector(
                          onTap: onBack,
                          child: Icon(Icons.arrow_back, size: 18, color: color),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          'Your ${_capitalize(planetName)} $label could be:',
                          style: TextStyle(
                            color: color,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: onClose,
                        child: Icon(Icons.close, size: 18, color: dimColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final option in options) ...[
                    GestureDetector(
                      onTap: () => onPush(
                        BeingFromName((
                          name: option.name,
                          type: option.type.name,
                          planet: planetName,
                          sign: option.signNumber,
                        )),
                      ),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Text(
                              '▸  ',
                              style: TextStyle(
                                color: accentColor,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              option.name,
                              style: TextStyle(
                                color: color,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '  ${_capitalize(option.type.name)} of '
                              '${adityaName(option.signNumber) ?? '?'}',
                              style: TextStyle(color: dimColor, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Tap a being to learn more.',
                    style: TextStyle(
                      color: dimColor,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
