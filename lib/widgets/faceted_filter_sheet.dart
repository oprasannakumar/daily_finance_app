import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../utils/currency_formatter.dart';
import 'swipeable_date_picker.dart';

enum FilterCategory {
  date('Date', Icons.calendar_today_outlined),
  narration('Narration', Icons.edit_note_outlined),
  flow('Flow', Icons.swap_horiz_rounded),
  spentFor('Spent For', Icons.people_outline),
  purpose('Purpose', Icons.label_outline),
  paymentType('Payment Type', Icons.payment_outlined),
  account('Account', Icons.account_balance_outlined),
  amounts('Amounts', Icons.currency_rupee_rounded);

  final String label;
  final IconData icon;
  const FilterCategory(this.label, this.icon);
}

class TransactionFilterCriteria {
  Set<String> selectedFlows;
  Set<String> selectedAccounts;
  Set<String> selectedPaymentTypes;
  Set<String> selectedPurposes;
  Set<String> selectedSpentFors;
  Set<String> selectedNarrations;
  Set<double> selectedAmounts;
  String datePreset; // All Time, Today, Yesterday, This Week, This Month, Custom
  DateTime? startDate;
  DateTime? endDate;
  String narrationQuery;
  double? minAmount;
  double? maxAmount;

  TransactionFilterCriteria({
    Set<String>? selectedFlows,
    Set<String>? selectedAccounts,
    Set<String>? selectedPaymentTypes,
    Set<String>? selectedPurposes,
    Set<String>? selectedSpentFors,
    Set<String>? selectedNarrations,
    Set<double>? selectedAmounts,
    this.datePreset = 'All Time',
    this.startDate,
    this.endDate,
    this.narrationQuery = '',
    this.minAmount,
    this.maxAmount,
  })  : selectedFlows = selectedFlows != null ? Set<String>.from(selectedFlows) : {},
        selectedAccounts = selectedAccounts != null ? Set<String>.from(selectedAccounts) : {},
        selectedPaymentTypes = selectedPaymentTypes != null ? Set<String>.from(selectedPaymentTypes) : {},
        selectedPurposes = selectedPurposes != null ? Set<String>.from(selectedPurposes) : {},
        selectedSpentFors = selectedSpentFors != null ? Set<String>.from(selectedSpentFors) : {},
        selectedNarrations = selectedNarrations != null ? Set<String>.from(selectedNarrations) : {},
        selectedAmounts = selectedAmounts != null ? Set<double>.from(selectedAmounts) : {};

  TransactionFilterCriteria copy() {
    return TransactionFilterCriteria(
      selectedFlows: Set<String>.from(selectedFlows),
      selectedAccounts: Set<String>.from(selectedAccounts),
      selectedPaymentTypes: Set<String>.from(selectedPaymentTypes),
      selectedPurposes: Set<String>.from(selectedPurposes),
      selectedSpentFors: Set<String>.from(selectedSpentFors),
      selectedNarrations: Set<String>.from(selectedNarrations),
      selectedAmounts: Set<double>.from(selectedAmounts),
      datePreset: datePreset,
      startDate: startDate,
      endDate: endDate,
      narrationQuery: narrationQuery,
      minAmount: minAmount,
      maxAmount: maxAmount,
    );
  }

  int get activeFilterCount {
    int count = 0;
    if (selectedFlows.isNotEmpty) count++;
    if (selectedAccounts.isNotEmpty) count++;
    if (selectedPaymentTypes.isNotEmpty) count++;
    if (selectedPurposes.isNotEmpty) count++;
    if (selectedSpentFors.isNotEmpty) count++;
    if (selectedNarrations.isNotEmpty || narrationQuery.trim().isNotEmpty) count++;
    if (startDate != null || (datePreset != 'All Time' && datePreset.isNotEmpty)) count++;
    if (selectedAmounts.isNotEmpty || minAmount != null || maxAmount != null) count++;
    return count;
  }

  bool get isEmpty => activeFilterCount == 0;

  void clear() {
    selectedFlows.clear();
    selectedAccounts.clear();
    selectedPaymentTypes.clear();
    selectedPurposes.clear();
    selectedSpentFors.clear();
    selectedNarrations.clear();
    selectedAmounts.clear();
    datePreset = 'All Time';
    startDate = null;
    endDate = null;
    narrationQuery = '';
    minAmount = null;
    maxAmount = null;
  }

  bool matches(FinanceTransaction tx) {
    // 1. Date
    if (startDate != null) {
      final startBound = DateTime(startDate!.year, startDate!.month, startDate!.day, 0, 0, 0);
      final endBound = endDate != null
          ? DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59)
          : DateTime(startDate!.year, startDate!.month, startDate!.day, 23, 59, 59);
      final txDate = sanitizeDateYear(tx.date);
      if (txDate.isBefore(startBound) || txDate.isAfter(endBound)) {
        return false;
      }
    }

