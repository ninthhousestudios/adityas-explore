import 'package:charts_dart/charts_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/chat_access.dart';
import '../state/chat_turn.dart';
import '../state/conversation.dart';
import 'chat_coming_soon.dart';
import 'chat_composer.dart';
import 'message_markdown.dart';
import 'tokens.dart';

/// Chat panel for the `conversation` layout mode.
///
/// Anyone can open the panel — it doubles as the layout-mode stub. The *wired*
/// chat (send + live token stream) is gated to the allowlist ([chatEnabledProvider],
/// mirroring the durable server `ai_chat_allowlist`); everyone else sees the
/// "coming soon" placeholder.
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

  const ChatPanel({
    super.key,
    required this.color,
    required this.backdropColor,
    required this.fontSize,
    this.chartData,
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

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    _stickToBottom = pos.maxScrollExtent - pos.pixels < 80;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onComposerSubmit(String text) {
    // The notifier is the single gate: it refuses a blank message, a second turn
    // while one is active, and an unavailable-entitlement send (→ TurnError).
    ref.read(chatTurnProvider.notifier).send(text);
    _scrollToEnd(force: true);
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
    final enabled = ref.watch(chatEnabledProvider);

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
          const SizedBox(height: 12),
          Expanded(
            child: enabled
                ? _conversation(color, dimColor, fontSize)
                : _placeholder(color, dimColor, fontSize),
          ),
          const SizedBox(height: 8),
          if (enabled)
            ChatComposer(
              color: color,
              dimColor: dimColor,
              fontSize: fontSize,
              onSubmit: _onComposerSubmit,
            )
          else
            _lockedComposer(dimColor, fontSize),
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
                enabled
                    ? 'Solar Prism'
                    : 'Stub — the real conversation UI lands later.',
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
      ],
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
      TurnAccessLapsed() => false,
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
    // Auto-scroll as the conversation grows or the in-flight turn streams.
    ref
      ..listen(conversationProvider, (_, _) => _scrollToEnd())
      ..listen(chatTurnProvider, (_, _) => _scrollToEnd());

    final messages = ref.watch(conversationProvider).messages;
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

    return ListView.builder(
      controller: _scroll,
      itemCount: messages.length + (active == null ? 0 : 1),
      itemBuilder: (_, i) {
        if (i < messages.length) {
          return _messageBubble(messages[i], color, fontSize);
        }
        return active!;
      },
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
        status: 'Thinking…',
      ),
      TurnStreaming(:final text) => _agentBubble(
        color,
        dimColor,
        fontSize,
        text: text,
        status: text.isEmpty ? 'Thinking…' : null,
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
      TurnIdle() || TurnDone() || TurnCancelled() => null,
    };
  }

  Widget _messageBubble(ChatMessage m, Color color, double fontSize) {
    final fromUser = m.role == MessageRole.user;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
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
      ),
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
    );
  }

  Widget _errorBubble(String message, double fontSize) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
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
      ),
    );
  }

  /// The renew prompt shown when access lapsed mid-session ([TurnAccessLapsed],
  /// adityas/ai/99). A calm, non-error notice: past turns stay readable, new
  /// turns wait until the window is renewed.
  ///
  /// PLACEHOLDER copy + no live renew CTA yet — purchase/renewal is not wired.
  /// adityas/ai/85 replaces [_renewPromptCopy] with the real launch copy and
  /// adds the purchase link right before go-live.
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
        child: Text(
          _renewPromptCopy,
          style: TextStyle(color: color, fontSize: fontSize, height: 1.4),
        ),
      ),
    );
  }

  // ── Placeholder (not allowlisted) ────────────────────────────────

  Widget _placeholder(Color color, Color dimColor, double fontSize) {
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

  Widget _lockedComposer(Color dimColor, double fontSize) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dimColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Hold something up to the Prism…',
              style: TextStyle(color: dimColor, fontSize: fontSize),
            ),
          ),
          Icon(Icons.send, size: fontSize * 1.2, color: dimColor),
        ],
      ),
    );
  }
}

/// PLACEHOLDER renew-prompt copy for the mid-session access lapse
/// ([TurnAccessLapsed], adityas/ai/99). Not final — adityas/ai/85 swaps this for
/// the real launch copy (and wires a live renew/purchase CTA) right before
/// go-live, alongside the sign-in-vs-buy gate split.
const _renewPromptCopy =
    'Your access has ended, so new messages are paused. Your past conversation '
    'stays here to read. Renew your access to continue the conversation.';

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
