import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in user, or `null` when signed out.
///
/// Single source of truth for auth across the app. Replaces the three
/// independent `auth.onAuthStateChange.listen(...)` subscriptions that used to
/// live in `_ExploreAppState`, `_AccountButtonState`, and `_SignInDialogState`
/// — this is now the *only* `onAuthStateChange` subscription in the codebase.
///
/// keepAlive (the default for a non-autoDispose [NotifierProvider]): the
/// account button is mounted for the whole app lifetime, so there is always a
/// live watcher. Only ever read after boot — [AuthNotifier.build] touches
/// `Supabase.instance`, which is not valid until `Supabase.initialize`
/// completes in `_ExploreAppState._boot`.
final authProvider = NotifierProvider<AuthNotifier, User?>(AuthNotifier.new);

class AuthNotifier extends Notifier<User?> {
  @override
  User? build() {
    final auth = Supabase.instance.client.auth;
    final sub = auth.onAuthStateChange.listen(
      (data) => state = data.session?.user,
      onError: (Object e) {
        // A failed background token refresh surfaces as a stream error; drop
        // the stale session so the app falls back to a clean signed-out state.
        if (e is AuthApiException) {
          dev.log('Auth error, signing out: ${e.code}', name: 'AUTH');
          auth.signOut();
        }
      },
    );
    ref.onDispose(sub.cancel);
    // gotrue's onAuthStateChange is a BehaviorSubject, so this late subscriber
    // is replayed the current session — but asynchronously. Seed synchronously
    // from currentUser to avoid a signed-out flash before the replay lands.
    // (The replay is value-equal to this seed, so Riverpod dedupes it.)
    return auth.currentUser;
  }
}
