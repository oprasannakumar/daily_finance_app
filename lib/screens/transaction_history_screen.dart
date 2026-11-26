import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/account_balance_model.dart';
import '../models/emi_plan_model.dart';
import '../models/transaction_model.dart';
import '../services/storage_service.dart';
import '../utils/currency_formatter.dart';
import '../widgets/faceted_filter_sheet.dart';
import '../widgets/statement_export_dialog.dart';
import '../widgets/emi_conversion_sheet.dart';
import 'borrowers_ledger_screen.dart';
import 'emi_manager_screen.dart';

class TransactionHistoryScreen extends StatefulWidget {
  final Listenable? refreshListenable;
  final String? initialSearchQuery;
  final String? initialAccountFilter;

  const TransactionHistoryScreen({
    super.key,
    this.refreshListenable,
    this.initialSearchQuery,
    this.initialAccountFilter,
  });

  @override
  State<TransactionHistoryScreen> createState() => TransactionHistoryScreenState();
}

class TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final StorageService _storage = StorageService.instance;
  List<FinanceTransaction> _transactions = [];
  LiveAccountBalanceSummary? _liveSummary;
  bool _isLoading = true;
  Set<String> _emiLinkedIds = {};
  Set<String> _emiLinkedRefs = {};
  Map<String, EmiPlan> _emiPlanById = {};
  Map<String, EmiPlan> _emiPlanByRef = {};
  Set<String> _knownCreditCards = {};

  // Modern Flipkart / Amazon Faceted Filter Criteria
  TransactionFilterCriteria _filterCriteria = TransactionFilterCriteria();
  final TextEditingController _searchController = TextEditingController();

  int get _activeFilterCount => _filterCriteria.activeFilterCount;

  void _resetAllFilters() {
    HapticFeedback.lightImpact();
    setState(() {
      _filterCriteria.clear();
      _searchController.clear();
    });
  }

  // Modern Multi-Selection State (Zero Checkboxes!)
  final Set<String> _selectedIds = {};
  bool get _isSelectionActive => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final initialQuery = widget.initialSearchQuery?.trim();
    if (initialQuery != null && initialQuery.isNotEmpty) {
      _searchController.text = initialQuery;
      _filterCriteria.narrationQuery = initialQuery;
    }
    final initialAccount = widget.initialAccountFilter?.trim();
    if (initialAccount != null && initialAccount.isNotEmpty) {
      _filterCriteria.selectedAccounts.add(initialAccount);
    }
    widget.refreshListenable?.addListener(_onRefreshNotified);
    StorageService.instance.transactionsNotifier.addListener(_loadTransactions);
    StorageService.instance.balanceConfigNotifier.addListener(_loadTransactions);
    StorageService.instance.emiPlansNotifier.addListener(_loadTransactions);
    _loadTransactions();
  }

  @override
  void didUpdateWidget(covariant TransactionHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_onRefreshNotified);
      widget.refreshListenable?.addListener(_onRefreshNotified);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    widget.refreshListenable?.removeListener(_onRefreshNotified);
    StorageService.instance.transactionsNotifier.removeListener(_loadTransactions);
    StorageService.instance.balanceConfigNotifier.removeListener(_loadTransactions);
    StorageService.instance.emiPlansNotifier.removeListener(_loadTransactions);
    super.dispose();
  }

  void _onRefreshNotified() {
    _loadTransactions();
  }

  void _openEmiPlan(FinanceTransaction tx) {
    HapticFeedback.selectionClick();
    final plan = _emiPlanById[tx.id] ?? _emiPlanByRef[tx.referenceId];
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'EMIs'),
        builder: (_) => EmiManagerScreen(initialPlanId: plan?.id),
      ),
    );
  }

  void _openBorrowerLedger(String borrowerName) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'Borrowers'),
        builder: (_) => BorrowersLedgerScreen(initialBorrowerName: borrowerName),
      ),
    );
  }

  Future<void> _loadTransactions({bool forceRefresh = false}) async {
    if (forceRefresh && mounted) setState(() => _isLoading = true);
    try {
      final list = await _storage.getTransactions(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _transactions = list;
          _isLoading = false;
          _selectedIds.removeWhere((id) => !_transactions.any((t) => t.id == id));
        });
      }

      final live = await _storage.getLiveAccountBalances();
      final emiPlans = await _storage.getCachedEmiPlans();
      final linkedRefs = <String>{};
      final linkedIds = <String>{};
      final planById = <String, EmiPlan>{};
      final planByRef = <String, EmiPlan>{};
      for (final p in emiPlans) {
        if (p.linkedTransactionRef != null && p.linkedTransactionRef!.isNotEmpty) {
          linkedRefs.add(p.linkedTransactionRef!);
          planByRef[p.linkedTransactionRef!] = p;
        }
        if (p.linkedTransactionId != null && p.linkedTransactionId!.isNotEmpty) {
          linkedIds.add(p.linkedTransactionId!);
          planById[p.linkedTransactionId!] = p;
        }
      }
      final categories = await _storage.getCategoryAccounts();
      final ccFromCats = categories['Credit Cards'] ?? [];
      final balanceConfig = await _storage.getAccountBalanceConfig();
      final ccFromConfig = balanceConfig.creditCardLimits.keys.toList();
      final knownCreditCards = <String>{
        ...ccFromCats.map((c) => c.trim()).where((c) => c.isNotEmpty && c != 'Other'),
        ...ccFromConfig.map((c) => c.trim()).where((c) => c.isNotEmpty),
      };

      if (mounted) {
        setState(() {
          _liveSummary = live;
          _emiLinkedRefs = linkedRefs;
          _emiLinkedIds = linkedIds;
          _emiPlanById = planById;
          _emiPlanByRef = planByRef;
          _knownCreditCards = knownCreditCards;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ==========================================
  // FLAT DATE PICKER PRESET HANDLERS
  // ==========================================

  void _setDatePreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    setState(() {
      _filterCriteria.datePreset = preset;
      switch (preset) {
        case 'All Time':
          _filterCriteria.startDate = null;
          _filterCriteria.endDate = null;
          break;
        case 'Today':
          _filterCriteria.startDate = today;
          _filterCriteria.endDate = today;
          break;
        case 'Yesterday':
          final yest = today.subtract(const Duration(days: 1));
          _filterCriteria.startDate = yest;
          _filterCriteria.endDate = yest;
          break;
        case 'This Week':
          final weekStart = today.subtract(Duration(days: today.weekday - 1));
          _filterCriteria.startDate = weekStart;
          _filterCriteria.endDate = today;
          break;
        case 'This Month':
          final monthStart = DateTime(today.year, today.month, 1);
          _filterCriteria.startDate = monthStart;
          _filterCriteria.endDate = today;
          break;
      }
    });
  }

  bool get _isSingleDay {
    if (_filterCriteria.startDate == null || _filterCriteria.endDate == null) return false;
    return _filterCriteria.startDate!.year == _filterCriteria.endDate!.year &&
        _filterCriteria.startDate!.month == _filterCriteria.endDate!.month &&
        _filterCriteria.startDate!.day == _filterCriteria.endDate!.day;
  }

  String get _dateRangeDisplayString {
    final fmt = DateFormat('d-MMM-yyyy');
    if (_filterCriteria.startDate == null && _filterCriteria.endDate == null) {
      return _filterCriteria.datePreset.isNotEmpty && _filterCriteria.datePreset != 'All Time'
          ? _filterCriteria.datePreset
          : 'All Time';
    } else if (_isSingleDay) {
      return fmt.format(_filterCriteria.startDate!);
    } else {
      return '${fmt.format(_filterCriteria.startDate!)} to ${fmt.format(_filterCriteria.endDate!)}';
    }
  }


  // ==========================================
  // MULTI-SELECTION HANDLERS
  // ==========================================

  void _toggleSelection(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<FinanceTransaction> items) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedIds.addAll(items.map((t) => t.id));
    });
  }

  void _clearSelection() {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedIds.clear();
    });
  }

  Future<void> _deleteSelectedTransactions() async {
    final count = _selectedIds.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Selected'),
        content: Text('Are you sure you want to delete $count transaction(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final idsToDelete = List<String>.from(_selectedIds);
      for (final id in idsToDelete) {
        FinanceTransaction? tx;
        for (final t in _transactions) {
          if (t.id == id) {
            tx = t;
            break;
          }
        }
        await _storage.deleteTransaction(id, referenceId: tx?.referenceId);
      }
      setState(() {
        _selectedIds.clear();
      });
      _loadTransactions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted $count transaction(s)', textAlign: TextAlign.center),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ==========================================
  // TRANSACTION DETAIL MODAL
  // ==========================================

  void _showTransactionDetail(FinanceTransaction tx) {
    final isTransfer = tx.isSelfTransfer || tx.flow == 'Transfer';
    final isWithdraw = tx.flow == 'Withdraw';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx.referenceId,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        DateFormat('dd/MMM/yyyy').format(tx.date),
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isTransfer
                        ? const Color(0xFF6366F1).withValues(alpha: 0.15)
                        : (isWithdraw ? const Color(0xFFEF4444) : const Color(0xFF10B981)).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isTransfer ? 'SELF TRANSFER' : tx.flow.toUpperCase(),
                    style: TextStyle(
                      color: isTransfer
                          ? const Color(0xFF4F46E5)
                          : (isWithdraw ? const Color(0xFFDC2626) : const Color(0xFF059669)),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // Amount summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isTransfer
                    ? const Color(0xFFEEF2FF)
                    : (isWithdraw ? const Color(0xFFFFF1F2) : const Color(0xFFF0FDF4)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isTransfer
                      ? const Color(0xFFC7D2FE)
                      : (isWithdraw ? const Color(0xFFFDA4AF) : const Color(0xFF86EFAC)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isTransfer ? 'Transfer Amount' : 'Total Amount', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${tx.totalAmount < 0 ? "-₹" : "₹"} ${IndianCurrency.format(tx.totalAmount.abs())}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isTransfer
                          ? const Color(0xFF4F46E5)
                          : (isWithdraw ? const Color(0xFFBE123C) : const Color(0xFF15803D)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _buildDetailRow(Icons.notes, 'Narration', tx.narration),
            if (tx.invoice.isNotEmpty) _buildDetailRow(Icons.receipt, 'Invoice', tx.invoice),
            if (!isTransfer) ...[
              _buildDetailRow(Icons.category, 'Purpose', tx.purpose),
              _buildDetailRow(Icons.person, 'Spent For', tx.spentFor),
            ],

            if (isTransfer) ...[
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(Icons.arrow_circle_up_rounded, size: 16, color: Color(0xFFE11D48)),
                  SizedBox(width: 6),
                  Text('From (Source)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFE11D48))),
                ],
              ),
              const SizedBox(height: 6),
              ...tx.breakdowns.map((b) => _buildBreakdownRow(b)),

              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.arrow_circle_down_rounded, size: 16, color: Color(0xFF0F766E)),
                  SizedBox(width: 6),
                  Text('To (Destination)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F766E))),
                ],
              ),
              const SizedBox(height: 6),
              ...(tx.toBreakdowns ?? []).map((b) => _buildBreakdownRow(b)),
            ] else ...[
              if (tx.isSplitMode || (tx.splitRecipients != null && tx.splitRecipients!.isNotEmpty)) ...[
                () {
                  final visibleRecipients = (tx.splitRecipients ?? [])
                      .where((r) => !((r.isPersonal || r.name.trim().toLowerCase() == 'personal share') && r.amount <= 0))
                      .toList();
                  if (visibleRecipients.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.call_split_rounded, size: 18, color: Color(0xFF0F766E)),
                          const SizedBox(width: 6),
                          const Text(
                            'Split Allocations',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F766E)),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              visibleRecipients.length <= 1 && tx.spentFor != 'Split'
                                  ? '100% Single Person'
                                  : '${visibleRecipients.length} Members',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...visibleRecipients.map((r) {
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: r.isPersonal ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: r.isPersonal ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    r.isPersonal ? Icons.person : Icons.group_outlined,
                                    size: 16,
                                    color: r.isPersonal ? const Color(0xFF0F766E) : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    r.name,
                                    style: TextStyle(
                                      fontWeight: r.isPersonal ? FontWeight.bold : FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '(${r.percentage.toStringAsFixed(1)}%)',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                              Text(
                                '₹ ${IndianCurrency.format(r.amount)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  );
                }(),
              ],

              const SizedBox(height: 12),
              const Text(
                'Payment Breakdowns',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              ...tx.breakdowns.map((b) => _buildBreakdownRow(b)),
            ],

            const SizedBox(height: 16),
            // Convert to Credit Card EMI / EMI Details
            () {
              final linkedPlan = _emiPlanById[tx.id] ?? _emiPlanByRef[tx.referenceId];
              if (linkedPlan != null) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5C38).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFF5C38).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.credit_card_rounded, size: 16, color: Color(0xFFFF5C38)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'EMI Plan: ${linkedPlan.title}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFFF5C38)),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF5C38).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              linkedPlan.status,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFF5C38)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Converted Principal: ₹${IndianCurrency.format(linkedPlan.bookingPrincipal)} (${linkedPlan.tenureMonths} Mo @ ${linkedPlan.annualInterestRate}%)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      if (linkedPlan.isPartialConversion) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Non-EMI Due: ₹${IndianCurrency.format(linkedPlan.nonEmiBalance)}',
                          style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                      ],
                      if (linkedPlan.reversalTransactionRef != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Credit Reversal: ${linkedPlan.reversalTransactionRef}',
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF00B074), fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF5C38),
                            side: const BorderSide(color: Color(0xFFFF5C38)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.edit_note_rounded, size: 18),
                          label: const Text('Edit EMI Plan / Schedule', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            EmiConversionSheet.show(context, existingPlan: linkedPlan);
                          },
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (!tx.isEligibleForEmiConversion(knownCreditCards: _knownCreditCards)) {
                return const SizedBox.shrink();
              }

              return SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5C38),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.credit_card_outlined, size: 20),
                  label: const Text('Convert to Card EMI',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    EmiConversionSheet.show(context, transaction: tx);
                  },
                ),
              );
            }(),
            const SizedBox(height: 10),
            Row(
              children: [
                // Delete button inside log
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444), width: 1.4),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text('Delete Transaction'),
                          content: Text('Are you sure you want to delete transaction "${tx.referenceId}"?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await _storage.deleteTransaction(tx.id, referenceId: tx.referenceId);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        _loadTransactions();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Deleted ${tx.referenceId}', textAlign: TextAlign.center),
                              backgroundColor: const Color(0xFFEF4444),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                // Edit button inside log
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.edit_note_rounded, size: 20),
                    label: const Text('Edit', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pop(context, [tx]);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownRow(PaymentBreakdown b) {
    final isCash = b.paymentType == 'Cash';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${b.paymentType} ${b.effectiveAccount.isNotEmpty ? "• ${b.effectiveAccount}" : ""}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                b.amount < 0
                    ? '-₹ ${IndianCurrency.format(b.amount.abs())}'
                    : '₹ ${IndianCurrency.format(b.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: b.amount < 0 ? const Color(0xFFEF4444) : null,
                ),
              ),
            ],
          ),
          if (isCash) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: b.denominations.entries
                  .where((e) => e.value != 0)
                  .map((e) => Chip(
                        visualDensity: VisualDensity.compact,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        label: Text(
                          '₹${e.key} × ${e.value}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          SizedBox(
            width: 75,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveChip(String label, VoidCallback onRemove, bool isDark) {
    return InkWell(
      onTap: onRemove,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: const Color(0xFF0F766E).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F766E)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.close, size: 13, color: Color(0xFF0F766E)),
          ],
        ),
      ),
    );
  }

  Future<void> _openFacetedFilter() async {
    HapticFeedback.lightImpact();
    final result = await FacetedFilterSheet.show(
      context: context,
      allTransactions: _transactions,
      initialCriteria: _filterCriteria,
    );

    if (result != null && mounted) {
      setState(() {
        _filterCriteria = result;
        _searchController.text = _filterCriteria.narrationQuery;
      });
    }
  }

  // ==========================================
  // BUILD METHOD
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Filter using Flipkart / Amazon two-pane faceted criteria
    final filtered = _transactions.where((tx) => _filterCriteria.matches(tx)).toList();

    // Summary calculation: ONLY FOR SELECTED ITEMS if selection active, else FOR ALL FILTERED
    final itemsToSum = _isSelectionActive
        ? filtered.where((t) => _selectedIds.contains(t.id)).toList()
        : filtered;

    double totalOutflow = 0.0;
    double totalInflow = 0.0;
    double totalTransfer = 0.0;
    for (final t in itemsToSum) {
      if (t.isSelfTransfer || t.flow == 'Transfer') {
        totalTransfer += t.totalAmount;
      } else if (t.flow == 'Withdraw') {
        totalOutflow += t.totalAmount;
      } else {
        totalInflow += t.totalAmount;
      }
    }
    final summaryCount = itemsToSum.length;

    return Scaffold(
      appBar: AppBar(
        title: _isSelectionActive
            ? Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_selectedIds.length} Selected',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ),
                ],
              )
            : const Text('History'),
        actions: [
          if (_isSelectionActive) ...[
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF4F46E5), size: 22),
              tooltip: 'Export Selected',
              onPressed: () {
                final selected = _transactions.where((t) => _selectedIds.contains(t.id)).toList();
                if (selected.isEmpty) return;
                StatementExportDialog.show(
                  context,
                  prefilteredTransactions: selected,
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF0F766E), size: 24),
              tooltip: 'Edit Selected',
              onPressed: () {
                final selected = _transactions.where((t) => _selectedIds.contains(t.id)).toList();
                if (selected.isEmpty) return;
                Navigator.of(context).pop(selected);
              },
            ),
            IconButton(
              icon: const Icon(Icons.select_all_rounded),
              tooltip: 'Select All',
              onPressed: () => _selectAll(filtered),
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444)),
              tooltip: 'Delete Selected',
              onPressed: _deleteSelectedTransactions,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Cancel Selection',
              onPressed: _clearSelection,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Export Statement',
              onPressed: () {
                StatementExportDialog.show(
                  context,
                  prefilteredTransactions: filtered,
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () => _loadTransactions(forceRefresh: true),
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              behavior: HitTestBehavior.translucent,
              child: SafeArea(
                  child: Stack(
                    children: [
                    Column(
                      children: [
                        // Search Input
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search narration, ref, accounts...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              suffixIconConstraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        icon: const Icon(Icons.close_rounded, size: 18),
                                        splashRadius: 18,
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _filterCriteria.narrationQuery = '');
                                        },
                                      ),
                                    )
                                  : null,
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            ),
                            onChanged: (val) => setState(() => _filterCriteria.narrationQuery = val),
                          ),
                        ),

                    // Filter Action Bar: Full Range Filters button + Flow Chips
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // Full Range Filter Trigger Button
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: InkWell(
                                onTap: _openFacetedFilter,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _activeFilterCount > 0
                                        ? const Color(0xFF0F766E).withValues(alpha: 0.15)
                                        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _activeFilterCount > 0
                                          ? const Color(0xFF0F766E)
                                          : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.tune_rounded,
                                        size: 15,
                                        color: _activeFilterCount > 0 ? const Color(0xFF0F766E) : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        _activeFilterCount > 0 ? 'Filters ($_activeFilterCount)' : 'Filters',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: _activeFilterCount > 0 ? const Color(0xFF0F766E) : (isDark ? Colors.white : const Color(0xFF1E293B)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            ...['All', 'Withdraw', 'Deposit', 'Transfer'].map((flow) {
                              final isSelected = flow == 'All'
                                  ? _filterCriteria.selectedFlows.isEmpty
                                  : _filterCriteria.selectedFlows.contains(flow);
                              return Padding(
                                padding: const EdgeInsets.only(right: 6.0),
                                child: FilterChip(
                                  label: Text(flow, style: const TextStyle(fontSize: 12)),
                                  selected: isSelected,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (selected) {
                                    setState(() {
                                      if (flow == 'All') {
                                        _filterCriteria.selectedFlows.clear();
                                      } else {
                                        if (selected) {
                                          _filterCriteria.selectedFlows.add(flow);
                                        } else {
                                          _filterCriteria.selectedFlows.remove(flow);
                                        }
                                      }
                                    });
                                  },
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),

                    // Active non-flow filter chips row
                    if (_filterCriteria.startDate != null ||
                        (_filterCriteria.datePreset != 'All Time' && _filterCriteria.datePreset.isNotEmpty) ||
                        _filterCriteria.selectedAccounts.isNotEmpty ||
                        _filterCriteria.selectedPaymentTypes.isNotEmpty ||
                        _filterCriteria.selectedPurposes.isNotEmpty ||
                        _filterCriteria.selectedSpentFors.isNotEmpty ||
                        _filterCriteria.selectedNarrations.isNotEmpty ||
                        _filterCriteria.selectedAmounts.isNotEmpty ||
                        _filterCriteria.minAmount != null ||
                        _filterCriteria.maxAmount != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              if (_filterCriteria.startDate != null || (_filterCriteria.datePreset != 'All Time' && _filterCriteria.datePreset.isNotEmpty))
                                _buildActiveChip('📅 $_dateRangeDisplayString', () => setState(() => _setDatePreset('All Time')), isDark),
                              ..._filterCriteria.selectedNarrations.map((narr) =>
                                _buildActiveChip('📝 $narr', () => setState(() => _filterCriteria.selectedNarrations.remove(narr)), isDark),
                              ),
                              ..._filterCriteria.selectedAccounts.map((acc) =>
                                _buildActiveChip('💳 $acc', () => setState(() => _filterCriteria.selectedAccounts.remove(acc)), isDark),
                              ),
                              ..._filterCriteria.selectedPaymentTypes.map((pt) =>
                                _buildActiveChip('⚡ $pt', () => setState(() => _filterCriteria.selectedPaymentTypes.remove(pt)), isDark),
                              ),
                              ..._filterCriteria.selectedPurposes.map((purp) =>
                                _buildActiveChip('🏷 $purp', () => setState(() => _filterCriteria.selectedPurposes.remove(purp)), isDark),
                              ),
                              ..._filterCriteria.selectedSpentFors.map((sf) =>
                                _buildActiveChip('👤 $sf', () => setState(() => _filterCriteria.selectedSpentFors.remove(sf)), isDark),
                              ),
                              ..._filterCriteria.selectedAmounts.map((amt) =>
                                _buildActiveChip('💰 ₹${IndianCurrency.formatSmart(amt)}', () => setState(() => _filterCriteria.selectedAmounts.remove(amt)), isDark),
                              ),
                              if (_filterCriteria.minAmount != null || _filterCriteria.maxAmount != null)
                                _buildActiveChip(
                                  '💰 ${_filterCriteria.minAmount != null ? "₹${IndianCurrency.formatSmart(_filterCriteria.minAmount!)}" : "₹0"} - ${_filterCriteria.maxAmount != null ? "₹${IndianCurrency.formatSmart(_filterCriteria.maxAmount!)}" : "∞"}',
                                  () => setState(() {
                                    _filterCriteria.minAmount = null;
                                    _filterCriteria.maxAmount = null;
                                  }),
                                  isDark,
                                ),
                              Padding(
                                padding: const EdgeInsets.only(left: 4.0),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _filterCriteria.startDate = null;
                                      _filterCriteria.endDate = null;
                                      _filterCriteria.datePreset = 'All Time';
                                      _filterCriteria.selectedNarrations.clear();
                                      _filterCriteria.selectedAccounts.clear();
                                      _filterCriteria.selectedPaymentTypes.clear();
                                      _filterCriteria.selectedPurposes.clear();
                                      _filterCriteria.selectedSpentFors.clear();
                                      _filterCriteria.selectedAmounts.clear();
                                      _filterCriteria.minAmount = null;
                                      _filterCriteria.maxAmount = null;
                                    });
                                  },
                                  child: const Text(
                                    'Clear',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                // ==========================================
                // SUMMARY STATS ROW (Dynamic based on selection)
                // ==========================================
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isSelectionActive
                        ? (isDark ? const Color(0xFF1E284A) : const Color(0xFFEFF6FF))
                        : (isDark ? const Color(0xFF161A30) : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isSelectionActive
                          ? const Color(0xFF3B82F6)
                          : (isDark ? const Color(0xFF2C3360) : const Color(0xFFE2E8F0)),
                      width: _isSelectionActive ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Outflow', style: TextStyle(fontSize: 10, color: Colors.red)),
                                Text(
                                  '₹${IndianCurrency.formatSmart(totalOutflow)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                          Container(height: 20, width: 1, color: Colors.grey.shade300),
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Inflow', style: TextStyle(fontSize: 10, color: Colors.green)),
                                Text(
                                  '₹${IndianCurrency.formatSmart(totalInflow)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green),
                                ),
                              ],
                            ),
                          ),
                          Container(height: 20, width: 1, color: Colors.grey.shade300),
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Transfer', style: TextStyle(fontSize: 10, color: Color(0xFF4F46E5))),
                                Text(
                                  '₹${IndianCurrency.formatSmart(totalTransfer)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF4F46E5)),
                                ),
                              ],
                            ),
                          ),
                          Container(height: 20, width: 1, color: Colors.grey.shade300),
                          Expanded(
                            child: Column(
                              children: [
                                Text(_isSelectionActive ? 'Selected' : 'Count', style: const TextStyle(fontSize: 10)),
                                Text(
                                  '$summaryCount',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: _isSelectionActive ? const Color(0xFF2563EB) : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ==========================================
                // TRANSACTIONS LIST WITH MODERN MULTI-SELECT
                // ==========================================
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text(
                                _transactions.isEmpty ? 'No transactions yet' : 'No matching transactions',
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                              ),
                              if (_activeFilterCount > 0) ...[
                                const SizedBox(height: 12),
                                FilledButton.tonalIcon(
                                  onPressed: _resetAllFilters,
                                  icon: const Icon(Icons.clear_all, size: 16),
                                  label: const Text('Reset All Filters', style: TextStyle(fontSize: 13)),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ValueListenableBuilder<Set<String>>(
                          valueListenable: StorageService.instance.pendingSyncSetNotifier,
                          builder: (context, pendingSyncSet, _) {
                            return ListView.builder(
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 64),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final tx = filtered[index];
                                final isTxTransfer = tx.isSelfTransfer || tx.flow == 'Transfer';
                                final isWithdraw = tx.flow == 'Withdraw';
                                final isSelected = _selectedIds.contains(tx.id);
                                final isPending = _storage.isPendingSync(tx.referenceId, tx.id);

                                final Color iconBg = isSelected
                                    ? const Color(0xFF2563EB)
                                    : (isTxTransfer
                                        ? const Color(0xFF6366F1).withValues(alpha: 0.12)
                                        : (isWithdraw ? const Color(0xFFEF4444) : const Color(0xFF10B981)).withValues(alpha: 0.12));

                                final IconData txIcon = isSelected
                                    ? Icons.check_rounded
                                    : (isTxTransfer
                                        ? Icons.swap_horiz_rounded
                                        : (isWithdraw ? Icons.arrow_upward : Icons.arrow_downward));

                                final Color iconColor = isSelected
                                    ? Colors.white
                                    : (isTxTransfer
                                        ? const Color(0xFF4F46E5)
                                        : (isWithdraw ? const Color(0xFFDC2626) : const Color(0xFF059669)));

                                final Color amountColor = isTxTransfer
                                    ? const Color(0xFF4F46E5)
                                    : (isWithdraw ? const Color(0xFFBE123C) : const Color(0xFF15803D));

                                String? runningBalStr;
                                if (_liveSummary != null && _liveSummary!.txRunningBalances.containsKey(tx.id)) {
                                  final runningMap = _liveSummary!.txRunningBalances[tx.id]!;
                                  if (runningMap.length == 1) {
                                    runningBalStr = '₹${IndianCurrency.format(runningMap.values.first)}';
                                  } else if (runningMap.isNotEmpty) {
                                    runningBalStr = runningMap.entries
                                        .map((e) => '${e.key.split(' ').first}: ₹${IndianCurrency.formatSmart(e.value)}')
                                        .join(' | ');
                                  }
                                }

                                return AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.symmetric(vertical: 3.5),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? (isDark ? const Color(0xFF1E284A) : const Color(0xFFEFF6FF))
                                          : (isDark ? const Color(0xFF161A30) : Colors.white),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF3B82F6)
                                            : (isDark ? const Color(0xFF2C3360) : const Color(0xFFE2E8F0)),
                                        width: isSelected ? 1.8 : 1.0,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: const Color(0xFF3B82F6).withValues(alpha: isDark ? 0.35 : 0.15),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: ListTile(
                                        dense: true,
                                      onLongPress: () => _toggleSelection(tx.id),
                                      onTap: () {
                                        if (_isSelectionActive) {
                                          _toggleSelection(tx.id);
                                        } else {
                                          _showTransactionDetail(tx);
                                        }
                                      },
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                      leading: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: iconBg,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          txIcon,
                                          size: 16,
                                          color: iconColor,
                                        ),
                                      ),
                                      // Title row with narration, sync status badge, and amount
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              tx.narration.isEmpty
                                                  ? (isTxTransfer ? 'Self Transfer' : 'Transaction')
                                                  : tx.narration,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: isSelected ? const Color(0xFF1D4ED8) : null,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          // EMI converted indicator
                                          if (_emiLinkedIds.contains(tx.id) || _emiLinkedRefs.contains(tx.referenceId)) ...[
                                            InkWell(
                                              onTap: () => _openEmiPlan(tx),
                                              borderRadius: BorderRadius.circular(6),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFF5C38).withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: const Color(0xFFFF5C38).withValues(alpha: 0.4), width: 0.8),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.credit_card, size: 10, color: Color(0xFFFF5C38)),
                                                    SizedBox(width: 3),
                                                    Text(
                                                      'EMI',
                                                      style: TextStyle(
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFFFF5C38),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                          ],
                                          // EMI reversal credit indicator
                                          if (tx.purpose == 'Credit Card EMI Reversal') ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF00B074).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFF00B074).withValues(alpha: 0.4), width: 0.8),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.undo_rounded, size: 10, color: Color(0xFF00B074)),
                                                  SizedBox(width: 3),
                                                  Text(
                                                    'EMI Credit',
                                                    style: TextStyle(
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFF00B074),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                          ],
                                          // EMI processing fee indicator
                                          if (tx.purpose == 'Bank Charges / Processing Fee' && tx.narration.toLowerCase().contains('emi')) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4), width: 0.8),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.receipt_long_rounded, size: 10, color: Color(0xFFD97706)),
                                                  SizedBox(width: 3),
                                                  Text(
                                                    'EMI Fee',
                                                    style: TextStyle(
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFFD97706),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                          ],
                                          // EMI installment debit indicator
                                          if (tx.purpose == 'Credit Card EMI Installment') ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4), width: 0.8),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.calendar_month_rounded, size: 10, color: Color(0xFF4F46E5)),
                                                  SizedBox(width: 3),
                                                  Text(
                                                    'EMI Due',
                                                    style: TextStyle(
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFF4F46E5),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                          ],
                                          // Sync status indicator: ONLY SHOWN IF NOT YET SYNCED!
                                          if (isPending) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFEF3C7),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFF59E0B), width: 0.8),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SizedBox(
                                                    width: 8,
                                                    height: 8,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 1.4,
                                                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD97706)),
                                                    ),
                                                  ),
                                                  SizedBox(width: 3.5),
                                                  Text(
                                                    'Syncing...',
                                                    style: TextStyle(
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFFB45309),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          Text(
                                            '${tx.totalAmount < 0 ? "-₹" : "₹"}${IndianCurrency.format(tx.totalAmount.abs())}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: amountColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      // Subtitle column with date, purpose, ref ID, and split member breakdown
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 2.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    isTxTransfer
                                                        ? '${FinanceTransaction.formatDate(tx.date)} • ${tx.fromSummary} ➔ ${tx.toSummary}'
                                                        : '${FinanceTransaction.formatDate(tx.date)} • ${tx.purpose}',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: isTxTransfer ? FontWeight.w500 : FontWeight.normal,
                                                      color: isTxTransfer ? const Color(0xFF4F46E5) : Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  tx.referenceId,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontFamily: 'monospace',
                                                    color: Colors.grey.shade500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (runningBalStr != null) ...[
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.account_balance_wallet_outlined,
                                                    size: 10.5,
                                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    'Bal: $runningBalStr',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w600,
                                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            if (!isTxTransfer &&
                                                (tx.isSplitMode || (tx.splitRecipients != null && tx.splitRecipients!.isNotEmpty)) &&
                                                tx.splitRecipients != null &&
                                                tx.splitRecipients!.isNotEmpty) ...[
                                              () {
                                                final visibleRecipients = tx.splitRecipients!
                                                    .where((r) => !((r.isPersonal || r.name.trim().toLowerCase() == 'personal share') && r.amount <= 0))
                                                    .toList();
                                                if (visibleRecipients.isEmpty) return const SizedBox.shrink();
                                                return Padding(
                                                  padding: const EdgeInsets.only(top: 4.0),
                                                  child: Wrap(
                                                    spacing: 4,
                                                    runSpacing: 2,
                                                    children: visibleRecipients.map((r) {
                                                      final chip = Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                        decoration: BoxDecoration(
                                                          color: r.isPersonal
                                                              ? const Color(0xFFF1F5F9)
                                                              : const Color(0xFF0F766E).withValues(alpha: 0.08),
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(
                                                            color: r.isPersonal
                                                                ? const Color(0xFFCBD5E1)
                                                                : const Color(0xFF0F766E).withValues(alpha: 0.3),
                                                            width: 0.8,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          '${r.name}: ₹${IndianCurrency.formatSmart(r.amount)}',
                                                          style: TextStyle(
                                                            fontSize: 9.5,
                                                            fontWeight: FontWeight.w600,
                                                            color: r.isPersonal ? const Color(0xFF475569) : const Color(0xFF0F766E),
                                                          ),
                                                        ),
                                                      );
                                                      if (r.isPersonal) return chip;
                                                      return InkWell(
                                                        onTap: () => _openBorrowerLedger(r.name),
                                                        borderRadius: BorderRadius.circular(4),
                                                        child: chip,
                                                      );
                                                    }).toList(),
                                                  ),
                                                );
                                              }(),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                                },
                            );
                          },
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
}
