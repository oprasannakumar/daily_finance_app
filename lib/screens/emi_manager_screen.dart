import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/emi_plan_model.dart';
import '../models/transaction_model.dart';
import '../services/google_sheets_service.dart';
import '../services/storage_service.dart';
import '../utils/currency_formatter.dart';
import '../widgets/emi_conversion_sheet.dart';

class EmiManagerScreen extends StatefulWidget {
  const EmiManagerScreen({super.key});

  @override
  State<EmiManagerScreen> createState() => _EmiManagerScreenState();
}

class _EmiManagerScreenState extends State<EmiManagerScreen> {
  final StorageService _storage = StorageService.instance;
  final GoogleSheetsService _sheets = GoogleSheetsService.instance;

  bool _isLoading = true;
  bool _isRefreshing = false;
  String _filter = 'ACTIVE'; // 'ACTIVE', 'COMPLETED', 'ALL'
  List<EmiPlan> _plans = [];

  @override
  void initState() {
    super.initState();
    _loadPlans();
    _storage.emiPlansNotifier.addListener(_onPlansChanged);
  }

  @override
  void dispose() {
    _storage.emiPlansNotifier.removeListener(_onPlansChanged);
    super.dispose();
  }

  void _onPlansChanged() {
    if (mounted) {
      _loadPlans(fromLocalOnly: true);
    }
  }

