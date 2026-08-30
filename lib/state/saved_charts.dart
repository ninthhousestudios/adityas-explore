import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/chart_service.dart';
import 'auth.dart';
import 'backend.dart';

/// The user's server-saved charts, kept in sync with auth.
///
/// Owns the list, the cross-account epoch guard, and the auth reaction that used
/// to live in `_ExploreAppState` (adityas/explore/56). The widget is a consumer.
class SavedChartsController extends Notifier<List<SavedChartSummary>> {
  /// Bumped on every auth transition. [_refresh] captures it and drops a late
  /// list response whose epoch is stale — otherwise an in-flight list for a
  /// signed-out/previous user could repopulate or overwrite the current list
  /// after an auth change (cross-account leak).
  int _epoch = 0;

  ChartService get _service => ref.read(chartServiceProvider);

  @override
  List<SavedChartSummary> build() {
    // The only saved-charts auth reaction in the app: refresh on sign-in, clear
    // on sign-out. NOT fireImmediately — the callback assigns `state`, which
    // during build() would trip "modify a provider while the widget tree was
    // building" (see explore/58). The initial load is handled below instead.
    ref.listen<User?>(authProvider, (previous, user) {
      _epoch++;
      if (user != null) {
        unawaited(_refresh());
      } else {
        state = const [];
      }
    });
    // Initial load if already signed in at first (post-boot) build. _refresh's
    // first await defers the state write out of build().
    if (ref.read(authProvider) != null) unawaited(_refresh());
    return const [];
  }

  Future<void> _refresh() async {
    final epoch = _epoch;
    try {
      final charts = await _service.list();
      if (epoch != _epoch) return;
      state = charts;
    } on ChartApiException catch (e) {
      if (e.statusCode == 401 && epoch == _epoch) state = const [];
      debugPrint('Error fetching saved charts: $e');
    } catch (e) {
      debugPrint('Error fetching saved charts: $e');
    }
  }

  /// Re-fetch the list from the server.
  Future<void> refresh() => _refresh();

  /// Persist a new chart, then refresh the list. Throws [ChartApiException] on
  /// failure so the caller can surface the right message (401/409/other).
  Future<void> create(String name, String chartToml) async {
    await _service.create(name, chartToml);
    await _refresh();
  }
}

final savedChartsProvider =
    NotifierProvider<SavedChartsController, List<SavedChartSummary>>(
      SavedChartsController.new,
    );
