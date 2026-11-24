import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/models/account_balance_model.dart';
import 'package:daily_finance_app/models/transaction_model.dart';
import 'package:daily_finance_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Startup Google Connect & Masters Restore Tests', () {
    test('extractAccountsFromTransactions correctly extracts bank, card, and wallet into categories', () async {
      final storage = StorageService.instance;
      await storage.saveCategoryAccounts({
        'Bank Accounts': ['HDFC Bank'],
        'Credit Cards': ['Axis Neo'],
        'Wallets': ['Paytm'],
      });

      final transactions = [
        FinanceTransaction(
          id: 'tx-1',
          date: DateTime.now(),
          referenceId: 'REF-001',
          narration: 'Shopping at Store',
          flow: 'Withdraw',
          invoice: 'INV-1',
          purpose: 'Shopping',
          spentFor: 'Self',
          breakdowns: [
            PaymentBreakdown(paymentType: 'UPI', account: 'Kotak Bank', amount: 500),
            PaymentBreakdown(paymentType: 'Credit', account: 'Axis Flipkart', amount: 1500),
            PaymentBreakdown(paymentType: 'Wallet', account: 'Amazon Pay', amount: 200),
          ],
          totalAmount: 2200,
        ),
      ];

      await storage.extractAccountsFromTransactions(transactions);

      final categories = await storage.getCategoryAccounts();
      expect(categories['Bank Accounts'], containsAll(['HDFC Bank', 'Kotak Bank']));
      expect(categories['Credit Cards'], containsAll(['Axis Neo', 'Axis Flipkart']));
      expect(categories['Wallets'], containsAll(['Paytm', 'Amazon Pay']));
    });

    test('AccountBalanceConfig serializes and deserializes with shared limits and billing dates', () {
      final config = AccountBalanceConfig(
        isConfigured: true,
        setupDate: DateTime(2026, 11, 24),
        bankOpeningBalances: {
          'Kotak 811': 25000.0,
        },
        creditCardLimits: {
          'Axis Flipkart': const CreditCardLimit(
            totalLimit: 100000.0,
            initialUsedAmount: 15000.0,
            sharedGroupName: 'Axis Shared Group',
            groupTotalLimit: 100000.0,
            billDay: 15,
            dueDay: 5,
            statementBilledAmount: 12000.0,
          ),
          'Axis Neo': const CreditCardLimit(
            totalLimit: 100000.0,
            initialUsedAmount: 5000.0,
            sharedGroupName: 'Axis Shared Group',
            groupTotalLimit: 100000.0,
            billDay: 20,
            dueDay: 10,
            statementBilledAmount: 4500.0,
          ),
        },
        cashOpeningDenominations: {
          500: 10,
          200: 5,
          100: 10,
          50: 4,
          20: 5,
          10: 10,
        },
      );

      final json = config.toJson();
      final roundTrip = AccountBalanceConfig.fromJson(json);

      expect(roundTrip.isConfigured, isTrue);
      expect(roundTrip.bankOpeningBalances['Kotak 811'], 25000.0);
      expect(roundTrip.creditCardLimits.length, 2);
      expect(roundTrip.creditCardLimits['Axis Flipkart']!.sharedGroupName, 'Axis Shared Group');
      expect(roundTrip.creditCardLimits['Axis Flipkart']!.billDay, 15);
      expect(roundTrip.creditCardLimits['Axis Flipkart']!.dueDay, 5);
      expect(roundTrip.creditCardLimits['Axis Flipkart']!.statementBilledAmount, 12000.0);
      expect(roundTrip.totalCashInHand, 7400.0);
    });

    test('Restoring masters JSON payload updates StorageService accurately', () async {
      final storage = StorageService.instance;

      final testPurposes = ['Groceries', 'Utilities', 'Investment'];
      final testSpentFors = ['Self', 'Family', 'Friends'];
      final testCategories = {
        'Bank Accounts': ['HDFC', 'SBI'],
        'Credit Cards': ['ICICI Amazon Pay'],
      };
      final List<TransactionTemplate> testTemplates = [
        TransactionTemplate(
          id: 'tmpl-1',
          name: 'Monthly Rent',
          narration: 'Rent for Flat',
          flow: 'Withdraw',
          purpose: 'Rent',
          spentFor: 'Self',
          breakdowns: [
            PaymentBreakdown(paymentType: 'UPI', account: 'HDFC', amount: 15000),
          ],
        ),
      ];
      final List<RecurringTransaction> testRecurring = [
        RecurringTransaction(
          id: 'rec-1',
          narration: 'Nifty 50 Index SIP',
          flow: 'Withdraw',
          purpose: 'Investment',
          spentFor: 'Self',
          breakdowns: [
            PaymentBreakdown(paymentType: 'UPI', account: 'HDFC', amount: 5000),
          ],
          totalAmount: 5000,
          frequency: 'Monthly',
          nextDueDate: DateTime(2026, 12, 1),
          isPaused: false,
        ),
      ];

      // Save payloads
      await storage.savePurposes(testPurposes);
      await storage.saveSpentFors(testSpentFors);
      await storage.saveCategoryAccounts(testCategories);
      await storage.saveAllTemplates(testTemplates);
      await storage.saveAllRecurringTransactions(testRecurring);

      // Verify retrieval
      expect(await storage.getPurposes(), containsAll(testPurposes));
      expect(await storage.getSpentFors(), containsAll(testSpentFors));
      final cats = await storage.getCategoryAccounts();
      expect(cats['Bank Accounts'], ['HDFC', 'SBI']);
      expect(cats['Credit Cards'], ['ICICI Amazon Pay']);

      final tmpls = await storage.getTemplates();
      expect(tmpls.length, 1);
      expect(tmpls.first.name, 'Monthly Rent');

      final recs = await storage.getRecurringTransactions();
      expect(recs.length, 1);
      expect(recs.first.narration, 'Nifty 50 Index SIP');
    });

    test('LiveAccountBalanceSummary correctly calculates due badges and shared limit pooling', () {
      final config = AccountBalanceConfig(
        isConfigured: true,
        setupDate: DateTime(2026, 11, 24),
        bankOpeningBalances: {
          'Kotak 811': 50000.0,
        },
        creditCardLimits: {
          'Axis Flipkart': const CreditCardLimit(
            totalLimit: 100000.0,
            initialUsedAmount: 10000.0,
            sharedGroupName: 'Axis Shared Group',
            groupTotalLimit: 100000.0,
            billDay: 15,
            dueDay: 5,
            statementBilledAmount: 10000.0,
          ),
          'Axis Neo': const CreditCardLimit(
            totalLimit: 100000.0,
            initialUsedAmount: 5000.0,
            sharedGroupName: 'Axis Shared Group',
            groupTotalLimit: 100000.0,
            billDay: 20,
            dueDay: 10,
            statementBilledAmount: 0.0,
          ),
        },
        cashOpeningDenominations: {},
      );

      final summary = LiveAccountBalanceSummary.calculate(
        config: config,
        transactions: [],
        categories: {
          'Bank Accounts': ['Kotak 811'],
          'Credit Cards': ['Axis Flipkart', 'Axis Neo'],
          'Wallets': [],
        },
        referenceDate: DateTime(2026, 11, 24),
      );

      // Total shared group limit = 100,000. Total used = 10,000 + 5,000 = 15,000.
      // Shared remaining = 85,000.
      final flipkartCard = summary.creditCardSummaries['Axis Flipkart']!;
      expect(flipkartCard.availableLimit, 85000.0);

      final neoCard = summary.creditCardSummaries['Axis Neo']!;
      expect(neoCard.availableLimit, 85000.0);

      // Check due bills
      expect(summary.dueBills.length, 2);
      final flipkartDue = summary.dueBills.firstWhere((b) => b.cardName == 'Axis Flipkart');
      expect(flipkartDue.remainingDue, 10000.0);
    });
  });
}
