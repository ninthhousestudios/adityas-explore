import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:explore/api/chart_service.dart';
import 'package:explore/state/entitlement.dart';
import 'package:explore/state/usage.dart';

/// A [UsageClient] that returns a fixed `used_pct` with no network, counting
/// calls so a gating test can assert it was never hit.
class _FakeUsage implements UsageClient {
  final int pct;
  int calls = 0;
  _FakeUsage(this.pct);

  @override
  Future<int> fetchUsagePct() async {
    calls++;
    return pct;
  }
}

/// A controllable stand-in for [chatAvailableProvider] — the auth/entitlement
/// gate the usage fetch hinges on — so a test flips it without the whole graph.
class _Gate extends Notifier<bool> {
  @override
  bool build() => true;

  void update(bool value) => state = value;
}

final _gateProvider = NotifierProvider<_Gate, bool>(_Gate.new);

ProviderContainer _container(UsageClient client, {bool available = true}) {
  final container = ProviderContainer(
    overrides: [
      usageClientProvider.overrideWithValue(client),
      chatAvailableProvider.overrideWith((ref) => ref.watch(_gateProvider)),
    ],
  );
  container.read(_gateProvider.notifier).update(available);
  // usageProvider is autoDispose: hold a listener so its async build isn't
  // orphaned (a bare read on an unlistened autoDispose provider disposes it
  // before the fetch completes).
  container.listen(usageProvider, (_, _) {});
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump([int times = 4]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('fetches used_pct when chat is available', () async {
    final client = _FakeUsage(42);
    final container = _container(client);

    // _container's keep-warm listen already triggered the async build; settle it.
    await _pump();

    expect(container.read(usageProvider).value, 42);
    expect(client.calls, 1);
  });

  test('reads null and never fetches when chat is unavailable', () async {
    final client = _FakeUsage(90);
    final container = _container(client, available: false);

    await _pump();

    expect(container.read(usageProvider).value, isNull);
    expect(client.calls, 0); // no doomed request for a non-entitled caller
  });

  group('near-ceiling band', () {
    Future<int?> pctFor(int used) async {
      final container = _container(_FakeUsage(used));
      await _pump();
      return container.read(usageNearCeilingPctProvider);
    }

    test('below the threshold shows no notice', () async {
      expect(await pctFor(usageNearCeilingThreshold - 1), isNull);
    });

    test(
      'at the threshold shows the notice with the floored percentage',
      () async {
        expect(
          await pctFor(usageNearCeilingThreshold),
          usageNearCeilingThreshold,
        );
      },
    );

    test('inside the band surfaces the percentage', () async {
      expect(await pctFor(93), 93);
    });

    test('at 100 yields to the at-ceiling surface (no near notice)', () async {
      expect(await pctFor(100), isNull);
    });
  });
}
