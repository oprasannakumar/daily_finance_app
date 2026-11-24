import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../utils/currency_formatter.dart';
import 'swipeable_date_picker.dart';

enum BorrowerFilterCategory {
  date('Date', Icons.calendar_today_outlined),
  borrower('Borrower', Icons.people_outline),
  narration('Narration', Icons.edit_note_outlined),
  invoice('Invoice', Icons.receipt_long_outlined),
  paymentType('Payment Type', Icons.payment_outlined),
  account('Account', Icons.account_balance_outlined),
  givenAmount('Given Amount', Icons.arrow_upward_rounded),
  receivedAmount('Recieved Amount', Icons.arrow_downward_rounded),
  referenceId('Reference ID', Icons.tag_rounded);

  final String label;
  final IconData icon;
  const BorrowerFilterCategory(this.label, this.icon);
}

class BorrowerFilterCriteria {
  Set<String> selectedBorrowers;
  Set<String> selectedNarrations;
  Set<String> selectedInvoices;
  Set<String> selectedPaymentTypes;
  Set<String> selectedAccounts;
  Set<double> selectedGivenAmounts;
  Set<double> selectedReceivedAmounts;
  Set<String> selectedReferenceIds;

  String datePreset; // All Time, Today, Yesterday, This Week, This Month, Custom
  DateTime? startDate;
  DateTime? endDate;

  String borrowerQuery;
  String narrationQuery;
  String invoiceQuery;
  String accountQuery;
  String referenceIdQuery;

  BorrowerFilterCriteria({
    Set<String>? selectedBorrowers,
    Set<String>? selectedNarrations,
    Set<String>? selectedInvoices,
    Set<String>? selectedPaymentTypes,
    Set<String>? selectedAccounts,
    Set<double>? selectedGivenAmounts,
    Set<double>? selectedReceivedAmounts,
    Set<String>? selectedReferenceIds,
    this.datePreset = 'All Time',
    this.startDate,
    this.endDate,
    this.borrowerQuery = '',
    this.narrationQuery = '',
    this.invoiceQuery = '',
    this.accountQuery = '',
    this.referenceIdQuery = '',
  })  : selectedBorrowers = selectedBorrowers != null ? Set<String>.from(selectedBorrowers) : {},
        selectedNarrations = selectedNarrations != null ? Set<String>.from(selectedNarrations) : {},
        selectedInvoices = selectedInvoices != null ? Set<String>.from(selectedInvoices) : {},
        selectedPaymentTypes = selectedPaymentTypes != null ? Set<String>.from(selectedPaymentTypes) : {},
        selectedAccounts = selectedAccounts != null ? Set<String>.from(selectedAccounts) : {},
        selectedGivenAmounts = selectedGivenAmounts != null ? Set<double>.from(selectedGivenAmounts) : {},
        selectedReceivedAmounts = selectedReceivedAmounts != null ? Set<double>.from(selectedReceivedAmounts) : {},
        selectedReferenceIds = selectedReferenceIds != null ? Set<String>.from(selectedReferenceIds) : {};

  BorrowerFilterCriteria copy() {
    return BorrowerFilterCriteria(
      selectedBorrowers: Set<String>.from(selectedBorrowers),
      selectedNarrations: Set<String>.from(selectedNarrations),
      selectedInvoices: Set<String>.from(selectedInvoices),
      selectedPaymentTypes: Set<String>.from(selectedPaymentTypes),
      selectedAccounts: Set<String>.from(selectedAccounts),
      selectedGivenAmounts: Set<double>.from(selectedGivenAmounts),
      selectedReceivedAmounts: Set<double>.from(selectedReceivedAmounts),
      selectedReferenceIds: Set<String>.from(selectedReferenceIds),
      datePreset: datePreset,
      startDate: startDate,
      endDate: endDate,
      borrowerQuery: borrowerQuery,
      narrationQuery: narrationQuery,
      invoiceQuery: invoiceQuery,
      accountQuery: accountQuery,
      referenceIdQuery: referenceIdQuery,
    );
  }

  int get activeFilterCount {
    int count = 0;
    if (startDate != null || (datePreset != 'All Time' && datePreset.isNotEmpty)) count++;
    if (selectedBorrowers.isNotEmpty || borrowerQuery.trim().isNotEmpty) count++;
    if (selectedNarrations.isNotEmpty || narrationQuery.trim().isNotEmpty) count++;
    if (selectedInvoices.isNotEmpty || invoiceQuery.trim().isNotEmpty) count++;
    if (selectedPaymentTypes.isNotEmpty) count++;
    if (selectedAccounts.isNotEmpty || accountQuery.trim().isNotEmpty) count++;
    if (selectedGivenAmounts.isNotEmpty) count++;
    if (selectedReceivedAmounts.isNotEmpty) count++;
    if (selectedReferenceIds.isNotEmpty || referenceIdQuery.trim().isNotEmpty) count++;
    return count;
  }

