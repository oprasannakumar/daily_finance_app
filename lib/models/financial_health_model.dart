import 'account_balance_model.dart';
import 'transaction_model.dart';

enum CreditHealthStatus {
  excellent, // < 30%
  moderate,  // 30 - 50%
  highRisk,  // > 50%
}

class MonthlyTrendPoint {
  final DateTime monthDate;
  final double inflow;
  final double outflow;
  double get savings => inflow - outflow;

  const MonthlyTrendPoint({
    required this.monthDate,
    required this.inflow,
    required this.outflow,
  });
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

  // Selected Month Velocity & Burn Rate
  final DateTime selectedMonth;
  final bool isCurrentMonth;
  final double currentMonthInflow;
  final double currentMonthOutflow;
  final double netMonthlySavings;
  final double monthlySavingsRatePercent;
  final double averageDailySpend;
  final double projectedMonthlySpend;
  final int selectedMonthTxCount;

  // Previous Month (for MoM comparison)
  final double prevMonthInflow;
  final double prevMonthOutflow;
  final double prevMonthSavings;

  // Ratios
  final double liquidityCoverageRatio; // Liquid Assets / Upcoming Credit Dues

  // Breakdowns
  final Map<String, double> assetAllocation; // 'Banks', 'Cash', 'Wallets'
  final Map<String, double> topExpensePurposes;
  final Map<String, double> monthlyPaymentModes;
  final List<MonthlyTrendPoint> monthlyTrends;
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
    required this.selectedMonth,
    required this.isCurrentMonth,
    required this.currentMonthInflow,
    required this.currentMonthOutflow,
    required this.netMonthlySavings,
    required this.monthlySavingsRatePercent,
    required this.averageDailySpend,
    required this.projectedMonthlySpend,
    required this.selectedMonthTxCount,
    required this.prevMonthInflow,
    required this.prevMonthOutflow,
    required this.prevMonthSavings,
    required this.liquidityCoverageRatio,
    required this.assetAllocation,
    required this.topExpensePurposes,
    required this.monthlyPaymentModes,
    required this.monthlyTrends,
    required this.bankWiseBalances,
    required this.creditCardSummaries,
    required this.dueBills,
  });

  factory FinancialHealthSummary.calculate({
    required LiveAccountBalanceSummary balanceSummary,
    required List<FinanceTransaction> transactions,
    DateTime? referenceDate,
    DateTime? selectedMonth,
  }) {
    final now = referenceDate ?? DateTime.now();
    final target = selectedMonth ?? DateTime(now.year, now.month, 1);
    final monthStart = DateTime(target.year, target.month, 1);
    final nextMonthStart = DateTime(target.year, target.month + 1, 1);
    final prevMonthStart = DateTime(target.year, target.month - 1, 1);
    final isCurrMonth = target.year == now.year && target.month == now.month;
    final daysInMonth = DateTime(target.year, target.month + 1, 0).day;
    final dayElapsed = isCurrMonth ? now.day.clamp(1, daysInMonth) : daysInMonth;

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

    // 4. Monthly Velocity, Burn Rate, Payment Modes & MoM Comparison
    double monthInflow = 0.0;
    double monthOutflow = 0.0;
    int txCount = 0;
    double prevInflow = 0.0;
    double prevOutflow = 0.0;
    final Map<String, double> monthPurposes = {};
    final Map<String, double> paymentModes = {};

    // Pre-build 6-month trend buckets ending at `monthStart`
    final List<DateTime> trendMonths = List.generate(
      6,
      (i) => DateTime(monthStart.year, monthStart.month - (5 - i), 1),
    );
    final Map<String, double> trendInflows = {};
    final Map<String, double> trendOutflows = {};

    for (final tx in transactions) {
      final isTransfer = tx.isSelfTransfer || tx.flow.toLowerCase().contains('transfer');
      final isDeposit = tx.flow.toLowerCase().contains('deposit');
      final ymKey = '${tx.date.year}-${tx.date.month}';

      if (isDeposit) {
        trendInflows[ymKey] = (trendInflows[ymKey] ?? 0.0) + tx.totalAmount;
      } else if (!isTransfer) {
        trendOutflows[ymKey] = (trendOutflows[ymKey] ?? 0.0) + tx.totalAmount;
      }

      if (!tx.date.isBefore(prevMonthStart) && tx.date.isBefore(monthStart)) {
        if (isDeposit) {
          prevInflow += tx.totalAmount;
        } else if (!isTransfer) {
          prevOutflow += tx.totalAmount;
        }
      }

      if (!tx.date.isBefore(monthStart) && tx.date.isBefore(nextMonthStart)) {
        txCount++;
        if (isDeposit) {
          monthInflow += tx.totalAmount;
        } else if (!isTransfer) {
          monthOutflow += tx.totalAmount;
          final p = tx.purpose.trim().isEmpty ? 'General' : tx.purpose.trim();
          monthPurposes[p] = (monthPurposes[p] ?? 0.0) + tx.totalAmount;

          for (final b in tx.breakdowns) {
            final rawPt = (b.paymentType ?? '').trim();
            final pt = rawPt.isEmpty ? 'Other' : rawPt;
            paymentModes[pt] = (paymentModes[pt] ?? 0.0) + b.amount;
          }
        }
      }
    }

    final double savings = monthInflow - monthOutflow;
    final double prevSavings = prevInflow - prevOutflow;
    final double savingsRate = monthInflow > 0 ? ((savings / monthInflow) * 100).clamp(-100.0, 100.0) : 0.0;
    final double dailySpend = monthOutflow / dayElapsed;
    final double projectedSpend = isCurrMonth ? (dailySpend * daysInMonth) : monthOutflow;

    final trends = trendMonths
        .map((m) {
          final k = '${m.year}-${m.month}';
          return MonthlyTrendPoint(
            monthDate: m,
            inflow: trendInflows[k] ?? 0.0,
            outflow: trendOutflows[k] ?? 0.0,
          );
        })
        .toList();

    // 5. Liquidity Coverage Ratio (Liquid Assets / Upcoming Dues)
    final double lcr = ccDues > 0 ? (liquidAssets / ccDues) : (liquidAssets > 0 ? 10.0 : 1.0);

    // 6. Asset Allocation
    final Map<String, double> allocation = {
      'Bank Accounts': bankTotal > 0 ? bankTotal : 0.0,
      'Cash in Hand': cashTotal > 0 ? cashTotal : 0.0,
      'Wallets': walletTotal > 0 ? walletTotal : 0.0,
    };

    // Sort purposes & payment modes by highest spend
    final sortedPurposes = Map.fromEntries(
      monthPurposes.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
    final sortedPaymentModes = Map.fromEntries(
      paymentModes.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
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
      selectedMonth: monthStart,
      isCurrentMonth: isCurrMonth,
      currentMonthInflow: monthInflow,
      currentMonthOutflow: monthOutflow,
      netMonthlySavings: savings,
      monthlySavingsRatePercent: savingsRate,
      averageDailySpend: dailySpend,
      projectedMonthlySpend: projectedSpend,
      selectedMonthTxCount: txCount,
      prevMonthInflow: prevInflow,
      prevMonthOutflow: prevOutflow,
      prevMonthSavings: prevSavings,
      liquidityCoverageRatio: lcr,
      assetAllocation: allocation,
      topExpensePurposes: sortedPurposes,
      monthlyPaymentModes: sortedPaymentModes,
      monthlyTrends: trends,
      bankWiseBalances: balanceSummary.bankBalances,
      creditCardSummaries: balanceSummary.creditCardSummaries.values.toList(),
      dueBills: balanceSummary.dueBills,
    );
  }
}
