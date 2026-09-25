import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The in-flight "Contemplating…" status for the chat bubble: a small sun
/// throwing out rays, followed by the [label] with a rippling ellipsis.
///
/// One repeating controller drives both the rays and the dots. Under the
/// platform's reduce-motion setting ([MediaQuery.disableAnimationsOf]) the
/// controller is stopped and a single static frame is painted.
class ContemplatingIndicator extends StatefulWidget {
  final String label;
  final Color textColor;
  final Color sunColor;
  final double fontSize;

  const ContemplatingIndicator({
    super.key,
    required this.label,
    required this.textColor,
    required this.sunColor,
    required this.fontSize,
  });

  @override
  State<ContemplatingIndicator> createState() => _ContemplatingIndicatorState();
}

class _ContemplatingIndicatorState extends State<ContemplatingIndicator>
    with SingleTickerProviderStateMixin {
  static const _period = Duration(milliseconds: 2000);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl
        ..stop()
        ..value = 0.35;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The panel-level live region announces the status; drop the trailing
    // ellipsis from the visible label since the animated dots replace it.
    final base = widget.label.endsWith('…')
        ? widget.label.substring(0, widget.label.length - 1)
        : widget.label;
    final style = TextStyle(
      color: widget.textColor,
      fontSize: widget.fontSize,
      fontStyle: FontStyle.italic,
    );
    final sunSize = widget.fontSize * 1.5;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: Size.square(sunSize),
              painter: _SunPainter(t: t, color: widget.sunColor),
            ),
            SizedBox(width: widget.fontSize * 0.4),
            Text.rich(
              TextSpan(
                style: style,
                children: [
                  TextSpan(text: base),
                  // All three dots always occupy their width (only alpha moves),
                  // so the label never jitters.
                  for (var i = 0; i < 3; i++)
                    TextSpan(
                      text: '.',
                      style: TextStyle(
                        color: widget.textColor.withValues(
                          alpha: widget.textColor.a * _dotAlpha(t, i),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// A travelling wave across the three dots: each brightens in turn.
  static double _dotAlpha(double t, int i) {
    final phase = (t - i / 6) * 2 * math.pi;
    return 0.2 + 0.8 * (0.5 + 0.5 * math.sin(phase)).clamp(0.0, 1.0);
  }
}

/// A gold disc with [_rayCount] rays, each a short dash that is thrown outward
/// from the rim and fades as it travels. Rays are staggered around the circle
/// so the emission ripples, and the whole crown rotates slowly.
class _SunPainter extends CustomPainter {
  static const _rayCount = 12;

  final double t;
  final Color color;

  const _SunPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final core = outer * 0.38;
    // Gentle breathing on the disc, twice per cycle.
    final pulse = 1 + 0.06 * math.sin(t * 4 * math.pi);

    canvas
      ..drawCircle(
        c,
        core * 1.6 * pulse,
        Paint()..color = color.withValues(alpha: color.a * 0.18),
      )
      ..drawCircle(c, core * pulse, Paint()..color = color);

    final ray = Paint()
      ..strokeWidth = math.max(1, outer * 0.11)
      ..strokeCap = StrokeCap.round;
    final start = core * 1.35;
    final travel = outer - start;
    final dash = travel * 0.45;
    final spin = t * 2 * math.pi / _rayCount;
    for (var i = 0; i < _rayCount; i++) {
      // Each ray runs its own emission cycle, offset around the circle.
      final p = (t * 2 + i / _rayCount) % 1.0;
      final angle = spin + i * 2 * math.pi / _rayCount;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final from = start + (travel - dash) * p;
      ray.color = color.withValues(alpha: color.a * (1 - p) * 0.9);
      canvas.drawLine(c + dir * from, c + dir * (from + dash), ray);
    }
  }

  @override
  bool shouldRepaint(_SunPainter old) => old.t != t || old.color != color;
}
