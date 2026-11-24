import 'account_balance_model.dart';
import 'transaction_model.dart';

enum CreditHealthStatus {
  excellent, // < 30%
  moderate,  // 30 - 50%
  highRisk,  // > 50%
}

class FinancialHealthSummary {
  // Net Liquidity
  final double totalBankBalance;
  final double totalCashInHand;
  final double totalWalletBalance;
  final double totalLiquidAssets;
  final double totalCreditCardLiabilities;
  final double totalCreditCardDues;
  final double netLiquidity;

  // Credit Limits & Utilization
  final double totalCreditLimit;
  final double totalCreditUsed;
  final double creditUtilizationPercent;
  final CreditHealthStatus creditHealthStatus;

  // Monthly Velocity & Burn Rate
  final double currentMonthInflow;
  final double currentMonthOutflow;
  final double netMonthlySavings;
  final double monthlySavingsRatePercent;
  final double averageDailySpend;
  final double projectedMonthlySpend;

  // Ratios
  final double liquidityCoverageRatio; // Liquid Assets / Upcoming Credit Dues

  // Breakdowns
  final Map<String, double> assetAllocation; // 'Banks', 'Cash', 'Wallets'
  final Map<String, double> topExpensePurposes;
  final Map<String, double> bankWiseBalances;
  final List<LiveCreditCardSummary> creditCardSummaries;
  final List<CreditCardDueBill> dueBills;

  FinancialHealthSummary({
    required this.totalBankBalance,
    required this.totalCashInHand,
    required this.totalWalletBalance,
    required this.totalLiquidAssets,
    required this.totalCreditCardLiabilities,
    required this.totalCreditCardDues,
    required this.netLiquidity,
    required this.totalCreditLimit,
    required this.totalCreditUsed,
    required this.creditUtilizationPercent,
    required this.creditHealthStatus,
    required this.currentMonthInflow,
    required this.currentMonthOutflow,
    required this.netMonthlySavings,
    required this.monthlySavingsRatePercent,
    required this.averageDailySpend,
    required this.projectedMonthlySpend,
    required this.liquidityCoverageRatio,
    required this.assetAllocation,
    required this.topExpensePurposes,
    required this.bankWiseBalances,
    required this.creditCardSummaries,
    required this.dueBills,
  });

  factory FinancialHealthSummary.calculate({
    required LiveAccountBalanceSummary balanceSummary,
    required List<FinanceTransaction> transactions,
    DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final dayElapsed = now.day.clamp(1, daysInMonth);

    // 1. Liquid Assets
    final double bankTotal = balanceSummary.totalBankBalance;
    final double cashTotal = balanceSummary.totalCashBalance;
    final double walletTotal = balanceSummary.totalWalletBalance;
    final double liquidAssets = bankTotal + cashTotal + walletTotal;

    // 2. Liabilities
    final double ccLiabilities = balanceSummary.totalCreditCardUsed;
    final double ccDues = balanceSummary.totalDueBills;
    final double netLiquidityVal = liquidAssets - ccLiabilities;

    // 3. Credit Utilization
    final double totalLimit = balanceSummary.totalCreditCardLimit;
    final double totalUsed = balanceSummary.totalCreditCardUsed;
    final double utilizationPct = totalLimit > 0 ? ((totalUsed / totalLimit) * 100).clamp(0.0, 100.0) : 0.0;

    CreditHealthStatus healthStatus = CreditHealthStatus.excellent;
    if (utilizationPct > 50) {
      healthStatus = CreditHealthStatus.highRisk;
    } else if (utilizationPct >= 30) {
      healthStatus = CreditHealthStatus.moderate;
    }

    // 4. Monthly Velocity & Burn Rate (Current Month transactions)
    double monthInflow = 0.0;
    double monthOutflow = 0.0;
    final Map<String, double> monthPurposes = {};

    for (final tx in transactions) {
      if (tx.date.isBefore(firstDayOfMonth)) continue;
      final isTransfer = tx.isSelfTransfer || tx.flow.toLowerCase().contains('transfer');
      final isDeposit = tx.flow.toLowerCase().contains('deposit');

      if (isDeposit) {
        monthInflow += tx.totalAmount;
      } else if (!isTransfer) {
        monthOutflow += tx.totalAmount;
        final p = tx.purpose.trim().isEmpty ? 'General' : tx.purpose.trim();
        monthPurposes[p] = (monthPurposes[p] ?? 0.0) + tx.totalAmount;
      }
    }

    final double savings = monthInflow - monthOutflow;
    final double savingsRate = monthInflow > 0 ? ((savings / monthInflow) * 100).clamp(-100.0, 100.0) : 0.0;
    final double dailySpend = monthOutflow / dayElapsed;
    final double projectedSpend = dailySpend * daysInMonth;

    // 5. Liquidity Coverage Ratio (Liquid Assets / Upcoming Dues)
    final double lcr = ccDues > 0 ? (liquidAssets / ccDues) : (liquidAssets > 0 ? 10.0 : 1.0);

    // 6. Asset Allocation
    final Map<String, double> allocation = {
      'Bank Accounts': bankTotal > 0 ? bankTotal : 0.0,
      'Cash in Hand': cashTotal > 0 ? cashTotal : 0.0,
      'Wallets': walletTotal > 0 ? walletTotal : 0.0,
    };

    // Sort purposes by highest spend
    final sortedPurposes = Map.fromEntries(
      monthPurposes.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );

    return FinancialHealthSummary(
      totalBankBalance: bankTotal,
      totalCashInHand: cashTotal,
      totalWalletBalance: walletTotal,
      totalLiquidAssets: liquidAssets,
      totalCreditCardLiabilities: ccLiabilities,
      totalCreditCardDues: ccDues,
      netLiquidity: netLiquidityVal,
      totalCreditLimit: totalLimit,
      totalCreditUsed: totalUsed,
      creditUtilizationPercent: utilizationPct,
      creditHealthStatus: healthStatus,
      currentMonthInflow: monthInflow,
      currentMonthOutflow: monthOutflow,
      netMonthlySavings: savings,
      monthlySavingsRatePercent: savingsRate,
      averageDailySpend: dailySpend,
      projectedMonthlySpend: projectedSpend,
      liquidityCoverageRatio: lcr,
      assetAllocation: allocation,
      topExpensePurposes: sortedPurposes,
      bankWiseBalances: balanceSummary.bankBalances,
      creditCardSummaries: balanceSummary.creditCardSummaries.values.toList(),
      dueBills: balanceSummary.dueBills,
    );
  }
}
