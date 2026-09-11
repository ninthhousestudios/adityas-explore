import 'dart:async';

import 'package:charts_dart/charts_dart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigate.dart' if (dart.library.js_interop) '../navigate_web.dart';
import '../state/auth.dart';
import '../state/chat_turn.dart';
import '../state/consent.dart';
import '../state/conversation.dart';
import '../state/entitlement.dart';
import '../state/usage.dart';
import 'chat_coming_soon.dart';
import 'chat_composer.dart';
import 'message_markdown.dart';
import 'tokens.dart';

/// Chat panel for the `conversation` layout mode.
///
/// Anyone can open the panel — it doubles as the layout-mode stub. The *wired*
/// chat (send + live token stream, plus read-only history) is shown to anyone
/// with chat access that is not [ChatAccess.none]: a live window OR a lapsed one
/// (a former subscriber keeps read-only history + a renew-on-send prompt,
/// adityas/ai/120; the allowlist folds into "available"). The never-entitled see
/// the "coming soon" placeholder (adityas/ai/85).
///
/// The conversation and in-flight turn live in keepAlive out-of-tree providers
/// ([conversationProvider], [chatTurnProvider]) — NOT this widget's `State` — so
/// they survive the panel unmounting on a layout-mode switch or a New-Chart chart
/// swap. This widget only renders that reactive state and drives it via
/// [ChatTurnNotifier.send]. See docs/chat-state-architecture.md.
class ChatPanel extends ConsumerStatefulWidget {
  final Color color;
  final Color backdropColor;
  final double fontSize;

  /// The currently-open chart. **Reserved for adityas/ai/63** (chart_facts on the
  /// durable path): the durable turn body is message-only today, so the chart is
  /// not yet sent and answers are chart-less. Kept plumbed so ai/63 can thread it
  /// into the turn request without re-wiring the panel.
  final ChartData? chartData;

  /// Dismiss the chat surface and return to Explore mode. When null (e.g. the
  /// mobile shell, which owns its own tab switching), the close affordance is
  /// hidden.
  final VoidCallback? onExit;

  const ChatPanel({
    super.key,
    required this.color,
    required this.backdropColor,
    required this.fontSize,
    this.chartData,
    this.onExit,
  });

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _scroll = ScrollController();

  /// Whether streamed tokens should keep the view pinned to the bottom. Flipped
  /// off when the user scrolls up to read back, on again when they return near
  /// the end (or send, which re-pins via [_scrollToEnd]'s force path).
  bool _stickToBottom = true;

  /// Whether the user dismissed the current near-ceiling notice. Local + session
  /// only (adityas/ai/100): a quiet notice is non-blocking, so a dismiss just
  /// hides it; [_nearCeilingNotice] re-arms it once usage drops out of the band.
  bool _nearNoticeDismissed = false;

  /// Whether the re-consent checkbox is ticked (adityas/ai/98). Session-local: the
  /// "Agree and continue" button stays disabled until it is, mirroring the
  /// checkout block's unchecked-by-default gate.
  bool _consentChecked = false;

  /// True while the consent POST is in flight — disables the gate and shows a
  /// spinner so a double-tap can't fire two records (idempotent server-side
  /// regardless, but the UI shouldn't invite it).
  bool _agreeing = false;

  /// Tap target for the inline T&C link in the consent gate (adityas/ai/98).
  /// Opens the site terms page in a new tab so the chat session is preserved.
  /// Held on the State so its lifecycle is a clean create/dispose.
  late final TapGestureRecognizer _termsTapRecognizer = TapGestureRecognizer()
    ..onTap = () => openUrlNewTab('/chat-terms-and-conditions');

  /// Tap target for the "Send Feedback" link under the composer. Opens a mailto
  /// so users can report a bad Prism (Gemini) answer straight to us.
  late final TapGestureRecognizer _feedbackTapRecognizer =
      TapGestureRecognizer()
        ..onTap = () => openUrlNewTab(
          'mailto:hello@84beings.com?subject=Solar%20Prism%20feedback',
        );

  /// The text the panel-level polite live region currently announces
  /// (adityas/ai/143). One persistent region rather than one on the transient
  /// bubble, so the final reply can be flushed to it AFTER the streaming bubble
  /// is replaced by the committed (non-live) history bubble.
  String _liveAnnouncement = '';

  /// Coalesces streaming announcements to a human-scale cadence
  /// ([kLiveRegionCadence]) so a screen reader is not re-read the whole growing
  /// reply on every ~16ms visual repaint (adityas/ai/143). Null when idle.
  Timer? _announceTimer;

