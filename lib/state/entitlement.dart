import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/chat_access.dart';
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
/// Derived, never stored. Available when signed in AND either:
///   1. the account is chat-allowlisted ([chatEnabledProvider]) — the current
///      access mechanism for the durable lane, whose backend gate is a
///      membership list (`AI_CHAT_ALLOWLIST`), NOT a paid entitlement; or
///   2. a non-null `access_until` still in the future per the injected
///      [clockProvider] — the production path for non-allowlisted paying users.
///
/// Recomputes whenever auth, allowlist membership, or entitlement changes. An
/// allowlisted tester with no purchase is available (no entitlement required);
/// at final cutover, when the allowlists are deleted, only clause (2) remains.
///
/// Time is read at compute; crossing `access_until` reflects on the next
/// recompute. The production trigger for that recompute near expiry (a timer,
/// or a per-turn re-check) belongs to the chat turn (adityas/explore/44); this
/// task delivers the derived logic and its clock seam.
///
/// UX gate only — it decides whether to *show* the chat entry point. It is not
/// the security boundary: the authoritative check runs server-side at the chat
/// endpoint. Availability here is not proof the backend will serve a turn (per
/// adityas security: no business logic on the client).
final chatAvailableProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return false;

  // Allowlist membership is the current access grant for both lanes.
  if (ref.watch(chatEnabledProvider)) return true;

  // Otherwise fall back to a live paid entitlement (future production path).
  final accessUntil = ref.watch(entitlementProvider).value?.accessUntil;
  if (accessUntil == null) return false;

  return accessUntil.isAfter(ref.watch(clockProvider).now());
});

/// The current user's `access_until` deadline, or `null` when there is none
/// (signed out, no entitlement, or still loading).
///
/// The absolute-time seam the chat turn schedules its mid-turn expiry timer
/// against — the "production trigger near expiry" [chatAvailableProvider] defers
/// to adityas/explore/44. [chatAvailableProvider] answers "available *now*?";
/// this answers "until *when*?" so the turn can arm a [clockProvider]-based
/// timer at exactly the boundary rather than waiting for an unrelated recompute.
/// Tests override it with a fixed deadline (no need to wire the fetch graph).
final accessDeadlineProvider = Provider<DateTime?>(
  (ref) => ref.watch(entitlementProvider).value?.accessUntil,
);
