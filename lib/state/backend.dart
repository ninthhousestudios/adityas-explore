import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/chart_service.dart';

/// The Supabase access token for authenticated backend calls.
///
/// Reads the current session's JWT, force-refreshing first when asked (the 401
/// retry path in [ChartService]). Extracted so `main.dart`'s ChartService and
/// [chartServiceProvider] share one definition rather than two copies of the
/// same closure. Only valid after `Supabase.initialize` (i.e. post-boot).
Future<String?> supabaseAccessToken({bool forceRefresh = false}) async {
  final auth = Supabase.instance.client.auth;
  if (forceRefresh) await auth.refreshSession();
  return auth.currentSession?.accessToken;
}

/// The app's single authenticated backend client, shared by chart CRUD
/// (`main.dart`) and the entitlement fetch ([EntitlementClient]). keepAlive —
/// it is stateless apart from its `http.Client`, and one instance avoids two
/// live HTTP clients.
final chartServiceProvider = Provider<ChartService>(
  (ref) => ChartService(tokenProvider: supabaseAccessToken),
);
