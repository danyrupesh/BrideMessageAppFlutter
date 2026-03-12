import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bride_message_app/main.dart';

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