  /// The latest streamed text awaiting the next cadence tick; only the most
  /// recent survives a window.
  String? _pendingAnnouncement;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    _stickToBottom = nearBottom(pos.maxScrollExtent, pos.pixels);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _termsTapRecognizer.dispose();
    _feedbackTapRecognizer.dispose();
    _announceTimer?.cancel();
    super.dispose();
  }

  /// Drive the panel-level live region from a turn transition (adityas/ai/143).
  ///
  /// Streaming text announces on a human-scale cadence ([kLiveRegionCadence]),
  /// decoupled from the ~16ms visual repaint that grows the bubble. A terminal
  /// transition (done / cancelled) flushes the final text IMMEDIATELY — before
  /// the transient bubble is torn down — so a burst of deltas followed at once by
  /// `done` still announces the answer rather than a stale "Contemplating…".
  void _announce(ChatTurn turn) {
    if (_isAnnounceTerminal(turn)) {
      // Done / Cancelled: flush the final text at once, before the transient
      // bubble is torn down. Always drop any pending streaming tick first so a
      // stale partial can't fire after it (adityas/ai/143).
      _announceTimer?.cancel();
      _announceTimer = null;
      _pendingAnnouncement = null;
      final spoken = _spokenLabel(turn);
      if (spoken != null) _setAnnouncement(spoken);
      return;
    }
    final spoken = _spokenLabel(turn);
    if (spoken == null) {
      // Error / Idle / reset: nothing to announce, but a streaming tick may be
      // pending — cancel and clear it so a partial doesn't speak after the turn
      // ended or the conversation was reset (adityas/ai/146).
      _announceTimer?.cancel();
      _announceTimer = null;
      _pendingAnnouncement = null;
      return;
    }
    // Streaming: pace the announcement. Coalesce; the timer publishes the latest.
    _pendingAnnouncement = spoken;
    _announceTimer ??= Timer(kLiveRegionCadence, _flushAnnouncement);
  }

  void _flushAnnouncement() {
    _announceTimer = null;
    final pending = _pendingAnnouncement;
    _pendingAnnouncement = null;
    if (pending != null) _setAnnouncement(pending);
  }

  void _setAnnouncement(String value) {
    if (!mounted || value == _liveAnnouncement) return;
    setState(() => _liveAnnouncement = value);
  }

  /// The spoken form of a turn state, or null when there is nothing to announce.
  /// Terminal states carry the full/partial reply; the in-flight states carry
  /// the growing text (or a status note when no text has streamed yet).
  static String? _spokenLabel(ChatTurn turn) => switch (turn) {
    TurnConnecting() => 'Contemplating…',
    TurnStreaming(:final text) => text.isEmpty ? 'Contemplating…' : text,
    TurnReconnecting(:final text) =>
      text.isEmpty ? 'Reconnecting…' : '$text. Reconnecting…',
    TurnDone(:final text) => text.isEmpty ? null : text,
    TurnCancelled(:final text) => text.isEmpty ? null : text,
    TurnIdle() ||
    TurnError() ||
    TurnAccessLapsed() ||
    TurnCeiling() ||
    TurnConsentRequired() => null,
  };

  /// Whether this transition should flush the final text at once rather than
  /// wait for the cadence tick (adityas/ai/143). The turn is ending, so the
  /// transient bubble is about to be replaced — announce now or lose it.
  static bool _isAnnounceTerminal(ChatTurn turn) =>
      turn is TurnDone || turn is TurnCancelled;

  bool _onComposerSubmit(String text) {
    // The notifier is the single gate: it refuses a blank message, a second turn
    // while one is active, and an unavailable-entitlement send (→ TurnError). It
    // reports acceptance so the composer clears only an accepted send
    // (adityas/ai/142).
    final accepted = ref.read(chatTurnProvider.notifier).send(text);
    if (accepted) _scrollToEnd(force: true);
    return accepted;
  }

  void _scrollToEnd({bool force = false}) {
    if (!force && !_stickToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final fontSize = widget.fontSize;
    final dimColor = color.withValues(alpha: 0.6);
    // Wired surface (history + composer) for a live or lapsed window; the
    // placeholder only for the never-entitled (adityas/ai/120). A lapsed user's
    // composer stays visible — new turns are refused into the renew prompt.
    final enabled = ref.watch(chatAccessProvider) != ChatAccess.none;
    // For the never-entitled placeholder (ChatAccess.none): signed-out → sign in
    // to purchase; signed-in without access → buy Solar Prism (adityas/ai/85).
    final gate = ref.watch(authProvider) == null
        ? ChatGate.signIn
        : ChatGate.purchase;
    // Block new turns behind the re-consent gate (adityas/ai/98) when the
    // proactive GET /v1/ai/consent reports a stale version, OR a mid-session 428
    // latched the turn into [TurnConsentRequired] before that refetch lands —
    // either raises the same gate with no window where the composer is live but
    // sends are refused. History above stays read-only.
    final consentGated =
        enabled &&
        (ref.watch(consentRequiredProvider) ||
            ref.watch(chatTurnProvider) is TurnConsentRequired);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.backdropColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(color, dimColor, fontSize, enabled: enabled),
          // One persistent, zero-size polite live region for the wired surface
          // (adityas/ai/143). It carries the paced/flushed reply announcement and
          // outlives the transient streaming bubble, so the final text reaches a
          // screen reader even after the bubble is swapped for the committed
          // (non-live) history message.
          if (enabled)
            StreamingLiveRegion(
              label: _liveAnnouncement,
              child: const SizedBox.shrink(),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: enabled
                ? _conversation(color, dimColor, fontSize)
                : _placeholder(color, dimColor, fontSize, gate),
          ),
          const SizedBox(height: 8),
          // Quiet near-ceiling notice sits just above the composer so it reads as
          // an advisory, not a message in the thread (adityas/ai/100). Only the
          // wired surface polls usage — and it yields to the consent gate, which
          // owns the below-thread slot when raised.
          if (enabled && !consentGated)
            _nearCeilingNotice(color, dimColor, fontSize),
          if (!enabled)
            _gateCta(gate, fontSize)
          else if (consentGated)
            _consentGate(color, dimColor, fontSize)
          else
            ChatComposer(
              color: color,
              dimColor: dimColor,
              fontSize: fontSize,
              onSubmit: _onComposerSubmit,
            ),
          // Standard AI disclaimer + a direct feedback line under the composer,
          // shown whenever the live composer is (i.e. not locked / gated).
          if (enabled && !consentGated)
            _composerDisclaimer(color, dimColor, fontSize),
        ],
      ),
    );
  }

  Widget _header(
    Color color,
    Color dimColor,
    double fontSize, {
    required bool enabled,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                enabled ? 'Solar Prism' : 'Contemplative AI Chat',
                style: TextStyle(
                  color: dimColor,
                  fontSize: fontSize * 0.85,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        // "＋ New" rotates to a fresh thread without changing the chart — the
        // canonical New-Chat spot (docs/conversation-history.md § New Chat).
        if (enabled)
          TextButton.icon(
            onPressed: _onNewChat,
            icon: Icon(Icons.add, size: fontSize, color: color),
            label: Text(
              'New',
              style: TextStyle(color: color, fontSize: fontSize * 0.9),
            ),
            style: TextButton.styleFrom(
              foregroundColor: color,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
          ),
        // Close the chat surface and return to Explore mode. Hidden where the
        // host owns its own navigation (mobile shell passes no onExit).
        if (widget.onExit != null)
          IconButton(
            onPressed: widget.onExit,
            icon: Icon(Icons.close, size: fontSize, color: color),
            tooltip: 'Back to Explore',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            style: IconButton.styleFrom(foregroundColor: color),
          ),
      ],
    );
  }

  /// Standard "AI can make mistakes" disclaimer plus a direct "Send Feedback"
  /// mailto, sitting just under the composer. The feedback line is deliberate:
  /// we want bad Prism answers reported straight from users (adityas/ai).
  Widget _composerDisclaimer(Color color, Color dimColor, double fontSize) {
    final noteStyle = TextStyle(color: dimColor, fontSize: fontSize * 0.72);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Solar Prism is AI and can make mistakes. '),
            TextSpan(
              text: 'Send Feedback',
              style: TextStyle(
                color: color,
                decoration: TextDecoration.underline,
                decorationColor: color.withValues(alpha: 0.5),
              ),
              recognizer: _feedbackTapRecognizer,
            ),
          ],
        ),
        textAlign: TextAlign.center,
        style: noteStyle,
      ),
    );
  }

  /// New Chat: rotate to a fresh thread. If a reply is still streaming, confirm
  /// first — starting fresh stops the in-flight turn server-side (still billed),
  /// so it must never be a silent orphan (docs/conversation-history.md).
  Future<void> _onNewChat() async {
    final turn = ref.read(chatTurnProvider);
    final streaming = switch (turn) {
      TurnConnecting() || TurnStreaming() || TurnReconnecting() => true,
      TurnIdle() ||
      TurnDone() ||
      TurnCancelled() ||
      TurnError() ||
      TurnAccessLapsed() ||
      TurnCeiling() ||
      TurnConsentRequired() => false,
    };
    if (streaming) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => _NewChatConfirmDialog(),
      );
      if (proceed != true) return;
    }
    // The confirm dialog awaited above; this panel can unmount on a layout-mode
    // switch while it was open. A disposed ConsumerState's ref throws.
    if (!mounted) return;
    ref.read(chatTurnProvider.notifier).startNewConversation();
  }

  // ── Wired chat (allowlisted) ─────────────────────────────────────

  Widget _conversation(Color color, Color dimColor, double fontSize) {
    // Auto-scroll as the conversation grows or the in-flight turn streams, and
    // pace the live-region announcement off the turn transitions (adityas/ai/143).
    ref
      ..listen(conversationProvider, (_, _) => _scrollToEnd())
      ..listen(chatTurnProvider, (_, next) {
        _scrollToEnd();
        _announce(next);
      });

    final conversation = ref.watch(conversationProvider);
    final messages = conversation.messages;
    final seamIndex = compactionSeamIndex(
      messages,
      conversation.compactedThrough,
    );
    final turn = ref.watch(chatTurnProvider);
    final active = _activeTurnBubble(turn, color, dimColor, fontSize);

    if (messages.isEmpty && active == null) {
      return Center(
        child: Text(
          'Ask about the Aditya beings, your Soul Stance, or any being by name.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: dimColor,
            fontSize: fontSize * 0.9,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    // SelectionArea makes the whole transcript selectable/copyable with native
    // gestures (drag-select across bubbles, Ctrl/Cmd+C, right-click Copy, and
    // long-press on touch) — the baseline copy affordance. Per-bubble hover
    // Copy buttons (see [_MessageBubble]) layer a one-click whole-message copy
    // on top for discoverability.
    return SelectionArea(
      child: ListView.builder(
        controller: _scroll,
        itemCount: messages.length + (active == null ? 0 : 1),
        itemBuilder: (_, i) {
          if (i < messages.length) {
            final bubble = _messageBubble(messages[i], color, fontSize);
            // The compaction seam sits above the first message that post-dates
            // the watermark (adityas/ai/121) — an honesty marker, not a
            // truncation: everything above still renders in full.
            if (i == seamIndex) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_seamDivider(dimColor, fontSize), bubble],
              );
            }
            return bubble;
          }
          return active!;
        },
      ),
    );
  }

  /// The transient bubble for the turn currently in flight — a completed turn's
  /// text is already committed to [conversationProvider], so this renders only
  /// the *active* states (and a terminal error). Returns `null` when there is no
  /// active turn to show.
  Widget? _activeTurnBubble(
    ChatTurn turn,
    Color color,
    Color dimColor,
    double fontSize,
  ) {
    return switch (turn) {
      TurnConnecting() => _agentBubble(
        color,
        dimColor,
        fontSize,
        status: 'Contemplating…',
      ),
      TurnStreaming(:final text) => _agentBubble(
        color,
        dimColor,
        fontSize,
        text: text,
        status: text.isEmpty ? 'Contemplating…' : null,
      ),
      TurnReconnecting(:final text) => _agentBubble(
        color,
        dimColor,
        fontSize,
        text: text,
        status: 'Reconnecting…',
      ),
      TurnError(:final message) => _errorBubble(message, fontSize),
      // Access lapsed mid-session (adityas/ai/99): a calm renew prompt, not the
      // red error bubble — retrying is futile until the window is renewed.
      TurnAccessLapsed() => _renewBubble(color, dimColor, fontSize),
      // Usage ceiling reached (adityas/ai/100): a calm at-ceiling notice, not the
      // red error bubble — new turns wait until the window resets. No dollar or
      // token figure (the no-meter invariant).
      TurnCeiling() => _ceilingBubble(color, dimColor, fontSize),
      // Re-consent required (adityas/ai/98): no in-thread bubble — the gate
      // replaces the composer below, and the rolled-back user message means there
      // is nothing to annotate here.
      TurnConsentRequired() ||
      TurnIdle() ||
      TurnDone() ||
      TurnCancelled() => null,
    };
  }

  /// The inline honesty divider marking the compaction seam (adityas/ai/121): a
  /// thin rule with a centered, dim label. Everything above it still renders in
  /// full — this only tells the reader the model's working memory of those
  /// earlier turns was condensed.
  Widget _seamDivider(Color dimColor, double fontSize) {
    final lineColor = dimColor.withValues(alpha: 0.4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Divider(color: lineColor, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              _seamLabel,
              style: TextStyle(
                color: dimColor,
                fontSize: fontSize * 0.8,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Expanded(child: Divider(color: lineColor, height: 1)),
        ],
      ),
    );
  }

  Widget _messageBubble(ChatMessage m, Color color, double fontSize) {
    final fromUser = m.role == MessageRole.user;
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: fromUser
            ? context.tokens.bubbleUser
            : context.tokens.bubbleAgent,
        borderRadius: BorderRadius.circular(12),
      ),
      // User text renders verbatim; a completed assistant reply is markdown.
      child: fromUser
          ? Text(
              m.text,
              style: TextStyle(color: color, fontSize: fontSize),
            )
          : MessageMarkdown(
              m.text,
              style: TextStyle(color: color, fontSize: fontSize),
              linkColor: context.tokens.gold,
              isStreaming: false,
            ),
    );
    return _CopyableBubble(
      copyText: m.text,
      fromUser: fromUser,
      fontSize: fontSize,
      iconColor: color.withValues(alpha: 0.6),
      copiedColor: context.tokens.gold,
      bubble: bubble,
    );
  }

  /// The in-flight assistant bubble: streamed [text] renders plain (markdown is
  /// parsed only once the turn completes and the message lands in the list), with
  /// an optional dim/italic [status] note beneath.
  Widget _agentBubble(
    Color color,
    Color dimColor,
    double fontSize, {
    String text = '',
    String? status,
  }) {
    final hasText = text.isNotEmpty;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: context.tokens.bubbleAgent,
          borderRadius: BorderRadius.circular(12),
        ),
        // The in-flight reply is announced through the panel-level live region
        // (adityas/ai/143), which paces announcements on a human-scale cadence
        // and flushes the final text on completion. The visible bubble here is
        // excluded from semantics so it is not read a second time alongside that
        // announcement.
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasText)
                Text(
                  text,
                  style: TextStyle(color: color, fontSize: fontSize),
                ),
              if (status != null)
                Padding(
                  padding: EdgeInsets.only(top: hasText ? 4 : 0),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: dimColor,
                      fontSize: fontSize * 0.85,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBubble(String message, double fontSize) {
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: context.tokens.errorBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(color: context.tokens.error, fontSize: fontSize),
      ),
    );
    // Errors are the text a user most wants to paste into Send Feedback, so the
    // same one-click copy applies here (adityas/ai).
    return _CopyableBubble(
      copyText: message,
      fromUser: false,
      fontSize: fontSize,
      iconColor: context.tokens.error.withValues(alpha: 0.7),
      copiedColor: context.tokens.gold,
      bubble: bubble,
    );
  }

  /// The renew prompt shown when access lapsed mid-session ([TurnAccessLapsed],
  /// adityas/ai/99). A calm, non-error notice: past turns stay readable, new
  /// turns wait until the window is renewed. The "Renew Solar Prism" action opens
  /// the shop page in a new tab (adityas/ai/85); on return, the tab-visibility
  /// refetch (main.dart) resolves the renewed window without a reload.
  Widget _renewBubble(Color color, Color dimColor, double fontSize) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: context.tokens.bubbleAgent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.tokens.gold.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              chatRenewPromptCopy,
              style: TextStyle(color: color, fontSize: fontSize, height: 1.4),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => openUrlNewTab(solarPrismShopUrl),
              style: TextButton.styleFrom(
                foregroundColor: context.tokens.gold,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                chatRenewCtaLabel,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The at-ceiling notice shown when the window budget is spent ([TurnCeiling],
  /// adityas/ai/100). A calm, non-error notice — past turns stay readable, new
  /// turns wait until the window resets. Never shows a dollar or token figure
  /// (the no-meter invariant): a plain "you've reached your usage limit."
  Widget _ceilingBubble(Color color, Color dimColor, double fontSize) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: context.tokens.bubbleAgent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.tokens.gold.withValues(alpha: 0.4)),
        ),
        child: Text(
          _ceilingNoticeCopy,
          style: TextStyle(color: color, fontSize: fontSize, height: 1.4),
        ),
      ),
    );
  }

  /// The quiet near-ceiling notice (adityas/ai/100): a thin, dismissable banner
  /// shown once usage crosses the near band (adityas/ai/97's `used_pct`). Quiet
  /// and non-blocking — chat continues; a coarse percentage, never a dollar or
  /// token figure (the no-meter invariant). Returns an empty box when there is
  /// nothing to show or the user has dismissed the current climb.
  Widget _nearCeilingNotice(Color color, Color dimColor, double fontSize) {
    final pct = ref.watch(usageNearCeilingPctProvider);
    // Re-arm the dismissal once usage drops back out of the band, so a fresh
    // climb toward the ceiling notices again.
    if (pct == null) {
      _nearNoticeDismissed = false;
      return const SizedBox.shrink();
    }
    if (_nearNoticeDismissed) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.tokens.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.tokens.gold.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "You've used about $pct% of this period's limit.",
              style: TextStyle(
                color: color,
                fontSize: fontSize * 0.85,
                height: 1.3,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _nearNoticeDismissed = true),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.close, size: fontSize, color: dimColor),
            ),
          ),
        ],
      ),
    );
  }

  // ── Re-consent gate (adityas/ai/98) ──────────────────────────────

  /// The in-app re-consent gate, shown in place of the composer when the accepted
  /// T&C version is stale (proactive `GET /v1/ai/consent`) or a write route
  /// returned 428. Blocks new turns until the updated terms are agreed; the
  /// conversation above stays read-only, so declining is simply not agreeing —
  /// there is no reject action, mirroring the checkout block's single
  /// agree-to-continue affordance. Copy: ai/docs/chat-consent-copy.md →
  /// "Re-consent gate copy".
  Widget _consentGate(Color color, Color dimColor, double fontSize) {
    final gold = context.tokens.gold;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.tokens.bubbleAgent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gold.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'We’ve updated the Chat terms',
            style: TextStyle(
              color: color,
              fontSize: fontSize * 1.05,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _consentBody(color, fontSize),
          const SizedBox(height: 12),
          InkWell(
            onTap: _agreeing
                ? null
                : () => setState(() => _consentChecked = !_consentChecked),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _consentChecked
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: fontSize * 1.3,
                  color: _consentChecked ? gold : dimColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'I’ve reviewed and agree to the updated AI Chat Terms & '
                    'Conditions.',
                    style: TextStyle(
                      color: color,
                      fontSize: fontSize * 0.9,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: (_consentChecked && !_agreeing)
                  ? _onAgreeConsent
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: context.tokens.onGold,
              ),
              child: _agreeing
                  ? SizedBox(
                      width: fontSize,
                      height: fontSize,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.tokens.onGold,
                      ),
                    )
                  : const Text('Agree and continue'),
            ),
          ),
        ],
      ),
    );
  }

  /// The gate body — the re-consent sentence with the T&C phrase as an inline
  /// gold link (opens the site terms page in a new tab, preserving the session).
  Widget _consentBody(Color color, double fontSize) {
    final gold = context.tokens.gold;
    return Text.rich(
      TextSpan(
        style: TextStyle(color: color, fontSize: fontSize * 0.9, height: 1.4),
        children: [
          const TextSpan(text: 'Our '),
          TextSpan(
            text: 'AI Chat Terms & Conditions',
            style: TextStyle(
              color: gold,
              decoration: TextDecoration.underline,
              decorationColor: gold,
            ),
            recognizer: _termsTapRecognizer,
          ),
          const TextSpan(
            text:
                ' have changed since you last agreed. Please review and '
                'agree to continue chatting.',
          ),
        ],
      ),
    );
  }

  /// Record agreement, then let the consent seam refetch and clear the gate. On
  /// failure, drop the spinner and keep the gate so the user can retry (with a
  /// quiet snackbar); the checkbox stays ticked.
  Future<void> _onAgreeConsent() async {
    setState(() => _agreeing = true);
    try {
      await ref.read(consentProvider.notifier).accept();
    } catch (_) {
      if (!mounted) return;
      setState(() => _agreeing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't save that just now. Please try again."),
        ),
      );
      return;
    }
    // The consentRequiredProvider listen clears the turn latch; the gate falls
    // away when the refetch reports needs_consent = false. Reset local flags so a
    // future re-consent starts unticked.
    if (!mounted) return;
    setState(() {
      _agreeing = false;
      _consentChecked = false;
    });
  }

  // ── Placeholder (not allowlisted) ────────────────────────────────

  Widget _placeholder(
    Color color,
    Color dimColor,
    double fontSize,
    ChatGate gate,
  ) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              _staticBubble(
                'Tell me about my Soul Stance.',
                fromUser: true,
                color: color,
                fontSize: fontSize,
              ),
              _staticBubble(
                'Your Sun sits with the Aditya beings — you’re called to '
                'express your love outward in the world.',
                fromUser: false,
                color: color,
                fontSize: fontSize,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Same copy, one source — mirrors the explore-pill coming-soon modal so
        // the two gated routes never drift (docs/chat-surface.md § 3).
        ChatComingSoonMessage(
          gate: gate,
          color: color,
          dimColor: dimColor,
          fontSize: fontSize,
        ),
      ],
    );
  }

  Widget _staticBubble(
    String text, {
    required bool fromUser,
    required Color color,
    required double fontSize,
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

  /// The never-entitled gate action, in the composer slot in place of a dead
  /// look-alike field (adityas/ai/85): "Sign in" for a signed-out user (opens the
  /// in-app sign-in dialog), "Get Solar Prism" for a signed-in user without access
  /// (opens the shop page). Mirrors the pill modal's CTA so the two routes match.
  Widget _gateCta(ChatGate gate, double fontSize) {
    final tokens = context.tokens;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () => runChatGateCta(context, gate),
        style: FilledButton.styleFrom(
          backgroundColor: tokens.gold,
          foregroundColor: tokens.onGold,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(ChatComingSoon.ctaFor(gate)),
      ),
    );
  }
}

