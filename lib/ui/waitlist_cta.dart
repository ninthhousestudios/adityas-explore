import 'package:flutter/material.dart';

import 'waitlist_dialog.dart';

class WaitlistCta extends StatelessWidget {
  final Color color;
  final Color backdropColor;
  final double fontSize;
  final bool signed;
  final VoidCallback onSigned;

  const WaitlistCta({
    super.key,
    required this.color,
    required this.backdropColor,
    required this.fontSize,
    required this.signed,
    required this.onSigned,
  });

  @override
  Widget build(BuildContext context) {
    final dimColor = color.withValues(alpha: 0.6);

    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backdropColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: signed
          ? Text(
              "You're on the list! We'll let you know.",
              style: TextStyle(
                color: dimColor,
                fontSize: fontSize,
                fontStyle: FontStyle.italic,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'More reports coming soon.',
                  style: TextStyle(
                    color: color,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Click here to get notified.',
                  style: TextStyle(
                    color: dimColor,
                    fontSize: fontSize * 0.85,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
    );

    if (signed) return box;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showWaitlistDialog(context),
        child: box,
      ),
    );
  }

  void _showWaitlistDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogColor = isDark ? Colors.white : Colors.black;

    showDialog(
      context: context,
      builder: (context) => WaitlistDialog(
        color: dialogColor,
        isDark: isDark,
        onSuccess: onSigned,
      ),
    );
  }
}
