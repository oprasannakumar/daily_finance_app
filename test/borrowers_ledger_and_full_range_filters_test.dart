import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/models/transaction_model.dart';
import 'package:daily_finance_app/services/storage_service.dart';
import 'package:daily_finance_app/services/google_sheets_service.dart';
import 'package:daily_finance_app/screens/borrowers_ledger_screen.dart';
import 'package:daily_finance_app/screens/transaction_history_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.initTheme();
    GoogleSheetsService.instance.clearSessionCache();
  });

  group('Borrowers Ledger & Full Range Filters Tests', () {
    testWidgets('BorrowersLedgerScreen displays loan entries, metrics and faceted filters', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final tx1 = FinanceTransaction(
        id: 'tx_borrower_1',
        date: DateTime.now(),
        flow: 'Withdraw',
        totalAmount: 3000.0,
        purpose: 'Dinner Party',
        spentFor: 'Split',
        invoice: 'INV-101',
        narration: 'Weekend dinner with team',
        referenceId: 'REF-22112026-AAAA',
        breakdowns: [
          PaymentBreakdown(paymentType: 'Credit', account: 'HDFC Regalia', amount: 3000.0),
        ],
        isSplitMode: true,
        splitRecipients: [
          SplitRecipient(name: 'Alice', amount: 1000.0, percentage: 33.3, isPersonal: false),
          SplitRecipient(name: 'Bob', amount: 1000.0, percentage: 33.3, isPersonal: false),
          SplitRecipient(name: 'Personal Share', amount: 1000.0, percentage: 33.3, isPersonal: true),
        ],
      );

      final tx2 = FinanceTransaction(
        id: 'tx_borrower_2',
        date: DateTime.now(),
        flow: 'Deposit',
        totalAmount: 500.0,
        purpose: 'Loan Repayment Received',
        spentFor: 'Split',
        invoice: 'INV-102',
        narration: 'Bob repaid dinner share',
        referenceId: 'REF-22112026-BBBB',
        breakdowns: [
          PaymentBreakdown(paymentType: 'UPI', account: 'SBI Savings', amount: 500.0),
        ],
        isSplitMode: true,
        splitRecipients: [
          SplitRecipient(name: 'Bob', amount: 500.0, percentage: 100.0, isPersonal: false),
        ],
      );

      await StorageService.instance.saveTransaction(tx1);
      await StorageService.instance.saveTransaction(tx2);

      await tester.pumpWidget(
        const MaterialApp(
          home: BorrowersLedgerScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify screen title and loan entries rendered
      expect(find.text('🤝 Borrowers Ledger'), findsOneWidget);
      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Bob'), findsWidgets);

      // Verify Given and Received badges
      expect(find.text('GIVEN'), findsWidgets);
      expect(find.text('RECEIVED'), findsWidgets);

      // Verify there is NO redundant flatpicker date button below the search bar
      expect(find.text('All Dates'), findsNothing);

      // Open Filters modal
      expect(find.text('Filters'), findsOneWidget);
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();

      // Verify Borrower Faceted filter sheet opened with 9 headers matching History
      expect(find.text('Full Range Filters'), findsOneWidget);
      expect(find.text('Borrower'), findsOneWidget);

      // Tap Borrower category and pick Alice
      await tester.tap(find.text('Borrower'));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsWidgets);
      await tester.tap(find.text('Alice').last);
      await tester.pumpAndSettle();

      // Tap Apply Filters
      await tester.tap(find.textContaining('Apply Filters'));
      await tester.pumpAndSettle();

      // Bob's repayment should be filtered out
      expect(find.text('Bob repaid dinner share'), findsNothing);
      expect(find.text('Weekend dinner with team'), findsWidgets);

      // Verify active chip for Alice is present
      expect(find.text('👤 Alice'), findsOneWidget);

      // Clear filter using active chip
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      // Both should be visible again
      expect(find.text('Weekend dinner with team'), findsWidgets);
      expect(find.text('Bob repaid dinner share'), findsWidgets);
    });

    testWidgets('TransactionHistoryScreen full range filters filter by Card/Account and Purpose', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final tx1 = FinanceTransaction(
        id: 'tx_hist_1',
        date: DateTime.now(),
        flow: 'Withdraw',
        totalAmount: 1500.0,
        purpose: 'Food & Groceries',
        spentFor: 'Self',
        invoice: 'INV-201',
        narration: 'Grocery run',
        referenceId: 'REF-22112026-CCCC',
        breakdowns: [
          PaymentBreakdown(paymentType: 'Credit', account: 'HDFC Regalia', amount: 1500.0),
        ],
      );

      final tx2 = FinanceTransaction(
        id: 'tx_hist_2',
        date: DateTime.now(),
        flow: 'Withdraw',
        totalAmount: 400.0,
        purpose: 'Fuel & Transport',
        spentFor: 'Self',
        invoice: 'INV-202',
        narration: 'Petrol bunk',
        referenceId: 'REF-22112026-DDDD',
        breakdowns: [
          PaymentBreakdown(paymentType: 'UPI', account: 'SBI Savings', amount: 400.0),
        ],
      );

      await StorageService.instance.saveTransaction(tx1);
      await StorageService.instance.saveTransaction(tx2);

      await tester.pumpWidget(
        const MaterialApp(
          home: TransactionHistoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Both should be visible initially
      expect(find.text('Grocery run'), findsOneWidget);
      expect(find.text('Petrol bunk'), findsOneWidget);

      // Open Full Range Filters modal
      expect(find.text('Filters'), findsOneWidget);
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();

      expect(find.text('Full Range Filters'), findsOneWidget);

      // In the two-pane Flipkart/Amazon filter, tap 'Account' category in the left pane
      expect(find.text('Account'), findsOneWidget);
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();

      // Tap HDFC Regalia filter in the right pane
      expect(find.text('HDFC Regalia'), findsOneWidget);
      await tester.tap(find.text('HDFC Regalia'));
      await tester.pumpAndSettle();

      // Tap Apply Filters
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      // Now only Grocery run (HDFC Regalia) should be visible
      expect(find.text('Grocery run'), findsOneWidget);
      expect(find.text('Petrol bunk'), findsNothing);

      // Active filter chip should appear
      expect(find.text('💳 HDFC Regalia'), findsOneWidget);

      // Tapping 'Clear' removes the filter
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      // Both should be visible again
      expect(find.text('Grocery run'), findsOneWidget);
      expect(find.text('Petrol bunk'), findsOneWidget);
    });
  });
}
