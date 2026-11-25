import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../services/statement_export_service.dart';
import '../services/storage_service.dart';
import '../utils/currency_formatter.dart';

class StatementExportDialog extends StatefulWidget {
  final List<FinanceTransaction>? prefilteredTransactions;
  final String? initialAccountFilter;

  const StatementExportDialog({
    super.key,
    this.prefilteredTransactions,
    this.initialAccountFilter,
  });

  static Future<void> show(
    BuildContext context, {
    List<FinanceTransaction>? prefilteredTransactions,
    String? initialAccountFilter,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatementExportDialog(
        prefilteredTransactions: prefilteredTransactions,
        initialAccountFilter: initialAccountFilter,
      ),
    );
  }

  @override
  State<StatementExportDialog> createState() => _StatementExportDialogState();
}

enum DatePreset {
  thisMonth,
  lastMonth,
  thisYear,
  last30Days,
  allTime,
  custom,
}

class _StatementExportDialogState extends State<StatementExportDialog> {
  DatePreset _selectedPreset = DatePreset.thisMonth;
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedAccount = 'All';
  String _selectedPurpose = 'All';
  final String _selectedFlow = 'All';

  List<FinanceTransaction> _allTransactions = [];
  List<String> _accountOptions = ['All'];
  List<String> _purposeOptions = ['All'];
  bool _isLoading = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _applyPreset(DatePreset.thisMonth);
    if (widget.initialAccountFilter != null) {
      _selectedAccount = widget.initialAccountFilter!;
    }
    _loadData();
  }

  void _applyPreset(DatePreset preset) {
    _selectedPreset = preset;
    final now = DateTime.now();

    switch (preset) {
      case DatePreset.thisMonth:
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 0);
        break;
      case DatePreset.lastMonth:
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        _startDate = DateTime(lastMonth.year, lastMonth.month, 1);
        _endDate = DateTime(now.year, now.month, 0);
        break;
      case DatePreset.thisYear:
        // Indian FY: April 1 to March 31
        final fyStartYear = now.month >= 4 ? now.year : now.year - 1;
        _startDate = DateTime(fyStartYear, 4, 1);
        _endDate = DateTime(fyStartYear + 1, 3, 31);
        break;
      case DatePreset.last30Days:
        _startDate = now.subtract(const Duration(days: 30));
        _endDate = now;
        break;
      case DatePreset.allTime:
        _startDate = null;
        _endDate = null;
        break;
      case DatePreset.custom:
        // Keep existing custom dates
        break;
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final storage = StorageService.instance;
    final txs = widget.prefilteredTransactions ?? await storage.getTransactions();
    final categories = await storage.getCategoryAccounts();
    final purposes = await storage.getPurposes();

    final accs = <String>{'All'};
    for (final list in categories.values) {
      accs.addAll(list);
    }
    // Also discover accounts from transactions
    for (final tx in txs) {
      for (final b in tx.breakdowns) {
        if (b.effectiveAccount.isNotEmpty && b.effectiveAccount != 'None') {
          accs.add(b.effectiveAccount);
        }
      }
      for (final b in tx.toBreakdowns ?? []) {
        if (b.effectiveAccount.isNotEmpty && b.effectiveAccount != 'None') {
          accs.add(b.effectiveAccount);
        }
      }
    }

    if (mounted) {
      setState(() {
        _allTransactions = txs;
        _accountOptions = accs.toList()..sort((a, b) => a == 'All' ? -1 : a.compareTo(b));
        _purposeOptions = ['All', ...purposes];
        _isLoading = false;
      });
    }
  }

  StatementFilterOptions get _filterOptions {
    String title = 'Financial Statement';
    if (_selectedAccount != 'All') {
      title = '$_selectedAccount Statement';
    } else if (_selectedPurpose != 'All') {
      title = '$_selectedPurpose Expenses Statement';
    }

    return StatementFilterOptions(
      startDate: _startDate,
      endDate: _endDate,
      accountFilter: _selectedAccount,
      purposeFilter: _selectedPurpose,
      flowFilter: _selectedFlow,
      title: title,
    );
  }

  List<FinanceTransaction> get _matchedTransactions {
    return StatementExportService.instance.filterTransactions(
      transactions: _allTransactions,
      options: _filterOptions,
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      initialDateRange: DateTimeRange(
        start: _startDate ?? now.subtract(const Duration(days: 30)),
        end: _endDate ?? now,
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: const Color(0xFF4F46E5),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedPreset = DatePreset.custom;
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _handlePdfPreview() async {
    final matched = _matchedTransactions;
    if (matched.isEmpty) {
      _showEmptyNotice();
      return;
    }
    setState(() => _isExporting = true);
    try {
      await StatementExportService.instance.previewOrPrintPdf(
        transactions: matched,
        options: _filterOptions,
      );
    } catch (e) {
      _showErrorNotice('Failed to generate PDF: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _handlePdfShare() async {
    final matched = _matchedTransactions;
    if (matched.isEmpty) {
      _showEmptyNotice();
      return;
    }
    setState(() => _isExporting = true);
    try {
      await StatementExportService.instance.sharePdfReport(
        transactions: matched,
        options: _filterOptions,
      );
    } catch (e) {
      _showErrorNotice('Failed to share PDF: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _handleCsvExport() async {
    final matched = _matchedTransactions;
    if (matched.isEmpty) {
      _showEmptyNotice();
      return;
    }
    setState(() => _isExporting = true);
    try {
      await StatementExportService.instance.exportAndShareCsv(
        transactions: matched,
        options: _filterOptions,
      );
    } catch (e) {
      _showErrorNotice('Failed to export Excel/CSV: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showEmptyNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No transactions found matching the selected filters.', textAlign: TextAlign.center),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _showErrorNotice(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, textAlign: TextAlign.center), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final matched = _matchedTransactions;
    final summary = StatementSummary.calculate(matched);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: _isLoading
          ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle pill
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF4F46E5), size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Export Financial Statement',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Download or share professional PDF & Excel reports',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Period Preset Chips
                  const Text('STATEMENT PERIOD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildPresetChip(DatePreset.thisMonth, 'This Month'),
                      _buildPresetChip(DatePreset.lastMonth, 'Last Month'),
                      _buildPresetChip(DatePreset.thisYear, 'This FY (Apr-Mar)'),
                      _buildPresetChip(DatePreset.last30Days, 'Last 30 Days'),
                      _buildPresetChip(DatePreset.allTime, 'All Time'),
                      _buildCustomDateChip(),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Filters: Account & Purpose
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdownFilter(
                          label: 'ACCOUNT',
                          value: _selectedAccount,
                          items: _accountOptions,
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedAccount = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildDropdownFilter(
                          label: 'PURPOSE',
                          value: _selectedPurpose,
                          items: _purposeOptions,
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedPurpose = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Live Matched Summary Box
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2B3D) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${matched.length} TRANSACTIONS MATCHED',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5), letterSpacing: 0.5),
                            ),
                            Text(
                              _selectedPreset == DatePreset.allTime
                                  ? 'All records'
                                  : '${_startDate != null ? DateFormat('dd MMM').format(_startDate!) : ""} - ${_endDate != null ? DateFormat('dd MMM yyyy').format(_endDate!) : ""}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem('Inflows', '₹${IndianCurrency.format(summary.totalInflows)}', Colors.green),
                            _buildStatItem('Outflows', '₹${IndianCurrency.format(summary.totalOutflows)}', Colors.red.shade600),
                            _buildStatItem('Net Flow', '₹${IndianCurrency.format(summary.netCashFlow)}', summary.netCashFlow >= 0 ? Colors.green : Colors.red.shade600),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Export Action Buttons
                  if (_isExporting) ...[
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 12),
                            Text('Preparing statement report...'),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.print_rounded, size: 18),
                            label: const Text('Preview / Print', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: _handlePdfPreview,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D9488),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.share_rounded, size: 18),
                            label: const Text('Share PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: _handlePdfShare,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.tealAccent : const Color(0xFF047857),
                          side: BorderSide(color: isDark ? Colors.tealAccent.withValues(alpha: 0.5) : const Color(0xFF047857), width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.table_chart_rounded, size: 18),
                        label: const Text('Export Excel / CSV', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _handleCsvExport,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildPresetChip(DatePreset preset, String label) {
    final isSelected = _selectedPreset == preset;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _applyPreset(preset));
      },
      selectedColor: const Color(0xFF4F46E5),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      backgroundColor: Colors.grey.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildCustomDateChip() {
    final isSelected = _selectedPreset == DatePreset.custom;
    final dateStr = isSelected && _startDate != null && _endDate != null
        ? '${DateFormat('dd/MM').format(_startDate!)} - ${DateFormat('dd/MM').format(_endDate!)}'
        : 'Custom Range';

    return ActionChip(
      avatar: const Icon(Icons.date_range_rounded, size: 16),
      label: Text(dateStr),
      backgroundColor: isSelected ? const Color(0xFF4F46E5).withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.1),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF4F46E5) : null,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      onPressed: _pickDateRange,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: isSelected ? const BorderSide(color: Color(0xFF4F46E5), width: 1.5) : BorderSide.none,
      ),
    );
  }

  Widget _buildDropdownFilter({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
              isExpanded: true,
              style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyLarge?.color),
              items: items.map((item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
