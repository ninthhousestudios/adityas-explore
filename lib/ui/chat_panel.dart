import 'package:flutter/material.dart';

/// Stub chat panel for the `conversation` layout mode.
///
/// Placeholder only — it exists to prove the mode transition (chart reflow +
/// docked column). The real chat UI is a later feature; nothing here is wired
/// up. See docs/layout-modes.md.
class ChatPanel extends StatelessWidget {
  final Color color;
  final Color backdropColor;
  final double fontSize;

  const ChatPanel({
    super.key,
    required this.color,
    required this.backdropColor,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final dimColor = color.withValues(alpha: 0.6);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backdropColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Chat',
            style: TextStyle(
              color: color,
              fontSize: fontSize * 1.2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Stub — the real conversation UI lands later.',
            style: TextStyle(
              color: dimColor,
              fontSize: fontSize * 0.85,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                _bubble(
                  'Tell me about my Soul Stance.',
                  fromUser: true,
                  dimColor: dimColor,
                ),
                _bubble(
                  'Your Sun sits with the Aditya beings — you’re called '
                  'to express your love outward in the world.',
                  fromUser: false,
                  dimColor: dimColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Ask about your chart…',
                    style: TextStyle(color: dimColor, fontSize: fontSize),
                  ),
                ),
                Icon(Icons.send, size: fontSize * 1.2, color: dimColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(
    String text, {
    required bool fromUser,
    required Color dimColor,
  }) {
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: color.withValues(alpha: fromUser ? 0.15 : 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: fontSize),
        ),
      ),
    );
  }
}
