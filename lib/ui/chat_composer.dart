import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/chat_turn.dart';

/// The Prism input prompt, shared by both surfaces that carry a live composer:
/// the docked [ChatPanel] (conversation mode) and the explore-mode chat pill.
/// One string source so the two never drift.
const chatComposerHint = 'Hold something up to the Prism…';

/// Max turn message length, in Unicode scalar values (runes). Mirrors backend
/// `MAX_MESSAGE_CHARS` in `backend/server/src/routes/chat.rs`, which counts with
/// Rust `str::chars().count()` — scalars, not grapheme clusters — so change the
/// two together. The server cap is the enforcement; this is UX only
/// (adityas/ai/221).
const maxChatMessageRunes = 8000;

/// The counter appears only once the input reaches this many runes (90% of
/// the cap) — no always-on "0/8000".
const _counterThresholdRunes = maxChatMessageRunes * 9 ~/ 10;

/// Caps the field at [maxRunes] Unicode scalar values.
///
/// Flutter's [LengthLimitingTextInputFormatter] counts grapheme clusters, so a
/// ZWJ emoji (one grapheme, several scalars) would let through text the server
/// rejects. This counts runes instead, and clips only the *inserted* span — a
/// paste in the middle of existing text keeps the text after the caret intact.
class RuneLimitingTextInputFormatter extends TextInputFormatter {
  final int maxRunes;

  const RuneLimitingTextInputFormatter(this.maxRunes);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Mid-IME-composition text is provisional; clip once it commits (the commit
    // arrives as a further update with the composing range cleared).
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    final next = newValue.text;
    if (next.runes.length <= maxRunes) return newValue;

    final prev = oldValue.text;
    // The edit is next = prefix + inserted + suffix, where prefix/suffix are
    // the longest spans shared with prev. Never split a surrogate pair.
    final shared = prev.length < next.length ? prev.length : next.length;
    var prefix = 0;
    while (prefix < shared &&
        prev.codeUnitAt(prefix) == next.codeUnitAt(prefix)) {
      prefix++;
    }
    if (prefix > 0 && _isLeadSurrogate(next.codeUnitAt(prefix - 1))) prefix--;
    var suffix = 0;
    while (suffix < shared - prefix &&
        prev.codeUnitAt(prev.length - 1 - suffix) ==
            next.codeUnitAt(next.length - 1 - suffix)) {
      suffix++;
    }
    if (suffix > 0 &&
        _isTrailSurrogate(next.codeUnitAt(next.length - suffix))) {
      suffix--;
    }

    final head = next.substring(0, prefix);
    final tail = next.substring(next.length - suffix);
    final room = maxRunes - head.runes.length - tail.runes.length;
    // Already at/over the cap without the insertion: refuse the edit outright.
    if (room <= 0) return oldValue;
    final inserted = String.fromCharCodes(
      next.substring(prefix, next.length - suffix).runes.take(room),
    );
    final text = '$head$inserted$tail';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: head.length + inserted.length),
    );
  }

  static bool _isLeadSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
  static bool _isTrailSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
}

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
  /// button). Returns whether the submission was accepted; the composer clears
  /// its input ONLY when it was, so text typed during a window that refuses the
  /// send (e.g. the post-Stop settling window) is never silently discarded
  /// (adityas/ai/142).
  final bool Function(String) onSubmit;

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
    // Clear only if the send was accepted — a refused send (a turn active or a
    // cancel still settling) must not eat the user's typed text (adityas/ai/142).
    if (widget.onSubmit(text)) _input.clear();
  }

  /// Stop the in-flight turn server-side (adityas/ai/137). The notifier POSTs the
  /// cancel and keeps the stream open for the terminal `done`; it no-ops unless a
  /// turn is active, so this is safe to fire whenever the button shows Stop.
  void _stop() => ref.read(chatTurnProvider.notifier).cancel();

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
    // The post-Stop settling window still shows [TurnCancelled] but refuses a
    // send until the server's trailing usage/done lands; keep the Stop affordance
    // through it so the button never invites a submit that would be dropped
    // (adityas/ai/142). Reading the notifier is safe: every latch change fires a
    // [chatTurnProvider] notification, so this rebuild re-reads a fresh value.
    final settling = ref.read(chatTurnProvider.notifier).isSettling;
    final active =
        settling ||
        switch (turn) {
          TurnConnecting() || TurnStreaming() || TurnReconnecting() => true,
          TurnIdle() ||
          TurnDone() ||
          TurnCancelled() ||
          TurnError() ||
          TurnAccessLapsed() ||
          TurnCeiling() ||
          TurnConsentRequired() ||
          TurnBusy() => false,
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
            // Rebuilds per edit only to show/update the near-cap counter.
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _input,
              builder: (context, value, _) {
                final runes = value.text.runes.length;
                return TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  inputFormatters: const [
                    RuneLimitingTextInputFormatter(maxChatMessageRunes),
                  ],
                  style: TextStyle(color: color, fontSize: fontSize),
                  cursorColor: color,
                  decoration: InputDecoration(
                    counterText: runes >= _counterThresholdRunes
                        ? '$runes / $maxChatMessageRunes'
                        : null,
                    counterStyle: TextStyle(
                      color: dimColor,
                      fontSize: fontSize * 0.8,
                    ),
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
                      borderSide: BorderSide(
                        color: color.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // While a turn is in flight the send affordance becomes a Stop button:
        // it cancels the turn server-side (adityas/ai/137) rather than sitting
        // disabled, so the user is never stuck watching a reply they don't want.
        IconButton(
          onPressed: active ? _stop : _submit,
          tooltip: active ? 'Stop' : 'Send',
          icon: Icon(
            active ? Icons.stop : Icons.send,
            size: fontSize * 1.2,
            color: color,
          ),
        ),
      ],
    );
  }
}
