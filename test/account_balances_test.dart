import 'package:flutter_test/flutter_test.dart';
import 'package:daily_finance_app/models/account_balance_model.dart';
import 'package:daily_finance_app/models/transaction_model.dart';
import 'package:daily_finance_app/utils/currency_formatter.dart';

void main() {
  group('AccountBalanceConfig and Live Calculation Tests', () {
    test('Calculates live balances, CC limits, and cash denominations accurately', () {
      final baselineDate = DateTime(2026, 11, 23);

      final config = AccountBalanceConfig(
        setupDate: baselineDate,
        isConfigured: true,
        bankOpeningBalances: {
          'HDFC Bank A/c': 50000.0,
          'SBI Savings A/c': 20000.0,
        },
        creditCardLimits: {
          'HDFC Regalia Card': const CreditCardLimit(totalLimit: 150000.0, initialUsedAmount: 30000.0),
        },
        cashOpeningDenominations: {
          500: 10, // 5000
          200: 5,  // 1000
          100: 10, // 1000
          50: 0,
          20: 0,
          10: 0,
          5: 0,
          2: 0,
          1: 0,
        },
      );

      expect(config.totalCashInHand, 7000.0);
      expect(config.creditCardLimits['HDFC Regalia Card']!.initialAvailableLimit, 120000.0);

      final categories = {
        'Bank Accounts': ['HDFC Bank A/c', 'SBI Savings A/c'],
        'Credit Cards': ['HDFC Regalia Card'],
      };

      // Transaction 1: Expense from HDFC Bank A/c (Withdraw ₹5,000)
      final tx1 = FinanceTransaction(
        id: 'tx_1',
        date: DateTime(2026, 11, 23, 10, 0),
        referenceId: '261123-0001',
        narration: 'Grocery shopping',
        flow: 'Withdraw',
        invoice: 'INV-1',
        purpose: 'Food & Groceries',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(
            paymentType: 'UPI',
            account: 'HDFC Bank A/c',
            amount: 5000.0,
          ),
        ],
        totalAmount: 5000.0,
      );

      // Transaction 2: Expense on Credit Card (Withdraw ₹10,000)
      final tx2 = FinanceTransaction(
        id: 'tx_2',
        date: DateTime(2026, 11, 23, 12, 0),
        referenceId: '261123-0002',
        narration: 'Flight tickets',
        flow: 'Withdraw',
        invoice: 'INV-2',
        purpose: 'Travel',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(
            paymentType: 'Credit',
            account: 'HDFC Regalia Card',
            amount: 10000.0,
          ),
        ],
        totalAmount: 10000.0,
      );

      // Transaction 3: Self Transfer (Pay credit card bill: HDFC Bank -> HDFC Regalia Card ₹15,000)
      final tx3 = FinanceTransaction(
        id: 'tx_3',
        date: DateTime(2026, 11, 23, 14, 0),
        referenceId: '261123-0003',
        narration: 'Cleared card bill',
        flow: 'Transfer',
        invoice: 'INV-3',
        purpose: 'Self Transfer',
        spentFor: 'Self',
        isSelfTransfer: true,
        breakdowns: [
          PaymentBreakdown(
            paymentType: 'Net',
            account: 'HDFC Bank A/c',
            amount: 15000.0,
          ),
        ],
        toBreakdowns: [
          PaymentBreakdown(
            paymentType: 'Credit',
            account: 'HDFC Regalia Card',
            amount: 15000.0,
          ),
        ],
        totalAmount: 15000.0,
      );

      // Transaction 4: Cash Expense (Spent 2 x ₹500 = ₹1,000)
      final tx4 = FinanceTransaction(
        id: 'tx_4',
        date: DateTime(2026, 11, 23, 16, 0),
        referenceId: '261123-0004',
        narration: 'Snacks & Tea',
        flow: 'Withdraw',
        invoice: 'INV-4',
        purpose: 'Food',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(
            paymentType: 'Cash',
            amount: 1000.0,
            denominations: {
              500: 2,
              200: 0,
              100: 0,
              50: 0,
              20: 0,
              10: 0,
              5: 0,
              2: 0,
              1: 0,
            },
          ),
        ],
        totalAmount: 1000.0,
      );

      final summary = LiveAccountBalanceSummary.calculate(
        config: config,
        transactions: [tx1, tx2, tx3, tx4],
        categories: categories,
      );

      // Bank Balance:
      // Opening HDFC: 50,000 - 5,000 (tx1) - 15,000 (tx3 bill pay) = 30,000
      expect(summary.bankBalances['HDFC Bank A/c'], 30000.0);
      expect(summary.bankBalances['SBI Savings A/c'], 20000.0);

      // Running Balances Map:
      // After tx1: HDFC Bank was 45,000
      expect(summary.txRunningBalances['tx_1']!['HDFC Bank A/c'], 45000.0);
      // After tx3: HDFC Bank was 30,000
      expect(summary.txRunningBalances['tx_3']!['HDFC Bank A/c'], 30000.0);

      // Credit Card:
      // Total: 150,000
      // Initial used: 30,000 + 10,000 (tx2) - 15,000 (tx3 bill pay) = 25,000
      // Available: 150,000 - 25,000 = 125,000
      final ccSummary = summary.creditCardSummaries['HDFC Regalia Card']!;
      expect(ccSummary.totalLimit, 150000.0);
      expect(ccSummary.usedLimit, 25000.0);
      expect(ccSummary.availableLimit, 125000.0);

      // Cash:
      // Opening: 10 x 500, spent 2 -> 8 remaining
      expect(summary.cashDenominations[500], 8);
      expect(summary.cashDenominations[200], 5);
      expect(summary.cashDenominations[100], 10);
      // Total cash remaining: 7000 - 1000 = 6000
      expect(summary.totalCashInHand, 6000.0);
    });

    test('Shared credit limit groups and bill due notifications calculate accurately', () {
      final today = DateTime(2026, 11, 23);

      final config = AccountBalanceConfig(
        setupDate: DateTime(2026, 11, 1),
        isConfigured: true,
        bankOpeningBalances: {'HDFC Bank A/c': 100000.0},
        creditCardLimits: {
          'Axis Flipkart': const CreditCardLimit(
            totalLimit: 150000.0,
            initialUsedAmount: 20000.0,
            sharedGroupName: 'Axis Group',
            groupTotalLimit: 150000.0,
            billDay: 15,
            dueDay: 5,
            statementBilledAmount: 20000.0,
          ),
          'Axis MyZone': const CreditCardLimit(
            totalLimit: 150000.0,
            initialUsedAmount: 10000.0,
            sharedGroupName: 'Axis Group',
            groupTotalLimit: 150000.0,
            billDay: 18,
            dueDay: 8,
          ),
        },
      );

      final categories = {
        'Bank Accounts': ['HDFC Bank A/c'],
        'Credit Cards': ['Axis Flipkart', 'Axis MyZone'],
      };

      // 1. Without payments:
      // Axis Flipkart bill generated on Nov 15th, due on Dec 5th.
      // Billed amount: 20,000.
      var summary = LiveAccountBalanceSummary.calculate(
        config: config,
        transactions: [],
        categories: categories,
        referenceDate: today,
      );

      expect(summary.creditCardSummaries['Axis Flipkart']!.isShared, true);
      expect(summary.creditCardSummaries['Axis Flipkart']!.groupTotalLimit, 150000.0);
      // Shared used: 20,000 + 10,000 = 30,000.
      // Available in group: 150,000 - 30,000 = 120,000.
      expect(summary.creditCardSummaries['Axis Flipkart']!.availableLimit, 120000.0);
      expect(summary.creditCardSummaries['Axis MyZone']!.availableLimit, 120000.0);

      // Check due bills
      expect(summary.dueBills.length, 2);
      final flipkartDue = summary.dueBills.firstWhere((b) => b.cardName == 'Axis Flipkart');
      expect(flipkartDue.billedAmount, 20000.0);
      expect(flipkartDue.paidAmount, 0.0);
      expect(flipkartDue.remainingDue, 20000.0);
      expect(flipkartDue.dueDate.month, 12);
      expect(flipkartDue.dueDate.day, 5);

      // 2. Partial Payment via Self Transfer (₹8,000 paid to Axis Flipkart with narration "Cleared card bill")
      final txPayPartial = FinanceTransaction(
        id: 'tx_pay_1',
        date: DateTime(2026, 11, 20),
        referenceId: '261120-0001',
        narration: 'Cleared card bill',
        flow: 'Transfer',
        invoice: '',
        purpose: 'Self Transfer',
        spentFor: 'Self',
        isSelfTransfer: true,
        breakdowns: [
          PaymentBreakdown(paymentType: 'Net', account: 'HDFC Bank A/c', amount: 8000.0),
        ],
        toBreakdowns: [
          PaymentBreakdown(paymentType: 'Credit', account: 'Axis Flipkart', amount: 8000.0),
        ],
        totalAmount: 8000.0,
      );

      summary = LiveAccountBalanceSummary.calculate(
        config: config,
        transactions: [txPayPartial],
        categories: categories,
        referenceDate: today,
      );

      final flipkartDuePartial = summary.dueBills.firstWhere((b) => b.cardName == 'Axis Flipkart');
      expect(flipkartDuePartial.paidAmount, 8000.0);
      expect(flipkartDuePartial.remainingDue, 12000.0);

      // 3. Full Payment via Self Transfer (remaining ₹12,000 paid to Axis Flipkart)
      final txPayFull = FinanceTransaction(
        id: 'tx_pay_2',
        date: DateTime(2026, 11, 22),
        referenceId: '261122-0001',
        narration: 'Cleared card bill',
        flow: 'Transfer',
        invoice: '',
        purpose: 'Self Transfer',
        spentFor: 'Self',
        isSelfTransfer: true,
        breakdowns: [
          PaymentBreakdown(paymentType: 'Net', account: 'HDFC Bank A/c', amount: 12000.0),
        ],
        toBreakdowns: [
          PaymentBreakdown(paymentType: 'Credit', account: 'Axis Flipkart', amount: 12000.0),
        ],
        totalAmount: 12000.0,
      );

      summary = LiveAccountBalanceSummary.calculate(
        config: config,
        transactions: [txPayPartial, txPayFull],
        categories: categories,
        referenceDate: today,
      );

      // Axis Flipkart is now fully paid! It should be removed from dueBills.
      expect(summary.dueBills.any((b) => b.cardName == 'Axis Flipkart'), false);

      // 4. Test Manual "Mark as Paid" override
      final configManuallyPaid = config.copyWith(
        creditCardLimits: {
          ...config.creditCardLimits,
          'Axis MyZone': config.creditCardLimits['Axis MyZone']!.copyWith(
            manualPaidCycle: summary.creditCardSummaries['Axis MyZone']!.dueBill!.cycleKey,
          ),
        },
      );

      final summaryManual = LiveAccountBalanceSummary.calculate(
        config: configManuallyPaid,
        transactions: [],
        categories: categories,
        referenceDate: today,
      );

      expect(summaryManual.dueBills.any((b) => b.cardName == 'Axis MyZone'), false);
    });

    test('Indian currency formatter formats according to Indian numbering system (12,34,56,789)', () {
      expect(IndianCurrency.format(123456789), '12,34,56,789.00');
      expect(IndianCurrency.format(123456789, showDecimals: false), '12,34,56,789');
      expect(IndianCurrency.formatSmart(123456789), '12,34,56,789');
      expect(IndianCurrency.formatSmart(123456.50), '1,23,456.50');
      expect(IndianCurrency.formatSmart(500), '500');
      expect(IndianCurrency.formatSmart(15000), '15,000');
      expect(IndianCurrency.formatSmart(150000), '1,50,000');
      expect(IndianCurrency.format(150000), '1,50,000.00');
    });

    test('Wallets and Rewards opening balances and live tracking calculations', () {
      final config = AccountBalanceConfig(
        isConfigured: true,
        walletOpeningBalances: {
          'Paytm Wallet': 1500.0,
          'Amazon Pay Balance': 350.0,
        },
        rewardOpeningBalances: {
          'Credit Card Reward Points': 12000.0,
          'Flipkart SuperCoins': 450.0,
        },
      );

      expect(config.totalWalletOpeningBalance, 1850.0);
      expect(config.totalRewardOpeningBalance, 12450.0);

      // Verify JSON serialization round-trip
      final json = config.toJson();
      final restored = AccountBalanceConfig.fromJson(json);
      expect(restored.walletOpeningBalances['Paytm Wallet'], 1500.0);
      expect(restored.walletOpeningBalances['Amazon Pay Balance'], 350.0);
      expect(restored.rewardOpeningBalances['Credit Card Reward Points'], 12000.0);
      expect(restored.rewardOpeningBalances['Flipkart SuperCoins'], 450.0);
      expect(restored.totalWalletOpeningBalance, 1850.0);
      expect(restored.totalRewardOpeningBalance, 12450.0);

      final categories = {
        'Bank Accounts': ['HDFC Bank A/c'],
        'Wallets': ['Paytm Wallet', 'Amazon Pay Balance'],
        'Rewards': ['Credit Card Reward Points', 'Flipkart SuperCoins'],
      };

      // Tx1: Expense from Paytm Wallet (Withdraw ₹300)
      final tx1 = FinanceTransaction(
        id: 'tx_w1',
        date: DateTime(2026, 11, 24, 10, 0),
        referenceId: '261124-0001',
        narration: 'Cab ride',
        flow: 'Withdraw',
        invoice: '',
        purpose: 'Travel',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(paymentType: 'Wallet', account: 'Paytm Wallet', amount: 300.0),
        ],
        totalAmount: 300.0,
      );

      // Tx2: Top up Amazon Pay from HDFC Bank (Transfer ₹1000)
      final tx2 = FinanceTransaction(
        id: 'tx_w2',
        date: DateTime(2026, 11, 24, 11, 0),
        referenceId: '261124-0002',
        narration: 'Wallet top up',
        flow: 'Transfer',
        invoice: '',
        purpose: 'Self Transfer',
        spentFor: 'Self',
        isSelfTransfer: true,
        breakdowns: [
          PaymentBreakdown(paymentType: 'Net', account: 'HDFC Bank A/c', amount: 1000.0),
        ],
        toBreakdowns: [
          PaymentBreakdown(paymentType: 'Wallet', account: 'Amazon Pay Balance', amount: 1000.0),
        ],
        totalAmount: 1000.0,
      );

      // Tx3: Reward earned (Deposit 500 reward points)
      final tx3 = FinanceTransaction(
        id: 'tx_r1',
        date: DateTime(2026, 11, 24, 12, 0),
        referenceId: '261124-0003',
        narration: 'Card milestone rewards',
        flow: 'Deposit',
        invoice: '',
        purpose: 'Cashback & Rewards',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(paymentType: 'Reward Points', account: 'Credit Card Reward Points', amount: 500.0),
        ],
        totalAmount: 500.0,
      );

      // Tx4: Redeem SuperCoins (Withdraw 100 points)
      final tx4 = FinanceTransaction(
        id: 'tx_r2',
        date: DateTime(2026, 11, 24, 13, 0),
        referenceId: '261124-0004',
        narration: 'Discount voucher',
        flow: 'Withdraw',
        invoice: '',
        purpose: 'Shopping',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(paymentType: 'Reward Points', account: 'Flipkart SuperCoins', amount: 100.0),
        ],
        totalAmount: 100.0,
      );

      final summary = LiveAccountBalanceSummary.calculate(
        config: config,
        transactions: [tx1, tx2, tx3, tx4],
        categories: categories,
      );

      // Paytm Wallet: 1500 - 300 = 1200
      expect(summary.walletBalances['Paytm Wallet'], 1200.0);
      // Amazon Pay: 350 + 1000 = 1350
      expect(summary.walletBalances['Amazon Pay Balance'], 1350.0);
      // Total wallet: 1200 + 1350 = 2550
      expect(summary.totalWalletBalance, 2550.0);

      // Reward Points: 12000 + 500 = 12500
      expect(summary.rewardBalances['Credit Card Reward Points'], 12500.0);
      // SuperCoins: 450 - 100 = 350
      expect(summary.rewardBalances['Flipkart SuperCoins'], 350.0);
      // Total reward: 12500 + 350 = 12850
      expect(summary.totalRewardBalance, 12850.0);
    });
  });
}
