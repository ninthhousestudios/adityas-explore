import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import 'package:explore/ui/message_markdown.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

const _style = TextStyle(fontSize: 14, color: Colors.white);

void main() {
  group('MessageMarkdown', () {
    testWidgets('parses markdown once the turn completes', (tester) async {
      await tester.pumpWidget(
        _host(
          const MessageMarkdown(
            'Your **Soul Stance** shines.',
            style: _style,
            linkColor: Colors.amber,
          ),
        ),
      );

      // Completed → routed through the markdown renderer, and the literal
      // asterisks are consumed by the bold parse (not shown verbatim).
      expect(find.byType(GptMarkdown), findsOneWidget);
      expect(find.textContaining('**'), findsNothing);
    });

    testWidgets('renders raw text while streaming (no per-token parse)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const MessageMarkdown(
            'Your **Soul Stance** shines.',
            style: _style,
            linkColor: Colors.amber,
            isStreaming: true,
          ),
        ),
      );

      // Streaming → plain Text, markdown deferred: the raw source is shown.
      expect(find.byType(GptMarkdown), findsNothing);
      expect(find.text('Your **Soul Stance** shines.'), findsOneWidget);
    });
  });
}
