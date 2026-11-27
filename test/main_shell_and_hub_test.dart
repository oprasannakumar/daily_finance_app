import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/main.dart';
import 'package:daily_finance_app/services/quick_nav_controller.dart';
import 'package:daily_finance_app/screens/workspace_hub_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MainShellScreen switches across Entry, History, Wallet, People, and Hub', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const DailyFinanceApp());
    await tester.pumpAndSettle();

    // Floating dock shows all 5 workspace tabs
    expect(find.text('Entry'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Hub'), findsOneWidget);
    expect(find.text('Smart Entry'), findsOneWidget);

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
}
