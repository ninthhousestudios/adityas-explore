import 'package:flutter/material.dart';

/// Geometry + gesture wiring that turns [OverlayShell] into a draggable +
/// resizable floating window (the desktop transient layer). When absent, the
/// shell renders as a centered modal — the mobile / fallback behavior. See
/// docs/layout-modes.md § "Two layers, two behaviors".
class FloatingConfig {
  /// Absolute rect of the window within its parent Stack.
  final Rect rect;

  /// Called with the pointer delta while dragging the title bar. The parent
  /// owns the geometry and does the on-screen clamping.
  final void Function(Offset delta) onDrag;

  /// Called with the pointer delta while dragging the resize handle.
  final void Function(Offset delta) onResize;

  const FloatingConfig({
    required this.rect,
    required this.onDrag,
    required this.onResize,
  });
}

class OverlayShell extends StatelessWidget {
  final Color color;
  final bool isDark;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  final Widget? headerLeading;
  final String title;
  final Widget body;

  /// When non-null the shell is a floating window; otherwise a centered modal.
  final FloatingConfig? floating;

  const OverlayShell({
    super.key,
    required this.color,
    required this.isDark,
    required this.onClose,
    this.onBack,
    this.headerLeading,
    required this.title,
    required this.body,
    this.floating,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xF0151015) : const Color(0xF0F5F1EA);
    final floating = this.floating;
    if (floating != null) return _buildFloating(cardBg, floating);
    return _buildModal(context, cardBg);
  }

  /// Shared header: back (optional), leading glyph (optional), title, close.
  Widget _headerRow() {
    return Row(
      children: [
        if (onBack != null) ...[
          IconButton(
            onPressed: onBack,
            icon: Icon(Icons.arrow_back, color: color, size: 20),
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
    );
  }

  /// Centered modal — the original look, kept for mobile and fallback.
  Widget _buildModal(BuildContext context, Color cardBg) {
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
                        child: _headerRow(),
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

  /// Floating window: draggable title bar, resize handle at the bottom-right,
  /// no scrim (the chart behind stays interactive). Height is bounded by the
  /// rect, so the body uses [Expanded] and scrolls within.
  Widget _buildFloating(Color cardBg, FloatingConfig f) {
    final r = f.rect;
    return Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Column(
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (d) => f.onDrag(d.delta),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                        child: _headerRow(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: body,
                    ),
                  ),
                ],
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeDownRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => f.onResize(d.delta),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.south_east,
                        size: 16,
                        color: color.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
