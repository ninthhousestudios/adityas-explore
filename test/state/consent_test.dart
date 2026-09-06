import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:explore/api/chart_service.dart';
import 'package:explore/state/consent.dart';
import 'package:explore/state/entitlement.dart';

/// A scripted [ConsentClient]: settable `needsConsent`, flipped false on record.
/// Counts calls so a test can assert the seam fetched (or didn't) and recorded.
class _FakeConsent implements ConsentClient {
  bool needsConsent;
  int fetches = 0;
  int records = 0;
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
  Future<void> recordConsent() async {
    records++;
    needsConsent = false;
  }
}

ProviderContainer _container(_FakeConsent consent, {required bool available}) {
  final container = ProviderContainer(
    overrides: [
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
    'a failed fetch fails open — the gate does not block on a transient read '
    '(the 428 backstop enforces consent regardless)',
    () async {
      final container = ProviderContainer(
        overrides: [
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
  Future<void> recordConsent() async {}
}