    // 2. Narration
    if (selectedNarrations.isNotEmpty) {
      if (!selectedNarrations.contains(tx.narration)) {
        return false;
      }
    }
    if (narrationQuery.trim().isNotEmpty) {
      final q = narrationQuery.trim().toLowerCase();
      final matchNarr = tx.narration.toLowerCase().contains(q);
      final matchRef = tx.referenceId.toLowerCase().contains(q);
      final matchInvoice = tx.invoice.toLowerCase().contains(q);
      final matchBorrower = (tx.splitRecipients ?? []).any((r) => r.name.toLowerCase().contains(q));
      final matchFrom = tx.fromSummary.toLowerCase().contains(q);
      final matchTo = tx.toSummary.toLowerCase().contains(q);
      final matchPurp = tx.purpose.toLowerCase().contains(q);
      final matchSpent = tx.spentFor.toLowerCase().contains(q);
      if (!(matchNarr || matchRef || matchInvoice || matchBorrower || matchFrom || matchTo || matchPurp || matchSpent)) {
        return false;
      }
    }

    // 3. Flow
    if (selectedFlows.isNotEmpty) {
      final isTxTransfer = tx.isSelfTransfer || tx.flow == 'Transfer';
      if (isTxTransfer) {
        if (!selectedFlows.contains('Transfer')) return false;
      } else {
        if (!selectedFlows.contains(tx.flow)) return false;
      }
    }

    // 4. Spent For
    if (selectedSpentFors.isNotEmpty) {
      if (!selectedSpentFors.contains(tx.spentFor)) return false;
    }

    // 5. Purpose
    if (selectedPurposes.isNotEmpty) {
      if (!selectedPurposes.contains(tx.purpose)) return false;
    }

    // 6. Payment Type
    if (selectedPaymentTypes.isNotEmpty) {
      final hasType = tx.breakdowns.any((b) => b.paymentType != null && selectedPaymentTypes.contains(b.paymentType)) ||
          (tx.toBreakdowns ?? []).any((b) => b.paymentType != null && selectedPaymentTypes.contains(b.paymentType));
      if (!hasType) return false;
    }

    // 7. Account
    if (selectedAccounts.isNotEmpty) {
      final fromMatch = selectedAccounts.contains(tx.fromSummary);
      final toMatch = selectedAccounts.contains(tx.toSummary);
      final breakdownMatch = tx.breakdowns.any((b) =>
          selectedAccounts.contains(b.effectiveAccount) || (b.account != null && selectedAccounts.contains(b.account)));
      final toBreakdownMatch = (tx.toBreakdowns ?? []).any((b) =>
          selectedAccounts.contains(b.effectiveAccount) || (b.account != null && selectedAccounts.contains(b.account)));
      if (!(fromMatch || toMatch || breakdownMatch || toBreakdownMatch)) return false;
    }

    // 8. Amounts
    if (selectedAmounts.isNotEmpty) {
      if (!selectedAmounts.contains(tx.totalAmount)) return false;
    }
    if (minAmount != null && tx.totalAmount < minAmount!) return false;
    if (maxAmount != null && tx.totalAmount > maxAmount!) return false;

    return true;
  }
}

/// Amazon / Flipkart styled two-pane faceted filter modal sheet.
class FacetedFilterSheet extends StatefulWidget {
  final List<FinanceTransaction> allTransactions;
  final TransactionFilterCriteria initialCriteria;

  const FacetedFilterSheet({
    super.key,
    required this.allTransactions,
    required this.initialCriteria,
  });

  static Future<TransactionFilterCriteria?> show({
    required BuildContext context,
    required List<FinanceTransaction> allTransactions,
    required TransactionFilterCriteria initialCriteria,
  }) {
    return showModalBottomSheet<TransactionFilterCriteria>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FacetedFilterSheet(
        allTransactions: allTransactions,
        initialCriteria: initialCriteria,
      ),
    );
  }

  @override
  State<FacetedFilterSheet> createState() => _FacetedFilterSheetState();
}

class _FacetedFilterSheetState extends State<FacetedFilterSheet> {
  late TransactionFilterCriteria _criteria;
  FilterCategory _selectedCategory = FilterCategory.flow;