  Future<void> _loadPlans({bool forceRefresh = false, bool fromLocalOnly = false}) async {
    if (fromLocalOnly) {
      final local = await _storage.getCachedEmiPlans();
      if (mounted) {
        setState(() {
          _plans = local;
          _isLoading = false;
        });
      }
      return;
    }

    setState(() {
      if (_plans.isEmpty) _isLoading = true;
      if (forceRefresh) _isRefreshing = true;
    });

    try {
      final fetched = await _sheets.fetchEmiPlans(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _plans = fetched;
        });
      }
    } catch (e) {
      debugPrint('Error loading EMI plans: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _openConversionSheet([EmiPlan? existingPlan]) async {
    final updated = await EmiConversionSheet.show(context, existingPlan: existingPlan);
    if (updated != null) {
      _loadPlans(fromLocalOnly: true);
    }
  }

  Future<void> _toggleInstallmentPaid(EmiPlan plan, int installmentNumber, bool currentStatus) async {
    final newStatus = !currentStatus;
    final inst = plan.installments.firstWhere(
      (it) => it.installmentNumber == installmentNumber,
      orElse: () => plan.installments.first,
    );

    String? newPaymentRef = inst.paymentReference;
    bool clearRef = false;

    if (newStatus == true) {
      final shouldPost = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Pay Installment #$installmentNumber?'),
          content: Text(
            'Mark Installment #$installmentNumber as paid (MRA: ₹${IndianCurrency.format(inst.totalDueWithTax)}) to release ₹${IndianCurrency.format(inst.principal)} of blocked principal on ${plan.account}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'mark_only'),
              child: const Text('Mark Paid Only'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF5C38)),
              onPressed: () => Navigator.pop(ctx, 'record_payment'),
              child: const Text('Pay & Release Limit'),
            ),
          ],
        ),
      );

      if (shouldPost == null || shouldPost == 'cancel') return;

      if (shouldPost == 'record_payment') {
        final refId = FinanceTransaction.generateReferenceId(inst.billingDate);
        final narration = 'EMI Installment #$installmentNumber Payment: ${plan.title} (Releasing Prin: ₹${IndianCurrency.format(inst.principal)})';
        final instTx = FinanceTransaction(
          date: inst.billingDate,
          referenceId: refId,
          narration: narration,
          flow: 'Deposit', // Credit/payment to card releases the blocked principal limit
          invoice: '',
          purpose: 'Credit Card EMI Payment',
          spentFor: 'Self',
          breakdowns: [
            PaymentBreakdown(
              paymentType: 'Credit',
              account: plan.account,
              amount: inst.totalDueWithTax,
            ),
          ],
          totalAmount: inst.totalDueWithTax,
        );
        await _storage.saveTransaction(instTx);
        newPaymentRef = refId;
      }
    } else {
      if (inst.paymentReference != null && inst.paymentReference!.isNotEmpty) {
        await _storage.deleteTransaction(inst.paymentReference!, referenceId: inst.paymentReference!);
        clearRef = true;
        newPaymentRef = null;
      }
    }

    await _sheets.updateEmiInstallmentPaid(
      plan.id,
      installmentNumber,
      newStatus,
      paidDate: newStatus ? DateTime.now() : null,
      paymentReference: newPaymentRef,
      clearPaymentReference: clearRef,
    );
    _loadPlans(fromLocalOnly: true);
  }

  Future<void> _confirmDeletePlan(EmiPlan plan) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E2240) : Colors.white,
        title: const Text('Delete EMI Plan?'),
        content: Text('Are you sure you want to remove "${plan.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // 1. Delete linked reversal and fee transactions from history / ledger to restore CC balance
      if (plan.reversalTransactionRef != null && plan.reversalTransactionRef!.isNotEmpty) {
        await _storage.deleteTransaction(plan.reversalTransactionRef!, referenceId: plan.reversalTransactionRef!);
      }
      if (plan.feeTransactionRef != null && plan.feeTransactionRef!.isNotEmpty) {
        await _storage.deleteTransaction(plan.feeTransactionRef!, referenceId: plan.feeTransactionRef!);
      }

      // 2. Delete EMI plan from local storage & Google Sheets
      await _sheets.deleteEmiPlan(plan.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('EMI Plan "${plan.title}" deleted (Ledger reversal removed)')),
        );
      }
      _loadPlans(fromLocalOnly: true);
    }
  }

  List<EmiPlan> get _filteredPlans {
    if (_filter == 'ACTIVE') {
      return _plans.where((p) => p.status.toUpperCase() == 'ACTIVE').toList();
    }
    if (_filter == 'COMPLETED') {
      return _plans.where((p) => p.status.toUpperCase() == 'COMPLETED' || p.status.toUpperCase() == 'PRECLOSED').toList();
    }
    return _plans;
  }

  double get _totalMonthlyCommitment {
    double sum = 0.0;
    for (final p in _plans.where((p) => p.status.toUpperCase() == 'ACTIVE')) {
      final next = p.nextDueInstallment;
      if (next != null) {
        sum += next.totalDueWithTax;
      }
    }
    return sum;
  }

  double get _totalOutstandingPrincipal {
    return _plans
        .where((p) => p.status.toUpperCase() == 'ACTIVE')
        .fold(0.0, (sum, p) => sum + p.remainingPrincipal);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111429) : const Color(0xFFF8F9FA);
    final cardBg = isDark ? const Color(0xFF1A1F3D) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2C3258) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    const coral = Color(0xFFFF5C38);
    const teal = Color(0xFF00B074);

    final activeCount = _plans.where((p) => p.status.toUpperCase() == 'ACTIVE').length;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Credit Card EMIs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: coral))
                : const Icon(Icons.sync),
            tooltip: 'Sync with Google Sheets',
            onPressed: () => _loadPlans(forceRefresh: true),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle, color: coral, size: 28),
            tooltip: 'New EMI Plan',
            onPressed: () => _openConversionSheet(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: coral))
          : RefreshIndicator(
              color: coral,
              onRefresh: () => _loadPlans(forceRefresh: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  // KPI Banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF2E1A47), const Color(0xFF162547)]
                            : [const Color(0xFFFFF0EB), const Color(0xFFE8F5E9)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Monthly Commitment', style: TextStyle(fontSize: 12, color: textSecondary)),
                                const SizedBox(height: 2),
                                Text(
                                  '₹${IndianCurrency.formatSmart(_totalMonthlyCommitment)}',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: coral),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: coral.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.credit_card, size: 14, color: coral),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$activeCount Active',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: coral),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Outstanding Principal: ₹${IndianCurrency.formatSmart(_totalOutstandingPrincipal)}',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: textPrimary),
                            ),
                            Text(
                              '${_plans.length} Total Plans',
                              style: TextStyle(fontSize: 12, color: textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Filter Chips Row
                  Row(
                    children: [
                      _buildFilterChip('Active ($activeCount)', 'ACTIVE', isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip('Completed', 'COMPLETED', isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip('All (${_plans.length})', 'ALL', isDark),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // List of Plans
                  if (_filteredPlans.isEmpty)
                    _buildEmptyState(isDark, textPrimary, textSecondary, coral)
                  else
                    ..._filteredPlans.map((plan) => _buildPlanCard(plan, isDark, cardBg, borderColor, textPrimary, textSecondary, coral, teal)),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterChip(String label, String value, bool isDark) {
    final isSelected = _filter == value;
    const coral = Color(0xFFFF5C38);
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: coral,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
      ),
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _buildEmptyState(bool isDark, Color textPrimary, Color textSecondary, Color coral) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: coral.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.credit_score, size: 48, color: Color(0xFFFF5C38)),
          ),
          const SizedBox(height: 16),
          Text(
            _filter == 'ACTIVE' ? 'No active credit card EMIs' : 'No EMI plans found',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Convert credit card swipes with partial amounts, or create a custom plan with bank amortization details.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: textSecondary),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: coral,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Convert / Add New EMI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => _openConversionSheet(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(
    EmiPlan plan,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textPrimary,
    Color textSecondary,
    Color coral,
    Color teal,
  ) {
    final nextDue = plan.nextDueInstallment;
    final isCompleted = plan.status.toUpperCase() == 'COMPLETED';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isCompleted ? Colors.grey.withValues(alpha: 0.15) : coral.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isCompleted ? Icons.check_circle_outline : Icons.credit_card,
              color: isCompleted ? Colors.grey : coral,
              size: 22,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  plan.title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isCompleted ? Colors.grey.withValues(alpha: 0.2) : teal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  plan.status,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isCompleted ? textSecondary : teal,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: coral.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.credit_card, size: 12, color: coral),
                        const SizedBox(width: 4),
                        Text(
                          plan.account,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: coral),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${plan.tenureMonths} Mo @ ${plan.annualInterestRate}% p.a.',
                      style: TextStyle(fontSize: 11.5, color: textSecondary)),
                ],
              ),
              if (plan.linkedTransactionRef != null) ...[
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: teal.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: teal.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link_rounded, size: 13, color: teal),
                      const SizedBox(width: 4),
                      Text(
                        'Linked Swipe: ${plan.linkedTransactionRef}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: teal),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Swipe: ₹${IndianCurrency.formatSmart(plan.totalTransactionAmount)}',
                        style: TextStyle(fontSize: 10.5, color: textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),

              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: plan.progressFraction,
                  minHeight: 6,
                  backgroundColor: isDark ? Colors.white10 : Colors.black12,
                  valueColor: AlwaysStoppedAnimation<Color>(isCompleted ? teal : coral),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${plan.paidInstallmentsCount} of ${plan.tenureMonths} Paid (${(plan.progressFraction * 100).toInt()}%)',
                    style: TextStyle(fontSize: 11, color: textSecondary),
                  ),
                  Text(
                    'Bal Principal: ₹${IndianCurrency.formatSmart(plan.remainingPrincipal)}',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: textPrimary),
                  ),
                ],
              ),

              // Partial conversion badge
              if (plan.isPartialConversion) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pie_chart_outline, size: 13, color: Colors.amber),
                      const SizedBox(width: 6),
                      Text(
                        'Partial: ₹${IndianCurrency.formatSmart(plan.bookingPrincipal)} of ₹${IndianCurrency.formatSmart(plan.totalTransactionAmount)} (Non-EMI Due: ₹${IndianCurrency.formatSmart(plan.nonEmiBalance)})',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber),
                      ),
                    ],
                  ),
                ),
              ],

              // Next Due Installment Banner
              if (!isCompleted && nextDue != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: coral.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: coral.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Next Due (#${nextDue.installmentNumber})',
                              style: TextStyle(fontSize: 10, color: textSecondary)),
                          Text(
                            DateFormat('dd MMM yyyy').format(nextDue.billingDate),
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: textPrimary),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('MRA Due (inc. GST)', style: TextStyle(fontSize: 10, color: textSecondary)),
                          Text(
                            '₹${IndianCurrency.formatSmart(nextDue.totalDueWithTax)}',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: coral),
                          ),
                        ],
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: coral,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _toggleInstallmentPaid(plan, nextDue.installmentNumber, false),
                        child: const Text('Pay', style: TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          children: [
            const Divider(height: 12),

            // Amortization Schedule Table
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.black.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                children: [
                  // Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(width: 20, child: Text('#', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                        Expanded(flex: 3, child: Text('Due Date', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                        Expanded(flex: 3, child: Text('MRA (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                        Expanded(flex: 2, child: Text('Tax (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                        Expanded(flex: 3, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                        SizedBox(width: 38, child: Text('Status', textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),

                  // Installment Rows
                  ...plan.installments.map((it) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: borderColor.withValues(alpha: 0.4))),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            child: Text('${it.installmentNumber}',
                                style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(DateFormat('dd/MM/yy').format(it.billingDate),
                                    style: TextStyle(fontSize: 11.5, color: textPrimary)),
                                if (it.paymentReference != null && it.paymentReference!.isNotEmpty)
                                  Text(
                                    'Billed',
                                    style: TextStyle(fontSize: 9, color: teal, fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text('₹${IndianCurrency.formatSmart(it.emiAmount)}',
                                textAlign: TextAlign.right,
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: coral)),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text('₹${IndianCurrency.formatSmart(it.applicableTaxes)}',
                                textAlign: TextAlign.right,
                                style: TextStyle(fontSize: 10.5, color: textSecondary)),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text('₹${IndianCurrency.formatSmart(it.balancePrincipal)}',
                                textAlign: TextAlign.right,
                                style: TextStyle(fontSize: 11, color: textSecondary)),
                          ),
                          SizedBox(
                            width: 38,
                            child: IconButton(
                              icon: Icon(
                                it.isPaid ? Icons.check_circle : Icons.radio_button_unchecked,
                                size: 18,
                                color: it.isPaid ? teal : Colors.grey,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _toggleInstallmentPaid(plan, it.installmentNumber, it.isPaid),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Plan Options Row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit Plan', style: TextStyle(fontSize: 12)),
                  onPressed: () => _openConversionSheet(plan),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                  label: const Text('Delete', style: TextStyle(fontSize: 12, color: Colors.red)),
                  onPressed: () => _confirmDeletePlan(plan),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
