import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/auth.dart';

/// Supabase user ids allowed to use the durable chat (`/v1/ai`, adityas/ai/11).
///
/// The chat *panel* is open to everyone (it doubles as the layout-mode stub),
/// but the wired client only talks to the backend for these accounts. This is
/// only a UX gate — the backend independently enforces the same list, so a
/// determined non-allowlisted user gets a 403, not tokens.
///
/// **Keep in sync with the backend `AI_CHAT_ALLOWLIST` env var** (server/src/
/// config.rs); an id here that the backend does not also allowlist gets a 403
/// on the first turn. There is a single lane now — the throwaway `/v1/ai/preview`
/// path was retired (see adityas/ai cutover).
const chatAllowlist = <String>{
  '01214259-228c-46a9-bb3d-e229c8c4cb3f', // josh@ninthhouse.studio
  'be96b3d3-5c64-40d2-ae77-73d6883d14a2', // info@lvbarat.com (Laura)
};

/// True when the signed-in user may use the wired chat client.
final chatEnabledProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  return user != null && chatAllowlist.contains(user.id);
});
