import 'package:flutter_test/flutter_test.dart';

import 'package:explore/main.dart';

void main() {
  testWidgets('App boots without error', (WidgetTester tester) async {
    await tester.pumpWidget(const ExploreApp());
    await tester.pump();
    expect(find.byType(ExploreApp), findsOneWidget);
  });
}
