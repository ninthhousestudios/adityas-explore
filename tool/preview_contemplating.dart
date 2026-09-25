// Standalone preview of the chat "Contemplating…" indicator — no backend, no
// turn. Run: flutter run -d chrome -t tool/preview_contemplating.dart
import 'package:explore/ui/contemplating_indicator.dart';
import 'package:explore/ui/tokens.dart';
import 'package:flutter/material.dart';

void main() => runApp(const _Preview());

class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Row(
          children: [
            Expanded(
              child: _Pane(
                tokens: ExploreTokens.immersive,
                bg: Color(0xFF110E14),
              ),
            ),
            Expanded(
              child: _Pane(tokens: ExploreTokens.light, bg: Color(0xFFF5F1EA)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  final ExploreTokens tokens;
  final Color bg;

  const _Pane({required this.tokens, required this.bg});

  @override
  Widget build(BuildContext context) {
    final dim = tokens.ink.withValues(alpha: 0.6);
    return ColoredBox(
      color: bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final size in const [14.0, 18.0, 28.0])
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: tokens.bubbleAgent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ContemplatingIndicator(
                  label: 'Contemplating…',
                  textColor: dim,
                  sunColor: tokens.gold,
                  fontSize: size * 0.85,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
