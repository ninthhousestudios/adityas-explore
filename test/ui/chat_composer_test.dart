import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:explore/state/turn_transport.dart';
import 'package:explore/ui/chat_composer.dart';

/// The composer mirrors the server's 8,000-scalar message cap (adityas/ai/221):
/// runes, not graphemes, so a ZWJ emoji counts as its scalars.

/// The composer only watches turn state; no turn is ever started here.
class _IdleTransport implements TurnTransport {
  @override
  String? conversationId;

  @override
  Stream<TurnEvent> start(TurnRequest request) => const Stream.empty();

  @override
  Stream<TurnEvent> resume(String cursor) => const Stream.empty();

  @override
  Future<bool> cancel() async => true;

  @override
  void adoptConversation(String id) => conversationId = id;

  @override
  void resetConversation() => conversationId = null;
}

Future<void> _pumpComposer(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [turnTransportProvider.overrideWithValue(_IdleTransport())],
      child: MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            color: Colors.white,
            dimColor: Colors.white70,
            fontSize: 14,
            onSubmit: (_) => true,
          ),
        ),
      ),
    ),
  );
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

// 👨‍👩‍👧: one grapheme, five scalars (3 emoji + 2 ZWJ), eight UTF-16 units.
const _family = '\u{1F468}‍\u{1F469}‍\u{1F467}';

void main() {
  testWidgets('input exactly at the cap is accepted', (tester) async {
    await _pumpComposer(tester);
    await tester.enterText(find.byType(TextField), 'a' * maxChatMessageRunes);
    expect(_fieldText(tester).runes.length, maxChatMessageRunes);
  });

  testWidgets('an over-cap paste is clipped to the cap', (tester) async {
    await _pumpComposer(tester);
    await tester.enterText(
      find.byType(TextField),
      'b' * (maxChatMessageRunes + 1000),
    );
    expect(_fieldText(tester).runes.length, maxChatMessageRunes);
  });

  testWidgets('a multi-scalar emoji counts as its scalars, not one grapheme', (
    tester,
  ) async {
    await _pumpComposer(tester);
    expect(_family.runes.length, 5);
    // Room for 3 more scalars: the 5-scalar family must not fit whole.
    final base = 'a' * (maxChatMessageRunes - 3);
    await tester.enterText(find.byType(TextField), base + _family);
    final text = _fieldText(tester);
    expect(text.runes.length, maxChatMessageRunes);
    expect(text.endsWith(_family), isFalse);
  });

  test('a mid-text paste clips the insertion and keeps the tail', () {
    const f = RuneLimitingTextInputFormatter(10);
    final out = f.formatEditUpdate(
      const TextEditingValue(
        text: 'abcdef',
        selection: TextSelection.collapsed(offset: 3),
      ),
      const TextEditingValue(
        text: 'abcXXXXXXXdef',
        selection: TextSelection.collapsed(offset: 10),
      ),
    );
    expect(out.text, 'abcXXXXdef');
    expect(out.selection, const TextSelection.collapsed(offset: 7));
  });

  test('clipping never splits a surrogate pair', () {
    const f = RuneLimitingTextInputFormatter(2);
    final out = f.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: 'a\u{1F468}\u{1F469}'),
    );
    expect(out.text, 'a\u{1F468}');
  });

  testWidgets('the counter appears only near the cap', (tester) async {
    await _pumpComposer(tester);
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(find.textContaining('/ $maxChatMessageRunes'), findsNothing);

    await tester.enterText(find.byType(TextField), 'a' * 7200);
    await tester.pump();
    expect(find.text('7200 / $maxChatMessageRunes'), findsOneWidget);
  });
}