  // Search controllers for right-pane lists
  final TextEditingController _narrationCtrl = TextEditingController();
  final TextEditingController _purposeSearchCtrl = TextEditingController();
  final TextEditingController _accountSearchCtrl = TextEditingController();
  final TextEditingController _spentForSearchCtrl = TextEditingController();
  final TextEditingController _minAmountCtrl = TextEditingController();
  final TextEditingController _maxAmountCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _criteria = widget.initialCriteria.copy();
    _narrationCtrl.text = _criteria.narrationQuery;
    if (_criteria.minAmount != null) _minAmountCtrl.text = _criteria.minAmount!.toStringAsFixed(0);
    if (_criteria.maxAmount != null) _maxAmountCtrl.text = _criteria.maxAmount!.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _narrationCtrl.dispose();
    _purposeSearchCtrl.dispose();
    _accountSearchCtrl.dispose();
    _spentForSearchCtrl.dispose();
    _minAmountCtrl.dispose();
    _maxAmountCtrl.dispose();
    super.dispose();
  }

  // =========================================================================
  // FACETED COUNT ENGINE (Flipkart & Amazon Cross-Filtering)
  // =========================================================================

  /// Returns the subset of transactions matching all criteria EXCEPT the given category.
  List<FinanceTransaction> _getSubsetExcluding(FilterCategory category) {
    final base = _criteria.copy();
    switch (category) {
      case FilterCategory.date:
        base.startDate = null;
        base.endDate = null;
        base.datePreset = 'All Time';
        break;
      case FilterCategory.narration:
        base.selectedNarrations.clear();
        base.narrationQuery = '';
        break;
      case FilterCategory.flow:
        base.selectedFlows.clear();
        break;
      case FilterCategory.spentFor:
        base.selectedSpentFors.clear();
        break;
      case FilterCategory.purpose:
        base.selectedPurposes.clear();
        break;
      case FilterCategory.paymentType:
        base.selectedPaymentTypes.clear();
        break;
      case FilterCategory.account:
        base.selectedAccounts.clear();
        break;
      case FilterCategory.amounts:
        base.selectedAmounts.clear();
        base.minAmount = null;
        base.maxAmount = null;
        break;
    }
    return widget.allTransactions.where((t) => base.matches(t)).toList();
  }

  /// Calculates total transactions matching the full active criteria
  int get _matchingCount {
    return widget.allTransactions.where((t) => _criteria.matches(t)).length;
  }

  void _setDatePreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _criteria.datePreset = preset;
      switch (preset) {
        case 'All Time':
          _criteria.startDate = null;
          _criteria.endDate = null;
          break;
        case 'Today':
          _criteria.startDate = today;
          _criteria.endDate = today;
          break;
        case 'Yesterday':
          final yest = today.subtract(const Duration(days: 1));
          _criteria.startDate = yest;
          _criteria.endDate = yest;
          break;
        case 'This Week':
          final weekStart = today.subtract(Duration(days: today.weekday - 1));
          _criteria.startDate = weekStart;
          _criteria.endDate = today;
          break;
        case 'This Month':
          final monthStart = DateTime(today.year, today.month, 1);
          _criteria.startDate = monthStart;
          _criteria.endDate = today;
          break;
      }
    });
  }

  Future<void> _openCustomDateRange() async {
    final now = DateTime.now();
    final result = await SwipeableDateRangePickerDialog.show(
      context: context,
      initialStartDate: _criteria.startDate ?? now,
      initialEndDate: _criteria.endDate ?? now,
      currentPreset: _criteria.datePreset,
    );

    if (result != null && mounted) {
      setState(() {
        if (result.isAllTime) {
          _setDatePreset('All Time');
        } else if (result.presetName != 'Custom') {
          _setDatePreset(result.presetName);
        } else {
          _criteria.startDate = result.start;
          _criteria.endDate = result.end;
          _criteria.datePreset = 'Custom';
        }
      });
    }
  }

  String _getCategoryBadge(FilterCategory category) {
    switch (category) {
      case FilterCategory.date:
        return _criteria.datePreset != 'All Time' ? _criteria.datePreset : '';
      case FilterCategory.narration:
        if (_criteria.selectedNarrations.isNotEmpty) {
          return '${_criteria.selectedNarrations.length}';
        }
        return _criteria.narrationQuery.trim().isNotEmpty ? 'Active' : '';
      case FilterCategory.flow:
        return _criteria.selectedFlows.isNotEmpty ? '${_criteria.selectedFlows.length}' : '';
      case FilterCategory.spentFor:
        return _criteria.selectedSpentFors.isNotEmpty ? '${_criteria.selectedSpentFors.length}' : '';
      case FilterCategory.purpose:
        return _criteria.selectedPurposes.isNotEmpty ? '${_criteria.selectedPurposes.length}' : '';
      case FilterCategory.paymentType:
        return _criteria.selectedPaymentTypes.isNotEmpty ? '${_criteria.selectedPaymentTypes.length}' : '';
      case FilterCategory.account:
        return _criteria.selectedAccounts.isNotEmpty ? '${_criteria.selectedAccounts.length}' : '';
      case FilterCategory.amounts:
        if (_criteria.selectedAmounts.isNotEmpty) {
          return '${_criteria.selectedAmounts.length}';
        }
        return (_criteria.minAmount != null || _criteria.maxAmount != null) ? 'Active' : '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = const Color(0xFF0F766E);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final sidebarBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final totalMatching = _matchingCount;

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // 1. Top Header with Drag Handle & Actions
          Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 42,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 8, 10),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 20, color: primaryColor),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Full Range Filters',
                        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$totalMatching items',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor),
                      ),
                    ),
                    const Spacer(),
                    if (!_criteria.isEmpty)
                      TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _criteria.clear();
                            _narrationCtrl.clear();
                            _minAmountCtrl.clear();
                            _maxAmountCtrl.clear();
                          });
                        },
                        child: const Text(
                          'Clear All',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: borderColor),
            ],
          ),

          // 2. Middle Body: Two-Pane Split View
          Expanded(
            child: Row(
              children: [
                // Left Pane: Category Headers
                Container(
                  width: 130,
                  color: sidebarBg,
                  child: ListView.builder(
                    itemCount: FilterCategory.values.length,
                    itemBuilder: (ctx, index) {
                      final cat = FilterCategory.values[index];
                      final isSelected = _selectedCategory == cat;
                      final badgeText = _getCategoryBadge(cat);
                      final hasBadge = badgeText.isNotEmpty;

                      return InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedCategory = cat);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                          decoration: BoxDecoration(
                            color: isSelected ? cardBg : Colors.transparent,
                            border: Border(
                              left: BorderSide(
                                color: isSelected ? primaryColor : Colors.transparent,
                                width: 4,
                              ),
                              bottom: BorderSide(color: borderColor.withValues(alpha: 0.4), width: 0.8),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    cat.icon,
                                    size: 15,
                                    color: isSelected ? primaryColor : textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      cat.label,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        color: isSelected ? primaryColor : textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (hasBadge) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: isSelected ? primaryColor.withValues(alpha: 0.15) : textSecondary.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        badgeText,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? primaryColor : textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Vertical Divider
                Container(width: 1, color: borderColor),

                // Right Pane: Available Data Regarding Selected Header
                Expanded(
                  child: Container(
                    color: cardBg,
                    child: _buildRightPaneContent(
                      context,
                      category: _selectedCategory,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      primaryColor: primaryColor,
                      borderColor: borderColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Bottom Action Bar: Clear & Apply Buttons
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: cardBg,
              border: Border(top: BorderSide(color: borderColor, width: 1.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: borderColor),
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _criteria.clear();
                        _narrationCtrl.clear();
                        _minAmountCtrl.clear();
                        _maxAmountCtrl.clear();
                      });
                    },
                    child: Text(
                      'Clear',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      Navigator.of(context).pop(_criteria);
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Apply Filters',
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        if (totalMatching > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '($totalMatching)',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal, color: Colors.white70),
                          ),
                        ],
                      ],
                    ),
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
  // RIGHT PANE RENDERERS (With Dynamic Faceted Filtering)
  // =========================================================================

  Widget _buildRightPaneContent(
    BuildContext context, {
    required FilterCategory category,
    required Color textPrimary,
    required Color textSecondary,
    required Color primaryColor,
    required Color borderColor,
  }) {
    switch (category) {
      case FilterCategory.date:
        return _buildDatePane(context, textPrimary, textSecondary, primaryColor, borderColor);
      case FilterCategory.narration:
        return _buildNarrationPane(context, textPrimary, textSecondary, primaryColor, borderColor);
      case FilterCategory.flow:
        return _buildFlowPane(context, textPrimary, textSecondary, primaryColor, borderColor);
      case FilterCategory.spentFor:
        return _buildSpentForPane(context, textPrimary, textSecondary, primaryColor, borderColor);
      case FilterCategory.purpose:
        return _buildPurposePane(context, textPrimary, textSecondary, primaryColor, borderColor);
      case FilterCategory.paymentType:
        return _buildPaymentTypePane(context, textPrimary, textSecondary, primaryColor, borderColor);
      case FilterCategory.account:
        return _buildAccountPane(context, textPrimary, textSecondary, primaryColor, borderColor);
      case FilterCategory.amounts:
        return _buildAmountsPane(context, textPrimary, textSecondary, primaryColor, borderColor);
    }
  }

  // 1. DATE PANE
  Widget _buildDatePane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final presets = ['All Time', 'Today', 'Yesterday', 'This Week', 'This Month', 'Custom'];
    final baseSubset = _getSubsetExcluding(FilterCategory.date);

    // Calculate count of transactions in each preset
    final Map<String, int> presetCounts = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final p in presets) {
      if (p == 'All Time') {
        presetCounts[p] = baseSubset.length;
      } else if (p == 'Today') {
        presetCounts[p] = baseSubset.where((t) {
          final d = sanitizeDateYear(t.date);
          return d.year == today.year && d.month == today.month && d.day == today.day;
        }).length;
      } else if (p == 'Yesterday') {
        final yest = today.subtract(const Duration(days: 1));
        presetCounts[p] = baseSubset.where((t) {
          final d = sanitizeDateYear(t.date);
          return d.year == yest.year && d.month == yest.month && d.day == yest.day;
        }).length;
      } else if (p == 'This Week') {
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        presetCounts[p] = baseSubset.where((t) {
          final d = sanitizeDateYear(t.date);
          return !d.isBefore(weekStart) && !d.isAfter(today.add(const Duration(hours: 23, minutes: 59)));
        }).length;
      } else if (p == 'This Month') {
        final monthStart = DateTime(today.year, today.month, 1);
        presetCounts[p] = baseSubset.where((t) {
          final d = sanitizeDateYear(t.date);
          return !d.isBefore(monthStart) && !d.isAfter(today.add(const Duration(hours: 23, minutes: 59)));
        }).length;
      } else {
        presetCounts[p] = baseSubset.length;
      }
    }

    final dateFmt = DateFormat('dd MMM yyyy');
    String rangeLabel = 'Select Date Period';
    if (_criteria.startDate != null && _criteria.endDate != null) {
      rangeLabel = '${dateFmt.format(_criteria.startDate!)} to ${dateFmt.format(_criteria.endDate!)}';
    } else if (_criteria.datePreset != 'All Time') {
      rangeLabel = _criteria.datePreset;
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Text(
          'Date Preset',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          rangeLabel,
          style: TextStyle(fontSize: 11.5, color: textSecondary),
        ),
        const SizedBox(height: 10),
        ...presets.map((preset) {
          final isSelected = _criteria.datePreset == preset;
          final count = presetCounts[preset] ?? 0;

          return InkWell(
            onTap: () {
              if (preset == 'Custom') {
                _openCustomDateRange();
              } else {
                _setDatePreset(preset);
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? primaryColor.withValues(alpha: 0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? primaryColor : borderColor.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 18,
                    color: isSelected ? primaryColor : textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      preset,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? primaryColor : textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '($count)',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: count > 0 ? (isSelected ? primaryColor : textSecondary) : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // 2. NARRATION PANE
  Widget _buildNarrationPane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final baseSubset = _getSubsetExcluding(FilterCategory.narration);

    // Collect frequent narration entries from baseSubset
    final Map<String, int> narrCounts = {};
    for (final t in baseSubset) {
      final n = t.narration.trim();
      if (n.isNotEmpty) {
        narrCounts[n] = (narrCounts[n] ?? 0) + 1;
      }
    }
    final sortedNarrations = narrCounts.entries.toList()
      ..sort((a, b) {
        final aSel = _criteria.selectedNarrations.contains(a.key);
        final bSel = _criteria.selectedNarrations.contains(b.key);
        if (aSel && !bSel) return -1;
        if (!aSel && bSel) return 1;
        return b.value.compareTo(a.value);
      });

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Text(
          'Narration Search',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _narrationCtrl,
          style: TextStyle(fontSize: 13, color: textPrimary),
          decoration: InputDecoration(
            hintText: 'Keyword in narration, ref...',
            hintStyle: TextStyle(fontSize: 12, color: textSecondary),
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _narrationCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      setState(() {
                        _narrationCtrl.clear();
                        _criteria.narrationQuery = '';
                      });
                    },
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (val) {
            setState(() => _criteria.narrationQuery = val.trim());
          },
        ),
        const SizedBox(height: 14),
        if (sortedNarrations.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Frequent Narrations (${sortedNarrations.length})',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textSecondary),
              ),
              if (_criteria.selectedNarrations.isNotEmpty)
                InkWell(
                  onTap: () => setState(() => _criteria.selectedNarrations.clear()),
                  child: Text(
                    'Reset',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ...sortedNarrations.take(25).map((entry) {
            final isSelected = _criteria.selectedNarrations.contains(entry.key);
            return InkWell(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _criteria.selectedNarrations.remove(entry.key);
                  } else {
                    _criteria.selectedNarrations.add(entry.key);
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18,
                      color: isSelected ? primaryColor : textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isSelected ? primaryColor : textPrimary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '(${entry.value})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? primaryColor : textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  // 3. FLOW PANE
  Widget _buildFlowPane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final baseSubset = _getSubsetExcluding(FilterCategory.flow);
    final flows = ['Withdraw', 'Deposit', 'Transfer'];

    final Map<String, int> flowCounts = {
      'Withdraw': baseSubset.where((t) => !t.isSelfTransfer && t.flow == 'Withdraw').length,
      'Deposit': baseSubset.where((t) => !t.isSelfTransfer && t.flow == 'Deposit').length,
      'Transfer': baseSubset.where((t) => t.isSelfTransfer || t.flow == 'Transfer').length,
    };

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select Flow',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
            ),
            if (_criteria.selectedFlows.isNotEmpty)
              InkWell(
                onTap: () => setState(() => _criteria.selectedFlows.clear()),
                child: Text('Reset', style: TextStyle(fontSize: 11.5, color: primaryColor, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ...flows.map((flow) {
          final isSelected = _criteria.selectedFlows.contains(flow);
          final count = flowCounts[flow] ?? 0;
          final isZero = count == 0;

          IconData icon = Icons.arrow_upward;
          Color iconCol = const Color(0xFFEF4444);
          if (flow == 'Deposit') {
            icon = Icons.arrow_downward;
            iconCol = const Color(0xFF10B981);
          } else if (flow == 'Transfer') {
            icon = Icons.swap_horiz_rounded;
            iconCol = const Color(0xFF6366F1);
          }

          return InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (isSelected) {
                  _criteria.selectedFlows.remove(flow);
                } else {
                  _criteria.selectedFlows.add(flow);
                }
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: isSelected ? primaryColor.withValues(alpha: 0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? primaryColor : borderColor.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 19,
                    color: isSelected ? primaryColor : textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Icon(icon, size: 16, color: iconCol),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      flow,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isZero && !isSelected ? Colors.grey.shade400 : textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '($count)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: count > 0 ? (isSelected ? primaryColor : textSecondary) : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // 4. SPENT FOR PANE
  Widget _buildSpentForPane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final baseSubset = _getSubsetExcluding(FilterCategory.spentFor);

    // Extract all distinct spentFor options from allTransactions
    final Set<String> allSpentFors = {};
    for (final t in widget.allTransactions) {
      if (t.spentFor.trim().isNotEmpty) allSpentFors.add(t.spentFor.trim());
    }

    // Compute dynamic faceted counts
    final Map<String, int> counts = {};
    for (final sf in allSpentFors) {
      counts[sf] = baseSubset.where((t) => t.spentFor.trim().toLowerCase() == sf.toLowerCase()).length;
    }

    // Sort: selected first, then highest count, then alphabetical
    var list = allSpentFors.toList()
      ..sort((a, b) {
        final aSel = _criteria.selectedSpentFors.contains(a);
        final bSel = _criteria.selectedSpentFors.contains(b);
        if (aSel && !bSel) return -1;
        if (!aSel && bSel) return 1;
        final cA = counts[a] ?? 0;
        final cB = counts[b] ?? 0;
        if (cA != cB) return cB.compareTo(cA);
        return a.compareTo(b);
      });

    final query = _spentForSearchCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((item) => item.toLowerCase().contains(query)).toList();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Spent For', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary)),
                  if (_criteria.selectedSpentFors.isNotEmpty)
                    InkWell(
                      onTap: () => setState(() => _criteria.selectedSpentFors.clear()),
                      child: Text('Reset', style: TextStyle(fontSize: 11.5, color: primaryColor, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              if (allSpentFors.length > 5) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _spentForSearchCtrl,
                  style: TextStyle(fontSize: 12.5, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search spent for...',
                    hintStyle: TextStyle(fontSize: 11.5, color: textSecondary),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            itemCount: list.length,
            itemBuilder: (ctx, idx) {
              final item = list[idx];
              final isSelected = _criteria.selectedSpentFors.contains(item);
              final count = counts[item] ?? 0;
              final isZero = count == 0;

              return InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (isSelected) {
                      _criteria.selectedSpentFors.remove(item);
                    } else {
                      _criteria.selectedSpentFors.add(item);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 18,
                        color: isSelected ? primaryColor : textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isZero && !isSelected ? Colors.grey.shade400 : textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '($count)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: count > 0 ? (isSelected ? primaryColor : textSecondary) : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // 5. PURPOSE PANE
  Widget _buildPurposePane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final baseSubset = _getSubsetExcluding(FilterCategory.purpose);

    final Set<String> allPurposes = {};
    for (final t in widget.allTransactions) {
      if (t.purpose.trim().isNotEmpty) allPurposes.add(t.purpose.trim());
    }

    final Map<String, int> counts = {};
    for (final p in allPurposes) {
      counts[p] = baseSubset.where((t) => t.purpose.trim().toLowerCase() == p.toLowerCase()).length;
    }

    var list = allPurposes.toList()
      ..sort((a, b) {
        final aSel = _criteria.selectedPurposes.contains(a);
        final bSel = _criteria.selectedPurposes.contains(b);
        if (aSel && !bSel) return -1;
        if (!aSel && bSel) return 1;
        final cA = counts[a] ?? 0;
        final cB = counts[b] ?? 0;
        if (cA != cB) return cB.compareTo(cA);
        return a.compareTo(b);
      });

    final query = _purposeSearchCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((item) => item.toLowerCase().contains(query)).toList();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Purpose', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary)),
                  if (_criteria.selectedPurposes.isNotEmpty)
                    InkWell(
                      onTap: () => setState(() => _criteria.selectedPurposes.clear()),
                      child: Text('Reset', style: TextStyle(fontSize: 11.5, color: primaryColor, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              if (allPurposes.length > 5) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _purposeSearchCtrl,
                  style: TextStyle(fontSize: 12.5, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search purpose...',
                    hintStyle: TextStyle(fontSize: 11.5, color: textSecondary),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            itemCount: list.length,
            itemBuilder: (ctx, idx) {
              final item = list[idx];
              final isSelected = _criteria.selectedPurposes.contains(item);
              final count = counts[item] ?? 0;
              final isZero = count == 0;

              return InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (isSelected) {
                      _criteria.selectedPurposes.remove(item);
                    } else {
                      _criteria.selectedPurposes.add(item);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 18,
                        color: isSelected ? primaryColor : textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isZero && !isSelected ? Colors.grey.shade400 : textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '($count)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: count > 0 ? (isSelected ? primaryColor : textSecondary) : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // 6. PAYMENT TYPE PANE
  Widget _buildPaymentTypePane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final baseSubset = _getSubsetExcluding(FilterCategory.paymentType);

    final Set<String> allPaymentTypes = {};
    for (final t in widget.allTransactions) {
      for (final b in t.breakdowns) {
        if (b.paymentType != null && b.paymentType!.trim().isNotEmpty) {
          allPaymentTypes.add(b.paymentType!.trim());
        }
      }
      for (final b in t.toBreakdowns ?? []) {
        if (b.paymentType != null && b.paymentType!.trim().isNotEmpty) {
          allPaymentTypes.add(b.paymentType!.trim());
        }
      }
    }

    final Map<String, int> counts = {};
    for (final pt in allPaymentTypes) {
      counts[pt] = baseSubset.where((t) {
        return t.breakdowns.any((b) => b.paymentType?.toLowerCase() == pt.toLowerCase()) ||
            (t.toBreakdowns ?? []).any((b) => b.paymentType?.toLowerCase() == pt.toLowerCase());
      }).length;
    }

    final list = allPaymentTypes.toList()
      ..sort((a, b) {
        final aSel = _criteria.selectedPaymentTypes.contains(a);
        final bSel = _criteria.selectedPaymentTypes.contains(b);
        if (aSel && !bSel) return -1;
        if (!aSel && bSel) return 1;
        final cA = counts[a] ?? 0;
        final cB = counts[b] ?? 0;
        if (cA != cB) return cB.compareTo(cA);
        return a.compareTo(b);
      });

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Payment Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary)),
            if (_criteria.selectedPaymentTypes.isNotEmpty)
              InkWell(
                onTap: () => setState(() => _criteria.selectedPaymentTypes.clear()),
                child: Text('Reset', style: TextStyle(fontSize: 11.5, color: primaryColor, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ...list.map((pt) {
          final isSelected = _criteria.selectedPaymentTypes.contains(pt);
          final count = counts[pt] ?? 0;
          final isZero = count == 0;

          return InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (isSelected) {
                  _criteria.selectedPaymentTypes.remove(pt);
                } else {
                  _criteria.selectedPaymentTypes.add(pt);
                }
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 18,
                    color: isSelected ? primaryColor : textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.credit_card_outlined, size: 15, color: isSelected ? primaryColor : textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pt,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isZero && !isSelected ? Colors.grey.shade400 : textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '($count)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: count > 0 ? (isSelected ? primaryColor : textSecondary) : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // 7. ACCOUNT PANE
  Widget _buildAccountPane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final baseSubset = _getSubsetExcluding(FilterCategory.account);

    final Set<String> allAccounts = {};
    for (final t in widget.allTransactions) {
      if (t.fromSummary.trim().isNotEmpty && t.fromSummary != 'None') allAccounts.add(t.fromSummary.trim());
      if (t.toSummary.trim().isNotEmpty && t.toSummary != 'None') allAccounts.add(t.toSummary.trim());
      for (final b in t.breakdowns) {
        if (b.effectiveAccount.trim().isNotEmpty && b.effectiveAccount != 'None') {
          allAccounts.add(b.effectiveAccount.trim());
        }
      }
      for (final b in t.toBreakdowns ?? []) {
        if (b.effectiveAccount.trim().isNotEmpty && b.effectiveAccount != 'None') {
          allAccounts.add(b.effectiveAccount.trim());
        }
      }
    }

    final Map<String, int> counts = {};
    for (final acc in allAccounts) {
      counts[acc] = baseSubset.where((t) {
        final aLower = acc.toLowerCase();
        final matchFrom = t.fromSummary.toLowerCase() == aLower;
        final matchTo = t.toSummary.toLowerCase() == aLower;
        final matchB = t.breakdowns.any((b) => b.effectiveAccount.toLowerCase() == aLower || b.account?.toLowerCase() == aLower);
        final matchToB = (t.toBreakdowns ?? []).any((b) => b.effectiveAccount.toLowerCase() == aLower || b.account?.toLowerCase() == aLower);
        return matchFrom || matchTo || matchB || matchToB;
      }).length;
    }

    var list = allAccounts.toList()
      ..sort((a, b) {
        final aSel = _criteria.selectedAccounts.contains(a);
        final bSel = _criteria.selectedAccounts.contains(b);
        if (aSel && !bSel) return -1;
        if (!aSel && bSel) return 1;
        final cA = counts[a] ?? 0;
        final cB = counts[b] ?? 0;
        if (cA != cB) return cB.compareTo(cA);
        return a.compareTo(b);
      });

    final query = _accountSearchCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((item) => item.toLowerCase().contains(query)).toList();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Card / Account', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary)),
                  if (_criteria.selectedAccounts.isNotEmpty)
                    InkWell(
                      onTap: () => setState(() => _criteria.selectedAccounts.clear()),
                      child: Text('Reset', style: TextStyle(fontSize: 11.5, color: primaryColor, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              if (allAccounts.length > 5) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _accountSearchCtrl,
                  style: TextStyle(fontSize: 12.5, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search card/account...',
                    hintStyle: TextStyle(fontSize: 11.5, color: textSecondary),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            itemCount: list.length,
            itemBuilder: (ctx, idx) {
              final item = list[idx];
              final isSelected = _criteria.selectedAccounts.contains(item);
              final count = counts[item] ?? 0;
              final isZero = count == 0;

              return InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (isSelected) {
                      _criteria.selectedAccounts.remove(item);
                    } else {
                      _criteria.selectedAccounts.add(item);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 18,
                        color: isSelected ? primaryColor : textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isZero && !isSelected ? Colors.grey.shade400 : textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '($count)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: count > 0 ? (isSelected ? primaryColor : textSecondary) : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // 8. AMOUNTS PANE (All Available Amounts as Checkboxes)
  Widget _buildAmountsPane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final baseSubset = _getSubsetExcluding(FilterCategory.amounts);

    // Extract all distinct amounts with faceted frequency counts
    final Map<double, int> amountCounts = {};
    for (final t in baseSubset) {
      amountCounts[t.totalAmount] = (amountCounts[t.totalAmount] ?? 0) + 1;
    }

    final sortedAmounts = amountCounts.entries.toList()
      ..sort((a, b) {
        final aSel = _criteria.selectedAmounts.contains(a.key);
        final bSel = _criteria.selectedAmounts.contains(b.key);
        if (aSel && !bSel) return -1;
        if (!aSel && bSel) return 1;
        return b.key.compareTo(a.key); // Higher amounts first
      });

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Available Amounts (${sortedAmounts.length})',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
            ),
            if (_criteria.selectedAmounts.isNotEmpty)
              InkWell(
                onTap: () {
                  setState(() => _criteria.selectedAmounts.clear());
                },
                child: Text('Reset', style: TextStyle(fontSize: 11.5, color: primaryColor, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (sortedAmounts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No amounts available for current filters',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
            ),
          )
        else
          ...sortedAmounts.map((entry) {
            final amt = entry.key;
            final count = entry.value;
            final isSelected = _criteria.selectedAmounts.contains(amt);

            return InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  if (isSelected) {
                    _criteria.selectedAmounts.remove(amt);
                  } else {
                    _criteria.selectedAmounts.add(amt);
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? primaryColor.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? primaryColor : borderColor.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18,
                      color: isSelected ? primaryColor : textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '₹${IndianCurrency.formatSmart(amt)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isSelected ? primaryColor : textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '($count)',
                      style: TextStyle(
                        fontSize: 11,
                        color: count > 0 ? (isSelected ? primaryColor : textSecondary) : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
