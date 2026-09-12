import 'dart:async';

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

/// An [EntitlementClient] whose fetch always fails — for the error path, where
/// the entitlement never resolves to a value (adityas/ai/194).
class _ThrowingEntitlementClient implements EntitlementClient {
  @override
  Future<Entitlement> fetchEntitlement() async =>
      throw Exception('entitlement fetch failed');
}

/// An [EntitlementClient] whose fetches hang until the test resolves them by
/// hand — so a transition test can observe the in-flight window (adityas/ai/195)
/// where an identity change must read as pending, not the previous identity's
/// value.
class _ControllableClient implements EntitlementClient {
  final _pending = <Completer<Entitlement>>[];
  int calls = 0;

  @override
  Future<Entitlement> fetchEntitlement() {
    calls++;
    final c = Completer<Entitlement>();
    _pending.add(c);
    return c.future;
  }

  void completeLast(Entitlement e) => _pending.last.complete(e);

  /// Completes the fetch at [index] in call order — lets a test resolve a
  /// *superseded* request (one abandoned when an auth change re-ran the build)
  /// after a later one has started, to prove a discarded build cannot corrupt
  /// the identity guard (adityas/ai/196).
  void completeAt(int index, Entitlement e) => _pending[index].complete(e);
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

/// Like [_StubAuth] but the test can flip the signed-in user at runtime, to
/// drive the null→user / user A→user B / user→null transitions (adityas/ai/195).
class _MutableAuth extends AuthNotifier {
  final User? _initial;
  _MutableAuth(this._initial);

  @override
  User? build() => _initial;