/// A transcript bubble ([bubble]) with a hover-reveal one-click Copy button.
///
/// Copy affordance is two-layered: the enclosing [SelectionArea] handles native
/// select + copy (partial and cross-message), while this button is the
/// discoverable "copy the whole thing" — it puts [copyText] on the clipboard
/// (the raw markdown source for an assistant reply, the full text for an error).
/// Hover-only, so it is a desktop nicety; touch users copy via the long-press
/// selection through the [SelectionArea]. [fromUser] drives alignment and which
/// side the button sits on (inner edge of the bubble).
class _CopyableBubble extends StatefulWidget {
  const _CopyableBubble({
    required this.bubble,
    required this.copyText,
    required this.fromUser,
    required this.fontSize,
    required this.iconColor,
    required this.copiedColor,
  });

  final Widget bubble;
  final String copyText;
  final bool fromUser;
  final double fontSize;

  /// Idle icon tint (dimmed message/error colour).
  final Color iconColor;

  /// Tint for the brief post-copy checkmark (brand gold).
  final Color copiedColor;

  @override
  State<_CopyableBubble> createState() => _CopyableBubbleState();
}

class _CopyableBubbleState extends State<_CopyableBubble> {
  bool _hovering = false;
  bool _copied = false;
  Timer? _copiedReset;

