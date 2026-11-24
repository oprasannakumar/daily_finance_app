import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/main.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('E2E Widget Test: Auto-Fill with Charges produces 2 modes (Gross + Reward) and Total 2575', (WidgetTester tester) async {
    const rawClipboard = '''
📅 Date: 06-09-2026
📱 App: PhonePe
👤 Name: Life Insurance Corporation (LIC)
🆔 ID: 284046757903
📝 Msg: Insurance Success
💰 Amount: 2575
💸 Charges: 28.06
📊 Direction: 🔴 OUT
⇄ Type: Credit
🏢 Account: HDFC PhonePe
🏷️ Category: Transfer to Others
🔗 Ref: REF-20260906-SYQE
''';

    // Mock clipboard channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.getData') {
          return {'text': rawClipboard};
        }
        return null;
      },
    );

    await tester.pumpWidget(const DailyFinanceApp());
    await tester.pumpAndSettle();

    // Verify Bell icon is NOT visible because dueCount == 0
    expect(find.text('🔔'), findsNothing);

    // Tap Auto-Fill button
    final autoFillBtn = find.text('Auto-Fill');
    expect(autoFillBtn, findsOneWidget);
    await tester.tap(autoFillBtn);
    await tester.pumpAndSettle();

    // Verify Fields
    expect(find.text('Paid to Life Insurance Corporation (LIC) - Insurance Success'), findsOneWidget);
    expect(find.text('REF-20260906-SYQE'), findsOneWidget);
    expect(find.text('Transfer to Others'), findsOneWidget);
    expect(find.text('Self'), findsOneWidget);

    // Verify Both Breakdowns
    // Mode 1: Credit Card / Credit, HDFC PhonePe, 2603.06
    // Mode 2: Rewards, HDFC PhonePe, -28.06
    expect(find.text('₹ 2603.06'), findsOneWidget);
    expect(find.text('-₹ 28.06'), findsOneWidget);
    expect(find.text('Rewards'), findsOneWidget);

    // Verify Total Amount is 2,575.00 (Indian currency formatted)
    expect(find.text('₹2,575.00'), findsOneWidget);
  });
}
