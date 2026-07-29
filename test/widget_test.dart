import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explore/main.dart';
import 'package:explore/ui/boot_error_screen.dart';
import 'package:explore/ui/theme.dart';

void main() {
  setUp(() {
    // _boot() reads prefs and Supabase recovers its session from storage.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App boots without error', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ExploreApp(
        authOptions: FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ExploreApp), findsOneWidget);
    // Boot is async and cannot complete under flutter_test (path_provider and
    // the ephemeris isolate need a real platform), so the app should be
    // sitting in its loading state rather than on the boot-error screen.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text("Couldn't load the chart explorer"), findsNothing);
  });

  testWidgets('App stays on the loading frame rather than settling', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ExploreApp(
        authOptions: FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
        ),
      ),
    );
    // Pinning the observed behaviour: _boot neither resolves nor throws under
    // flutter_test, so the spinner persists. If a future change makes boot
    // fail fast instead, this test goes red and the boot-error assertion above
    // stops being a vacuous "not yet" — which is the trap it currently is.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(BootErrorScreen), findsNothing);
  });

  group('BootErrorScreen', () {
    testWidgets('renders the failure copy and a retry affordance', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: immersiveTheme(),
          home: BootErrorScreen(onRetry: () {}),
        ),
      );

      expect(find.text("Couldn't load the chart explorer"), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    });

    testWidgets('Try again invokes onRetry exactly once per tap', (
      WidgetTester tester,
    ) async {
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: immersiveTheme(),
          home: BootErrorScreen(onRetry: () => retries++),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pump();

      expect(retries, 1);
    });
  });
}
