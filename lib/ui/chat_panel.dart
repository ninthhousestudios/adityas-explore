import 'dart:async';

import 'package:charts_dart/charts_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/solar_mirror_client.dart';

/// Chat panel for the `conversation` layout mode.
///
/// Anyone can open the panel — it doubles as the layout-mode stub. The *wired*
/// chat (send + live token stream) is gated to the skeleton allowlist
/// ([chatEnabledProvider]); everyone else sees the "coming soon" placeholder.
///
/// Throwaway walking-skeleton client (adityas/ai/4): plain-text streaming over
/// the two-call SSE path, local state, no history persistence — closing the
/// panel discards the conversation. See docs/layout-modes.md.
class ChatPanel extends ConsumerStatefulWidget {
  final Color color;
  final Color backdropColor;
  final double fontSize;

  /// The currently-open chart, whose birth data rides along with each turn so
  /// the model can speak about *this* chart's activated beings. Null → the turn
  /// still sends, chart-less (backend yields `chart_facts` 'unavailable').
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

class _ChatMessage {
  _ChatMessage({required this.fromUser, String text = ''})
    : _buffer = StringBuffer(text);

  final bool fromUser;
  final StringBuffer _buffer;
  bool isError = false;

  /// A transient note shown dim/italic under the text ("Thinking…", a tool
  /// lookup) — cleared once real text arrives or the turn ends.
  String? status;

  String get text => _buffer.toString();
  void append(String s) => _buffer.write(s);
  set text(String s) => _buffer
    ..clear()
    ..write(s);
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatMessage>[];

  /// Accepted for URL parity by the backend but unused (no persistence yet).
  final _conversationId = 'explore-${DateTime.now().millisecondsSinceEpoch}';

  StreamSubscription<ChatEvent>? _sub;
  bool _streaming = false;

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
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _streaming) return;
    _input.clear();

    final assistant = _ChatMessage(fromUser: false)..status = 'Thinking…';
    setState(() {
      _messages
        ..add(_ChatMessage(fromUser: true, text: text))
        ..add(assistant);
      _streaming = true;
    });
    _scrollToEnd(force: true);

    final client = ref.read(solarMirrorClientProvider);
    try {
      final turnId = await client.createTurn(
        conversationId: _conversationId,
        message: text,
        chart: widget.chartData,
      );
      _sub = client
          .streamTurn(turnId)
          .listen(
            (event) => _onEvent(assistant, event),
            onError: (Object e) => _fail(assistant, e.toString()),
            onDone: () {
              if (mounted) setState(() => _streaming = false);
            },
            cancelOnError: true,
          );
    } catch (e) {
      _fail(assistant, e.toString());
    }
  }

  void _onEvent(_ChatMessage assistant, ChatEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event) {
        case ChatDelta(:final text):
          assistant.status = null;
          assistant.append(text);
        case ChatToolStart(:final name):
          assistant.status = _toolNote(name);
        case ChatToolEnd():
          assistant.status = assistant.text.isEmpty ? 'Thinking…' : null;
        case ChatError(:final message):
          _markError(assistant, message);
        case ChatDone():
          _streaming = false;
      }
    });
    _scrollToEnd();
  }

  void _fail(_ChatMessage assistant, String message) {
    if (!mounted) return;
    setState(() {
      _markError(assistant, message);
      _streaming = false;
    });
  }

  void _markError(_ChatMessage assistant, String message) {
    assistant
      ..status = null
      ..isError = true;
    if (assistant.text.isEmpty) {
      assistant.text = message;
    } else {
      assistant.append('\n\n[$message]');
    }
  }

  String _toolNote(String tool) =>
      tool == 'get_being' ? 'Consulting the beings…' : 'Working ($tool)…';

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
              ? 'Solar Prism — skeleton streaming client'
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
    if (_messages.isEmpty) {
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
      itemCount: _messages.length,
      itemBuilder: (_, i) => _bubble(_messages[i], color, dimColor, fontSize),
    );
  }

  Widget _bubble(_ChatMessage m, Color color, Color dimColor, double fontSize) {
    final hasText = m.text.isNotEmpty;
    final textColor = m.isError ? const Color(0xFFE57373) : color;
    return Align(
      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: m.isError
              ? const Color(0x33E57373)
              : color.withValues(alpha: m.fromUser ? 0.15 : 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasText)
              Text(
                m.text,
                style: TextStyle(color: textColor, fontSize: fontSize),
              ),
            if (m.status != null)
              Padding(
                padding: EdgeInsets.only(top: hasText ? 4 : 0),
                child: Text(
                  m.status!,
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

  Widget _composer(Color color, Color dimColor, double fontSize) {
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
          onPressed: _streaming ? null : _send,
          icon: Icon(
            Icons.send,
            size: fontSize * 1.2,
            color: _streaming ? dimColor : color,
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
