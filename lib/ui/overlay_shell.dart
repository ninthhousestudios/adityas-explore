import 'package:flutter/material.dart';

class OverlayShell extends StatelessWidget {
  final Color color;
  final bool isDark;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  final Widget? headerLeading;
  final String title;
  final Widget body;

  const OverlayShell({
    super.key,
    required this.color,
    required this.isDark,
    required this.onClose,
    this.onBack,
    this.headerLeading,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xF0151015) : const Color(0xF0F5F1EA);

    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(44, 24, 44, 0),
                        child: Row(
                          children: [
                            if (onBack != null) ...[
                              IconButton(
                                onPressed: onBack,
                                icon: Icon(
                                  Icons.arrow_back,
                                  color: color,
                                  size: 20,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (headerLeading != null) ...[
                              headerLeading!,
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: onClose,
                              icon: Icon(Icons.close, color: color, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(44, 0, 44, 24),
                          child: body,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
