import 'package:flutter/material.dart';

import 'tokens.dart';

/// The single source of the Solar Prism "coming soon" copy, shared by the two
/// routes a not-yet-entitled user can reach it (docs/chat-surface.md § 3):
///
/// - tapping the explore-mode pill → [showChatComingSoonModal];
/// - the settings → Mode → Chat back-door → the conversation panel placeholder.
///
/// Both render [ChatComingSoonMessage], so entitlement's presentation can't
/// drift between the two. Purchase is not live, so logged-out and
/// logged-in-without-entitlement collapse into this one message today; it splits
/// into sign-in vs. buy at launch (gates adityas/ai/74).
class ChatComingSoon {
  const ChatComingSoon._();

  static const title = 'Solar Prism';
  static const tagline = 'Contemplative AI Chat';
  static const body =
      'Ask about the Aditya beings, your Soul Stance, or any being by name — a '
      'contemplative conversation grounded in your chart. Coming soon.';
}

/// The shared tagline + description block. Rendered by both the pill modal and
/// the panel placeholder so the message stays identical on both routes.
class ChatComingSoonMessage extends StatelessWidget {
  final Color color;
  final Color dimColor;
  final double fontSize;

  const ChatComingSoonMessage({
    super.key,
    required this.color,
    required this.dimColor,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          ChatComingSoon.tagline,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          ChatComingSoon.body,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: dimColor,
            fontSize: fontSize * 0.9,
            fontStyle: FontStyle.italic,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// Centered "coming soon" modal shown when a non-entitled user taps the
/// explore-mode chat pill: a focused interruption, dismiss to return. Not a
/// draggable transient popup — see docs/chat-surface.md § 3.
Future<void> showChatComingSoonModal(BuildContext context) {
  final tokens = context.tokens;
  return _showChatAccessModal(
    context,
    title: ChatComingSoon.title,
    body: ChatComingSoonMessage(
      color: tokens.ink,
      dimColor: tokens.ink.withValues(alpha: 0.6),
      fontSize: 15,
    ),
  );
}

/// Centered renew modal shown when a *lapsed* user sends from the explore-mode
/// pill (adityas/ai/120). Same focused-interruption chrome as the coming-soon
/// modal — Explore has no thread to host the in-panel renew bubble the
/// conversation surface shows, so a former subscriber who types into the pill
/// gets this informing popup rather than a dead Send button.
///
/// PLACEHOLDER copy + no live renew CTA yet, exactly like the panel's renew
/// bubble: adityas/ai/85 swaps [chatRenewPromptCopy] for the launch copy and
/// wires the real renew/purchase action right before go-live.
Future<void> showChatRenewModal(BuildContext context) {
  final tokens = context.tokens;
  return _showChatAccessModal(
    context,
    title: 'Renew your access',
    body: Text(
      chatRenewPromptCopy,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: tokens.ink.withValues(alpha: 0.6),
        fontSize: 15 * 0.9,
        height: 1.4,
      ),
    ),
  );
}

/// The shared chrome for the two centered chat-access modals (coming-soon and
/// renew): a gold [title], a [body] block, and a Close action. One shell so the
/// two gates can't drift in look, only in copy (docs/chat-surface.md § 3).
Future<void> _showChatAccessModal(
  BuildContext context, {
  required String title,
  required Widget body,
}) {
  final tokens = context.tokens;
  final color = tokens.ink;
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: tokens.wheelBackdrop,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.gold,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                body,
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: color),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// PLACEHOLDER renew-prompt copy for a lapsed former subscriber
/// ([TurnAccessLapsed], adityas/ai/99, ai/120). Shared by the conversation
/// panel's in-thread renew bubble and the explore-mode renew modal so the two
/// never drift. Not final — adityas/ai/85 swaps this for the launch copy (and
/// wires a live renew/purchase CTA) right before go-live.
const chatRenewPromptCopy =
    'Your access has ended, so new messages are paused. Your past conversation '
    'stays here to read. Renew your access to continue the conversation.';
