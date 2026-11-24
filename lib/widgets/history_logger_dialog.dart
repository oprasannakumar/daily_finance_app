import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../services/storage_service.dart';
import '../utils/currency_formatter.dart';
import 'swipeable_date_picker.dart';
import 'transaction_details_dialog.dart';

/// Modal dialog for History Logger matching video recording (media_1794923870034_1cf03a4d.mp4)
class HistoryLoggerDialog extends StatefulWidget {
  final DateTime initialStartDate;
  final DateTime initialEndDate;
  final Function(double totalIn, double totalOut, DateTime start, DateTime end)? onStatsUpdated;
  final Function(FinanceTransaction tx)? onEditTransaction;

  const HistoryLoggerDialog({
    super.key,
    required this.initialStartDate,
    required this.initialEndDate,
    this.onStatsUpdated,
    this.onEditTransaction,
  });

  static Future<void> show(
    BuildContext context, {
    required DateTime initialStartDate,
    required DateTime initialEndDate,
    Function(double totalIn, double totalOut, DateTime start, DateTime end)? onStatsUpdated,
    Function(FinanceTransaction tx)? onEditTransaction,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => HistoryLoggerDialog(
        initialStartDate: initialStartDate,
        initialEndDate: initialEndDate,
        onStatsUpdated: onStatsUpdated,
        onEditTransaction: onEditTransaction,
      ),
    );
  }

  @override
  State<HistoryLoggerDialog> createState() => _HistoryLoggerDialogState();
}

class _HistoryLoggerDialogState extends State<HistoryLoggerDialog> {
  final StorageService _storage = StorageService.instance;
  late DateTime _startDate;
  late DateTime _endDate;

  bool _isLoading = true;
  List<FinanceTransaction> _allTransactions = [];
  List<FinanceTransaction> _filteredTransactions = [];

  String _searchQuery = '';
  String _selectedCategory = 'All';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startDate = DateTime(
      widget.initialStartDate.year,
      widget.initialStartDate.month,
      widget.initialStartDate.day,
    );
    _endDate = DateTime(
      widget.initialEndDate.year,
      widget.initialEndDate.month,
      widget.initialEndDate.day,
    );
    _fetchTransactions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isSingleDay {
    return _startDate.year == _endDate.year &&
        _startDate.month == _endDate.month &&
        _startDate.day == _endDate.day;
  }

  String get _dateRangeDisplayString {
    final fmt = DateFormat('d-MMM-yyyy');
    if (_isSingleDay) {
      return fmt.format(_startDate);
    } else {
      return '${fmt.format(_startDate)} to ${fmt.format(_endDate)}';
    }
  }

  String get _titleDisplayString {
    final fmt = DateFormat('d-MMM-yyyy');
    if (_isSingleDay) {
      return 'Logs for ${fmt.format(_startDate)}';
    } else {
      return '${fmt.format(_startDate)} to ${fmt.format(_endDate)}';
    }
  }

