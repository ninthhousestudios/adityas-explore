import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explore/state/auth.dart';
import 'package:explore/state/conversation.dart';
import 'package:explore/state/entitlement.dart';
import 'package:explore/ui/chat_coming_soon.dart';
import 'package:explore/ui/chat_pill.dart';

/// The explore-pill's not-entitled fork (adityas/ai/183): a `none` user with
/// archived history opens the *renew* modal, one without opens the never-entitled
/// buy modal — the same archive split the panel makes.

const _stubUser = User(
  id: 'test-user',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

class _StubAuth extends AuthNotifier {
  @override
  User? build() => _stubUser;
}

/// A signed-in `none` user; [history] resolves hasConversationsProvider, or
/// [historyError] makes the archive check fail. [historyError] throws lazily
/// inside the provider so the errored future is never dangling (which
/// flutter_test would flag as an unhandled async error).
ProviderContainer _noneContainer({
  Future<bool>? history,
  Exception? historyError,
}) {
  final container = ProviderContainer(
    // No retry: an errored archive check would otherwise schedule a backoff
    // retry timer that never settles under fake-async and leaks past dispose.
    retry: (_, _) => null,
    overrides: [
      authProvider.overrideWith(_StubAuth.new),
      chatAccessProvider.overrideWithValue(ChatAccess.none),
      hasConversationsProvider.overrideWith((ref) async {
        if (historyError != null) throw historyError;
        return history!;
      }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpPill(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: ChatPill(
            color: Colors.white,
            dimColor: Colors.white70,
            backdropColor: Colors.black,
            fontSize: 14,
            onSubmit: (_) => true,
            onConsentGate: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'a former subscriber with history opens the renew modal, not the buy modal '
    '(adityas/ai/183)',
    (tester) async {
      final container = _noneContainer(history: Future.value(true));
      await _pumpPill(tester, container);
      await tester.pump(); // resolve hasConversationsProvider

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(find.text('Renew your access'), findsOneWidget);
      expect(find.text(ChatComingSoon.ctaFor(ChatGate.purchase)), findsNothing);
    },
  );

  testWidgets(
    'a never-entitled user (no history) opens the buy modal, not the renew modal '
    '(adityas/ai/183)',
    (tester) async {
      final container = _noneContainer(history: Future.value(false));
      await _pumpPill(tester, container);
      await tester.pump();

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(
        find.text(ChatComingSoon.ctaFor(ChatGate.purchase)),
        findsOneWidget,
      );
      expect(find.text('Renew your access'), findsNothing);
    },
  );

  testWidgets(
    'while the archive check is unresolved the pill is inert — no modal opens '
    '(adityas/ai/183)',
    (tester) async {
      final container = _noneContainer(history: Completer<bool>().future);
      await _pumpPill(tester, container);
      await tester.pump();

      await tester.tap(find.byType(InkWell), warnIfMissed: false);
      await tester.pumpAndSettle();

      // No modal of either kind opened.
      expect(find.text('Renew your access'), findsNothing);
      expect(find.text(ChatComingSoon.ctaFor(ChatGate.purchase)), findsNothing);
    },
  );

  testWidgets(
    'a failed archive check opens the renew modal, not the buy modal — a lookup '
    'error is not a confirmed-empty archive (adityas/42)',
    (tester) async {
      final container = _noneContainer(
        historyError: Exception('archive check blip'),
      );
      await _pumpPill(tester, container);
      await tester.pump(); // flush the archive check's microtask → error

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(find.text('Renew your access'), findsOneWidget);
      expect(find.text(ChatComingSoon.ctaFor(ChatGate.purchase)), findsNothing);
    },
  );

  testWidgets(
    'a non-empty in-session transcript opens the renew modal even when the '
    'archive check reads empty — a first-conversation user keeps renew after a '
    'mid-session 403 (adityas/42)',
    (tester) async {
      final container = _noneContainer(history: Future.value(false));
      container.read(conversationProvider.notifier).appendUser('hello');
      await _pumpPill(tester, container);
      await tester.pump();

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(find.text('Renew your access'), findsOneWidget);
      expect(find.text(ChatComingSoon.ctaFor(ChatGate.purchase)), findsNothing);
    },
  );
}