  @override
  void dispose() {
    _copiedReset?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.copyText));
    setState(() => _copied = true);
    _copiedReset?.cancel();
    _copiedReset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fromUser = widget.fromUser;
    // The button sits on the bubble's inner side (left of a user bubble, right
    // of an agent bubble). Kept laid out at all times and only faded in, so it
    // never shifts the bubble as the pointer enters/leaves.
    final copyButton = AnimatedOpacity(
      opacity: _hovering || _copied ? 1 : 0,
      duration: const Duration(milliseconds: 120),
      child: IconButton(
        onPressed: _copy,
        tooltip: _copied ? 'Copied' : 'Copy',
        iconSize: widget.fontSize,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(),
        icon: Icon(
          _copied ? Icons.check : Icons.copy_outlined,
          color: _copied ? widget.copiedColor : widget.iconColor,
        ),
      ),
    );

    // The bubble is Flexible so a wide message (which reaches its own 320 max)
    // yields space to the button instead of overflowing the panel edge.
    final flexBubble = Flexible(child: widget.bubble);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: fromUser ? [copyButton, flexBubble] : [flexBubble, copyButton],
    );

    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: row,
        ),
      ),
    );
  }
}

/// Index of the first message rendered *after* the compaction seam — the first
/// whose server time is later than [compactedThrough] (adityas/ai/121). The
/// divider is drawn immediately above that message: everything above it was
/// condensed in the model's prompt (though still shown in full here).
///
/// Returns `null` only when there is nothing to disclose — no watermark, or no
/// message post-dates it. When the *first* message already post-dates the
/// watermark (index 0) the divider still renders at the very top: the condensed
/// content sits above the whole transcript, and hiding the marker there would
/// suppress the honesty disclosure exactly when it matters (adityas/ai/133).
/// Live-appended messages carry a null `createdAt` and always land below a
/// resumed seam, so they never match.
int? compactionSeamIndex(
  List<ChatMessage> messages,
  DateTime? compactedThrough,
) {
  if (compactedThrough == null) return null;
  for (var i = 0; i < messages.length; i++) {
    final createdAt = messages[i].createdAt;
    if (createdAt != null && createdAt.isAfter(compactedThrough)) {
      return i;
    }
  }
  return null;
}

