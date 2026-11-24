import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daily_finance_app/main.dart';
import 'package:daily_finance_app/models/transaction_model.dart';
import 'package:daily_finance_app/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.initTheme();
  });

  testWidgets('Recurrence toggle and custom interval dialog test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const DailyFinanceApp());
    await tester.pumpAndSettle();

    // Verify main screen loaded
    expect(find.text('Smart Entry'), findsOneWidget);

    // Verify sand timer icon is present
    expect(find.text('⌛'), findsOneWidget);

    // Tap sand timer icon to enable recurrence mode
    await tester.tap(find.text('⌛'));
    await tester.pumpAndSettle();

    // Verify recurrence frequency dropdown is visible
    expect(find.text('⏳ RECURRENCE FREQUENCY'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);

    // Tap dropdown to select 'Custom'
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom').last);
    await tester.pumpAndSettle();

    // Custom dialog appears
    expect(find.text('Custom Recurrence'), findsOneWidget);
    expect(find.text('Months (Optional)'), findsOneWidget);
    expect(find.text('Days (Optional)'), findsOneWidget);

    // Enter 3 months and 15 days
    await tester.enterText(find.widgetWithText(TextField, 'Months (Optional)'), '3');
    await tester.enterText(find.widgetWithText(TextField, 'Days (Optional)'), '15');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Custom (3 months, 15 days)'), findsOneWidget);

    // Toggle sand timer back to off
    await tester.tap(find.text('⌛'));
    await tester.pumpAndSettle();

    // Verify recurrence dropdown is hidden
    expect(find.text('⏳ RECURRENCE FREQUENCY'), findsNothing);
  });

  testWidgets('Recurrence bell badge, popup display and forwarding on Save', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    final storage = StorageService.instance;
    final today = DateTime.now();

    // Save a due recurring transaction (nextDueDate is today)
    await storage.saveRecurringTransaction(
      RecurringTransaction(
        id: 'rec_electricity',
        narration: 'Electricity Bill',
        nextDueDate: today,
        frequency: 'Month',
        totalAmount: 1850,
        flow: 'Withdraw',
        purpose: 'Rent & Utilities',
        spentFor: 'Home',
        breakdowns: [PaymentBreakdown(paymentType: 'UPI', account: 'HDFC Bank A/c', amount: 1850)],
      ),
    );

    await tester.pumpWidget(const DailyFinanceApp());
    await tester.pumpAndSettle();

    // Verify Bell icon badge shows '1' since 1 recurrence is due today
    expect(find.text('🔔'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // Tap bell icon to open recurrence popup
    await tester.tap(find.text('🔔'));
    await tester.pumpAndSettle();

    // Verify recurring popup shows Narration, Date, and Amount ONLY (Indian formatted)
    expect(find.text('Recurring Transactions'), findsOneWidget);
    expect(find.text('Electricity Bill'), findsOneWidget);
    expect(find.text('₹1,850'), findsOneWidget);

    // Tap the recurring item to load it into the form excluding recurrence mode
    await tester.tap(find.text('Electricity Bill'));
    await tester.pumpAndSettle();

    // Verify popup closed and form loaded
    expect(find.text('Recurring Transactions'), findsNothing);
    expect(find.text('⏳ RECURRENCE FREQUENCY'), findsNothing); // recurrence mode is excluded!
    expect(find.text('Electricity Bill'), findsOneWidget);

    // Hit Save button
    await tester.scrollUntilVisible(
      find.text('Save'),
      200.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Verify regular transaction was saved
    final savedTxs = await storage.getTransactions();
    expect(savedTxs.any((t) => t.narration == 'Electricity Bill'), isTrue);

    // Verify recurrence nextDueDate was forwarded to next month
    final updatedRecurrences = await storage.getRecurringTransactions();
    final updatedBill = updatedRecurrences.firstWhere((r) => r.id == 'rec_electricity');
    expect(updatedBill.nextDueDate.isAfter(today), isTrue);

    // Verify bell badge is cleared (0 due)
    await tester.pumpAndSettle();
    expect(find.text('1'), findsNothing);
  });
}
