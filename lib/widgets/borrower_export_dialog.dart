import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../services/statement_export_service.dart';
import '../utils/currency_formatter.dart';

class BorrowerExportDialog extends StatefulWidget {
  final List<LoanEntry> allEntries;
  final String? initialBorrower;

  const BorrowerExportDialog({
    super.key,
    required this.allEntries,
    this.initialBorrower,
  });

  static Future<void> show(
    BuildContext context, {
    required List<LoanEntry> allEntries,
    String? initialBorrower,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BorrowerExportDialog(
        allEntries: allEntries,
        initialBorrower: initialBorrower,
      ),
    );
  }

  @override
  State<BorrowerExportDialog> createState() => _BorrowerExportDialogState();
}

enum BorrowerDatePreset {
  allTime,
  thisMonth,
  lastMonth,
  thisYear,
  custom,
}

class _BorrowerExportDialogState extends State<BorrowerExportDialog> {
  BorrowerDatePreset _selectedPreset = BorrowerDatePreset.allTime;
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedBorrower = 'All';
  bool _isGenerating = false;

  late List<String> _borrowerOptions;

  @override
  void initState() {
    super.initState();
    final borrowersSet = widget.allEntries
        .map((e) => e.borrower.trim())
        .where((b) => b.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    _borrowerOptions = ['All', ...borrowersSet];
    if (widget.initialBorrower != null && _borrowerOptions.contains(widget.initialBorrower)) {
      _selectedBorrower = widget.initialBorrower!;
    }
  }

  void _applyPreset(BorrowerDatePreset preset) {
    final now = DateTime.now();
    setState(() {
      _selectedPreset = preset;
      switch (preset) {
        case BorrowerDatePreset.allTime:
          _startDate = null;
          _endDate = null;
          break;
        case BorrowerDatePreset.thisMonth:
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
          break;
        case BorrowerDatePreset.lastMonth:
          _startDate = DateTime(now.year, now.month - 1, 1);
          _endDate = DateTime(now.year, now.month, 0, 23, 59, 59);
          break;
        case BorrowerDatePreset.thisYear:
          // Financial year Apr 1 to Mar 31
          if (now.month >= 4) {
            _startDate = DateTime(now.year, 4, 1);
            _endDate = DateTime(now.year + 1, 3, 31, 23, 59, 59);
          } else {
            _startDate = DateTime(now.year - 1, 4, 1);
            _endDate = DateTime(now.year, 3, 31, 23, 59, 59);
          }
          break;
        case BorrowerDatePreset.custom:
          break;
      }
    });
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _selectedPreset = BorrowerDatePreset.custom;
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
    }
  }

  List<LoanEntry> get _filteredEntries {
    return widget.allEntries.where((e) {
      if (_startDate != null) {
        final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        if (e.date.isBefore(start)) return false;
      }
      if (_endDate != null) {
        final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        if (e.date.isAfter(end)) return false;
      }
      if (_selectedBorrower != 'All') {
        if (e.borrower.trim().toLowerCase() != _selectedBorrower.trim().toLowerCase()) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final primaryColor = isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5);

    final filtered = _filteredEntries;
    final summary = BorrowerStatementSummary.calculate(filtered);

    final df = DateFormat('dd MMM yyyy');
    final String rangeDisplay = (_startDate != null || _endDate != null)
        ? '${_startDate != null ? df.format(_startDate!) : "Start"} - ${_endDate != null ? df.format(_endDate!) : "Present"}'
        : 'All Time';

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('🤝', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Export Borrower Statement',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Generate printable PDF statements & loan ledgers',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Period Selector
            Text(
              'STATEMENT PERIOD',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildPresetChip('All Time', BorrowerDatePreset.allTime, primaryColor),
                _buildPresetChip('This Month', BorrowerDatePreset.thisMonth, primaryColor),
                _buildPresetChip('Last Month', BorrowerDatePreset.lastMonth, primaryColor),
                _buildPresetChip('This FY', BorrowerDatePreset.thisYear, primaryColor),
                ActionChip(
                  avatar: const Icon(Icons.date_range_rounded, size: 16),
                  label: Text(_selectedPreset == BorrowerDatePreset.custom ? rangeDisplay : 'Custom Range'),
                  backgroundColor: _selectedPreset == BorrowerDatePreset.custom
                      ? primaryColor.withValues(alpha: 0.15)
                      : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
                  side: BorderSide(
                    color: _selectedPreset == BorrowerDatePreset.custom ? primaryColor : borderColor,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: _selectedPreset == BorrowerDatePreset.custom ? FontWeight.bold : FontWeight.normal,
                    color: _selectedPreset == BorrowerDatePreset.custom ? primaryColor : textPrimary,
                  ),
                  onPressed: _pickCustomDateRange,
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Borrower Selector
            Text(
              'SELECT BORROWER',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedBorrower,
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down_rounded),
                  items: _borrowerOptions.map((b) {
                    return DropdownMenuItem<String>(
                      value: b,
                      child: Text(
                        b == 'All' ? '👥 All Borrowers (${widget.allEntries.length} total entries)' : '👤 $b',
                        style: TextStyle(fontSize: 13, color: textPrimary),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedBorrower = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Match Summary Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${filtered.length} TRANSACTIONS MATCHED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        rangeDisplay,
                        style: TextStyle(fontSize: 11, color: textSecondary),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMetric('Total Given', summary.totalGiven, const Color(0xFFEA580C)),
                      Container(width: 1, height: 28, color: borderColor),
                      _buildMetric('Total Received', summary.totalReceived, const Color(0xFF10B981)),
                      Container(width: 1, height: 28, color: borderColor),
                      _buildMetric(
                        'Net Due',
                        summary.netDue.abs(),
                        summary.netDue > 0
                            ? const Color(0xFFEF4444)
                            : (summary.netDue < 0 ? const Color(0xFF3B82F6) : textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Action Buttons
            if (_isGenerating)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 1,
                      ),
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text(
                        'Preview / Print',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      onPressed: filtered.isEmpty ? null : () => _executeAction(isPreview: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 1,
                      ),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text(
                        'Share PDF',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      onPressed: filtered.isEmpty ? null : () => _executeAction(isPreview: false),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, BorrowerDatePreset preset, Color primaryColor) {
    final isSelected = _selectedPreset == preset;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: primaryColor.withValues(alpha: 0.2),
      checkmarkColor: primaryColor,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? primaryColor : textPrimary,
      ),
      onSelected: (_) => _applyPreset(preset),
    );
  }

  Widget _buildMetric(String label, double amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 3),
        Text(
          IndianCurrency.formatSmart(amount),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Future<void> _executeAction({required bool isPreview}) async {
    setState(() => _isGenerating = true);
    try {
      final entries = _filteredEntries;
      final borrowerFilter = _selectedBorrower != 'All' ? _selectedBorrower : null;
      final title = borrowerFilter != null
          ? 'Borrower Statement - $borrowerFilter'
          : 'Borrowers Ledger Statement';

      if (isPreview) {
        await StatementExportService.instance.previewOrPrintBorrowerPdf(
          context,
          entries: entries,
          title: title,
          borrowerFilter: borrowerFilter,
          startDate: _startDate,
          endDate: _endDate,
        );
      } else {
        await StatementExportService.instance.shareBorrowerPdfReport(
          entries: entries,
          title: title,
          borrowerFilter: borrowerFilter,
          startDate: _startDate,
          endDate: _endDate,
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }
}
