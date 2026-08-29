import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// Renders an assistant message body — the single markdown-renderer swap seam.
///
/// Every chat message routes its text through this widget, so switching the
/// underlying package is a one-file change (adityas/ai/12). `gpt_markdown`
/// replaces the discontinued `flutter_markdown`.
///
/// Streaming policy: while a turn is in flight we render the raw text with a
/// plain [Text]; re-parsing markdown on every token is the documented jank
/// source (docs/chat-state-architecture.md § Client notes, ai tier-1 notes). We
/// parse once, on completion — pass `isStreaming: false` and the accumulated
/// text is handed to the renderer a single time.
class MessageMarkdown extends StatelessWidget {
  const MessageMarkdown(
    this.text, {
    required this.style,
    required this.linkColor,
    this.isStreaming = false,
    super.key,
  });

  final String text;

  /// Base text style (colour + size) for body text; block/inline elements
  /// derive from it.
  final TextStyle style;

  /// Brand accent for links (`tokens.gold`).
  final Color linkColor;

  /// True while the turn is still streaming — render plain, defer the parse.
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    if (isStreaming) {
      return Text(text, style: style);
    }
    return GptMarkdown(
      text,
      style: style,
      // We already hold the complete text; skip gpt_markdown's own reveal
      // animation so a finished message doesn't re-type itself.
      isStreaming: false,
      styleSheet: GptMarkdownStyleSheet(link: LinkStyle(color: linkColor)),
    );
  }
}
