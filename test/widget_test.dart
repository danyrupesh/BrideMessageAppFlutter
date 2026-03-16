import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:MessageApp/main.dart';

void main() {
  testWidgets('App boots', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: BrideMessageApp(),
      ),
    );
    expect(find.byType(BrideMessageApp), findsOneWidget);
  });
}