  Future<void> _fetchTransactions() async {
    setState(() => _isLoading = true);

    final allTx = await _storage.getTransactions();

    final startBound = DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0, 0);
    final endBound = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);

    final inRange = allTx.where((tx) {
      return (tx.date.isAfter(startBound) || tx.date.isAtSameMomentAs(startBound)) &&
          (tx.date.isBefore(endBound) || tx.date.isAtSameMomentAs(endBound));
    }).toList();

    // Sort descending by date
    inRange.sort((a, b) => b.date.compareTo(a.date));

    // Calculate totals for range (excluding self-transfers as requested)
    double inSum = 0.0;
    double outSum = 0.0;
    for (final t in inRange) {
      if (t.isSelfTransfer || t.flow == 'Transfer') {
        continue;
      } else if (t.flow == 'Deposit') {
        inSum += t.totalAmount;
      } else if (t.flow == 'Withdraw') {
        outSum += t.totalAmount;
      }
    }

    widget.onStatsUpdated?.call(inSum, outSum, _startDate, _endDate);

    if (mounted) {
      setState(() {
        _allTransactions = inRange;
        _isLoading = false;
        _applyFilters();
      });
    }
  }

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    _filteredTransactions = _allTransactions.where((tx) {
      // Category filter
      if (_selectedCategory != 'All') {
        final matchesPurpose = tx.purpose.toLowerCase() == _selectedCategory.toLowerCase();
        final matchesSpent = tx.spentFor.toLowerCase() == _selectedCategory.toLowerCase();
        if (!matchesPurpose && !matchesSpent) return false;
      }

      // Search query filter
      if (q.isNotEmpty) {
        final matchNarr = tx.narration.toLowerCase().contains(q);
        final matchFrom = tx.fromSummary.toLowerCase().contains(q);
        final matchTo = tx.toSummary.toLowerCase().contains(q);
        final matchPurp = tx.purpose.toLowerCase().contains(q);
        final matchSpent = tx.spentFor.toLowerCase().contains(q);
        final matchRef = tx.referenceId.toLowerCase().contains(q);
        final matchAmt = tx.totalAmount.toStringAsFixed(2).contains(q);
        return matchNarr || matchFrom || matchTo || matchPurp || matchSpent || matchRef || matchAmt;
      }

      return true;
    }).toList();
  }

  List<String> get _categories {
    final set = <String>{'All'};
    for (final t in _allTransactions) {
      if (t.purpose.isNotEmpty && t.purpose != 'Other') {
        set.add(t.purpose);
      }
      if (t.isSelfTransfer) {
        set.add('Transfer to Others');
      }
    }
    return set.toList();
  }

  double get _totalInflow {
    double sum = 0.0;
    for (final t in _filteredTransactions) {
      if (t.isSelfTransfer || t.flow == 'Transfer') continue;
      if (t.flow == 'Deposit') {
        sum += t.totalAmount;
      }
    }
    return sum;
  }

  double get _totalOutflow {
    double sum = 0.0;
    for (final t in _filteredTransactions) {
      if (t.isSelfTransfer || t.flow == 'Transfer') continue;
      if (t.flow == 'Withdraw') {
        sum += t.totalAmount;
      }
    }
    return sum;
  }

  double get _netBalance => _totalInflow - _totalOutflow;

  void _notifyStats() {
    double inSum = 0.0;
    double outSum = 0.0;
    for (final t in _allTransactions) {
      if (t.isSelfTransfer || t.flow == 'Transfer') {
        continue;
      } else if (t.flow == 'Deposit') {
        inSum += t.totalAmount;
      } else if (t.flow == 'Withdraw') {
        outSum += t.totalAmount;
      }
    }
    widget.onStatsUpdated?.call(inSum, outSum, _startDate, _endDate);
  }

  Future<void> _handleDeleteTransaction(FinanceTransaction tx) async {
    HapticFeedback.mediumImpact();
    await _storage.deleteTransaction(tx.id);
    setState(() {
      _allTransactions.removeWhere((t) => t.id == tx.id);
      _filteredTransactions.removeWhere((t) => t.id == tx.id);
    });
    _notifyStats();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deleted "${tx.narration.isNotEmpty ? tx.narration : tx.purpose}" (₹${IndianCurrency.format(tx.totalAmount)})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: Colors.white,
            onPressed: () async {
              await _storage.saveTransaction(tx);
              setState(() {
                _allTransactions.add(tx);
                _allTransactions.sort((a, b) => b.date.compareTo(a.date));
                _applyFilters();
              });
              _notifyStats();
            },
          ),
        ),
      );
    }
  }

  Future<void> _openDateSelection() async {
    final pickedRange = await SwipeableDateRangePickerDialog.show(
      context: context,
      initialStartDate: _startDate,
      initialEndDate: _endDate,
    );

    if (pickedRange != null && mounted) {
      setState(() {
        if (pickedRange.isAllTime) {
          _startDate = DateTime(2000, 1, 1);
          _endDate = DateTime.now().add(const Duration(days: 365));
        } else {
          _startDate = pickedRange.start ?? _startDate;
          _endDate = pickedRange.end ?? _endDate;
        }
      });
      _fetchTransactions();
    }
  }

  void _showTransactionDetails(FinanceTransaction tx) {
    TransactionDetailsDialog.show(context, tx);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF151932) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF262C54) : const Color(0xFFF1E5DC);
    final inputBg = isDark ? const Color(0xFF1B2042) : const Color(0xFFFFF8F6);
    final inputBorder = isDark ? const Color(0xFF2C3360) : const Color(0xFFF0E5DE);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    const coralAccent = Color(0xFFFF5C38);
    const cyanAccent = Color(0xFF00D2B4);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 680),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cardBorder, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // 1. Header: 📋 Logs for Date / Range + ✕ Close
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
              child: Row(
                children: [
                  const Text('📋 ', style: TextStyle(fontSize: 18)),
                  Expanded(
                    child: Text(
                      _titleDisplayString,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: textSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // 2. Date Input / Range Selector Box (Matches form's date selector)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: InkWell(
                onTap: _openDateSelection,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1B2042) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? const Color(0xFF2C3360) : const Color(0xFFE2E8F0),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text('📅 ', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _dateRangeDisplayString,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 18,
                        color: textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 3. Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: inputBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: inputBorder, width: 1.0),
                ),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(fontSize: 13, color: textPrimary),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _applyFilters();
                              });
                            },
                          )
                        : null,
                    hintText: 'Search narration, account, amount...',
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                      _applyFilters();
                    });
                  },
                ),
              ),
            ),

            // 4. Category Filter Chips (Horizontal Scroll - Sleek Compact Tags)
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _categories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedCategory = cat;
                          _applyFilters();
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark ? const Color(0xFF381A2D) : const Color(0xFFFFF1F2))
                              : (isDark ? const Color(0xFF1B2042) : Colors.white),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? coralAccent
                                : (isDark ? const Color(0xFF2C3360) : const Color(0xFFE2E8F0)),
                            width: isSelected ? 1.4 : 1.0,
                          ),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? coralAccent : textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 6),

            // 5. Transaction List / Loading State
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: coralAccent,
                            strokeWidth: 2.8,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Fetching transactions...',
                            style: TextStyle(color: textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : _filteredTransactions.isEmpty
                      ? Center(
                          child: Text(
                            'No transactions found for this date range.',
                            style: TextStyle(color: textSecondary, fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          itemCount: _filteredTransactions.length,
                          itemBuilder: (ctx, idx) {
                            final tx = _filteredTransactions[idx];
                            final isDeposit = tx.flow == 'Deposit';
                            final isTransfer = tx.isSelfTransfer || tx.flow == 'Transfer';

                            Color amtColor;
                            if (isTransfer) {
                              amtColor = const Color(0xFFF59E0B);
                            } else if (isDeposit) {
                              amtColor = cyanAccent;
                            } else {
                              amtColor = coralAccent;
                            }

                            final accountSubtitle = isTransfer
                                ? '${tx.fromSummary} → ${tx.toSummary}'
                                : tx.fromSummary;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Dismissible(
                                  key: ValueKey(tx.id),
                                  direction: DismissDirection.horizontal,
                                  movementDuration: const Duration(milliseconds: 260),
                                  resizeDuration: const Duration(milliseconds: 260),
                                  dismissThresholds: const {
                                    DismissDirection.startToEnd: 0.28,
                                    DismissDirection.endToStart: 0.28,
                                  },
                                  // Swipe Left -> Right (startToEnd): EDIT
                                  background: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF059669), Color(0xFF10B981)],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 18),
                                    alignment: Alignment.centerLeft,
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.edit_rounded, color: Colors.white, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'Edit',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Swipe Right -> Left (endToStart): DELETE
                                  secondaryBackground: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
                                        begin: Alignment.centerRight,
                                        end: Alignment.centerLeft,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 18),
                                    alignment: Alignment.centerRight,
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Delete',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(Icons.delete_forever_rounded, color: Colors.white, size: 20),
                                      ],
                                    ),
                                  ),
                                  confirmDismiss: (direction) async {
                                    if (direction == DismissDirection.startToEnd) {
                                      // Swipe Left -> Right = Edit
                                      HapticFeedback.mediumImpact();
                                      Navigator.of(context).pop();
                                      widget.onEditTransaction?.call(tx);
                                      return false;
                                    } else if (direction == DismissDirection.endToStart) {
                                      // Swipe Right -> Left = Delete
                                      await _handleDeleteTransaction(tx);
                                      return true;
                                    }
                                    return false;
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1B2042) : Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isDark ? const Color(0xFF2C3360) : const Color(0xFFF1E5DC),
                                        width: 1.0,
                                      ),
                                    ),
                                    child: InkWell(
                                      onTap: () => _showTransactionDetails(tx),
                                      borderRadius: BorderRadius.circular(14),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    tx.narration.isNotEmpty ? tx.narration : tx.purpose,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                      color: textPrimary,
                                                    ),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '₹${IndianCurrency.format(tx.totalAmount)}',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: amtColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    accountSubtitle,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: textSecondary,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (!_isSingleDay)
                                                  Text(
                                                    DateFormat('d-MMM').format(tx.date),
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: textSecondary,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // 6. Dialog Bottom Summary: In / Out and Net
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF13172E) : const Color(0xFFFFFBF9),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                border: Border(
                  top: BorderSide(
                    color: isDark ? const Color(0xFF262C54) : const Color(0xFFF1E5DC),
                    width: 1.0,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'In: ₹${IndianCurrency.format(_totalInflow)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: cyanAccent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Out: ₹${IndianCurrency.format(_totalOutflow)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: coralAccent,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Net: ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        '${_netBalance >= 0 ? "+" : "-"}₹${IndianCurrency.format(_netBalance.abs())}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _netBalance >= 0 ? cyanAccent : coralAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
