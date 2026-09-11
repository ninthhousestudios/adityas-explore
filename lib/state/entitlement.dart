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
/// Derived, never stored. Available when signed in AND a non-null `access_until`
/// still in the future per the injected [clockProvider] — pure paid entitlement.
/// (The pre-launch allowlist was retired at cutover, adityas/ai/122; a comp
/// entitlement grant now preserves operator access through the same seam.)
///
/// Recomputes whenever auth or entitlement changes. Time is read at compute;
/// crossing `access_until` reflects on the next recompute. The production
/// trigger for that recompute near expiry (a timer, or a per-turn re-check)
/// belongs to the chat turn (adityas/explore/44); this provider delivers the
/// derived logic and its clock seam.
///
/// UX gate only — it decides whether to *show* the chat entry point. It is not
/// the security boundary: the authoritative check runs server-side at the chat
/// endpoint. Availability here is not proof the backend will serve a turn (per
/// adityas security: no business logic on the client).
final chatAvailableProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return false;

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

/// The chat surface's three access states, richer than the [chatAvailableProvider]
/// boolean (adityas/ai/120). The distinction the boolean can't make is between a
/// window that *closed* and one that *never opened*:
///
///   - [available] — chat is usable now (a live paid window).
///   - [lapsed]    — a paid window closed: `access_until` is set but not in the
///     future. Past conversations stay reachable, but **new turns** are refused
///     with a renew prompt (retention window, backend served by ai/89).
///     "Read-only" here is turn-level only: download / rename / delete stay
///     available (owner-gated, adityas/ai/181).
///   - [none]      — never entitled, or signed out. For the pill/panel this is the
///     coming-soon / sign-in-vs-buy surface (adityas/ai/85).
///   - [pending]   — signed in, but the entitlement fetch hasn't resolved yet
///     (loading, or errored with no prior value). Distinct from [none] on
///     purpose: [none] drives an active "buy Solar Prism" prompt, and showing
///     that to a signed-in user whose entitlement is merely still loading would
///     tell an *entitled* user to buy (adityas/ai/194). The pill/panel treat
///     [pending] as a quiet, non-committal state — no buy CTA — until it settles.
///
/// This enum gates the pill/panel and the per-row Resume action. It does **not**
/// gate the Conversations picker's visibility — that is [hasConversationsProvider]
/// (archive existence), so a former subscriber whose `access_until` was cleared
/// (→ [none]) still reaches their history to manage it (adityas/ai/181).
enum ChatAccess { available, lapsed, none, pending }

/// Whether the current user's entitlement has *resolved* — so a not-available,
/// no-deadline reading from [chatAccessProvider] is a confirmed "not entitled"
/// ([ChatAccess.none]) rather than a fetch still in flight ([ChatAccess.pending],
/// adityas/ai/194).
///
/// Signed-out is always settled: [entitlementProvider] returns [Entitlement.none]
/// with no fetch. Signed-in is settled once the fetch has a value — `hasValue`
/// stays true across a refresh (Riverpod keeps the prior value through
/// `ref.invalidate`), so the tab-visibility refetch (main.dart) never re-opens a
/// pending window for an already-resolved user.
///
/// A dedicated seam — rather than reading [entitlementProvider] inline in
/// [chatAccessProvider] — so the state tests that override [chatAvailableProvider]
/// / [accessDeadlineProvider] keep the entitlement fetch (and its network) out of
/// the graph with a single `overrideWithValue(true)`.
final entitlementSettledProvider = Provider<bool>((ref) {
  if (ref.watch(authProvider) == null) return true;
  return ref.watch(entitlementProvider).hasValue;
});

/// Derives [ChatAccess] from the existing seams — [chatAvailableProvider] (the
/// live-window check) plus [accessDeadlineProvider] (the `access_until`
/// timestamp). Composing from those
/// two, rather than re-reading [entitlementProvider], keeps this testable through
/// the same overrides the chat-turn tests already use.
///
/// A non-null deadline while *not* available means the window is in the past
/// (an available future window would have made [chatAvailableProvider] true), so
/// it reads as [ChatAccess.lapsed]; a null deadline reads as [ChatAccess.none].
final chatAccessProvider = Provider<ChatAccess>((ref) {
  if (ref.watch(chatAvailableProvider)) return ChatAccess.available;
  if (ref.watch(accessDeadlineProvider) != null) return ChatAccess.lapsed;
  // Not available and no deadline: either a *confirmed* not-entitled response, or
  // the entitlement fetch hasn't resolved yet. Withhold the [none] verdict — which
  // drives the buy/sign-in gate (adityas/ai/85) — until it settles, so a signed-in
  // entitled user is never shown "buy Solar Prism" mid-fetch (adityas/ai/194).
  return ref.watch(entitlementSettledProvider)
      ? ChatAccess.none
      : ChatAccess.pending;
});