/// The compaction-seam divider label (adityas/ai/121). Plain, honest system
/// voice — no jargon ("compaction", "tokens"): the reader only needs to know the
/// older turns above were condensed to keep the conversation focused. Mirrors the
/// backend contract's own suggested marker text (adityas/ai/119).
const _seamLabel = 'Earlier messages condensed to keep this focused';

/// How often the panel-level live region may re-announce the growing reply
/// (adityas/ai/143). A human-scale cadence, deliberately decoupled from the
/// ~16ms visual delta throttle (lib/state/delta_throttle.dart): re-reading the
/// whole growing label every visual repaint is screen-reader-hostile. Terminal
/// (done/cancelled) text bypasses this and flushes at once so the final answer
/// is never dropped.
const Duration kLiveRegionCadence = Duration(seconds: 2);

/// A polite ARIA live region for the streaming assistant reply (adityas/ai/138,
/// cadence reworked in adityas/ai/143).
///
/// Flutter's [Semantics.liveRegion] maps to `aria-live="polite"` on web and
/// re-announces when the node's [label] changes. The chat panel mounts a single
/// persistent instance (not one per bubble) and drives its [label] on a
/// human-scale cadence ([kLiveRegionCadence]), flushing the final text on
/// completion — so the answer is announced even after the transient streaming
/// bubble is replaced by the committed history message. The visible [child] is
/// wrapped in [ExcludeSemantics] so the announcement is this one [label] rather
/// than a duplicate read of any descendant Text.
class StreamingLiveRegion extends StatelessWidget {
  final String label;
  final Widget child;

