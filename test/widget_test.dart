import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explore/main.dart';

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
}
