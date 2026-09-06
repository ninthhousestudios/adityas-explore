import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explore/api/chart_service.dart';
import 'package:explore/state/auth.dart';
import 'package:explore/state/clock.dart';
import 'package:explore/state/entitlement.dart';

/// A clock the test advances by hand.
class _FakeClock implements Clock {
  DateTime _now;
  _FakeClock(this._now);

  @override
  DateTime now() => _now;

  void set(DateTime t) => _now = t;
}

/// An [EntitlementClient] that returns a fixed entitlement with no network.
class _FakeEntitlementClient implements EntitlementClient {
  final Entitlement entitlement;
  int calls = 0;
  _FakeEntitlementClient(this.entitlement);

  @override
  Future<Entitlement> fetchEntitlement() async {
    calls++;
    return entitlement;
  }
}

/// authProvider touches `Supabase.instance`, which isn't initialized headless,
/// so every test overrides it with a fixed user.
const _stubUser = User(
  id: 'test-user',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

class _StubAuth extends AuthNotifier {
  final User? _user;
  _StubAuth(this._user);

  @override
  User? build() => _user;
}

ProviderContainer _container({
  required User? user,
  required EntitlementClient client,
  required Clock clock,
}) {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => _StubAuth(user)),
      entitlementClientProvider.overrideWithValue(client),
      clockProvider.overrideWithValue(clock),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  final accessUntil = DateTime.utc(2026, 9, 1);

  test(
    'entitlementProvider fetches access_until via the injected client',
    () async {
      final client = _FakeEntitlementClient(
        Entitlement(accessUntil: accessUntil),
      );
      final container = _container(
        user: _stubUser,
        client: client,
        clock: _FakeClock(DateTime.utc(2026, 8, 1)),
      );

      final entitlement = await container.read(entitlementProvider.future);
      expect(entitlement.accessUntil, accessUntil);
      expect(client.calls, 1);
    },
  );

  test(
    'signed-out user gets Entitlement.none without hitting the client',
    () async {
      final client = _FakeEntitlementClient(
        Entitlement(accessUntil: accessUntil),
      );
      final container = _container(
        user: null,
        client: client,
        clock: _FakeClock(DateTime.utc(2026, 8, 1)),
      );

      final entitlement = await container.read(entitlementProvider.future);
      expect(entitlement.accessUntil, isNull);
      expect(client.calls, 0);
    },
  );

  test('chatAvailable is false for a signed-out user', () async {
    final container = _container(
      user: null,
      client: _FakeEntitlementClient(Entitlement(accessUntil: accessUntil)),
      clock: _FakeClock(DateTime.utc(2026, 8, 1)),
    );

    // Keep the derived provider (and its entitlement dep) resident, then settle.
    final sub = container.listen(chatAvailableProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(entitlementProvider.future);

    expect(container.read(chatAvailableProvider), isFalse);
  });

  test(
    'injected clock crossing access_until flips chatAvailable to false',
    () async {
      final clock = _FakeClock(DateTime.utc(2026, 8, 1)); // before expiry
      final container = _container(
        user: _stubUser,
        client: _FakeEntitlementClient(Entitlement(accessUntil: accessUntil)),
        clock: clock,
      );

      // Keep the graph resident and let the async entitlement fetch settle.
      final sub = container.listen(chatAvailableProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(entitlementProvider.future);

      // Before access_until: available.
      expect(container.read(chatAvailableProvider), isTrue);

      // Advance past access_until and recompute (the production recompute trigger
      // near expiry lands with the chat turn, explore/44).
      clock.set(accessUntil.add(const Duration(seconds: 1)));
      container.invalidate(chatAvailableProvider);

      expect(container.read(chatAvailableProvider), isFalse);
    },
  );

  test(
    'null access_until means chat unavailable even when signed in',
    () async {
      final container = _container(
        user: _stubUser,
        client: _FakeEntitlementClient(const Entitlement.none()),
        clock: _FakeClock(DateTime.utc(2026, 8, 1)),
      );

      final sub = container.listen(chatAvailableProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(entitlementProvider.future);

      expect(container.read(chatAvailableProvider), isFalse);
    },
  );

  // ── chatAccessProvider: available / lapsed / none (adityas/ai/120) ──

  test('chatAccess is available inside a live window', () async {
    final container = _container(
      user: _stubUser,
      client: _FakeEntitlementClient(Entitlement(accessUntil: accessUntil)),
      clock: _FakeClock(DateTime.utc(2026, 8, 1)), // before expiry
    );
    final sub = container.listen(chatAccessProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(entitlementProvider.future);

    expect(container.read(chatAccessProvider), ChatAccess.available);
  });

  test('chatAccess is lapsed once a real window closes', () async {
    final container = _container(
      user: _stubUser,
      client: _FakeEntitlementClient(Entitlement(accessUntil: accessUntil)),
      clock: _FakeClock(accessUntil.add(const Duration(days: 1))), // after
    );
    final sub = container.listen(chatAccessProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(entitlementProvider.future);

    // access_until is set but past → read-only history, renew-on-send.
    expect(container.read(chatAccessProvider), ChatAccess.lapsed);
  });

  test('chatAccess is none for a never-entitled user', () async {
    final container = _container(
      user: _stubUser,
      client: _FakeEntitlementClient(const Entitlement.none()),
      clock: _FakeClock(DateTime.utc(2026, 8, 1)),
    );
    final sub = container.listen(chatAccessProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(entitlementProvider.future);

    // No access_until ever → the coming-soon / buy surface, not lapsed history.
    expect(container.read(chatAccessProvider), ChatAccess.none);
  });

  test('chatAccess is none for a signed-out user', () async {
    final container = _container(
      user: null,
      client: _FakeEntitlementClient(Entitlement(accessUntil: accessUntil)),
      clock: _FakeClock(DateTime.utc(2026, 8, 1)),
    );
    final sub = container.listen(chatAccessProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(entitlementProvider.future);

    expect(container.read(chatAccessProvider), ChatAccess.none);
  });
}
