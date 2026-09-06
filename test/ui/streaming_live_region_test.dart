import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:explore/ui/chat_panel.dart';

/// Live-region semantics for the streaming assistant reply (adityas/ai/138).
///
/// [StreamingLiveRegion] is the a11y seam: it must expose ONE polite live region
/// carrying the growing reply as its label, with the visible children excluded
/// so the announcement isn't a duplicate read. The isLiveRegion flag is what
/// Flutter's web engine renders as `aria-live` — asserting it here is the
/// device-independent proof the region reaches the semantics tree.
void main() {
  testWidgets('exposes a single polite live region labelled with the reply', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StreamingLiveRegion(
            label: 'Hello there. Thinking…',
            child: Column(children: [Text('Hello there'), Text('Thinking…')]),
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(StreamingLiveRegion)),
      matchesSemantics(isLiveRegion: true, label: 'Hello there. Thinking…'),
    );

    handle.dispose();
  });

  testWidgets('re-announces the grown label as more text streams in', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    Widget region(String label) => MaterialApp(
      home: Scaffold(
        body: StreamingLiveRegion(label: label, child: Text(label)),
      ),
    );

    await tester.pumpWidget(region('Hel'));
    expect(
      tester.getSemantics(find.byType(StreamingLiveRegion)),
      matchesSemantics(isLiveRegion: true, label: 'Hel'),
    );

    // A later throttle tick grows the reply; the same one region now carries the
    // longer label — no second live region is introduced.
    await tester.pumpWidget(region('Hello there'));
    expect(
      tester.getSemantics(find.byType(StreamingLiveRegion)),
      matchesSemantics(isLiveRegion: true, label: 'Hello there'),
    );

    handle.dispose();
  });

  testWidgets('the visible children do not double-announce (excluded)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StreamingLiveRegion(
            label: 'the reply',
            child: Text('the reply'),
          ),
        ),
      ),
    );

    // The excluded child produces no semantics node of its own, so the reply
    // text appears exactly once in the tree — on the live region's label.
    expect(find.bySemanticsLabel('the reply'), findsOneWidget);

    handle.dispose();
  });
}
