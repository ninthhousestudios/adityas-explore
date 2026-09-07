import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/chart_service.dart';
import 'auth.dart';
import 'backend.dart';
import 'entitlement.dart';

/// The consent transport (adityas/ai/98), behind [ConsentClient] so headless
/// tests inject a scripted fake. Production reads it from the shared
/// [chartServiceProvider], exactly as [entitlementClientProvider] and
/// [usageClientProvider] do.
final consentClientProvider = Provider<ConsentClient>(
  (ref) => ref.watch(chartServiceProvider),
);

/// The signed-in user's AI-Chat consent status (adityas/ai/98): GET
/// `/v1/ai/consent`. `null` when there is nothing to gate — chat is not
/// available (signed out / never entitled / lapsed), so no consent is asked.
///
/// Gated on [chatAvailableProvider] rather than mere auth: the endpoint is
/// auth-only, but a caller who cannot chat must never be nagged to re-consent to
/// a feature they cannot use — the gate sits *behind* entitlement. `watch`, so a
/// live access change (renewal, sign-out) rebuilds and refetches. Refetched on
/// demand (`ref.invalidate(consentProvider)`) after a mid-session 428 or a
/// recorded agreement. Nominally autoDispose, but note the keep-alive
/// [ChatTurnNotifier] listens to [consentRequiredProvider] for the app's
/// lifetime, pinning this provider resident — so re-entering chat does not by
/// itself refetch. User-identity keying (below) and the 428 backstop, not
/// disposal, are what keep the read honest (adityas/ai/135).
final consentProvider = AsyncNotifierProvider<ConsentNotifier, ChatConsent?>(
  ConsentNotifier.new,
  isAutoDispose: true,
);

class ConsentNotifier extends AsyncNotifier<ChatConsent?> {
  @override
  Future<ChatConsent?> build() async {
    // Key on user identity so an account switch where BOTH users are chat-available
    // (so [chatAvailableProvider] never changes value) still triggers a fresh GET —
    // otherwise user A's consent result would linger for user B until a 428
    // (adityas/ai/135). The id read alone is enough to force the rebuild; the fetch
    // authenticates with the current session token regardless.
    ref.watch(authProvider.select((u) => u?.id));
    if (!ref.watch(chatAvailableProvider)) return null;
    return ref.watch(consentClientProvider).fetchConsent();
  }

  /// Record agreement to the current T&C version, then refetch so the gate
  /// clears. The version echoed to the backend is the one this seam last read
  /// (`current_version` from the GET) — the exact string the gate displayed — so a
  /// stale client cannot record consent for terms the user never saw (the backend
  /// 400s a mismatch, adityas/ai/101). POST `/v1/ai/consent` is append-only and
  /// idempotent by version, so a double-tap is harmless. Rethrows on failure — the
  /// caller keeps the gate (and its button) so the user can retry.
  Future<void> accept() async {
    final version = state.value?.currentVersion;
    if (version == null) {
      throw StateError(
        'cannot record consent before the current version is known',
      );
    }
    await ref.read(consentClientProvider).recordConsent(version);
    ref.invalidateSelf();
  }
}

/// Whether the in-app (re-)consent gate should block new turns right now
/// (adityas/ai/98): chat is available AND the backend reports `needs_consent`.
///
/// Fail-open on a loading / failed / absent read (`?? false`): the authoritative
/// backstop is the **428** the write routes return regardless, which raises the
/// same gate reactively — so a transient GET failure must not lock a consenting
/// user out of chat.
final consentRequiredProvider = Provider<bool>((ref) {
  return ref.watch(consentProvider).value?.needsConsent ?? false;
});
