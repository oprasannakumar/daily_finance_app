import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/main.dart';
import 'package:daily_finance_app/models/transaction_model.dart';
import 'package:daily_finance_app/services/ai_transaction_service.dart';
import 'package:daily_finance_app/services/google_sheets_service.dart';
import 'package:daily_finance_app/services/quick_nav_controller.dart';
import 'package:daily_finance_app/services/storage_service.dart';
import 'package:daily_finance_app/screens/workspace_hub_screen.dart';
import 'package:daily_finance_app/widgets/swipe_to_delete_wrapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleSheetsService.instance.clearSessionCache();
  });

  testWidgets('MainShellScreen switches across Entry, History, Wallet, People, and Hub', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const DailyFinanceApp());
    await tester.pumpAndSettle();

    // Floating dock shows all 5 workspace tabs + Tap to Auto-Fill replaces Hero Total
    expect(find.text('Entry'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Hub'), findsOneWidget);
    expect(find.text('Smart Entry'), findsOneWidget);
    expect(find.text('Tap to Auto-Fill'), findsOneWidget);
    expect(find.text('TRANSACTION TOTAL'), findsNothing);

    // Switch to History workspace
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsNWidgets(2)); // Dock label + AppBar title
    expect(find.text('Filters'), findsOneWidget);

    // Switch to Wallet (Balances & Limits) workspace
    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Balances & Limits'), findsOneWidget);

    // Switch to People (Borrowers Ledger) workspace
    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    expect(find.text('🤝 Borrowers Ledger'), findsOneWidget);

    // Switch to Hub workspace & verify Bento grid
    await tester.tap(find.text('Hub'));
    await tester.pumpAndSettle();
    expect(find.text('LIQUID WEALTH SNAPSHOT'), findsOneWidget);
    expect(find.text('WORKSPACES'), findsOneWidget);
    expect(find.text('Financial Health'), findsOneWidget);
    expect(find.text('Invoice Studio'), findsOneWidget);
    expect(find.text('EMI Tracker'), findsOneWidget);
    expect(find.text('Manage Masters'), findsOneWidget);
    expect(find.text('Saved Templates'), findsOneWidget);
    expect(find.text('Recurring Bills'), findsOneWidget);

    // Scroll down in Hub's outer ListView to see Cloud & AI Engine cards
    final hubScroll = find.descendant(
      of: find.byType(WorkspaceHubScreen),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('AI Engine & API Keys'),
      200.0,
      scrollable: hubScroll.first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Google Sheets Sync'), findsOneWidget);
    expect(find.text('AI Engine & API Keys'), findsOneWidget);

    // Programmatic QuickNavController switch back to Entry
    QuickNavController.instance.switchShellTab('Entry');
    await tester.pumpAndSettle();
    expect(find.text('Smart Entry'), findsOneWidget);
  });

  testWidgets('WorkspaceHubScreen invokes route callback for Bento cards', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    String? navigatedRoute;

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceHubScreen(
          onNavigateTool: (route) => navigatedRoute = route,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invoice Studio'));
    await tester.pump();
    expect(navigatedRoute, 'Invoices');

    await tester.tap(find.text('Financial Health'));
    await tester.pump();
    expect(navigatedRoute, 'Dashboard');
  });

  testWidgets('Editing a transaction log from History dock tab loads into Entry without crashing', (
    WidgetTester tester,
  ) async {
    final tx = FinanceTransaction(
      id: 'tx_edit_shell_1',
      date: DateTime(2026, 11, 27),
      flow: 'Withdraw',
      totalAmount: 450.0,
      purpose: 'Food',
      spentFor: 'Self',
      invoice: '',
      narration: 'Coffee Shop',
      referenceId: 'REF-27112026-EDIT1',
      breakdowns: [
        PaymentBreakdown(paymentType: 'UPI', account: 'GPay', amount: 450.0),
      ],
    );
    await StorageService.instance.saveTransaction(tx);

    await tester.pumpWidget(const DailyFinanceApp());
    await tester.pumpAndSettle();

    // Go to History tab in MainShellScreen
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('Coffee Shop'), findsOneWidget);
    await tester.tap(find.text('Coffee Shop'));
    await tester.pumpAndSettle();

    // Scroll inside DraggableScrollableSheet to Edit button and tap it (previously crashed on root pop)
    final sheetScroll = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('Edit'),
      150.0,
      scrollable: sheetScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    // Switched back cleanly to Smart Entry with log loaded for editing
    expect(find.text('Smart Entry'), findsOneWidget);
    expect(find.text('Coffee Shop'), findsOneWidget);
    expect(find.textContaining('Loaded for editing:'), findsOneWidget);
  });

  testWidgets('SwipeToDeleteWrapper reveals disjoint LOAD and DELETE strips without bleed or overflow', (
    WidgetTester tester,
  ) async {
    var deleted = false;
    var loaded = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: SwipeToDeleteWrapper(
              onDelete: () => deleted = true,
              onSwipeRight: () => loaded = true,
              rightLabel: 'LOAD',
              child: Container(
                height: 56,
                color: Colors.white,
                alignment: Alignment.center,
                child: const Text('Row Item'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Partial left swipe reveals DELETE pill beside the sliding child without overflow
    await tester.drag(find.text('Row Item'), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(find.text('DELETE'), findsOneWidget);
    expect(deleted, isFalse);

    // Partial right swipe reveals LOAD pill cleanly
    await tester.drag(find.text('Row Item'), const Offset(190, 0));
    await tester.pumpAndSettle();
    expect(find.text('LOAD'), findsOneWidget);
    expect(loaded, isFalse);

    // Tap revealed LOAD pill triggers right action
    await tester.tap(find.text('LOAD'));
    await tester.pumpAndSettle();
    expect(loaded, isTrue);
  });

  test('AiTransactionService parses HDFC card SMS as Credit Withdraw (not Self Transfer)', () {
    const sms =
        'Spent Rs.324 On HDFC Bank Card 4179 At AVENUE SUPERMARTS LIMI On 2026-11-27:14:54:01.Not You? To Block+Reissue Call 18002586161/SMS BLOCK CC 4179 to 7308080808';

    final parsed = AiTransactionService.instance.parseLocalRulesOnly(
      userInput: sms,
      purposes: const ['Groceries', 'Food & Dining', 'Others'],
      spentFors: const ['Self', 'Home'],
      categoryAccounts: const {
        'Credit Cards': ['HDFC Millennia 4179', 'Axis MyZone'],
        'Bank Accounts': ['HDFC Bank', 'SBI Bank'],
      },
    );

    expect(parsed.isSelfTransfer, isFalse);
    expect(parsed.flow, 'Withdraw');
    expect(parsed.amount, 324.0);
    expect(parsed.paymentType, 'Credit');
    expect(parsed.account, 'HDFC Millennia 4179');
    expect(parsed.purpose, 'Groceries');
    expect(parsed.date, DateTime(2026, 11, 27));
    expect(parsed.narration.contains('7308080808'), isFalse);
    expect(parsed.narration.toLowerCase().contains('avenue supermarts'), isTrue);
  });
}
