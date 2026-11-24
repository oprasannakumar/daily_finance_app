import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/models/transaction_model.dart';
import 'package:daily_finance_app/services/storage_service.dart';
import 'package:daily_finance_app/services/google_sheets_service.dart';
import 'package:daily_finance_app/widgets/faceted_filter_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.initTheme();
    GoogleSheetsService.instance.clearSessionCache();
  });

  group('Faceted Filter Sheet (Flipkart / Amazon Style)', () {
    final transactions = [
      FinanceTransaction(
        id: 'tx_facet_1',
        date: DateTime(2026, 11, 20),
        flow: 'Withdraw',
        totalAmount: 1200.0,
        purpose: 'Dining Out',
        spentFor: 'Friends',
        invoice: 'INV-F1',
        narration: 'Team lunch at Bistro',
        referenceId: 'REF-20112026-F101',
        breakdowns: [
          PaymentBreakdown(paymentType: 'Credit', account: 'HDFC Regalia', amount: 1200.0),
        ],
      ),
      FinanceTransaction(
        id: 'tx_facet_2',
        date: DateTime(2026, 11, 21),
        flow: 'Withdraw',
        totalAmount: 350.0,
        purpose: 'Groceries',
        spentFor: 'Self',
        invoice: 'INV-F2',
        narration: 'Supermarket vegetables',
        referenceId: 'REF-21112026-F102',
        breakdowns: [
          PaymentBreakdown(paymentType: 'UPI', account: 'SBI Savings', amount: 350.0),
        ],
      ),
      FinanceTransaction(
        id: 'tx_facet_3',
        date: DateTime(2026, 11, 22),
        flow: 'Deposit',
        totalAmount: 50000.0,
        purpose: 'Salary',
        spentFor: 'Self',
        invoice: 'INV-F3',
        narration: 'Monthly corporate salary',
        referenceId: 'REF-22112026-F103',
        breakdowns: [
          PaymentBreakdown(paymentType: 'Net Banking', account: 'ICICI Salary', amount: 50000.0),
        ],
      ),
      FinanceTransaction(
        id: 'tx_facet_4',
        date: DateTime(2026, 11, 22),
        flow: 'Transfer',
        isSelfTransfer: true,
        totalAmount: 10000.0,
        purpose: 'Savings Transfer',
        spentFor: 'Self',
        invoice: 'INV-F4',
        narration: 'Fund transfer to savings',
        referenceId: 'REF-22112026-F104',
        breakdowns: [
          PaymentBreakdown(paymentType: 'Transfer', account: 'ICICI Salary', amount: 10000.0),
        ],
        toBreakdowns: [
          PaymentBreakdown(paymentType: 'Transfer', account: 'SBI Savings', amount: 10000.0),
        ],
      ),
    ];

    testWidgets('Displays all 8 category headers on the left pane', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      TransactionFilterCriteria? appliedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    appliedResult = await FacetedFilterSheet.show(
                      context: ctx,
                      allTransactions: transactions,
                      initialCriteria: TransactionFilterCriteria(),
                    );
                  },
                  child: const Text('Open Filters'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Filters'));
      await tester.pumpAndSettle();

      // Check sheet title and matching total items
      expect(find.text('Full Range Filters'), findsOneWidget);
      expect(find.text('4 items'), findsOneWidget);

      // Verify all 8 left-hand headers exist
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Narration'), findsOneWidget);
      expect(find.text('Flow'), findsOneWidget);
      expect(find.text('Spent For'), findsOneWidget);
      expect(find.text('Purpose'), findsOneWidget);
      expect(find.text('Payment Type'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Amounts'), findsOneWidget);

      // Default selected category is Flow: check right pane options
      expect(find.text('Withdraw'), findsOneWidget);
      expect(find.text('Deposit'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);

      // Select 'Withdraw' in Flow
      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();

      // Badge on Flow in left pane should now show '1'
      expect(find.text('1'), findsWidgets);

      // Total matching items in top bar should now show '2 items'
      expect(find.text('2 items'), findsOneWidget);

      // Now switch to Purpose header on the left
      await tester.tap(find.text('Purpose'));
      await tester.pumpAndSettle();

      // Under Purpose, only Dining Out (1) and Groceries (1) should have counts > 0
      expect(find.text('Dining Out'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);

      // Select 'Dining Out'
      await tester.tap(find.text('Dining Out'));
      await tester.pumpAndSettle();

      // Total matching items should now be '1 item'
      expect(find.text('1 items'), findsOneWidget);

      // Apply Filters
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      // Applied result should have selectedFlows = {'Withdraw'} and selectedPurposes = {'Dining Out'}
      expect(appliedResult, isNotNull);
      expect(appliedResult!.selectedFlows, contains('Withdraw'));
      expect(appliedResult!.selectedPurposes, contains('Dining Out'));
      expect(appliedResult!.activeFilterCount, equals(2));
    });

    testWidgets('Clear All resets all faceted categories and counts', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      TransactionFilterCriteria? appliedResult;
      final initial = TransactionFilterCriteria(
        selectedFlows: {'Deposit'},
        selectedAccounts: {'ICICI Salary'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    appliedResult = await FacetedFilterSheet.show(
                      context: ctx,
                      allTransactions: transactions,
                      initialCriteria: initial,
                    );
                  },
                  child: const Text('Open Filters'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Filters'));
      await tester.pumpAndSettle();

      // Initially 1 matching item
      expect(find.text('1 items'), findsOneWidget);

      // Tap 'Clear All' button at the top
      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();

      // Counts should restore to all 4 items
      expect(find.text('4 items'), findsOneWidget);

      // Apply Filters
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(appliedResult, isNotNull);
      expect(appliedResult!.isEmpty, isTrue);
      expect(appliedResult!.activeFilterCount, equals(0));
    });

    testWidgets('Narration category displays checkboxes and allows multi-selection', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      TransactionFilterCriteria? appliedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    appliedResult = await FacetedFilterSheet.show(
                      context: ctx,
                      allTransactions: transactions,
                      initialCriteria: TransactionFilterCriteria(),
                    );
                  },
                  child: const Text('Open Filters'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Filters'));
      await tester.pumpAndSettle();

      // Tap 'Narration' on the left pane
      await tester.tap(find.text('Narration'));
      await tester.pumpAndSettle();

      // Check that checkboxes are present (Icons.check_box_outline_blank)
      expect(find.byIcon(Icons.check_box_outline_blank), findsWidgets);

      // Checkbox items for narrations
      expect(find.text('Team lunch at Bistro'), findsOneWidget);
      expect(find.text('Supermarket vegetables'), findsOneWidget);

      // Tap first narration checkbox
      await tester.tap(find.text('Team lunch at Bistro'));
      await tester.pumpAndSettle();

      // Now an active checked checkbox icon should be present
      expect(find.byIcon(Icons.check_box), findsWidgets);

      // Total matching count should be 1
      expect(find.text('1 items'), findsOneWidget);

      // Tap Apply Filters
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(appliedResult, isNotNull);
      expect(appliedResult!.selectedNarrations, contains('Team lunch at Bistro'));
    });
  });
}
