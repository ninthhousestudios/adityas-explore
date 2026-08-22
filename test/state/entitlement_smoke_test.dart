@Tags(['smoke'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:explore/api/chart_service.dart';

/// Live smoke test for the entitlement wire — opt-in, hits the network.
///
/// Nothing in the app calls [ChartService.fetchEntitlement] yet (the chat entry
/// point is explore/44), so this is the only way to confirm the deployed
/// `GET /v1/entitlement` endpoint + the real client parse path actually work
/// end-to-end. It:
///   1. does a Supabase password grant to get a real JWT, then
///   2. calls the *real* [ChartService.fetchEntitlement] against the backend.
///
/// Skipped unless `SMOKE_EMAIL` / `SMOKE_PASSWORD` are set, so a normal
/// `flutter test` (and CI) stays offline and green. Run it with:
///
///   SMOKE_EMAIL=you@example.com SMOKE_PASSWORD=... flutter test --tags smoke
///
/// Point it at a local backend by also passing
/// `--dart-define API_BASE_URL=http://localhost:3000`.
///
/// Expected result today: `access_until = null` (nothing writes it until the
/// purchase→extend wiring lands, backend/45). Seed a row
/// (`INSERT INTO public.entitlements ...`) to see a non-null timestamp — that
/// is the value `chatAvailableProvider` compares against the clock.
const _supabaseUrl = 'https://brkrnuucfdzuligvttol.supabase.co';
const _publishableKey = 'sb_publishable_0G0m4eJ_w5SjhgzDOyvbMg_hJGWQIWZ';

void main() {
  final email = Platform.environment['SMOKE_EMAIL'];
  final password = Platform.environment['SMOKE_PASSWORD'];
  final haveCreds =
      (email?.isNotEmpty ?? false) && (password?.isNotEmpty ?? false);

  test(
    'GET /v1/entitlement returns a parseable Entitlement for a real user',
    () async {
      // 1. Real JWT via Supabase password grant (the anon/publishable key is
      // public by design; the same values ship in main.dart).
      final tokenResp = await http.post(
        Uri.parse('$_supabaseUrl/auth/v1/token?grant_type=password'),
        headers: {
          'apikey': _publishableKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'email': email, 'password': password}),
      );
      expect(
        tokenResp.statusCode,
        200,
        reason: 'Supabase sign-in failed: ${tokenResp.body}',
      );
      final token =
          (jsonDecode(tokenResp.body) as Map<String, dynamic>)['access_token']
              as String;

      // 2. The real client path against the deployed backend (default base URL
      // is prod; override with --dart-define API_BASE_URL for local).
      final service = ChartService(
        tokenProvider: ({forceRefresh = false}) async => token,
      );
      final entitlement = await service.fetchEntitlement();

      // No assertion on the value — null is valid (no row seeded yet). Reaching
      // here at all proves: endpoint live, JWT accepted, response parsed.
      // ignore: avoid_print
      print('✅ /v1/entitlement OK — access_until = ${entitlement.accessUntil}');
    },
    skip: haveCreds
        ? false
        : 'set SMOKE_EMAIL / SMOKE_PASSWORD env vars to run the live smoke test',
  );
}
