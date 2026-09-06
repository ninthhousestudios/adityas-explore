import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/chat_turn.dart';

/// The Prism input prompt, shared by both surfaces that carry a live composer:
/// the docked [ChatPanel] (conversation mode) and the explore-mode chat pill.
/// One string source so the two never drift.
const chatComposerHint = 'Hold something up to the Prism…';

/// The chat input field + send button, extracted so the docked panel and the
/// explore-mode pill share one input implementation (adityas/ai/81).
///
/// Owns its own [TextEditingController] and clears on submit. The send button is
/// disabled while a turn is in flight ([chatTurnProvider]); the caller decides
/// what a submit *does* via [onSubmit] — the panel sends into the open
/// conversation, the pill ramps into conversation mode first (see
/// docs/chat-surface.md § 1).
class ChatComposer extends ConsumerStatefulWidget {
  final Color color;
  final Color dimColor;
  final double fontSize;

  /// Called with the trimmed, non-empty text on submit (Enter or the send
  /// button). The composer clears itself immediately after invoking this.
  final ValueChanged<String> onSubmit;

  const ChatComposer({
    super.key,
    required this.color,
    required this.dimColor,
    required this.fontSize,
    required this.onSubmit,
  });

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
    _input.clear();
  }

  /// Enter sends; Shift+Enter (or Alt+Enter) inserts a newline.
  ///
  /// Handled on an ancestor [Focus] whose `onKeyEvent` fires *before* Flutter's
  /// `DefaultTextEditingShortcuts` (which sit near the app root, above this
  /// node), so returning `handled` for plain Enter suppresses the default
  /// newline. Rather than relying on the platform default for the modifier
  /// case, we insert the newline ourselves — deterministic across web/desktop
  /// (docs/chat-surface.md § keyboard). Repeats and key-up are ignored so a held
  /// Enter fires a single send.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isEnter =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed || keyboard.isAltPressed) {
      _insertNewline();
      return KeyEventResult.handled;
    }
    _submit();
    return KeyEventResult.handled;
  }

  /// Insert a newline at the caret (replacing any selection) and advance the
  /// caret past it. Explicit so the modifier-newline behaviour does not depend
  /// on platform default shortcut maps.
  void _insertNewline() {
    final value = _input.value;
    final sel = value.selection;
    if (!sel.isValid) {
      final text = '${value.text}\n';
      _input.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      return;
    }
    final text = '${sel.textBefore(value.text)}\n${sel.textAfter(value.text)}';
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: sel.start + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final dimColor = widget.dimColor;
    final fontSize = widget.fontSize;
    final turn = ref.watch(chatTurnProvider);
    final active = switch (turn) {
      TurnConnecting() || TurnStreaming() || TurnReconnecting() => true,
      TurnIdle() ||
      TurnDone() ||
      TurnCancelled() ||
      TurnError() ||
      TurnAccessLapsed() => false,
    };
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
    );
    return Row(
      children: [
        Expanded(
          child: Focus(
            skipTraversal: true,
            onKeyEvent: _onKeyEvent,
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: TextStyle(color: color, fontSize: fontSize),
              cursorColor: color,
              decoration: InputDecoration(
                isDense: true,
                hintText: chatComposerHint,
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
        ),
        IconButton(
          onPressed: active ? null : _submit,
          icon: Icon(
            Icons.send,
            size: fontSize * 1.2,
            color: active ? dimColor : color,
          ),
        ),
      ],
    );
  }
}
