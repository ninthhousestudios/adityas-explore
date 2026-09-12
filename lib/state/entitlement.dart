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

/// An [Entitlement] paired with the auth id it was resolved for (`null` for the
/// signed-out `none`). Binding the two in one *published* value is the identity
/// guard (adityas/ai/196): the id travels inside the value, so a value retained
/// across an auth change always carries the id of the build that produced it —
/// there is no separate field a discarded build could corrupt. See
/// [currentEntitlementProvider] for why that matters.
typedef ResolvedEntitlement = ({String? userId, Entitlement entitlement});

/// The signed-in user's [Entitlement] (`access_until`), fetched async from the
/// backend DB, tagged with the [ResolvedEntitlement.userId] it belongs to.
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
    AsyncNotifierProvider<EntitlementNotifier, ResolvedEntitlement>(
      EntitlementNotifier.new,
      isAutoDispose: true,
    );

class EntitlementNotifier extends AsyncNotifier<ResolvedEntitlement> {
  @override
  Future<ResolvedEntitlement> build() async {
    final user = ref.watch(authProvider);
    if (user == null) {
      return (userId: null, entitlement: const Entitlement.none());
    }
    final entitlement = await ref
        .watch(entitlementClientProvider)
        .fetchEntitlement();
    // Tag the result with the id it was fetched for. If this build was
    // superseded by an auth change mid-fetch, Riverpod discards this returned
    // value — it is never published — so the tag can never drift from the
    // entitlement it was resolved with (adityas/ai/196).
    return (userId: user.id, entitlement: entitlement);
  }
}

/// The current user's [Entitlement] value, but only once it belongs to the
/// *current* identity — `null` while a fetch for a freshly signed-in or switched
/// user is still in flight.
///
/// The identity guard (adityas/ai/195, hardened in adityas/ai/196): on an auth
/// change Riverpod retains the previous identity's value as an
/// AsyncLoading-with-previous, so a naive `entitlementProvider.value` read would
/// leak the signed-out `none` (a false buy prompt) or user A's live window to
/// user B. The published [ResolvedEntitlement] carries the id it was resolved
/// for, so a retained value whose id doesn't match the current user is rejected
/// until this user's own fetch lands. Because the id travels *inside* the
/// published value — not a side field — a build superseded by the auth change
/// (whose async body still runs but whose result Riverpod never publishes) can
/// never corrupt the guard (the ai/195 `resolvedFor` field could). A same-user
/// refresh keeps a matching id, so the tab-visibility invalidate never re-opens
/// a pending window (adityas/ai/194). Signed-out resolves to [Entitlement.none]
/// directly, never reading a retained value — so a sign-out reads as `none`
/// immediately.
///
/// Scope of the guard: it isolates *distinct* identities (B never reads A's
/// value) and makes a genuinely new identity pending until its own fetch lands.
/// It does **not** force pending on a user returning to their own still-resident
/// value (e.g. A→B→A before B resolves reads A's retained window): that is the
/// same "keep last-known while re-fetching" behavior as a refresh (adityas/ai/194)
/// and is deliberately *not* re-gated on an auth-transition generation — the UX
/// gate is not the security boundary (the backend re-checks every turn), the
/// value shown is the user's own, and any real change self-heals when the fetch
/// lands.
///
/// The single seam every derived provider reads, so the guard lives in one place
/// rather than being duplicated across [chatAvailableProvider],
/// [accessDeadlineProvider], and [entitlementSettledProvider].
final currentEntitlementProvider = Provider<Entitlement?>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return const Entitlement.none();
  final resolved = ref.watch(entitlementProvider).value;
  if (resolved == null) return null;
  return resolved.userId == user.id ? resolved.entitlement : null;
});

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
  // Read through the identity-guarded seam: a value retained from a previous
  // identity (or the signed-out none) reads as null here, so a switched-to user
  // never inherits the prior user's live window mid-fetch (adityas/ai/195).
  final accessUntil = ref.watch(currentEntitlementProvider)?.accessUntil;
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
  // Identity-guarded (adityas/ai/195): null while a newly signed-in / switched
  // user's fetch is in flight, so the lapsed check never reads a prior user's
  // access_until.
  (ref) => ref.watch(currentEntitlementProvider)?.accessUntil,
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
/// Signed-out is always settled ([currentEntitlementProvider] resolves to
/// [Entitlement.none] with no fetch). Signed-in is settled once the fetch has a
/// value *for this identity* — the guarded seam keeps a value retained from a
/// previous identity from counting (a freshly signed-in / switched user reads as
/// pending until their own fetch lands, adityas/ai/195), while a same-user
/// refresh keeps its matching value so the tab-visibility invalidate never
/// re-opens a pending window (adityas/ai/194).
///
/// A dedicated seam — rather than reading [entitlementProvider] inline in
/// [chatAccessProvider] — so the state tests that override [chatAvailableProvider]
/// / [accessDeadlineProvider] keep the entitlement fetch (and its network) out of
/// the graph with a single `overrideWithValue(true)`.
final entitlementSettledProvider = Provider<bool>(
  (ref) => ref.watch(currentEntitlementProvider) != null,
);

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
  // Signed out is always the sign-in-to-buy surface (adityas/ai/195). The
  // guarded seams already resolve signed-out to none, but short-circuiting here
  // states the invariant directly and keeps it independent of that derivation.
  if (ref.watch(authProvider) == null) return ChatAccess.none;
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
