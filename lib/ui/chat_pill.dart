import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/chat_access.dart';
import 'chat_coming_soon.dart';
import 'chat_composer.dart';

/// The explore-mode chat entrance: a composer-only pill docked bottom-right
/// (no message history over the chart — history belongs to the panel). Visible
/// to everyone so the feature is discoverable; behaviour forks on entitlement
/// (docs/chat-surface.md § 1, § 3).
///
/// - **Entitled** — a real [ChatComposer]. Submitting ramps into conversation
///   mode ([onSubmit], wired by the chart wheel) and sends.
/// - **Not entitled** — a look-alike button (no focus, no typing) that opens the
///   centered coming-soon modal on tap. Focus-to-trigger, not
///   submit-to-reject: the user never types into a dead end.
class ChatPill extends ConsumerWidget {
  final Color color;
  final Color dimColor;
  final Color backdropColor;
  final double fontSize;

  /// Invoked with the submitted text when an entitled user sends from the pill.
  final ValueChanged<String> onSubmit;

  const ChatPill({
    super.key,
    required this.color,
    required this.dimColor,
    required this.backdropColor,
    required this.fontSize,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(chatEnabledProvider);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: backdropColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: enabled
          ? ChatComposer(
              color: color,
              dimColor: dimColor,
              fontSize: fontSize,
              onSubmit: onSubmit,
            )
          : _lookAlike(context),
    );
  }

  /// A composer look-alike for a non-entitled user: the field's chrome without a
  /// real input, opening the coming-soon modal on tap.
  Widget _lookAlike(BuildContext context) {
    return InkWell(
      onTap: () => showChatComingSoonModal(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: dimColor.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                chatComposerHint,
                style: TextStyle(color: dimColor, fontSize: fontSize),
              ),
            ),
            Icon(Icons.send, size: fontSize * 1.2, color: dimColor),
          ],
        ),
      ),
    );
  }
}