  void setUser(User? user) => state = user;
}

/// A signed-in user with an arbitrary id, for the user-switch transition.
User _userWithId(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

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

/// Container whose auth can be flipped at runtime (via the [_MutableAuth]
/// notifier) for the identity-transition tests (adityas/ai/195).
ProviderContainer _mutableContainer({
  required User? user,
  required EntitlementClient client,
  required Clock clock,
}) {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => _MutableAuth(user)),
      entitlementClientProvider.overrideWithValue(client),
      clockProvider.overrideWithValue(clock),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Flush the microtask queue a few times so provider rebuilds triggered by an
/// auth flip run before we assert.
Future<void> _pump() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Flip the signed-in user on a [_MutableAuth]-backed container.
void _setUser(ProviderContainer container, User? user) =>
    (container.read(authProvider.notifier) as _MutableAuth).setUser(user);

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

      final resolved = await container.read(entitlementProvider.future);
      expect(resolved.entitlement.accessUntil, accessUntil);
      expect(resolved.userId, _stubUser.id);
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

      final resolved = await container.read(entitlementProvider.future);
      expect(resolved.entitlement.accessUntil, isNull);
      expect(resolved.userId, isNull);
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

  // ── pending vs confirmed none: the buy CTA must wait for a settled fetch
  //    (adityas/ai/194) ────────────────────────────────────────────────

  test('chatAccess is pending while a signed-in entitlement is still loading '
      '(not none — the buy CTA must not show mid-fetch)', () async {
    final container = _container(
      user: _stubUser,
      client: _FakeEntitlementClient(const Entitlement.none()),
      clock: _FakeClock(DateTime.utc(2026, 8, 1)),
    );
    final sub = container.listen(chatAccessProvider, (_, _) {});
    addTearDown(sub.close);

    // Read BEFORE the fetch settles: entitlement has no value yet.
    expect(container.read(entitlementSettledProvider), isFalse);
    expect(container.read(chatAccessProvider), ChatAccess.pending);

    // Once it resolves to a real (empty) entitlement, the verdict is a
    // confirmed none — now the buy CTA is correct.
    await container.read(entitlementProvider.future);
    expect(container.read(entitlementSettledProvider), isTrue);
    expect(container.read(chatAccessProvider), ChatAccess.none);
  });

  test('chatAccess is pending when the entitlement fetch errors — never a false '
      'buy prompt for a possibly-entitled user', () async {
    final container = _container(
      user: _stubUser,
      client: _ThrowingEntitlementClient(),
      clock: _FakeClock(DateTime.utc(2026, 8, 1)),
    );
    final sub = container.listen(chatAccessProvider, (_, _) {});
    addTearDown(sub.close);

    // Let the first fetch attempt run and reject. We do NOT await
    // entitlementProvider.future — Riverpod's default build auto-retry keeps it
    // unresolved (looping loading→error), which is exactly the point: until a
    // value lands the state stays pending, never a confirmed none.
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(container.read(entitlementProvider).hasValue, isFalse);
    expect(container.read(entitlementSettledProvider), isFalse);
    expect(container.read(chatAccessProvider), ChatAccess.pending);
  });

  test(
    'a signed-out user is settled immediately — none, never pending, with no '
    'fetch',
    () async {
      final client = _FakeEntitlementClient(
        Entitlement(accessUntil: accessUntil),
      );
      final container = _container(
        user: null,
        client: client,
        clock: _FakeClock(DateTime.utc(2026, 8, 1)),
      );
      final sub = container.listen(chatAccessProvider, (_, _) {});
      addTearDown(sub.close);

      // No await: signed-out short-circuits, so it never reads as pending and
      // never touches the client.
      expect(container.read(entitlementSettledProvider), isTrue);
      expect(container.read(chatAccessProvider), ChatAccess.none);
      expect(client.calls, 0);
    },
  );

  // ── identity transitions: a value resolved for one identity must never be
  //    read as another's settled entitlement (adityas/ai/195) ──────────────

  test('null→user: a signed-out resident `none` is dropped on sign-in — pending '
      'mid-fetch, not a false confirmed none (buy CTA)', () async {
    final client = _ControllableClient();
    final container = _mutableContainer(
      user: null,
      client: client,
      clock: _FakeClock(DateTime.utc(2026, 8, 1)),
    );
    // Keep entitlement resident while signed out, exactly as the live pill does
    // (via accessDeadlineProvider) — so it holds a resolved `none` whose
    // hasValue would otherwise leak across the sign-in rebuild.
    final entSub = container.listen(entitlementProvider, (_, _) {});
    addTearDown(entSub.close);
    await container.read(entitlementProvider.future);
    expect(container.read(entitlementProvider).hasValue, isTrue);
    expect(
      container.read(entitlementProvider).value?.entitlement.accessUntil,
      isNull,
    );
    expect(client.calls, 0); // signed-out short-circuit, no fetch

    // Sign in — the dangerous transition. The retained `none` must not be read
    // as the new user's settled entitlement.
    (container.read(authProvider.notifier) as _MutableAuth).setUser(_stubUser);
    await _pump();

    // Riverpod retains the signed-out `none` as an AsyncLoading-with-previous
    // across the rebuild (hasValue stays true) — the identity guard is what
    // rejects it: currentEntitlementProvider reads null until this user's own
    // fetch lands, so settled is false and the surface is pending, not a false
    // confirmed none.
    expect(container.read(entitlementProvider).hasValue, isTrue);
    expect(container.read(currentEntitlementProvider), isNull);
    expect(container.read(entitlementSettledProvider), isFalse);
    expect(container.read(chatAccessProvider), ChatAccess.pending);

    // The new user's fetch resolves to a real (empty) entitlement → the
    // confirmed none (buy CTA) is now correct.
    client.completeLast(const Entitlement.none());
    await container.read(entitlementProvider.future);
    expect(container.read(chatAccessProvider), ChatAccess.none);
  });

  test(
    'user A→user B: A\'s live window does not leak to B while B\'s fetch is in '
    'flight',
    () async {
      final userA = _userWithId('user-a');
      final userB = _userWithId('user-b');
      final client = _ControllableClient();
      final container = _mutableContainer(
        user: userA,
        client: client,
        clock: _FakeClock(DateTime.utc(2026, 8, 1)), // before expiry
      );
      final sub = container.listen(chatAccessProvider, (_, _) {});
      addTearDown(sub.close);

      // A is inside a live paid window.
      await _pump();
      client.completeLast(Entitlement(accessUntil: accessUntil));
      await container.read(entitlementProvider.future);
      expect(container.read(chatAccessProvider), ChatAccess.available);

      // Switch to B. A's accessUntil must not be read as B's.
      (container.read(authProvider.notifier) as _MutableAuth).setUser(userB);
      await _pump();
      expect(container.read(chatAccessProvider), isNot(ChatAccess.available));
      expect(container.read(chatAccessProvider), ChatAccess.pending);

      // B resolves to no entitlement.
      client.completeLast(const Entitlement.none());
      await container.read(entitlementProvider.future);
      expect(container.read(chatAccessProvider), ChatAccess.none);
    },
  );

  test(
    'user→null: sign-out reads none immediately, never the retained live window',
    () async {
      final client = _ControllableClient();
      final container = _mutableContainer(
        user: _stubUser,
        client: client,
        clock: _FakeClock(DateTime.utc(2026, 8, 1)),
      );
      final sub = container.listen(chatAccessProvider, (_, _) {});
      addTearDown(sub.close);

      await _pump();
      client.completeLast(Entitlement(accessUntil: accessUntil));
      await container.read(entitlementProvider.future);
      expect(container.read(chatAccessProvider), ChatAccess.available);

      // Sign out. Read synchronously — before any rebuild pump — to catch the
      // transient where entitlement still holds the previous user's value.
      (container.read(authProvider.notifier) as _MutableAuth).setUser(null);
      expect(container.read(chatAccessProvider), ChatAccess.none);
    },
  );

  test('same-user refresh keeps the resolved value — no pending flash on the '
      'tab-visibility invalidate (adityas/ai/194 preserved)', () async {
    final client = _ControllableClient();
    final container = _mutableContainer(
      user: _stubUser,
      client: client,
      clock: _FakeClock(DateTime.utc(2026, 8, 1)),
    );
    final sub = container.listen(chatAccessProvider, (_, _) {});
    addTearDown(sub.close);

    await _pump();
    client.completeLast(Entitlement(accessUntil: accessUntil));
    await container.read(entitlementProvider.future);
    expect(container.read(chatAccessProvider), ChatAccess.available);
    expect(container.read(entitlementSettledProvider), isTrue);

    // Same-user refresh: the prior value must survive the rebuild (identity
    // unchanged), so the user is never bounced back to pending.
    container.invalidate(entitlementProvider);
    await _pump();
    expect(container.read(entitlementProvider).hasValue, isTrue);
    expect(container.read(entitlementSettledProvider), isTrue);
    expect(container.read(chatAccessProvider), ChatAccess.available);

    // The refetch lands; still available.
    client.completeLast(Entitlement(accessUntil: accessUntil));
    await container.read(entitlementProvider.future);
    expect(container.read(chatAccessProvider), ChatAccess.available);
  });

  // ── superseded builds: a fetch abandoned by an auth change completes late and
  //    mutates the ai/195 `resolvedFor` side channel. The corruption must not be
  //    readable on the NEXT recompute (adityas/ai/196). Ordering is load-bearing:
  //    completing a superseded fetch publishes NO state, so it invalidates
  //    nothing — a test that completes it *after* the exposing transition just
  //    reads a cached value and passes even against the broken field. Each test
  //    lands the corruption BEFORE a transition that forces the recompute, so it
  //    genuinely fails against ai/195 and passes with identity carried in the
  //    value (verified by running both against 957318d).

  test('a superseded fetch that completes while signed out cannot fabricate a '
      'confirmed none on the next same-user sign-in (adityas/ai/196)', () async {
    final client = _ControllableClient();
    final container = _mutableContainer(
      user: null,
      client: client,
      clock: _FakeClock(DateTime.utc(2026, 8, 1)),
    );
    final accessSub = container.listen(chatAccessProvider, (_, _) {});
    final entSub = container.listen(entitlementProvider, (_, _) {});
    addTearDown(accessSub.close);
    addTearDown(entSub.close);

    // Sign in — fetch #0 starts (captures this user id), pending.
    _setUser(container, _stubUser);
    await _pump();
    expect(client.calls, 1);
    expect(container.read(chatAccessProvider), ChatAccess.pending);

    // Sign out before #0 lands: the signed-out none publishes; #0 is abandoned.
    _setUser(container, null);
    await _pump();
    expect(container.read(chatAccessProvider), ChatAccess.none);

    // The abandoned #0 completes NOW, while signed out. Under the ai/195 side
    // channel its continuation runs `resolvedFor = user.id` (the captured
    // _stubUser) — corrupting the field while the published value is the
    // signed-out none. Nothing publishes, so nothing recomputes yet.
    client.completeAt(0, const Entitlement.none());
    await _pump();

    // Sign in as the SAME user — fetch #1 starts. This transition republishes
    // (loading-with-previous) and forces the recompute that READS the tag.
    //   ai/195: resolvedFor now == this user → the retained signed-out none
    //           counts as settled → false confirmed none (buy CTA).  [FAILS here]
    //   ai/196: the retained published value carries userId=null → rejected →
    //           pending.
    _setUser(container, _stubUser);
    await _pump();
    expect(client.calls, 2);
    expect(container.read(chatAccessProvider), ChatAccess.pending);

    // #1 lands → a correct confirmed none.
    client.completeAt(1, const Entitlement.none());
    await container.read(entitlementProvider.future);
    expect(container.read(chatAccessProvider), ChatAccess.none);
  });

  test('a superseded fetch that completes for the incoming user cannot leak the '
      'prior user\'s live window on the next switch (adityas/ai/196)', () async {
    final userA = _userWithId('user-a');
    final userB = _userWithId('user-b');
    final client = _ControllableClient();
    final container = _mutableContainer(
      user: userA,
      client: client,
      clock: _FakeClock(DateTime.utc(2026, 8, 1)), // before expiry
    );
    final accessSub = container.listen(chatAccessProvider, (_, _) {});
    final entSub = container.listen(entitlementProvider, (_, _) {});
    addTearDown(accessSub.close);
    addTearDown(entSub.close);

    // A resolves inside a live paid window (fetch #0) — the value that stays
    // published (retained) through the pending hops below.
    await _pump();
    client.completeAt(0, Entitlement(accessUntil: accessUntil));
    await container.read(entitlementProvider.future);
    expect(container.read(chatAccessProvider), ChatAccess.available);

    // A → B (#1 pending) → A (#2 pending; #1 now superseded). Back on A, still
    // A's own live window; nothing new published, so retained value is #0's.
    _setUser(container, userB);
    await _pump();
    _setUser(container, userA);
    await _pump();
    expect(client.calls, 3);
    expect(container.read(chatAccessProvider), ChatAccess.available);

    // Complete B's *superseded* fetch (#1) NOW, while A is current. Under ai/195
    // its continuation runs `resolvedFor = user.id` for B — corrupting the field.
    // A is current (resolvedFor B ≠ A), so no visible effect yet.
    client.completeAt(1, const Entitlement.none());
    await _pump();

    // Switch to B — fetch #3 starts. This transition forces the recompute that
    // READS the tag.
    //   ai/195: resolvedFor == B == current user → hands back the retained value,
    //           which is A's LIVE window → B sees a paid session that isn't
    //           theirs (available).  [FAILS here]
    //   ai/196: the retained value carries userId=A ≠ B → rejected → pending.
    _setUser(container, userB);
    await _pump();
    expect(client.calls, 4);
    expect(container.read(chatAccessProvider), isNot(ChatAccess.available));
    expect(container.read(chatAccessProvider), ChatAccess.pending);

    // B's own fetch (#3) lands as no entitlement → confirmed none, no trace of A.
    client.completeAt(3, const Entitlement.none());
    await container.read(entitlementProvider.future);
    expect(container.read(chatAccessProvider), ChatAccess.none);
  });
}
