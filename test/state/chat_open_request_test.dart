import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:explore/state/chat_open_request.dart';

void main() {
  test('consumePending reports a request exactly once (adityas/ai/92)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(chatOpenRequestProvider.notifier);

    // No request yet.
    expect(notifier.consumePending(), isFalse);

    // A Resume made while the wheel was unmounted still lands the request.
    notifier.request();
    expect(notifier.consumePending(), isTrue); // applied on the next mount
    expect(
      notifier.consumePending(),
      isFalse,
    ); // a later remount does NOT reopen

    // Each further Resume fires once more.
    notifier
      ..request()
      ..request();
    expect(notifier.consumePending(), isTrue);
    expect(notifier.consumePending(), isFalse);
  });
}
