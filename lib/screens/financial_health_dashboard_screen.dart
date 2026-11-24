import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/financial_health_model.dart';
import '../models/transaction_model.dart';
import '../services/storage_service.dart';
import '../utils/currency_formatter.dart';
import '../widgets/statement_export_dialog.dart';

class FinancialHealthDashboardScreen extends StatefulWidget {
  const FinancialHealthDashboardScreen({super.key});

  @override
  State<FinancialHealthDashboardScreen> createState() => _FinancialHealthDashboardScreenState();
}

class _FinancialHealthDashboardScreenState extends State<FinancialHealthDashboardScreen> {
  bool _isLoading = true;
  FinancialHealthSummary? _healthSummary;
  List<FinanceTransaction> _transactions = [];

  @override
  void initState() {
    super.initState();
    _loadHealthData();
  }

  Future<void> _loadHealthData() async {
    setState(() => _isLoading = true);
    final storage = StorageService.instance;
    final balanceSummary = await storage.getLiveAccountBalances();
    final txs = await storage.getTransactions();

    final health = FinancialHealthSummary.calculate(
      balanceSummary: balanceSummary,
      transactions: txs,
    );

    if (mounted) {
      setState(() {
        _healthSummary = health;
        _transactions = txs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF13141F) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Financial Health & Liquidity',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'Net worth, credit utilization & cash flow',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export Statement',
            onPressed: () {
              StatementExportDialog.show(
                context,
                prefilteredTransactions: _transactions,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadHealthData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHealthData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Net Liquidity Hero Card
                    _buildNetLiquidityCard(isDark),
                    const SizedBox(height: 16),

                    // 2. Credit Health & Utilization Card
                    _buildCreditUtilizationCard(isDark),
                    const SizedBox(height: 16),

                    // 3. Cash Flow & Burn Rate Grid
                    _buildCashFlowGrid(isDark),
                    const SizedBox(height: 16),

                    // 4. Asset Allocation Breakdown
                    _buildAssetAllocationCard(isDark),
                    const SizedBox(height: 16),

                    // 5. Monthly Top Spending Categories
                    _buildTopSpendingPurposesCard(isDark),
                    const SizedBox(height: 16),

                    // 6. Credit Cards & Dues Status Matrix
                    _buildCreditCardsStatusCard(isDark),
                    const SizedBox(height: 24),

                    // 7. Statement Export Action Bar
                    _buildExportBanner(isDark),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  // =========================================================================
  // 1. NET LIQUIDITY CARD
  // =========================================================================
  Widget _buildNetLiquidityCard(bool isDark) {
    final h = _healthSummary!;
    final isPositive = h.netLiquidity >= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPositive
              ? [const Color(0xFF1E3A8A), const Color(0xFF3B82F6)]
              : [const Color(0xFF831843), const Color(0xFFE11D48)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isPositive ? const Color(0xFF3B82F6) : const Color(0xFFE11D48)).withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'NET LIQUIDITY',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isPositive ? 'HEALTHY' : 'DEFICIT',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '₹${IndianCurrency.format(h.netLiquidity)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Assets: ₹${IndianCurrency.format(h.totalLiquidAssets)}  -  Liabilities: ₹${IndianCurrency.format(h.totalCreditCardLiabilities)}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildHeroSubStat('🏦 Banks', '₹${IndianCurrency.format(h.totalBankBalance)}'),
                Container(height: 20, width: 1, color: Colors.white24),
                _buildHeroSubStat('💵 Cash', '₹${IndianCurrency.format(h.totalCashInHand)}'),
                Container(height: 20, width: 1, color: Colors.white24),
                _buildHeroSubStat('📱 Wallets', '₹${IndianCurrency.format(h.totalWalletBalance)}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSubStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // =========================================================================
  // 2. CREDIT HEALTH & UTILIZATION CARD
  // =========================================================================
  Widget _buildCreditUtilizationCard(bool isDark) {
    final h = _healthSummary!;
    final util = h.creditUtilizationPercent;

    Color statusColor;
    String statusTitle;
    String statusAdvice;

    switch (h.creditHealthStatus) {
      case CreditHealthStatus.excellent:
        statusColor = const Color(0xFF10B981); // Green
        statusTitle = 'Optimal Utilization (<30%)';
        statusAdvice = 'Great! Your credit utilization is in the ideal zone for high credit health.';
        break;
      case CreditHealthStatus.moderate:
        statusColor = const Color(0xFFF59E0B); // Amber
        statusTitle = 'Moderate Utilization (30% - 50%)';
        statusAdvice = 'Fair usage. Consider clearing bills to bring usage below 30% for best rating.';
        break;
      case CreditHealthStatus.highRisk:
        statusColor = const Color(0xFFEF4444); // Red
        statusTitle = 'High Utilization (>50%)';
        statusAdvice = 'High credit line usage. Prioritize paying down balances to avoid heavy interest.';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.credit_card_rounded, color: Color(0xFF4F46E5), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Credit Card Utilization',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${util.toStringAsFixed(1)}%',
                  style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Utilization Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (util / 100).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.grey.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Used: ₹${IndianCurrency.format(h.totalCreditUsed)}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              Text(
                'Total Limit: ₹${IndianCurrency.format(h.totalCreditLimit)}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Status Badge and Advice
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: statusColor, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusTitle,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        statusAdvice,
                        style: TextStyle(fontSize: 10, color: isDark ? Colors.white70 : Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 3. CASH FLOW & BURN RATE GRID
  // =========================================================================
  Widget _buildCashFlowGrid(bool isDark) {
    final h = _healthSummary!;
    final now = DateTime.now();
    final monthName = DateFormat('MMMM').format(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$monthName Cash Flow & Velocity',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                isDark: isDark,
                icon: Icons.arrow_downward_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'MONTH INFLOW',
                amount: '₹${IndianCurrency.format(h.currentMonthInflow)}',
                subtitle: 'Total Deposits',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                isDark: isDark,
                icon: Icons.arrow_upward_rounded,
                iconColor: const Color(0xFFEF4444),
                title: 'MONTH OUTFLOW',
                amount: '₹${IndianCurrency.format(h.currentMonthOutflow)}',
                subtitle: 'Total Expenses',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                isDark: isDark,
                icon: Icons.savings_outlined,
                iconColor: const Color(0xFF6366F1),
                title: 'NET SAVINGS',
                amount: '₹${IndianCurrency.format(h.netMonthlySavings)}',
                subtitle: '${h.monthlySavingsRatePercent.toStringAsFixed(1)}% savings rate',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                isDark: isDark,
                icon: Icons.speed_rounded,
                iconColor: const Color(0xFFF59E0B),
                title: 'DAILY BURN RATE',
                amount: '₹${IndianCurrency.format(h.averageDailySpend)}/day',
                subtitle: 'Proj: ₹${IndianCurrency.format(h.projectedMonthlySpend)}',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String amount,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            amount,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 4. ASSET ALLOCATION BREAKDOWN
  // =========================================================================
  Widget _buildAssetAllocationCard(bool isDark) {
    final h = _healthSummary!;
    final total = h.totalLiquidAssets;

    final bankPct = total > 0 ? (h.totalBankBalance / total) : 0.0;
    final cashPct = total > 0 ? (h.totalCashInHand / total) : 0.0;
    final walletPct = total > 0 ? (h.totalWalletBalance / total) : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Liquid Asset Allocation',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),

          // Stacked Segmented Allocation Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  if (bankPct > 0)
                    Expanded(
                      flex: (bankPct * 100).round().clamp(1, 100),
                      child: Container(color: const Color(0xFF3B82F6)),
                    ),
                  if (cashPct > 0)
                    Expanded(
                      flex: (cashPct * 100).round().clamp(1, 100),
                      child: Container(color: const Color(0xFF10B981)),
                    ),
                  if (walletPct > 0)
                    Expanded(
                      flex: (walletPct * 100).round().clamp(1, 100),
                      child: Container(color: const Color(0xFF8B5CF6)),
                    ),
                  if (total <= 0)
                    Expanded(
                      child: Container(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildAllocationLegend(
                color: const Color(0xFF3B82F6),
                title: 'Banks',
                pct: '${(bankPct * 100).toStringAsFixed(1)}%',
                amount: '₹${IndianCurrency.format(h.totalBankBalance)}',
              ),
              _buildAllocationLegend(
                color: const Color(0xFF10B981),
                title: 'Cash',
                pct: '${(cashPct * 100).toStringAsFixed(1)}%',
                amount: '₹${IndianCurrency.format(h.totalCashInHand)}',
              ),
              _buildAllocationLegend(
                color: const Color(0xFF8B5CF6),
                title: 'Wallets',
                pct: '${(walletPct * 100).toStringAsFixed(1)}%',
                amount: '₹${IndianCurrency.format(h.totalWalletBalance)}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAllocationLegend({
    required Color color,
    required String title,
    required String pct,
    required String amount,
  }) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$title ($pct)', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text(amount, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  // =========================================================================
  // 5. MONTHLY TOP SPENDING PURPOSES
  // =========================================================================
  Widget _buildTopSpendingPurposesCard(bool isDark) {
    final h = _healthSummary!;
    final totalOutflow = h.currentMonthOutflow;
    final top5 = h.topExpensePurposes.entries.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Top Spending Categories (This Month)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              Text(
                '₹${IndianCurrency.format(totalOutflow)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (top5.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text('No expense transactions recorded this month.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            )
          else
            ...top5.map((entry) {
              final pct = totalOutflow > 0 ? (entry.value / totalOutflow) : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        Text(
                          '₹${IndianCurrency.format(entry.value)} (${(pct * 100).toStringAsFixed(1)}%)',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: Colors.grey.withValues(alpha: 0.12),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // =========================================================================
  // 6. CREDIT CARDS & DUES STATUS MATRIX
  // =========================================================================
  Widget _buildCreditCardsStatusCard(bool isDark) {
    final h = _healthSummary!;
    final cards = h.creditCardSummaries;

    if (cards.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Credit Cards & Outstanding Dues',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              if (h.totalCreditCardDues > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Due: ₹${IndianCurrency.format(h.totalCreditCardDues)}',
                    style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ...cards.map((c) {
            final dueBill = h.dueBills.where((b) => b.cardName == c.cardName).toList();
            final hasDue = dueBill.isNotEmpty && dueBill.first.remainingDue > 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF252636) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: hasDue ? Colors.red.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.credit_card_rounded, color: Color(0xFF4F46E5), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(c.cardName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            if (c.isShared) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  c.sharedGroupName ?? 'Shared',
                                  style: const TextStyle(fontSize: 9, color: Colors.indigo, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Available: ₹${IndianCurrency.format(c.availableLimit)} of ₹${IndianCurrency.format(c.totalLimit)}',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  if (hasDue)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${IndianCurrency.format(dueBill.first.remainingDue)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                        Text(
                          'Due ${DateFormat('dd MMM').format(dueBill.first.dueDate)}',
                          style: TextStyle(fontSize: 9, color: Colors.red.shade400, fontWeight: FontWeight.w600),
                        ),
                      ],
                    )
                  else
                    const Text(
                      'No Due',
                      style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // =========================================================================
  // 7. STATEMENT EXPORT ACTION BANNER
  // =========================================================================
  Widget _buildExportBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF2A2B3D), const Color(0xFF1E1E2E)]
              : [const Color(0xFFEEF2FF), const Color(0xFFE0E7FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.file_download_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Download Financial Statement',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Export detailed PDF report or Excel/CSV spreadsheet for accounting and records.',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () {
              StatementExportDialog.show(
                context,
                prefilteredTransactions: _transactions,
              );
            },
            child: const Text('Export', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
