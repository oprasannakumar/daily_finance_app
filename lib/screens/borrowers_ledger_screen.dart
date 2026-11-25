import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../services/storage_service.dart';
import '../utils/currency_formatter.dart';
import '../widgets/borrower_faceted_filter_sheet.dart';
import '../widgets/transaction_details_dialog.dart';
import '../widgets/borrower_export_dialog.dart';

class BorrowersLedgerScreen extends StatefulWidget {
  final String? initialBorrowerName;

  const BorrowersLedgerScreen({super.key, this.initialBorrowerName});

  @override
  State<BorrowersLedgerScreen> createState() => _BorrowersLedgerScreenState();
}

class _BorrowersLedgerScreenState extends State<BorrowersLedgerScreen> {
  bool _isLoading = true;
  List<LoanEntry> _entries = [];

  // Flipkart & Amazon style Faceted Filter Criteria
  BorrowerFilterCriteria _filterCriteria = BorrowerFilterCriteria();

  // Quick Type Filter (All, Given, Received)
  String _quickType = 'All';

  // Search Query
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialBorrowerName?.trim();
    if (initial != null && initial.isNotEmpty) {
      _searchQuery = initial;
      _searchCtrl.text = initial;
    }
    final warm = StorageService.instance.cachedLoanEntriesSync;
    if (warm != null && warm.isNotEmpty) {
      _entries = warm;
      _isLoading = false;
    }
    StorageService.instance.loansNotifier.addListener(_onLoansChanged);
    StorageService.instance.transactionsNotifier.addListener(_onLoansChanged);
    _loadEntries();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    StorageService.instance.loansNotifier.removeListener(_onLoansChanged);
    StorageService.instance.transactionsNotifier.removeListener(_onLoansChanged);
    super.dispose();
  }

  void _onLoansChanged() {
    _loadEntries();
  }

  Future<void> _loadEntries({bool forceRefresh = false}) async {
    final list = await StorageService.instance.getLoanEntries(forceRefresh: forceRefresh);
    if (mounted) {
      setState(() {
        _entries = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _openBorrowerFilters() async {
    HapticFeedback.lightImpact();
    final result = await BorrowerFacetedFilterSheet.show(
      context: context,
      allEntries: _entries,
      initialCriteria: _filterCriteria,
    );

    if (result != null && mounted) {
      setState(() {
        _filterCriteria = result;
      });
    }
  }

  String get _dateRangeDisplayString {
    final fmt = DateFormat('d MMM');
    if (_filterCriteria.startDate == null && _filterCriteria.endDate == null) {
      if (_filterCriteria.datePreset.isNotEmpty && _filterCriteria.datePreset != 'All Time') {
        return _filterCriteria.datePreset;
      }
      return 'All Dates';
    } else if (_filterCriteria.startDate != null && _filterCriteria.endDate != null &&
        _filterCriteria.startDate!.year == _filterCriteria.endDate!.year &&
        _filterCriteria.startDate!.month == _filterCriteria.endDate!.month &&
        _filterCriteria.startDate!.day == _filterCriteria.endDate!.day) {
      return fmt.format(_filterCriteria.startDate!);
    } else if (_filterCriteria.startDate != null && _filterCriteria.endDate != null) {
      return '${fmt.format(_filterCriteria.startDate!)} - ${fmt.format(_filterCriteria.endDate!)}';
    } else if (_filterCriteria.startDate != null) {
      return 'From ${fmt.format(_filterCriteria.startDate!)}';
    } else {
      return 'All Dates';
    }
  }

  void _resetAllFilters() {
    HapticFeedback.lightImpact();
    setState(() {
      _filterCriteria.clear();
      _quickType = 'All';
      _searchQuery = '';
      _searchCtrl.clear();
    });
  }

  Widget _buildActiveChip(String label, VoidCallback onDeleted) {
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: InkWell(
        onTap: onDeleted,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0F766E).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = const Color(0xFF0F766E);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    // Filter entries using faceted filter criteria + quick filters
    final filtered = _entries.where((e) {
      if (!_filterCriteria.matches(e)) {
        return false;
      }
      if (_quickType == 'Given' && !e.isGiven) {
        return false;
      }
      if (_quickType == 'Received' && e.isGiven) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchBorrower = e.borrower.toLowerCase().contains(q);
        final matchNarr = e.narration.toLowerCase().contains(q);
        final matchAcc = e.account.toLowerCase().contains(q);
        final matchRef = e.referenceId.toLowerCase().contains(q);
        final matchInv = e.invoice.toLowerCase().contains(q);
        if (!(matchBorrower || matchNarr || matchAcc || matchRef || matchInv)) {
          return false;
        }
      }
      return true;
    }).toList();

    // Summary calculations on filtered
    double totalGiven = 0.0;
    double totalReceived = 0.0;
    for (final e in filtered) {
      totalGiven += e.givenAmount;
      totalReceived += e.receivedAmount;
    }
    final netDue = totalGiven - totalReceived;

    final hasActiveFilter = !_filterCriteria.isEmpty ||
        _quickType != 'All' ||
        _searchQuery.isNotEmpty;

    final activeFilterCount = _filterCriteria.activeFilterCount;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🤝 Borrowers Ledger',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              '${filtered.length} logs · loan sheet',
              style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 22),
            tooltip: 'Export Borrower PDF',
            onPressed: () {
              HapticFeedback.lightImpact();
              final initialBorrower = _filterCriteria.selectedBorrowers.length == 1
                  ? _filterCriteria.selectedBorrowers.first
                  : null;
              BorrowerExportDialog.show(
                context,
                allEntries: filtered.isNotEmpty ? filtered : _entries,
                initialBorrower: initialBorrower,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 22),
            tooltip: 'Refresh from Google Sheets',
            onPressed: () => _loadEntries(forceRefresh: true),
          ),
          if (hasActiveFilter)
            IconButton(
              icon: const Icon(Icons.filter_alt_off_outlined, size: 22),
              tooltip: 'Clear all filters',
              onPressed: _resetAllFilters,
            ),
        ],
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              behavior: HitTestBehavior.translucent,
              child: RefreshIndicator(
                onRefresh: () => _loadEntries(forceRefresh: true),
                child: Column(
                  children: [
                    // Search Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search borrower, narration, card, ref...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                          suffixIcon: _searchCtrl.text.isNotEmpty
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
                                      _searchCtrl.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  ),
                                )
                              : null,
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        ),
                        onChanged: (val) {
                          setState(() => _searchQuery = val.trim());
                        },
                      ),
                    ),

                  // Filter Action Bar: Filters trigger button + Type quick chips
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // Faceted Filter Trigger Button
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: InkWell(
                              onTap: _openBorrowerFilters,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: activeFilterCount > 0
                                      ? primaryColor.withValues(alpha: 0.15)
                                      : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: activeFilterCount > 0
                                        ? primaryColor
                                        : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.tune_rounded,
                                      size: 15,
                                      color: activeFilterCount > 0 ? primaryColor : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      activeFilterCount > 0 ? 'Filters ($activeFilterCount)' : 'Filters',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: activeFilterCount > 0 ? primaryColor : (isDark ? Colors.white : const Color(0xFF1E293B)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Type Quick Chips (All, Given, Received)
                          ...['All', 'Given', 'Received'].map((type) {
                            final isSelected = _quickType == type;
                            Color activeBg = primaryColor;
                            if (type == 'Given') activeBg = const Color(0xFFF97316);
                            if (type == 'Received') activeBg = const Color(0xFF10B981);

                            return Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: ChoiceChip(
                                label: Text(type, style: const TextStyle(fontSize: 12)),
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? Colors.white : textSecondary,
                                ),
                                selected: isSelected,
                                selectedColor: activeBg,
                                backgroundColor: cardBg,
                                visualDensity: VisualDensity.compact,
                                onSelected: (val) {
                                  if (val) setState(() => _quickType = type);
                                },
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),

                  // Active Filter Chips Row (Date, Borrower, Narration, Invoice, etc.)
                  if (_filterCriteria.startDate != null ||
                      (_filterCriteria.datePreset != 'All Time' && _filterCriteria.datePreset.isNotEmpty) ||
                      _filterCriteria.selectedBorrowers.isNotEmpty ||
                      _filterCriteria.selectedNarrations.isNotEmpty ||
                      _filterCriteria.selectedInvoices.isNotEmpty ||
                      _filterCriteria.selectedPaymentTypes.isNotEmpty ||
                      _filterCriteria.selectedAccounts.isNotEmpty ||
                      _filterCriteria.selectedGivenAmounts.isNotEmpty ||
                      _filterCriteria.selectedReceivedAmounts.isNotEmpty ||
                      _filterCriteria.selectedReferenceIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            if (_filterCriteria.startDate != null ||
                                (_filterCriteria.datePreset != 'All Time' && _filterCriteria.datePreset.isNotEmpty))
                              _buildActiveChip(
                                '📅 $_dateRangeDisplayString',
                                () => setState(() {
                                  _filterCriteria.startDate = null;
                                  _filterCriteria.endDate = null;
                                  _filterCriteria.datePreset = 'All Time';
                                }),
                              ),
                            ..._filterCriteria.selectedBorrowers.map((b) =>
                              _buildActiveChip('👤 $b', () => setState(() => _filterCriteria.selectedBorrowers.remove(b))),
                            ),
                            ..._filterCriteria.selectedNarrations.map((n) =>
                              _buildActiveChip('📝 $n', () => setState(() => _filterCriteria.selectedNarrations.remove(n))),
                            ),
                            ..._filterCriteria.selectedInvoices.map((inv) =>
                              _buildActiveChip('🧾 $inv', () => setState(() => _filterCriteria.selectedInvoices.remove(inv))),
                            ),
                            ..._filterCriteria.selectedPaymentTypes.map((pt) =>
                              _buildActiveChip('⚡ $pt', () => setState(() => _filterCriteria.selectedPaymentTypes.remove(pt))),
                            ),
                            ..._filterCriteria.selectedAccounts.map((acc) =>
                              _buildActiveChip('💳 $acc', () => setState(() => _filterCriteria.selectedAccounts.remove(acc))),
                            ),
                            ..._filterCriteria.selectedGivenAmounts.map((amt) =>
                              _buildActiveChip('⬆️ ₹${IndianCurrency.formatSmart(amt)}', () => setState(() => _filterCriteria.selectedGivenAmounts.remove(amt))),
                            ),
                            ..._filterCriteria.selectedReceivedAmounts.map((amt) =>
                              _buildActiveChip('⬇️ ₹${IndianCurrency.formatSmart(amt)}', () => setState(() => _filterCriteria.selectedReceivedAmounts.remove(amt))),
                            ),
                            ..._filterCriteria.selectedReferenceIds.map((ref) =>
                              _buildActiveChip('🏷 $ref', () => setState(() => _filterCriteria.selectedReferenceIds.remove(ref))),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 4.0),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _filterCriteria.clear();
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

                  // Summary Metric Card
                  _buildSummaryHeader(
                    context,
                    totalGiven: totalGiven,
                    totalReceived: totalReceived,
                    netDue: netDue,
                    cardBg: cardBg,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    borderColor: borderColor,
                  ),

                  // List of Loan Records
                  Expanded(
                    child: filtered.isEmpty
                        ? _buildEmptyState(context, hasActiveFilter, textSecondary, primaryColor)
                        : ListView.separated(
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (ctx, index) {
                              final item = filtered[index];
                              return _buildLoanCard(
                                context,
                                item,
                                cardBg: cardBg,
                                textPrimary: textPrimary,
                                textSecondary: textSecondary,
                                borderColor: borderColor,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildSummaryHeader(
    BuildContext context, {
    required double totalGiven,
    required double totalReceived,
    required double netDue,
    required Color cardBg,
    required Color textPrimary,
    required Color textSecondary,
    required Color borderColor,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Total Given
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.arrow_upward_rounded, size: 13, color: Color(0xFFF97316)),
                    const SizedBox(width: 3),
                    Text(
                      'Total Given',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '₹${IndianCurrency.format(totalGiven)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF97316),
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 32, color: borderColor),
          // Total Received
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.arrow_downward_rounded, size: 13, color: Color(0xFF10B981)),
                      const SizedBox(width: 3),
                      Text(
                        'Received',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '₹${IndianCurrency.format(totalReceived)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 32, color: borderColor),
          // Net Balance
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        netDue > 0 ? Icons.pending_actions_rounded : Icons.check_circle_outline,
                        size: 13,
                        color: netDue > 0 ? const Color(0xFFE11D48) : const Color(0xFF0F766E),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        netDue >= 0 ? 'To Collect' : 'Surplus',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '₹${IndianCurrency.format(netDue.abs())}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: netDue > 0 ? const Color(0xFFE11D48) : const Color(0xFF0F766E),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoanCard(
    BuildContext context,
    LoanEntry item, {
    required Color cardBg,
    required Color textPrimary,
    required Color textSecondary,
    required Color borderColor,
  }) {
    final dateFmt = DateFormat('dd MMM yyyy');
    final isGiven = item.isGiven;

    return InkWell(
      onTap: () {
        if (item.parentTransaction != null) {
          TransactionDetailsDialog.show(context, item.parentTransaction!);
        } else {
          _showLoanDetailSheet(context, item);
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Borrower Avatar & Name + Status Badge + Amount
            Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: (isGiven ? const Color(0xFFF97316) : const Color(0xFF10B981)).withValues(alpha: 0.15),
                  child: Text(
                    item.borrower.isNotEmpty ? item.borrower[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isGiven ? const Color(0xFFF97316) : const Color(0xFF10B981),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.borrower,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateFmt.format(item.date),
                        style: TextStyle(fontSize: 11, color: textSecondary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: (isGiven ? const Color(0xFFF97316) : const Color(0xFF10B981)).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isGiven ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                            size: 11,
                            color: isGiven ? const Color(0xFFF97316) : const Color(0xFF10B981),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            isGiven ? 'GIVEN' : 'RECEIVED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isGiven ? const Color(0xFFF97316) : const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '₹${IndianCurrency.format(item.amount)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isGiven ? const Color(0xFFEA580C) : const Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (item.narration.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                item.narration,
                style: TextStyle(fontSize: 12.5, color: textPrimary.withValues(alpha: 0.85)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 8),
            // Bottom Metadata: Card / Account Badge + Reference Badge
            Row(
              children: [
                if (item.account.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.credit_card, size: 12, color: Color(0xFF2563EB)),
                        const SizedBox(width: 4),
                        Text(
                          item.account,
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (item.referenceId.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.referenceId,
                      style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: textSecondary),
                    ),
                  ),
                const Spacer(),
                if (item.parentTransaction != null)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Details',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F766E)),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: Color(0xFF0F766E)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLoanDetailSheet(BuildContext context, LoanEntry item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dateFmt = DateFormat('dd MMMM yyyy');

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Loan Sheet Record',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              _buildSheetRow('Borrower', item.borrower),
              _buildSheetRow('Date', dateFmt.format(item.date)),
              _buildSheetRow('Type', item.isGiven ? 'Given (Loan/Borrowing)' : 'Received (Repayment)'),
              _buildSheetRow('Amount', '₹${IndianCurrency.format(item.amount)}'),
              if (item.account.isNotEmpty) _buildSheetRow('Account / Card', item.account),
              if (item.narration.isNotEmpty) _buildSheetRow('Narration', item.narration),
              if (item.invoice.isNotEmpty) _buildSheetRow('Invoice No.', item.invoice),
              if (item.referenceId.isNotEmpty) _buildSheetRow('Reference ID', item.referenceId),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSheetRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    bool hasActiveFilter,
    Color textSecondary,
    Color primaryColor,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.handshake_outlined, size: 64, color: textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Text(
              hasActiveFilter ? 'No matching loan logs found' : 'No loan or borrower records yet',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              hasActiveFilter
                  ? 'Try adjusting or clearing your filters to see more results.'
                  : 'Split transactions and loan sheet entries will appear here automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: textSecondary.withValues(alpha: 0.8)),
            ),
            if (hasActiveFilter) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _resetAllFilters,
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Reset All Filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
