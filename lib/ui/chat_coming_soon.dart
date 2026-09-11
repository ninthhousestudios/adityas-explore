import 'package:flutter/material.dart';

import '../navigate.dart' if (dart.library.js_interop) '../navigate_web.dart';
import 'sign_in_dialog.dart';
import 'tokens.dart';

/// The Solar Prism product page — the one destination for buying or renewing
/// access. Explore never runs checkout itself (no business logic on the client,
/// per adityas security): every buy/renew CTA opens this page in a new tab, where
/// sign-in, pricing, and Stripe all live. On return, the entitlement gate
/// refreshes via the tab-visibility signal (adityas/ai/85, main.dart).
const solarPrismShopUrl = 'https://84beings.com/shop/solar-prism';

/// Label for the buy/renew action button, shared by the renew modal and the
/// in-thread renew bubble so the two never drift.
const chatRenewCtaLabel = 'Renew Solar Prism';

/// Which of the two gated states a not-yet-entitled user is in (adityas/ai/85).
/// Derives the copy and the CTA: [signIn] for a signed-out visitor (sign-in is
/// the first step toward buying), [purchase] for a signed-in user who has no
/// live access (one step left — buy it).
enum ChatGate { signIn, purchase }

/// Runs the CTA for [gate]: opens the in-app sign-in dialog for [ChatGate.signIn]
/// (a signed-out visitor stays in Explore, and on sign-in the entitlement refetch
/// re-renders this surface into the [ChatGate.purchase] state), or the Solar Prism
/// shop page for [ChatGate.purchase]. Callers inside a modal pop it first; the
/// inline panel CTA calls this directly.
void runChatGateCta(BuildContext context, ChatGate gate) {
  switch (gate) {
    case ChatGate.signIn:
      showSignInDialog(context);
    case ChatGate.purchase:
      openUrlNewTab(solarPrismShopUrl);
  }
}

/// The Solar Prism gate copy, shared by the two routes a not-yet-entitled user
/// can reach it (docs/chat-surface.md § 3):
///
/// - tapping the explore-mode pill → [showChatComingSoonModal];
/// - the settings → Mode → Chat back-door → the conversation panel placeholder.
///
/// Both render [ChatComingSoonMessage], so entitlement's presentation can't drift
/// between the two. The single "coming soon" message split at launch into the two
/// real states (adityas/ai/85): signed-out → sign in to purchase; signed-in
/// without access → buy Solar Prism.
class ChatComingSoon {
  const ChatComingSoon._();

  static const title = 'Solar Prism';
  static const tagline = 'Contemplative AI Chat';

  static const _lead =
      'A contemplative conversation grounded in your chart — ask about the '
      'Aditya beings, your Soul Stance, or any being by name.';

  /// Signed out: sign-in is a prerequisite to purchase, not the unlock itself —
  /// the copy says so plainly rather than implying signing in grants access.
  static const signInBody =
      '$_lead Sign in to your account to purchase Solar Prism.';

  /// Signed in without access: one step left.
  static const purchaseBody = '$_lead Unlock Solar Prism to begin.';

  static String bodyFor(ChatGate gate) =>
      gate == ChatGate.signIn ? signInBody : purchaseBody;

  static String ctaFor(ChatGate gate) =>
      gate == ChatGate.signIn ? 'Sign in' : 'Get Solar Prism';
}

/// The shared tagline + description block. Rendered by both the pill modal and
/// the panel placeholder so the message stays identical on both routes; [gate]
/// selects the signed-out vs. no-access wording.
class ChatComingSoonMessage extends StatelessWidget {
  final ChatGate gate;
  final Color color;
  final Color dimColor;
  final double fontSize;

  const ChatComingSoonMessage({
    super.key,
    required this.gate,
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
          ChatComingSoon.bodyFor(gate),
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

/// Centered gate modal shown when a non-entitled user taps the explore-mode chat
/// pill: a focused interruption, dismiss to return. Not a draggable transient
/// popup — see docs/chat-surface.md § 3. [signedIn] selects the sign-in vs. buy
/// state and its CTA (adityas/ai/85).
Future<void> showChatComingSoonModal(
  BuildContext context, {
  required bool signedIn,
}) {
  final tokens = context.tokens;
  final gate = signedIn ? ChatGate.purchase : ChatGate.signIn;
  return _showChatAccessModal(
    context,
    title: ChatComingSoon.title,
    body: ChatComingSoonMessage(
      gate: gate,
      color: tokens.ink,
      dimColor: tokens.ink.withValues(alpha: 0.6),
      fontSize: 15,
    ),
    ctaLabel: ChatComingSoon.ctaFor(gate),
    onCta: () => runChatGateCta(context, gate),
  );
}

/// Centered renew modal shown when a *lapsed* user sends from the explore-mode
/// pill (adityas/ai/120) or picks "Renew to resume" in the Conversations picker
/// (adityas/ai/181). Same focused-interruption chrome as the coming-soon modal —
/// Explore has no thread to host the in-panel renew bubble the conversation
/// surface shows, so a former subscriber gets this informing popup with a live
/// renew CTA rather than a dead Send button.
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
    ctaLabel: chatRenewCtaLabel,
    onCta: () => openUrlNewTab(solarPrismShopUrl),
  );
}

/// The shared chrome for the two centered chat-access modals (coming-soon and
/// renew): a gold [title], a [body] block, an optional primary CTA, and a Close
/// action. One shell so the two gates can't drift in look, only in copy
/// (docs/chat-surface.md § 3). When [ctaLabel]/[onCta] are given, tapping the CTA
/// dismisses the modal and then runs the action (open the sign-in dialog, or the
/// shop page in a new tab).
Future<void> _showChatAccessModal(
  BuildContext context, {
  required String title,
  required Widget body,
  String? ctaLabel,
  VoidCallback? onCta,
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
                if (ctaLabel != null && onCta != null)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onCta();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: tokens.gold,
                        foregroundColor: tokens.onGold,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(ctaLabel),
                    ),
                  ),
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

/// The renew-prompt copy for a lapsed former subscriber ([TurnAccessLapsed],
/// adityas/ai/99, ai/120). Shared by the conversation panel's in-thread renew
/// bubble and the explore-mode renew modal so the two never drift; both pair it
/// with a live [chatRenewCtaLabel] CTA to the shop page (adityas/ai/85).
const chatRenewPromptCopy =
    'Your access has ended, so new messages are paused. Your past conversation '
    'stays here to read. Renew to continue the conversation.';
