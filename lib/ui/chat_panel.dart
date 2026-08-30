import 'package:charts_dart/charts_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/chat_access.dart';
import '../state/chat_turn.dart';
import '../state/conversation.dart';
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
  final _input = TextEditingController();
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
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    // The notifier is the single gate: it refuses a blank message, a second turn
    // while one is active, and an unavailable-entitlement send (→ TurnError).
    ref.read(chatTurnProvider.notifier).send(text);
    _input.clear();
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
            _composer(color, dimColor, fontSize)
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
    return Column(
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
    );
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

  Widget _composer(Color color, Color dimColor, double fontSize) {
    final turn = ref.watch(chatTurnProvider);
    final active = switch (turn) {
      TurnConnecting() || TurnStreaming() || TurnReconnecting() => true,
      TurnIdle() || TurnDone() || TurnCancelled() || TurnError() => false,
    };
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
    );
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            onSubmitted: (_) => _send(),
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            style: TextStyle(color: color, fontSize: fontSize),
            cursorColor: color,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Hold something up to the Prism…',
              hintStyle: TextStyle(color: dimColor, fontSize: fontSize),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: border,
              enabledBorder: border,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: color.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: active ? null : _send,
          icon: Icon(
            Icons.send,
            size: fontSize * 1.2,
            color: active ? dimColor : color,
          ),
        ),
      ],
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
        Text(
          'Contemplative AI chat coming soon…',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: dimColor,
            fontSize: fontSize * 0.85,
            fontStyle: FontStyle.italic,
          ),
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
