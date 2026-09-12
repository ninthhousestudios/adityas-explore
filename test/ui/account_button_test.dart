import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explore/state/auth.dart';
import 'package:explore/state/conversation.dart';
import 'package:explore/state/entitlement.dart';
import 'package:explore/ui/account_button.dart';

/// The account menu's *Conversations* item is gated on archive existence
/// (adityas/ai/181), and that archive answer must be trusted only when it was
/// resolved for the current identity — a value retained across a user switch
/// must not surface a prior user's archive to the new one (adityas/ai/198
/// finding A, the account-menu twin of the buy-stub fork hardening).

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

/// A signed-in user whose archive check resolves to [has], tagged with
/// [historyUserId] (defaults to the signed-in stub; set a different id to
/// simulate a value retained across an auth change). chat access is forced to
/// `none` so *Conversations* is driven purely by the archive signal.
ProviderContainer _container({
  required bool has,
  String? historyUserId = 'test-user',
}) {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_StubAuth.new),
      chatAccessProvider.overrideWithValue(ChatAccess.none),
      hasConversationsProvider.overrideWith(
        (ref) async => (userId: historyUserId, has: has),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpMenu(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: AccountButton())),
    ),
  );
  await tester.pump(); // resolve the archive future
  await tester.tap(find.byIcon(Icons.person));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a confirmed non-empty archive for THIS user shows the Conversations item',
    (tester) async {
      await _pumpMenu(tester, _container(has: true));
      expect(find.text('Conversations'), findsOneWidget);
    },
  );

  testWidgets(
    'a non-empty archive answer resolved for a DIFFERENT identity does NOT show '
    'the Conversations item — a retained cross-identity value never leaks a prior '
    "user's archive (adityas/ai/198 finding A)",
    (tester) async {
      await _pumpMenu(
        tester,
        _container(has: true, historyUserId: 'other-user'),
      );
      expect(find.text('Conversations'), findsNothing);
    },
  );

  testWidgets('a confirmed-empty archive for this user hides the item', (
    tester,
  ) async {
    await _pumpMenu(tester, _container(has: false));
    expect(find.text('Conversations'), findsNothing);
  });
}