  bool get isEmpty => activeFilterCount == 0;

  void clear() {
    selectedBorrowers.clear();
    selectedNarrations.clear();
    selectedInvoices.clear();
    selectedPaymentTypes.clear();
    selectedAccounts.clear();
    selectedGivenAmounts.clear();
    selectedReceivedAmounts.clear();
    selectedReferenceIds.clear();
    datePreset = 'All Time';
    startDate = null;
    endDate = null;
    borrowerQuery = '';
    narrationQuery = '';
    invoiceQuery = '';
    accountQuery = '';
    referenceIdQuery = '';
  }

  bool matches(LoanEntry entry) {
    // 1. Date
    if (startDate != null) {
      final startBound = DateTime(startDate!.year, startDate!.month, startDate!.day, 0, 0, 0);
      final endBound = endDate != null
          ? DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59)
          : DateTime(startDate!.year, startDate!.month, startDate!.day, 23, 59, 59);
      final entryDate = sanitizeDateYear(entry.date);
      if (entryDate.isBefore(startBound) || entryDate.isAfter(endBound)) {
        return false;
      }
    }

    // 2. Borrower
    if (selectedBorrowers.isNotEmpty && !selectedBorrowers.contains(entry.borrower)) {
      return false;
    }
    if (borrowerQuery.trim().isNotEmpty &&
        !entry.borrower.toLowerCase().contains(borrowerQuery.trim().toLowerCase())) {
      return false;
    }

    // 3. Narration
    if (selectedNarrations.isNotEmpty && !selectedNarrations.contains(entry.narration)) {
      return false;
    }
    if (narrationQuery.trim().isNotEmpty &&
        !entry.narration.toLowerCase().contains(narrationQuery.trim().toLowerCase())) {
      return false;
    }

    // 4. Invoice
    if (selectedInvoices.isNotEmpty && !selectedInvoices.contains(entry.invoice)) {
      return false;
    }
    if (invoiceQuery.trim().isNotEmpty &&
        !entry.invoice.toLowerCase().contains(invoiceQuery.trim().toLowerCase())) {
      return false;
    }

    // 5. Payment Type
    if (selectedPaymentTypes.isNotEmpty && !selectedPaymentTypes.contains(entry.transactionType)) {
      return false;
    }

    // 6. Account
    if (selectedAccounts.isNotEmpty && !selectedAccounts.contains(entry.account)) {
      return false;
    }
    if (accountQuery.trim().isNotEmpty &&
        !entry.account.toLowerCase().contains(accountQuery.trim().toLowerCase())) {
      return false;
    }

    // 7. Given Amount
    if (selectedGivenAmounts.isNotEmpty && !selectedGivenAmounts.contains(entry.givenAmount)) {
      return false;
    }

    // 8. Received Amount
    if (selectedReceivedAmounts.isNotEmpty && !selectedReceivedAmounts.contains(entry.receivedAmount)) {
      return false;
    }

    // 9. Reference ID
    if (selectedReferenceIds.isNotEmpty && !selectedReferenceIds.contains(entry.referenceId)) {
      return false;
    }
    if (referenceIdQuery.trim().isNotEmpty &&
        !entry.referenceId.toLowerCase().contains(referenceIdQuery.trim().toLowerCase())) {
      return false;
    }

    return true;
  }
}

class BorrowerFacetedFilterSheet extends StatefulWidget {
  final List<LoanEntry> allEntries;
  final BorrowerFilterCriteria initialCriteria;

  const BorrowerFacetedFilterSheet({
    super.key,
    required this.allEntries,
    required this.initialCriteria,
  });

  static Future<BorrowerFilterCriteria?> show({
    required BuildContext context,
    required List<LoanEntry> allEntries,
    required BorrowerFilterCriteria initialCriteria,
  }) {
    return showModalBottomSheet<BorrowerFilterCriteria>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BorrowerFacetedFilterSheet(
        allEntries: allEntries,
        initialCriteria: initialCriteria,
      ),
    );
  }

  @override
  State<BorrowerFacetedFilterSheet> createState() => _BorrowerFacetedFilterSheetState();
}

