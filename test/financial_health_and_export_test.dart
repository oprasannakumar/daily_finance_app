import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/models/account_balance_model.dart';
import 'package:daily_finance_app/models/financial_health_model.dart';
import 'package:daily_finance_app/models/transaction_model.dart';
import 'package:daily_finance_app/screens/financial_health_dashboard_screen.dart';
import 'package:daily_finance_app/services/statement_export_service.dart';
import 'package:daily_finance_app/widgets/statement_export_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Financial Health & Net Liquidity Engine Tests', () {
    test('Calculates Net Liquidity, Credit Utilization, and LCR accurately', () {
      final config = AccountBalanceConfig(
        isConfigured: true,
        setupDate: DateTime(2026, 11, 1),
        bankOpeningBalances: {
          'HDFC Bank': 60000.0,
          'SBI Savings': 40000.0,
        },
        creditCardLimits: {
          'Axis Flipkart': const CreditCardLimit(
            totalLimit: 100000.0,
            initialUsedAmount: 15000.0,
            billDay: 15,
            dueDay: 5,
            statementBilledAmount: 15000.0,
          ),
          'ICICI Amazon': const CreditCardLimit(
            totalLimit: 100000.0,
            initialUsedAmount: 5000.0,
            billDay: 20,
            dueDay: 10,
            statementBilledAmount: 5000.0,
          ),
        },
        cashOpeningDenominations: {
          500: 20, // 10,000
        },
      );

      final balanceSummary = LiveAccountBalanceSummary.calculate(
        config: config,
        transactions: [],
        categories: {
          'Bank Accounts': ['HDFC Bank', 'SBI Savings'],
          'Credit Cards': ['Axis Flipkart', 'ICICI Amazon'],
          'Wallets': [],
        },
        referenceDate: DateTime(2026, 11, 24),
      );

      final transactions = [
        FinanceTransaction(
          id: 'tx-1',
          date: DateTime(2026, 11, 10),
          referenceId: 'REF-01',
          narration: 'Monthly Salary',
          flow: 'Deposit',
          invoice: '',
          purpose: 'Salary & Income',
          spentFor: 'Self',
          breakdowns: [
            PaymentBreakdown(paymentType: 'Net', account: 'HDFC Bank', amount: 50000.0),
          ],
          totalAmount: 50000.0,
        ),
        FinanceTransaction(
          id: 'tx-2',
          date: DateTime(2026, 11, 12),
          referenceId: 'REF-02',
          narration: 'Grocery Mart',
          flow: 'Withdraw',
          invoice: '',
          purpose: 'Food & Groceries',
          spentFor: 'Self',
          breakdowns: [
            PaymentBreakdown(paymentType: 'UPI', account: 'HDFC Bank', amount: 10000.0),
          ],
          totalAmount: 10000.0,
        ),
      ];

      final health = FinancialHealthSummary.calculate(
        balanceSummary: balanceSummary,
        transactions: transactions,
        referenceDate: DateTime(2026, 11, 24),
      );

      // Banks = 100,000, Cash = 10,000 => Liquid Assets = 110,000
      expect(health.totalLiquidAssets, 110000.0);

      // Total Credit Used = 20,000 => Net Liquidity = 110,000 - 20,000 = 90,000
      expect(health.totalCreditCardLiabilities, 20000.0);
      expect(health.netLiquidity, 90000.0);

      // Credit utilization = 20,000 / 200,000 = 10%
      expect(health.creditUtilizationPercent, 10.0);
      expect(health.creditHealthStatus, CreditHealthStatus.excellent);

      // Cash flow
      expect(health.currentMonthInflow, 50000.0);
      expect(health.currentMonthOutflow, 10000.0);
      expect(health.netMonthlySavings, 40000.0);
      expect(health.monthlySavingsRatePercent, 80.0);

      // Asset Allocation
      expect(health.assetAllocation['Bank Accounts'], 100000.0);
      expect(health.assetAllocation['Cash in Hand'], 10000.0);
    });

    test('Statement Export Service generates valid CSV with BOM and summary', () {
      final transactions = [
        FinanceTransaction(
          id: 'tx-1',
          date: DateTime(2026, 11, 15),
          referenceId: 'REF-20261115-001',
          narration: 'Supermarket shopping',
          flow: 'Withdraw',
          purpose: 'Food & Groceries',
          spentFor: 'Home',
          invoice: 'INV-99',
          breakdowns: [
            PaymentBreakdown(paymentType: 'UPI', account: 'Kotak Bank', amount: 2500.0),
          ],
          totalAmount: 2500.0,
        ),
        FinanceTransaction(
          id: 'tx-2',
          date: DateTime(2026, 11, 18),
          referenceId: 'REF-20261118-002',
          narration: 'Freelance payment received',
          flow: 'Deposit',
          purpose: 'Salary & Income',
          spentFor: 'Self',
          invoice: '',
          breakdowns: [
            PaymentBreakdown(paymentType: 'Net', account: 'HDFC Bank', amount: 15000.0),
          ],
          totalAmount: 15000.0,
        ),
      ];

      final csv = StatementExportService.instance.generateCsvReport(
        transactions: transactions,
        options: const StatementFilterOptions(title: 'November 2026 Test Statement'),
      );

      // Ensure UTF-8 BOM
      expect(csv.startsWith('\uFEFF'), isTrue);

      // Verify headers and content
      expect(csv, contains('"DAILY FINANCE STATEMENT"'));
      expect(csv, contains('November 2026 Test Statement'));
      expect(csv, contains('REF-20261115-001'));
      expect(csv, contains('Supermarket shopping'));
      expect(csv, contains('Kotak Bank'));
      expect(csv, contains('2500.00'));
      expect(csv, contains('Freelance payment received'));
      expect(csv, contains('15000.00'));
    });

    test('Statement Filter Options filters by date, account, and purpose accurately', () {
      final tx1 = FinanceTransaction(
        id: 'tx-1',
        date: DateTime(2026, 11, 5),
        referenceId: 'REF-01',
        narration: 'Coffee',
        flow: 'Withdraw',
        invoice: '',
        purpose: 'Food & Groceries',
        spentFor: 'Self',
        breakdowns: [PaymentBreakdown(paymentType: 'UPI', account: 'HDFC Bank', amount: 150.0)],
        totalAmount: 150.0,
      );

      final tx2 = FinanceTransaction(
        id: 'tx-2',
        date: DateTime(2026, 11, 20),
        referenceId: 'REF-02',
        narration: 'Shopping Mall',
        flow: 'Withdraw',
        invoice: '',
        purpose: 'Shopping',
        spentFor: 'Family',
        breakdowns: [PaymentBreakdown(paymentType: 'Credit', account: 'Axis Neo', amount: 3500.0)],
        totalAmount: 3500.0,
      );

      final service = StatementExportService.instance;

      // Filter by Purpose: Shopping
      final shoppingOnly = service.filterTransactions(
        transactions: [tx1, tx2],
        options: const StatementFilterOptions(purposeFilter: 'Shopping'),
      );
      expect(shoppingOnly.length, 1);
      expect(shoppingOnly.first.referenceId, 'REF-02');

      // Filter by Account: HDFC Bank
      final hdfcOnly = service.filterTransactions(
        transactions: [tx1, tx2],
        options: const StatementFilterOptions(accountFilter: 'HDFC Bank'),
      );
      expect(hdfcOnly.length, 1);
      expect(hdfcOnly.first.referenceId, 'REF-01');

      // Filter by Date Range: Nov 10 to Nov 25
      final dateFiltered = service.filterTransactions(
        transactions: [tx1, tx2],
        options: StatementFilterOptions(
          startDate: DateTime(2026, 11, 10),
          endDate: DateTime(2026, 11, 25),
        ),
      );
      expect(dateFiltered.length, 1);
      expect(dateFiltered.first.referenceId, 'REF-02');
    });

    testWidgets('StatementExportDialog renders and displays matched count', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    StatementExportDialog.show(context);
                  },
                  child: const Text('Open Export'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Export'));
      await tester.pumpAndSettle();

      expect(find.text('Export Financial Statement'), findsOneWidget);
      expect(find.text('This Month'), findsOneWidget);
      expect(find.text('Preview / Print'), findsOneWidget);
      expect(find.text('Export Excel / CSV'), findsOneWidget);
    });

    testWidgets('FinancialHealthDashboardScreen renders smoothly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FinancialHealthDashboardScreen(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Financial Health & Liquidity'), findsOneWidget);
      expect(find.text('NET LIQUIDITY'), findsOneWidget);
      expect(find.text('Credit Card Utilization'), findsOneWidget);
    });

    test('BorrowerStatementSummary calculates total given, received and net due correctly', () {
      final entries = [
        LoanEntry(
          date: DateTime(2026, 11, 10),
          borrower: 'Ramesh',
          narration: 'Dinner split',
          givenAmount: 1500.0,
          receivedAmount: 0.0,
          referenceId: 'REF-001',
        ),
        LoanEntry(
          date: DateTime(2026, 11, 15),
          borrower: 'Ramesh',
          narration: 'UPI return',
          givenAmount: 0.0,
          receivedAmount: 1000.0,
          referenceId: 'REF-002',
        ),
        LoanEntry(
          date: DateTime(2026, 11, 18),
          borrower: 'Suresh',
          narration: 'Cab ride',
          givenAmount: 500.0,
          receivedAmount: 0.0,
          referenceId: 'REF-003',
        ),
      ];

      final summary = BorrowerStatementSummary.calculate(entries);
      expect(summary.totalEntries, 3);
      expect(summary.totalGiven, 2000.0);
      expect(summary.totalReceived, 1000.0);
      expect(summary.netDue, 1000.0);

      expect(summary.borrowerBreakdowns['Ramesh']!.given, 1500.0);
      expect(summary.borrowerBreakdowns['Ramesh']!.received, 1000.0);
      expect(summary.borrowerBreakdowns['Ramesh']!.net, 500.0);

      expect(summary.borrowerBreakdowns['Suresh']!.given, 500.0);
      expect(summary.borrowerBreakdowns['Suresh']!.net, 500.0);
    });
  });
}
