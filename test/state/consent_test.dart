import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explore/api/chart_service.dart';
import 'package:explore/state/auth.dart';
import 'package:explore/state/consent.dart';
import 'package:explore/state/entitlement.dart';

/// A scripted [ConsentClient]: settable `needsConsent`, flipped false on record.
/// Counts calls so a test can assert the seam fetched (or didn't) and recorded.
class _FakeConsent implements ConsentClient {
  bool needsConsent;
  int fetches = 0;
  int records = 0;
  String? recordedVersion;
  _FakeConsent({this.needsConsent = false});

  @override
  Future<ChatConsent> fetchConsent() async {
    fetches++;
    return ChatConsent(
      currentVersion: 'chat-terms-v1',
      acceptedVersion: needsConsent ? 'chat-terms-v0' : 'chat-terms-v1',
      needsConsent: needsConsent,
    );
  }

  @override
  Future<void> recordConsent(String version) async {
    records++;
    recordedVersion = version;
    needsConsent = false;
  }
}

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

/// authProvider touches `Supabase.instance` (uninitialized headless), so a fixed
/// user is stubbed. build() now watches the user id (adityas/ai/135), so every
/// consent test must override auth or the real notifier would throw.
class _StubAuth extends AuthNotifier {
  final User? _seed;
  _StubAuth(this._seed);

  @override
  User? build() => _seed;

  /// Emulate an account switch — the state change the id-keyed refetch reacts to.
  void switchTo(User? user) => state = user;
}

ProviderContainer _container(_FakeConsent consent, {required bool available}) {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => _StubAuth(_user('test-user'))),
      chatAvailableProvider.overrideWithValue(available),
      consentClientProvider.overrideWithValue(consent),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump([int times = 4]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('consent is not fetched when chat is unavailable — no nagging a caller '
      'who cannot chat (adityas/ai/98)', () async {
    final consent = _FakeConsent(needsConsent: true);
    final container = _container(consent, available: false)
      ..listen(consentRequiredProvider, (_, _) {});

    await _pump();
    expect(await container.read(consentProvider.future), isNull);
    expect(container.read(consentRequiredProvider), isFalse);
    expect(consent.fetches, 0); // gated behind availability, never fired
  });

  test(
    'an available caller with a stale version reports consent required',
    () async {
      final consent = _FakeConsent(needsConsent: true);
      final container = _container(consent, available: true)
        ..listen(consentRequiredProvider, (_, _) {});

      await _pump();
      expect(container.read(consentRequiredProvider), isTrue);
      expect(consent.fetches, greaterThan(0));
    },
  );

  test('an available caller who is current does not see the gate', () async {
    final consent = _FakeConsent(needsConsent: false);
    final container = _container(consent, available: true)
      ..listen(consentRequiredProvider, (_, _) {});

    await _pump();
    expect(container.read(consentRequiredProvider), isFalse);
  });

  test(
    'a user switch refetches consent even when both users stay chat-available — '
    "user A's result never lingers for user B (adityas/ai/135)",
    () async {
      final consent = _FakeConsent(needsConsent: false);
      final auth = _StubAuth(_user('user-a'));
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => auth),
          // Availability never changes (both users can chat), so the ONLY signal
          // that must drive a refetch is the user id.
          chatAvailableProvider.overrideWithValue(true),
          consentClientProvider.overrideWithValue(consent),
        ],
      );
      addTearDown(container.dispose);
      container.listen(consentProvider, (_, _) {}); // keep it resident

      await container.read(consentProvider.future);
      expect(consent.fetches, 1);

      // Account switch to a different user with the same availability.
      auth.switchTo(_user('user-b'));
      await _pump();
      await container.read(consentProvider.future);
      expect(consent.fetches, 2); // the id-keyed rebuild issued a fresh GET
    },
  );

  test('accept records agreement and clears the requirement', () async {
    final consent = _FakeConsent(needsConsent: true);
    final container = _container(consent, available: true)
      ..listen(consentRequiredProvider, (_, _) {});

    await _pump();
    expect(container.read(consentRequiredProvider), isTrue);

    await container.read(consentProvider.notifier).accept();
    await _pump();
    expect(consent.records, 1);
    expect(container.read(consentRequiredProvider), isFalse);
  });

  test(
    'accept echoes the displayed current version to the backend — a stale client '
    'cannot record consent for terms it did not show (adityas/ai/101)',
    () async {
      final consent = _FakeConsent(needsConsent: true);
      final container = _container(consent, available: true)
        ..listen(consentRequiredProvider, (_, _) {});

      await _pump();
      await container.read(consentProvider.notifier).accept();
      await _pump();
      expect(consent.recordedVersion, 'chat-terms-v1');
    },
  );

  test(
    'a failed fetch fails open — the gate does not block on a transient read '
    '(the 428 backstop enforces consent regardless)',
    () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _StubAuth(_user('test-user'))),
          chatAvailableProvider.overrideWithValue(true),
          consentClientProvider.overrideWithValue(_ThrowingConsent()),
        ],
      );
      addTearDown(container.dispose);
      container.listen(consentRequiredProvider, (_, _) {});

      await _pump();
      expect(container.read(consentRequiredProvider), isFalse);
    },
  );
}

/// A [ConsentClient] whose fetch always throws — the transient-failure case.
class _ThrowingConsent implements ConsentClient {
  @override
  Future<ChatConsent> fetchConsent() async => throw Exception('consent down');

  @override
  Future<void> recordConsent(String version) async {}
}
