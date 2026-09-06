import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/chart_service.dart';
import 'backend.dart';
import 'entitlement.dart';

/// The usage-headroom seam (adityas/ai/97), behind [UsageClient] so headless
/// tests inject a scripted fake. Production reads it from the shared
/// [chartServiceProvider], exactly as [entitlementClientProvider] does.
final usageClientProvider = Provider<UsageClient>(
  (ref) => ref.watch(chartServiceProvider),
);

/// The near-ceiling threshold the client owns (adityas/ai/97 decision: the server
/// returns a raw `used_pct`, never a policy const, so the notice UX picks the band
/// and the copy). At or above this floored percentage the quiet notice shows; the
/// hard at-ceiling stop stays the 402 on `POST .../turns`, not this signal.
const usageNearCeilingThreshold = 80;

/// The current caller's coarse usage percentage (adityas/ai/97): GET
/// `/v1/ai/usage` → `used_pct` 0..100, a floored fraction of the window budget.
/// `null` when there is nothing to show — chat is not available (signed out /
/// never entitled), or the value is still loading / failed to fetch.
///
/// NEVER a dollar or token figure (the no-meter invariant) — only the derived
/// fraction the backend already floors. Auth/entitlement-keyed via
/// [chatAvailableProvider]: a signed-out or non-entitled caller reads `null`
/// rather than firing a doomed request, and access flipping live refetches.
///
/// Refetched on demand (`ref.invalidate(usageProvider)`) after a turn settles —
/// the only time the window spend moves — so the near notice reflects the fresh
/// headroom without a wall-clock poll. autoDispose: a chat surface that is not
/// mounted (and whose turn notifier is torn down) holds no resident usage.
final usageProvider = AsyncNotifierProvider<UsageNotifier, int?>(
  UsageNotifier.new,
  isAutoDispose: true,
);

class UsageNotifier extends AsyncNotifier<int?> {
  @override
  Future<int?> build() async {
    // Gate on availability, not just auth: a non-entitled caller would only earn
    // a 403 from /v1/ai/usage, so short-circuit to null. Watch, so a live access
    // change (renewal, sign-out) rebuilds and refetches.
    if (!ref.watch(chatAvailableProvider)) return null;
    return ref.watch(usageClientProvider).fetchUsagePct();
  }
}

/// The floored usage percentage when it is inside the quiet near-ceiling band and
/// worth a notice, else `null`. The band is `[threshold, 100)`: at 100 the notice
/// yields to the hard at-ceiling surface (the 402 → [TurnCeiling]), so the two
/// never stack. Derived so the panel and its tests read one place.
final usageNearCeilingPctProvider = Provider<int?>((ref) {
  final pct = ref.watch(usageProvider).value;
  if (pct == null) return null;
  return (pct >= usageNearCeilingThreshold && pct < 100) ? pct : null;
});
