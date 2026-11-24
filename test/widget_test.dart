import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DailyFinanceApp loads and renders main screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const DailyFinanceApp());
    await tester.pumpAndSettle();

    // Verify main components render
    expect(find.text('Smart Entry'), findsOneWidget);

    // Scroll to see Payment Breakdown
    await tester.scrollUntilVisible(
      find.text('💳 PAYMENT BREAKDOWN'),
      200.0,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('💳 PAYMENT BREAKDOWN'), findsOneWidget);
  });
}
