import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/auth.dart';
import '../state/chat_turn.dart';
import '../state/consent.dart';
import '../state/entitlement.dart';
import 'chat_coming_soon.dart';
import 'chat_composer.dart';

/// The explore-mode chat entrance: a composer-only pill docked bottom-right
/// (no message history over the chart — history belongs to the panel). Visible
/// to everyone so the feature is discoverable; behaviour forks on entitlement
/// (docs/chat-surface.md § 1, § 3).
///
/// - **Entitled, no gate** — a real [ChatComposer]. Submitting ramps into
///   conversation mode ([onSubmit], wired by the chart wheel) and sends.
/// - **Entitled, re-consent gated** — a look-alike that ramps into conversation
///   mode ([onConsentGate]) so the gate (which lives in the panel, replacing the
///   composer) can be shown. Gate on the tap, not on send: were this a live
///   composer, a whole typed paragraph would vanish the instant Send ramped away
///   to the gate (adityas/ai/98).
/// - **Not entitled** — a look-alike button (no focus, no typing) that opens a
///   centered modal on tap: the coming-soon/buy modal for a never-entitled user,
///   or the renew modal for a former subscriber who still has archived
///   conversations (adityas/ai/183).
///
/// Across all three the rule is one and the same: focus-to-trigger, not
/// submit-to-reject — the user never types into a dead end.
class ChatPill extends ConsumerWidget {
  final Color color;
  final Color dimColor;
  final Color backdropColor;
  final double fontSize;

  /// Invoked with the submitted text when an entitled user sends from the pill.
  /// Returns whether the send was accepted so the composer clears only then
  /// (adityas/ai/142).
  final bool Function(String) onSubmit;

  /// Invoked when an entitled-but-re-consent-gated user taps the pill: ramp into
  /// conversation mode so the panel raises the gate (adityas/ai/98).
  final VoidCallback onConsentGate;

  const ChatPill({
    super.key,
    required this.color,
    required this.dimColor,
    required this.backdropColor,
    required this.fontSize,
    required this.onSubmit,
    required this.onConsentGate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reachable to anyone with chat history — a live window OR a lapsed one
    // (read-only history + renew-on-send, adityas/ai/120). A never-entitled user
    // gets the look-alike → coming-soon/buy modal (adityas/ai/85); a former
    // subscriber whose window is gone gets the renew modal instead (below).
    final access = ref.watch(chatAccessProvider);
    final enabled =
        access == ChatAccess.available || access == ChatAccess.lapsed;
    // A signed-in former subscriber whose window is gone (→ none) but who owns
    // chat history opens the *renew* modal, not the buy modal — mirroring the
    // panel (adityas/ai/183) and the picker's "Renew to resume" (ai/181). History
    // is an in-session transcript OR archived conversations, and an archive-check
    // error reads as history; [chatAccessFork] holds the shared derivation so the
    // pill and panel cannot drift (adityas/42). [pending] (unresolved entitlement,
    // adityas/ai/194, or an in-flight archive check) keeps the look-alike inert so
    // no modal opens before the fork settles.
    final fork = chatAccessFork(ref, access);
    final renew = fork.renew;
    final pending = fork.pending;
    // Mirror the panel's gate (chat_panel.dart): a proactive GET that found the
    // T&C version stale, or a mid-session 428 latched into TurnConsentRequired
    // before that refetch lands. `.select` so a live turn's every delta does not
    // rebuild the pill — only a flip of the consent-required bit does.
    final consentGated =
        enabled &&
        (ref.watch(consentRequiredProvider) ||
            ref.watch(
              chatTurnProvider.select((t) => t is TurnConsentRequired),
            ));
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: backdropColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: enabled && !consentGated
          ? ChatComposer(
              color: color,
              dimColor: dimColor,
              fontSize: fontSize,
              onSubmit: onSubmit,
            )
          : _lookAlike(
              // Consent-gated: ramp to conversation so the panel shows the gate.
              // Pending: inert — entitlement still resolving, so no modal at all.
              // Otherwise never-entitled: open the coming-soon modal.
              onTap: consentGated
                  ? onConsentGate
                  : pending
                  ? null
                  // Former subscriber with history → renew modal (adityas/ai/183).
                  : renew
                  ? () => showChatRenewModal(context)
                  // Signed-out → sign in to purchase; signed-in without access →
                  // buy Solar Prism (adityas/ai/85). The gate splits on auth.
                  : () => showChatComingSoonModal(
                      context,
                      signedIn: ref.read(authProvider) != null,
                    ),
            ),
    );
  }

  /// A composer look-alike: the field's chrome without a real input, running
  /// [onTap] on tap. Used for the never-entitled (opens the coming-soon modal)
  /// and the re-consent-gated (ramps to the gate) — neither should be typeable.
  Widget _lookAlike({required VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
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
