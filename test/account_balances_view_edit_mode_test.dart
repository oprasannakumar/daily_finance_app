import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/screens/account_balances_screen.dart';
import 'package:daily_finance_app/models/account_balance_model.dart';
import 'package:daily_finance_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    final config = AccountBalanceConfig(
      bankOpeningBalances: {'HDFC Bank': 50000.0, 'SBI Bank': 25000.0},
      creditCardLimits: {
        'Axis Flipkart': CreditCardLimit(
          totalLimit: 150000.0,
          initialUsedAmount: 10000.0,
          sharedGroupName: 'Axis Cards',
          groupTotalLimit: 150000.0,
          billDay: 15,
          dueDay: 2,
        ),
      },
      cashOpeningDenominations: {500: 10, 200: 5, 100: 10},
      isConfigured: true,
    );

    await StorageService.instance.saveCategoryAccounts({
      'Bank Accounts': ['HDFC Bank', 'SBI Bank'],
      'Credit Cards': ['Axis Flipkart'],
      'Wallets': ['Paytm Wallet'],
      'Rewards': ['Flipkart SuperCoins'],
    });

    final configWithWallets = config.copyWith(
      walletOpeningBalances: {'Paytm Wallet': 1200.0},
      rewardOpeningBalances: {'Flipkart SuperCoins': 450.0},
    );
    await StorageService.instance.saveAccountBalanceConfig(configWithWallets);
  });

  testWidgets('AccountBalancesScreen initially opens in View Mode and transitions to Edit Mode on demand',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AccountBalancesScreen(),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Initial State: VIEW MODE
    expect(find.text('Balances & Limits'), findsOneWidget);
    expect(find.text('Available balances & limits overview'), findsOneWidget);
    expect(find.text('TOTAL AVAILABLE IN BANKS'), findsOneWidget);
    expect(find.text('HDFC Bank'), findsOneWidget);
    expect(find.text('SBI Bank'), findsOneWidget);

    // Edit button should be visible in AppBar and bottom bar
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Edit Balances & Limits'), findsOneWidget);

    // Opening Balance TextFields should NOT be visible in View Mode
    expect(find.byType(TextField), findsNothing);

    // 2. Tap 'Edit' to enter EDIT MODE
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    // Verify Edit Mode
    expect(find.text('Edit Balances & Limits'), findsOneWidget);
    expect(find.text('Set baseline opening balances & limits'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Save Balances & Limits'), findsOneWidget);

    // TextFields are now visible for editing
    expect(find.byType(TextField), findsWidgets);

    // 3. Tap 'Cancel' to return to VIEW MODE
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Verify returned to View Mode
    expect(find.text('Balances & Limits'), findsOneWidget);
    expect(find.text('Available balances & limits overview'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    // 4. Test Tab Switching in View Mode
    // Switch to Credit Cards Tab
    await tester.tap(find.text('Credit Cards'));
    await tester.pumpAndSettle();
    expect(find.text('TOTAL CREDIT CARDS LIMIT'), findsOneWidget);
    expect(find.text('Axis Flipkart'), findsOneWidget);
    expect(find.text('Shared: Axis Cards'), findsOneWidget);

    // Switch to Cash In Hand Tab
    await tester.tap(find.text('Cash In Hand'));
    await tester.pumpAndSettle();
    expect(find.text('TOTAL CASH IN HAND'), findsOneWidget);
    expect(find.text('Cash Denominations (3 × 3 Grid)'), findsOneWidget);

    // Switch to Wallets Tab
    await tester.tap(find.text('Wallets'));
    await tester.pumpAndSettle();
    expect(find.text('TOTAL AVAILABLE IN WALLETS'), findsOneWidget);
    expect(find.text('Paytm Wallet'), findsOneWidget);

    // Switch to Rewards Tab
    await tester.tap(find.text('Rewards'));
    await tester.pumpAndSettle();
    expect(find.text('TOTAL REWARD POINTS / BALANCE'), findsOneWidget);
    expect(find.text('Flipkart SuperCoins'), findsOneWidget);
  });

  test('removeAccountFromBalances removes account from categories and config', () async {
    final categoriesBefore = await StorageService.instance.getCategoryAccounts();
    expect(categoriesBefore['Bank Accounts']!.contains('SBI Bank'), true);

    final configBefore = await StorageService.instance.getAccountBalanceConfig();
    expect(configBefore.bankOpeningBalances.containsKey('SBI Bank'), true);

    // Remove SBI Bank
    await StorageService.instance.removeAccountFromBalances('Bank Accounts', 'SBI Bank');

    final categoriesAfter = await StorageService.instance.getCategoryAccounts();
    expect(categoriesAfter['Bank Accounts']!.contains('SBI Bank'), false);

    final configAfter = await StorageService.instance.getAccountBalanceConfig();
    expect(configAfter.bankOpeningBalances.containsKey('SBI Bank'), false);
    // HDFC Bank should remain untouched
    expect(configAfter.bankOpeningBalances.containsKey('HDFC Bank'), true);
  });
}