  const StreamingLiveRegion({
    super.key,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      label: label,
      child: ExcludeSemantics(child: child),
    );
  }
}

/// Distance from the bottom, in logical px, within which the chat view is
/// treated as "at the end" and keeps auto-pinning to new content (adityas/ai/29).
/// A small band, not zero, so a stream that overshoots the exact extent by a
/// pixel or two still counts as stuck.
const double kStickToBottomThreshold = 80;

/// Whether the scroll position is close enough to the bottom to keep sticking to
/// it as messages arrive or tokens stream. [_ChatPanelState._onScroll] flips its
/// stick flag from this; [_ChatPanelState._scrollToEnd] honours it (force aside).
/// Pure so the sticky/read-back boundary is unit-testable without a scroll view.
bool nearBottom(double maxScrollExtent, double pixels) =>
    maxScrollExtent - pixels < kStickToBottomThreshold;

/// The at-ceiling notice for a spent usage window ([TurnCeiling], adityas/ai/100).
/// Mirrors the 402 body's human message; deliberately carries no dollar or token
/// figure (the no-meter invariant) — a coarse "usage limit for this period."
///
/// The limit is per 30-day period of access. The reset line is phrased
/// conditionally on purpose: a subscription rolls into a fresh period each month,
/// but a one-time month simply ends (no renew), so it must not *promise* a reset
/// the client can't guarantee — the entitlement model carries only `access_until`,
/// not the plan type, so this copy can't branch on it.
const _ceilingNoticeCopy =
    "You've reached your usage limit for this period, so new messages are "
    'paused. Your past conversation stays here to read. If your access '
    'continues into a new 30-day period, your limit resets then.';

/// Confirm starting a new chat while a reply is still streaming — the current
/// turn is stopped server-side (still billed), never silently orphaned.
class _NewChatConfirmDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.ink;

    return AlertDialog(
      backgroundColor: t.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      title: Text(
        'Start a new chat?',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
      content: Text(
        'A reply is still coming in. Starting a new chat stops it.',
        style: TextStyle(color: color.withValues(alpha: 0.85), height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Keep chatting',
            style: TextStyle(color: color.withValues(alpha: 0.7)),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: t.gold,
            foregroundColor: t.onGold,
          ),
          child: const Text('New chat'),
        ),
      ],
    );
  }
}