class _BorrowerFacetedFilterSheetState extends State<BorrowerFacetedFilterSheet> {
  late BorrowerFilterCriteria _criteria;
  BorrowerFilterCategory _selectedCategory = BorrowerFilterCategory.date;

  final TextEditingController _borrowerSearchCtrl = TextEditingController();
  final TextEditingController _narrationSearchCtrl = TextEditingController();
  final TextEditingController _invoiceSearchCtrl = TextEditingController();
  final TextEditingController _accountSearchCtrl = TextEditingController();
  final TextEditingController _referenceIdSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _criteria = widget.initialCriteria.copy();
    _borrowerSearchCtrl.text = _criteria.borrowerQuery;
    _narrationSearchCtrl.text = _criteria.narrationQuery;
    _invoiceSearchCtrl.text = _criteria.invoiceQuery;
    _accountSearchCtrl.text = _criteria.accountQuery;
    _referenceIdSearchCtrl.text = _criteria.referenceIdQuery;
  }

  @override
  void dispose() {
    _borrowerSearchCtrl.dispose();
    _narrationSearchCtrl.dispose();
    _invoiceSearchCtrl.dispose();
    _accountSearchCtrl.dispose();
    _referenceIdSearchCtrl.dispose();
    super.dispose();
  }

  List<LoanEntry> _getSubsetExcluding(BorrowerFilterCategory excluded) {
    return widget.allEntries.where((e) {
      if (excluded != BorrowerFilterCategory.date) {
        if (_criteria.startDate != null) {
          final startBound = DateTime(_criteria.startDate!.year, _criteria.startDate!.month, _criteria.startDate!.day, 0, 0, 0);
          final endBound = _criteria.endDate != null
              ? DateTime(_criteria.endDate!.year, _criteria.endDate!.month, _criteria.endDate!.day, 23, 59, 59)
              : DateTime(_criteria.startDate!.year, _criteria.startDate!.month, _criteria.startDate!.day, 23, 59, 59);
          final entryDate = sanitizeDateYear(e.date);
          if (entryDate.isBefore(startBound) || entryDate.isAfter(endBound)) return false;
        }
      }
      if (excluded != BorrowerFilterCategory.borrower) {
        if (_criteria.selectedBorrowers.isNotEmpty && !_criteria.selectedBorrowers.contains(e.borrower)) {
          return false;
        }
        if (_criteria.borrowerQuery.trim().isNotEmpty &&
            !e.borrower.toLowerCase().contains(_criteria.borrowerQuery.trim().toLowerCase())) {
          return false;
        }
      }
      if (excluded != BorrowerFilterCategory.narration) {
        if (_criteria.selectedNarrations.isNotEmpty && !_criteria.selectedNarrations.contains(e.narration)) {
          return false;
        }
        if (_criteria.narrationQuery.trim().isNotEmpty &&
            !e.narration.toLowerCase().contains(_criteria.narrationQuery.trim().toLowerCase())) {
          return false;
        }
      }
      if (excluded != BorrowerFilterCategory.invoice) {
        if (_criteria.selectedInvoices.isNotEmpty && !_criteria.selectedInvoices.contains(e.invoice)) {
          return false;
        }
        if (_criteria.invoiceQuery.trim().isNotEmpty &&
            !e.invoice.toLowerCase().contains(_criteria.invoiceQuery.trim().toLowerCase())) {
          return false;
        }
      }
      if (excluded != BorrowerFilterCategory.paymentType) {
        if (_criteria.selectedPaymentTypes.isNotEmpty && !_criteria.selectedPaymentTypes.contains(e.transactionType)) {
          return false;
        }
      }
      if (excluded != BorrowerFilterCategory.account) {
        if (_criteria.selectedAccounts.isNotEmpty && !_criteria.selectedAccounts.contains(e.account)) {
          return false;
        }
        if (_criteria.accountQuery.trim().isNotEmpty &&
            !e.account.toLowerCase().contains(_criteria.accountQuery.trim().toLowerCase())) {
          return false;
        }
      }
      if (excluded != BorrowerFilterCategory.givenAmount) {
        if (_criteria.selectedGivenAmounts.isNotEmpty && !_criteria.selectedGivenAmounts.contains(e.givenAmount)) {
          return false;
        }
      }
      if (excluded != BorrowerFilterCategory.receivedAmount) {
        if (_criteria.selectedReceivedAmounts.isNotEmpty && !_criteria.selectedReceivedAmounts.contains(e.receivedAmount)) {
          return false;
        }
      }
      if (excluded != BorrowerFilterCategory.referenceId) {
        if (_criteria.selectedReferenceIds.isNotEmpty && !_criteria.selectedReferenceIds.contains(e.referenceId)) {
          return false;
        }
        if (_criteria.referenceIdQuery.trim().isNotEmpty &&
            !e.referenceId.toLowerCase().contains(_criteria.referenceIdQuery.trim().toLowerCase())) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  String _getCategoryBadge(BorrowerFilterCategory category) {
    switch (category) {
      case BorrowerFilterCategory.date:
        return (_criteria.startDate != null || (_criteria.datePreset != 'All Time' && _criteria.datePreset.isNotEmpty)) ? '1' : '';
      case BorrowerFilterCategory.borrower:
        final count = _criteria.selectedBorrowers.length + (_criteria.borrowerQuery.trim().isNotEmpty ? 1 : 0);
        return count > 0 ? '$count' : '';
      case BorrowerFilterCategory.narration:
        final count = _criteria.selectedNarrations.length + (_criteria.narrationQuery.trim().isNotEmpty ? 1 : 0);
        return count > 0 ? '$count' : '';
      case BorrowerFilterCategory.invoice:
        final count = _criteria.selectedInvoices.length + (_criteria.invoiceQuery.trim().isNotEmpty ? 1 : 0);
        return count > 0 ? '$count' : '';
      case BorrowerFilterCategory.paymentType:
        return _criteria.selectedPaymentTypes.isNotEmpty ? '${_criteria.selectedPaymentTypes.length}' : '';
      case BorrowerFilterCategory.account:
        final count = _criteria.selectedAccounts.length + (_criteria.accountQuery.trim().isNotEmpty ? 1 : 0);
        return count > 0 ? '$count' : '';
      case BorrowerFilterCategory.givenAmount:
        return _criteria.selectedGivenAmounts.isNotEmpty ? '${_criteria.selectedGivenAmounts.length}' : '';
      case BorrowerFilterCategory.receivedAmount:
        return _criteria.selectedReceivedAmounts.isNotEmpty ? '${_criteria.selectedReceivedAmounts.length}' : '';
      case BorrowerFilterCategory.referenceId:
        final count = _criteria.selectedReferenceIds.length + (_criteria.referenceIdQuery.trim().isNotEmpty ? 1 : 0);
        return count > 0 ? '$count' : '';
    }
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

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final pickedRange = await SwipeableDateRangePickerDialog.show(
      context: context,
      initialStartDate: _criteria.startDate ?? now,
      initialEndDate: _criteria.endDate ?? now,
      currentPreset: _criteria.datePreset,
    );

    if (pickedRange != null && mounted) {
      if (pickedRange.isAllTime) {
        _setDatePreset('All Time');
      } else if (pickedRange.presetName != 'Custom') {
        _setDatePreset(pickedRange.presetName);
      } else {
        setState(() {
          _criteria.startDate = pickedRange.start;
          _criteria.endDate = pickedRange.end;
          _criteria.datePreset = 'Custom';
        });
      }
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
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);

    final totalMatching = widget.allEntries.where((e) => _criteria.matches(e)).length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 1. Top Header Bar (Matching FacetedFilterSheet exactly)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: borderColor,
                    borderRadius: BorderRadius.circular(2),
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
                            _borrowerSearchCtrl.clear();
                            _narrationSearchCtrl.clear();
                            _invoiceSearchCtrl.clear();
                            _accountSearchCtrl.clear();
                            _referenceIdSearchCtrl.clear();
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
                    itemCount: BorrowerFilterCategory.values.length,
                    itemBuilder: (ctx, index) {
                      final cat = BorrowerFilterCategory.values[index];
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
                        _borrowerSearchCtrl.clear();
                        _narrationSearchCtrl.clear();
                        _invoiceSearchCtrl.clear();
                        _accountSearchCtrl.clear();
                        _referenceIdSearchCtrl.clear();
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

  Widget _buildRightPaneContent(
    BuildContext context, {
    required BorrowerFilterCategory category,
    required Color textPrimary,
    required Color textSecondary,
    required Color primaryColor,
    required Color borderColor,
  }) {
    switch (category) {
      case BorrowerFilterCategory.date:
        return _buildDatePane(context, textPrimary, textSecondary, primaryColor, borderColor);
      case BorrowerFilterCategory.borrower:
        return _buildBorrowerPane(context, textPrimary, textSecondary, primaryColor, borderColor);
      case BorrowerFilterCategory.narration:
        return _buildNarrationPane(context, textPrimary, textSecondary, primaryColor, borderColor);
      case BorrowerFilterCategory.invoice:
        return _buildInvoicePane(context, textPrimary, textSecondary, primaryColor, borderColor);
      case BorrowerFilterCategory.paymentType:
        return _buildPaymentTypePane(context, textPrimary, textSecondary, primaryColor, borderColor);
      case BorrowerFilterCategory.account:
        return _buildAccountPane(context, textPrimary, textSecondary, primaryColor, borderColor);
      case BorrowerFilterCategory.givenAmount:
        return _buildGivenAmountPane(context, textPrimary, textSecondary, primaryColor, borderColor);
      case BorrowerFilterCategory.receivedAmount:
        return _buildReceivedAmountPane(context, textPrimary, textSecondary, primaryColor, borderColor);
      case BorrowerFilterCategory.referenceId:
        return _buildReferenceIdPane(context, textPrimary, textSecondary, primaryColor, borderColor);
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
    final baseSubset = _getSubsetExcluding(BorrowerFilterCategory.date);

    final Map<String, int> presetCounts = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final p in presets) {
      if (p == 'All Time') {
        presetCounts[p] = baseSubset.length;
      } else if (p == 'Today') {
        presetCounts[p] = baseSubset.where((e) {
          final d = sanitizeDateYear(e.date);
          return d.year == today.year && d.month == today.month && d.day == today.day;
        }).length;
      } else if (p == 'Yesterday') {
        final yest = today.subtract(const Duration(days: 1));
        presetCounts[p] = baseSubset.where((e) {
          final d = sanitizeDateYear(e.date);
          return d.year == yest.year && d.month == yest.month && d.day == yest.day;
        }).length;
      } else if (p == 'This Week') {
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        presetCounts[p] = baseSubset.where((e) {
          final d = sanitizeDateYear(e.date);
          return !d.isBefore(weekStart) && !d.isAfter(DateTime(today.year, today.month, today.day, 23, 59, 59));
        }).length;
      } else if (p == 'This Month') {
        final monthStart = DateTime(today.year, today.month, 1);
        presetCounts[p] = baseSubset.where((e) {
          final d = sanitizeDateYear(e.date);
          return !d.isBefore(monthStart) && !d.isAfter(DateTime(today.year, today.month, today.day, 23, 59, 59));
        }).length;
      } else {
        presetCounts[p] = baseSubset.length;
      }
    }

    final fmt = DateFormat('dd MMM yyyy');
    String rangeLabel = 'All Dates';
    if (_criteria.startDate != null) {
      if (_criteria.endDate != null &&
          _criteria.startDate!.year == _criteria.endDate!.year &&
          _criteria.startDate!.month == _criteria.endDate!.month &&
          _criteria.startDate!.day == _criteria.endDate!.day) {
        rangeLabel = fmt.format(_criteria.startDate!);
      } else if (_criteria.endDate != null) {
        rangeLabel = '${fmt.format(_criteria.startDate!)} - ${fmt.format(_criteria.endDate!)}';
      } else {
        rangeLabel = 'From ${fmt.format(_criteria.startDate!)}';
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Text(
          'Date Presets',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Active: $rangeLabel',
          style: TextStyle(fontSize: 11.5, color: primaryColor, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        ...presets.map((preset) {
          final isSelected = _criteria.datePreset == preset;
          final count = presetCounts[preset] ?? 0;

          return InkWell(
            onTap: () {
              if (preset == 'Custom') {
                _pickCustomDateRange();
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

  // 2. BORROWER PANE
  Widget _buildBorrowerPane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final baseSubset = _getSubsetExcluding(BorrowerFilterCategory.borrower);

    final Map<String, int> borrowerCounts = {};
    for (final e in baseSubset) {
      if (e.borrower.trim().isNotEmpty) {
        borrowerCounts[e.borrower] = (borrowerCounts[e.borrower] ?? 0) + 1;
      }
    }

    final query = _criteria.borrowerQuery.trim().toLowerCase();
    final sortedBorrowers = borrowerCounts.entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.key.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) {
        final aSel = _criteria.selectedBorrowers.contains(a.key);
        final bSel = _criteria.selectedBorrowers.contains(b.key);
        if (aSel && !bSel) return -1;
        if (!aSel && bSel) return 1;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Text(
          'Borrower Search',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _borrowerSearchCtrl,
          style: TextStyle(fontSize: 13, color: textPrimary),
          decoration: InputDecoration(
            hintText: 'Search borrower...',
            hintStyle: TextStyle(fontSize: 12, color: textSecondary),
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _borrowerSearchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _borrowerSearchCtrl.clear();
                      setState(() => _criteria.borrowerQuery = '');
                    },
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (val) => setState(() => _criteria.borrowerQuery = val),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Borrowers (${sortedBorrowers.length})',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textSecondary),
            ),
            if (_criteria.selectedBorrowers.isNotEmpty)
              InkWell(
                onTap: () => setState(() => _criteria.selectedBorrowers.clear()),
                child: Text(
                  'Reset',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (sortedBorrowers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Center(
              child: Text(
                'No borrowers found',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
            ),
          )
        else
          ...sortedBorrowers.map((entry) {
            final b = entry.key;
            final count = entry.value;
            final isSelected = _criteria.selectedBorrowers.contains(b);

            return InkWell(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _criteria.selectedBorrowers.remove(b);
                  } else {
                    _criteria.selectedBorrowers.add(b);
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
                        b,
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
                      '($count)',
                      style: TextStyle(fontSize: 11.5, color: textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // 3. NARRATION PANE
  Widget _buildNarrationPane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final baseSubset = _getSubsetExcluding(BorrowerFilterCategory.narration);

    final Map<String, int> narrCounts = {};
    for (final e in baseSubset) {
      if (e.narration.trim().isNotEmpty) {
        narrCounts[e.narration] = (narrCounts[e.narration] ?? 0) + 1;
      }
    }

    final query = _criteria.narrationQuery.trim().toLowerCase();
    final sortedNarrations = narrCounts.entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.key.toLowerCase().contains(query);
    }).toList()
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
          controller: _narrationSearchCtrl,
          style: TextStyle(fontSize: 13, color: textPrimary),
          decoration: InputDecoration(
            hintText: 'Keyword in narration...',
            hintStyle: TextStyle(fontSize: 12, color: textSecondary),
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _narrationSearchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _narrationSearchCtrl.clear();
                      setState(() => _criteria.narrationQuery = '');
                    },
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (val) => setState(() => _criteria.narrationQuery = val),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Narrations (${sortedNarrations.length})',
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
        if (sortedNarrations.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Center(
              child: Text(
                'No narrations found',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
            ),
          )
        else
          ...sortedNarrations.map((entry) {
            final n = entry.key;
            final count = entry.value;
            final isSelected = _criteria.selectedNarrations.contains(n);

            return InkWell(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _criteria.selectedNarrations.remove(n);
                  } else {
                    _criteria.selectedNarrations.add(n);
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
                        n,
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
                      '($count)',
                      style: TextStyle(fontSize: 11.5, color: textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // 4. INVOICE PANE
  Widget _buildInvoicePane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final baseSubset = _getSubsetExcluding(BorrowerFilterCategory.invoice);

    final Map<String, int> invCounts = {};
    for (final e in baseSubset) {
      if (e.invoice.trim().isNotEmpty) {
        invCounts[e.invoice] = (invCounts[e.invoice] ?? 0) + 1;
      }
    }

    final query = _criteria.invoiceQuery.trim().toLowerCase();
    final sortedInvoices = invCounts.entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.key.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) {
        final aSel = _criteria.selectedInvoices.contains(a.key);
        final bSel = _criteria.selectedInvoices.contains(b.key);
        if (aSel && !bSel) return -1;
        if (!aSel && bSel) return 1;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Text(
          'Invoice Search',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _invoiceSearchCtrl,
          style: TextStyle(fontSize: 13, color: textPrimary),
          decoration: InputDecoration(
            hintText: 'Search invoice...',
            hintStyle: TextStyle(fontSize: 12, color: textSecondary),
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _invoiceSearchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _invoiceSearchCtrl.clear();
                      setState(() => _criteria.invoiceQuery = '');
                    },
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (val) => setState(() => _criteria.invoiceQuery = val),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Invoices (${sortedInvoices.length})',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textSecondary),
            ),
            if (_criteria.selectedInvoices.isNotEmpty)
              InkWell(
                onTap: () => setState(() => _criteria.selectedInvoices.clear()),
                child: Text(
                  'Reset',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (sortedInvoices.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Center(
              child: Text(
                'No invoices found',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
            ),
          )
        else
          ...sortedInvoices.map((entry) {
            final inv = entry.key;
            final count = entry.value;
            final isSelected = _criteria.selectedInvoices.contains(inv);

            return InkWell(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _criteria.selectedInvoices.remove(inv);
                  } else {
                    _criteria.selectedInvoices.add(inv);
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
                        inv,
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
                      '($count)',
                      style: TextStyle(fontSize: 11.5, color: textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // 5. PAYMENT TYPE PANE
  Widget _buildPaymentTypePane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final baseSubset = _getSubsetExcluding(BorrowerFilterCategory.paymentType);

    final Map<String, int> ptCounts = {};
    for (final e in baseSubset) {
      if (e.transactionType.trim().isNotEmpty) {
        ptCounts[e.transactionType] = (ptCounts[e.transactionType] ?? 0) + 1;
      }
    }

    final sortedPTs = ptCounts.entries.toList()
      ..sort((a, b) {
        final aSel = _criteria.selectedPaymentTypes.contains(a.key);
        final bSel = _criteria.selectedPaymentTypes.contains(b.key);
        if (aSel && !bSel) return -1;
        if (!aSel && bSel) return 1;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Payment Types (${sortedPTs.length})',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textSecondary),
            ),
            if (_criteria.selectedPaymentTypes.isNotEmpty)
              InkWell(
                onTap: () => setState(() => _criteria.selectedPaymentTypes.clear()),
                child: Text(
                  'Reset',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (sortedPTs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Center(
              child: Text(
                'No payment types available',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
            ),
          )
        else
          ...sortedPTs.map((entry) {
            final pt = entry.key;
            final count = entry.value;
            final isSelected = _criteria.selectedPaymentTypes.contains(pt);

            return InkWell(
              onTap: () {
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
                        pt,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isSelected ? primaryColor : textPrimary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    Text(
                      '($count)',
                      style: TextStyle(fontSize: 11.5, color: textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // 6. ACCOUNT PANE
  Widget _buildAccountPane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final baseSubset = _getSubsetExcluding(BorrowerFilterCategory.account);

    final Map<String, int> accCounts = {};
    for (final e in baseSubset) {
      if (e.account.trim().isNotEmpty) {
        accCounts[e.account] = (accCounts[e.account] ?? 0) + 1;
      }
    }

    final query = _criteria.accountQuery.trim().toLowerCase();
    final sortedAccounts = accCounts.entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.key.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) {
        final aSel = _criteria.selectedAccounts.contains(a.key);
        final bSel = _criteria.selectedAccounts.contains(b.key);
        if (aSel && !bSel) return -1;
        if (!aSel && bSel) return 1;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Text(
          'Account / Card Search',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _accountSearchCtrl,
          style: TextStyle(fontSize: 13, color: textPrimary),
          decoration: InputDecoration(
            hintText: 'Search account/card...',
            hintStyle: TextStyle(fontSize: 12, color: textSecondary),
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _accountSearchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _accountSearchCtrl.clear();
                      setState(() => _criteria.accountQuery = '');
                    },
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (val) => setState(() => _criteria.accountQuery = val),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Accounts (${sortedAccounts.length})',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textSecondary),
            ),
            if (_criteria.selectedAccounts.isNotEmpty)
              InkWell(
                onTap: () => setState(() => _criteria.selectedAccounts.clear()),
                child: Text(
                  'Reset',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (sortedAccounts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Center(
              child: Text(
                'No accounts found',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
            ),
          )
        else
          ...sortedAccounts.map((entry) {
            final acc = entry.key;
            final count = entry.value;
            final isSelected = _criteria.selectedAccounts.contains(acc);

            return InkWell(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _criteria.selectedAccounts.remove(acc);
                  } else {
                    _criteria.selectedAccounts.add(acc);
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
                        acc,
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
                      '($count)',
                      style: TextStyle(fontSize: 11.5, color: textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // 7. GIVEN AMOUNT PANE (All Available Amounts as Checkboxes)
  Widget _buildGivenAmountPane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final baseSubset = _getSubsetExcluding(BorrowerFilterCategory.givenAmount);

    final Map<double, int> amountCounts = {};
    for (final e in baseSubset) {
      if (e.givenAmount > 0) {
        amountCounts[e.givenAmount] = (amountCounts[e.givenAmount] ?? 0) + 1;
      }
    }

    final sortedAmounts = amountCounts.entries.toList()
      ..sort((a, b) {
        final aSel = _criteria.selectedGivenAmounts.contains(a.key);
        final bSel = _criteria.selectedGivenAmounts.contains(b.key);
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
              'Given Amounts (${sortedAmounts.length})',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textSecondary),
            ),
            if (_criteria.selectedGivenAmounts.isNotEmpty)
              InkWell(
                onTap: () => setState(() => _criteria.selectedGivenAmounts.clear()),
                child: Text(
                  'Reset',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (sortedAmounts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Center(
              child: Text(
                'No given amounts found',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
            ),
          )
        else
          ...sortedAmounts.map((entry) {
            final amt = entry.key;
            final count = entry.value;
            final isSelected = _criteria.selectedGivenAmounts.contains(amt);

            return InkWell(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _criteria.selectedGivenAmounts.remove(amt);
                  } else {
                    _criteria.selectedGivenAmounts.add(amt);
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
                      color: isSelected ? const Color(0xFFF97316) : textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '₹${IndianCurrency.formatSmart(amt)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? const Color(0xFFF97316) : textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '($count)',
                      style: TextStyle(fontSize: 11.5, color: textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // 8. RECEIVED AMOUNT PANE (All Available Amounts as Checkboxes)
  Widget _buildReceivedAmountPane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final baseSubset = _getSubsetExcluding(BorrowerFilterCategory.receivedAmount);

    final Map<double, int> amountCounts = {};
    for (final e in baseSubset) {
      if (e.receivedAmount > 0) {
        amountCounts[e.receivedAmount] = (amountCounts[e.receivedAmount] ?? 0) + 1;
      }
    }

    final sortedAmounts = amountCounts.entries.toList()
      ..sort((a, b) {
        final aSel = _criteria.selectedReceivedAmounts.contains(a.key);
        final bSel = _criteria.selectedReceivedAmounts.contains(b.key);
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
              'Recieved Amounts (${sortedAmounts.length})',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textSecondary),
            ),
            if (_criteria.selectedReceivedAmounts.isNotEmpty)
              InkWell(
                onTap: () => setState(() => _criteria.selectedReceivedAmounts.clear()),
                child: Text(
                  'Reset',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (sortedAmounts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Center(
              child: Text(
                'No recieved amounts found',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
            ),
          )
        else
          ...sortedAmounts.map((entry) {
            final amt = entry.key;
            final count = entry.value;
            final isSelected = _criteria.selectedReceivedAmounts.contains(amt);

            return InkWell(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _criteria.selectedReceivedAmounts.remove(amt);
                  } else {
                    _criteria.selectedReceivedAmounts.add(amt);
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
                      color: isSelected ? const Color(0xFF10B981) : textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '₹${IndianCurrency.formatSmart(amt)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? const Color(0xFF10B981) : textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '($count)',
                      style: TextStyle(fontSize: 11.5, color: textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // 9. REFERENCE ID PANE
  Widget _buildReferenceIdPane(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color primaryColor,
    Color borderColor,
  ) {
    final baseSubset = _getSubsetExcluding(BorrowerFilterCategory.referenceId);

    final Map<String, int> refCounts = {};
    for (final e in baseSubset) {
      if (e.referenceId.trim().isNotEmpty) {
        refCounts[e.referenceId] = (refCounts[e.referenceId] ?? 0) + 1;
      }
    }

    final query = _criteria.referenceIdQuery.trim().toLowerCase();
    final sortedRefs = refCounts.entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.key.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) {
        final aSel = _criteria.selectedReferenceIds.contains(a.key);
        final bSel = _criteria.selectedReferenceIds.contains(b.key);
        if (aSel && !bSel) return -1;
        if (!aSel && bSel) return 1;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Text(
          'Reference ID Search',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _referenceIdSearchCtrl,
          style: TextStyle(fontSize: 13, color: textPrimary),
          decoration: InputDecoration(
            hintText: 'Search reference ID...',
            hintStyle: TextStyle(fontSize: 12, color: textSecondary),
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _referenceIdSearchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _referenceIdSearchCtrl.clear();
                      setState(() => _criteria.referenceIdQuery = '');
                    },
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (val) => setState(() => _criteria.referenceIdQuery = val),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Reference IDs (${sortedRefs.length})',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textSecondary),
            ),
            if (_criteria.selectedReferenceIds.isNotEmpty)
              InkWell(
                onTap: () => setState(() => _criteria.selectedReferenceIds.clear()),
                child: Text(
                  'Reset',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (sortedRefs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Center(
              child: Text(
                'No reference IDs found',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
            ),
          )
        else
          ...sortedRefs.map((entry) {
            final ref = entry.key;
            final count = entry.value;
            final isSelected = _criteria.selectedReferenceIds.contains(ref);

            return InkWell(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _criteria.selectedReferenceIds.remove(ref);
                  } else {
                    _criteria.selectedReferenceIds.add(ref);
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
                        ref,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontFamily: 'monospace',
                          color: isSelected ? primaryColor : textPrimary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '($count)',
                      style: TextStyle(fontSize: 11.5, color: textSecondary),
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
