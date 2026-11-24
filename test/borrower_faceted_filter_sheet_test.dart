import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daily_finance_app/models/transaction_model.dart';
import 'package:daily_finance_app/widgets/borrower_faceted_filter_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testEntries = [
    LoanEntry(
      date: DateTime.now(),
      borrower: 'Alice',
      narration: 'Team Dinner',
      invoice: 'INV-001',
      transactionType: 'Credit',
      account: 'HDFC Regalia',
      givenAmount: 1200.0,
      receivedAmount: 0.0,
      referenceId: 'REF-001',
    ),
    LoanEntry(
      date: DateTime.now(),
      borrower: 'Bob',
      narration: 'Movie Tickets',
      invoice: 'INV-002',
      transactionType: 'UPI',
      account: 'SBI Savings',
      givenAmount: 500.0,
      receivedAmount: 0.0,
      referenceId: 'REF-002',
    ),
    LoanEntry(
      date: DateTime.now(),
      borrower: 'Alice',
      narration: 'Alice repayment',
      invoice: '',
      transactionType: 'UPI',
      account: 'SBI Savings',
      givenAmount: 0.0,
      receivedAmount: 1200.0,
      referenceId: 'REF-003',
    ),
  ];

  group('Borrower Faceted Filter Sheet (Flipkart / Amazon Style)', () {
    testWidgets('Displays all 9 requested category headers on left pane', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      BorrowerFilterCriteria criteria = BorrowerFilterCriteria();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BorrowerFacetedFilterSheet(
              allEntries: testEntries,
              initialCriteria: criteria,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the 9 main headers are present
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Borrower'), findsOneWidget);
      expect(find.text('Narration'), findsOneWidget);
      expect(find.text('Invoice'), findsOneWidget);
      expect(find.text('Payment Type'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Given Amount'), findsOneWidget);
      expect(find.text('Recieved Amount'), findsOneWidget);
      expect(find.text('Reference ID'), findsOneWidget);
    });

    testWidgets('Borrower and Given Amount multi-select checkboxes and counts', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      BorrowerFilterCriteria criteria = BorrowerFilterCriteria();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BorrowerFacetedFilterSheet(
              allEntries: testEntries,
              initialCriteria: criteria,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Tap Borrower category
      await tester.tap(find.text('Borrower'));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      // Select Alice
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      // Verify checkbox selected
      expect(find.byIcon(Icons.check_box), findsWidgets);

      // 2. Tap Given Amount category
      await tester.tap(find.text('Given Amount'));
      await tester.pumpAndSettle();

      // Should show distinct available given amounts
      expect(find.textContaining('1,200'), findsWidgets);

      // Select given amount
      await tester.tap(find.textContaining('1,200'));
      await tester.pumpAndSettle();

      // Deselect given amount so it doesn't cross-filter out the repayment entry
      await tester.tap(find.textContaining('1,200'));
      await tester.pumpAndSettle();

      // 3. Tap Recieved Amount category
      await tester.tap(find.text('Recieved Amount'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1,200'), findsWidgets);
    });

    testWidgets('Clear All resets all faceted categories in Borrower filter', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      BorrowerFilterCriteria criteria = BorrowerFilterCriteria(
        selectedBorrowers: {'Alice'},
        selectedPaymentTypes: {'Credit'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BorrowerFacetedFilterSheet(
              allEntries: testEntries,
              initialCriteria: criteria,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clear All'), findsOneWidget);
      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();

      expect(find.text('Clear All'), findsNothing);
    });
  });
}
