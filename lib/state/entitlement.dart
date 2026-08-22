import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/chart_service.dart';
import 'auth.dart';
import 'backend.dart';
import 'clock.dart';

/// The entitlement transport, behind the [EntitlementClient] interface so
/// headless tests inject a scripted fake. Production reads it from the shared
/// [chartServiceProvider].
final entitlementClientProvider = Provider<EntitlementClient>(
  (ref) => ref.watch(chartServiceProvider),
);

/// The signed-in user's [Entitlement] (`access_until`), fetched async from the
/// backend DB.
///
/// Auth-keyed: it watches [authProvider], so a sign-out rebuilds to
/// [Entitlement.none] (never leaving the previous user's entitlement resident)
/// and a sign-in refetches. autoDispose — a signed-out app holds no resident
/// entitlement once nothing watches it. Riverpod 3's default build auto-retry
/// (200ms→6.4s backoff) is *welcome* here: a transient fetch failure
/// self-heals. (Contrast the chat turn, where build-retry must be kept away.)
///
/// Invalidate it (`ref.invalidate(entitlementProvider)`) on a purchase/webhook
/// signal to pull a fresh `access_until`.
final entitlementProvider =
    AsyncNotifierProvider<EntitlementNotifier, Entitlement>(
      EntitlementNotifier.new,
      isAutoDispose: true,
    );

class EntitlementNotifier extends AsyncNotifier<Entitlement> {
  @override
  Future<Entitlement> build() async {
    final user = ref.watch(authProvider);
    if (user == null) return const Entitlement.none();
    return ref.watch(entitlementClientProvider).fetchEntitlement();
  }
}

/// Whether the chat feature is available to the current user right now.
///
/// Derived, never stored: signed in AND a non-null `access_until` still in the
/// future per the injected [clockProvider]. Recomputes whenever auth or
/// entitlement changes. While entitlement is still loading (or errored), this
/// is `false` — chat is not granted until entitlement is confirmed.
///
/// Time is read at compute; crossing `access_until` reflects on the next
/// recompute. The production trigger for that recompute near expiry (a timer,
/// or a per-turn re-check) belongs to the chat turn (adityas/explore/44); this
/// task delivers the derived logic and its clock seam.
///
/// UX gate only — it decides whether to *show* the chat entry point. It is not
/// the security boundary: the authoritative entitlement check runs server-side
/// at the chat endpoint. A non-null `access_until` here is not proof the backend
/// will serve a turn (per adityas security: no business logic on the client).
final chatAvailableProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return false;

  final accessUntil = ref.watch(entitlementProvider).value?.accessUntil;
  if (accessUntil == null) return false;

  return accessUntil.isAfter(ref.watch(clockProvider).now());
});
