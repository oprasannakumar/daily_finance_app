import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../services/quick_nav_controller.dart';
import '../services/storage_service.dart';
import '../utils/currency_formatter.dart';
import '../widgets/borrower_export_dialog.dart';
import '../widgets/transaction_details_dialog.dart';

class BorrowerDetailScreen extends StatefulWidget {
  final String borrowerName;
  final List<LoanEntry> initialEntries;

  const BorrowerDetailScreen({
    super.key,
    required this.borrowerName,
    required this.initialEntries,
  });

  @override
  State<BorrowerDetailScreen> createState() => _BorrowerDetailScreenState();
}

class _BorrowerDetailScreenState extends State<BorrowerDetailScreen> {
  late List<LoanEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = _filterForBorrower(widget.initialEntries);
    StorageService.instance.loansNotifier.addListener(_reload);
    StorageService.instance.transactionsNotifier.addListener(_reload);
  }

  @override
  void dispose() {
    StorageService.instance.loansNotifier.removeListener(_reload);
    StorageService.instance.transactionsNotifier.removeListener(_reload);
    super.dispose();
  }

  List<LoanEntry> _filterForBorrower(List<LoanEntry> source) {
    final target = widget.borrowerName.trim().toLowerCase();
    final list = source.where((e) => e.borrower.trim().toLowerCase() == target).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  Future<void> _reload() async {
    final all = await StorageService.instance.getLoanEntries();
    if (!mounted) return;
    setState(() {
      _entries = _filterForBorrower(all);
    });
  }

  void _copyStatementSummary(double given, double received, double net) {
    final buf = StringBuffer();
    buf.writeln('*${widget.borrowerName} — Balance Summary*');
    if (net > 0.01) {
      buf.writeln('Pending Receivable: ₹${IndianCurrency.format(net)}');
    } else if (net < -0.01) {
      buf.writeln('Pending Payable: ₹${IndianCurrency.format(net.abs())}');
    } else {
      buf.writeln('Status: Settled (₹0)');
    }
    buf.writeln('Total Given: ₹${IndianCurrency.format(given)}');
    buf.writeln('Total Received: ₹${IndianCurrency.format(received)}');
    buf.writeln('');
    buf.writeln('Recent Entries:');
    for (final e in _entries.take(10)) {
      final tag = e.isGiven ? 'Given' : 'Received';
      final narr = e.narration.trim().isNotEmpty ? ' (${e.narration.trim()})' : '';
      buf.writeln('• ${DateFormat('dd MMM yyyy').format(e.date)} — $tag ₹${IndianCurrency.format(e.amount)}$narr');
    }
    Clipboard.setData(ClipboardData(text: buf.toString().trim()));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Borrower summary copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openEntryDetails(LoanEntry entry) async {
    if (entry.parentTransaction != null) {
      await showDialog<void>(
        context: context,
        builder: (_) => TransactionDetailsDialog(tx: entry.parentTransaction!),
      );
      return;
    }
    final allTxs = await StorageService.instance.getTransactions();
    final match = allTxs.where((t) => t.referenceId == entry.referenceId).toList();
    if (!mounted) return;
    if (match.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (_) => TransactionDetailsDialog(tx: match.first),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Full transaction details unavailable for this entry.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    const accent = Color(0xFF6366F1);

    double totalGiven = 0.0;
    double totalReceived = 0.0;
    final Map<String, ({DateTime month, double given, double received})> monthlyMap = {};
    final Map<String, ({double amount, int count})> typeMap = {};

    for (final e in _entries) {
      totalGiven += e.givenAmount;
      totalReceived += e.receivedAmount;

      final mKey = '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}';
      final prevM = monthlyMap[mKey];
      monthlyMap[mKey] = (
        month: DateTime(e.date.year, e.date.month, 1),
        given: (prevM?.given ?? 0.0) + e.givenAmount,
        received: (prevM?.received ?? 0.0) + e.receivedAmount,
      );

      final tKey = e.transactionType.trim().isEmpty ? 'General' : e.transactionType.trim();
      final prevT = typeMap[tKey];
      typeMap[tKey] = (
        amount: (prevT?.amount ?? 0.0) + e.amount,
        count: (prevT?.count ?? 0) + 1,
      );
    }

    final net = totalGiven - totalReceived;
    final recoveryPct = totalGiven > 0 ? ((totalReceived / totalGiven) * 100).clamp(0.0, 100.0) : 0.0;
    final lastDate = _entries.isNotEmpty ? _entries.first.date : null;
    final firstDate = _entries.isNotEmpty ? _entries.last.date : null;
    final daysSinceLast = lastDate != null ? DateTime.now().difference(lastDate).inDays : 0;

    final monthlyList = monthlyMap.values.toList()..sort((a, b) => b.month.compareTo(a.month));
    final typeList = typeMap.entries.toList()..sort((a, b) => b.value.amount.compareTo(a.value.amount));

    final netColor = net > 0.01
        ? const Color(0xFF10B981)
        : (net < -0.01 ? const Color(0xFFEF4444) : textSecondary);
    final netLabel = net > 0.01
        ? 'You will get'
        : (net < -0.01 ? 'You owe' : 'Settled');

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.borrowerName,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: textPrimary),
            ),
            Text(
              '${_entries.length} entries${lastDate != null ? ' · Last ${DateFormat('dd MMM yy').format(lastDate)}' : ''}',
              style: TextStyle(fontSize: 11, color: textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: 'Copy Reminder Summary',
            onPressed: () => _copyStatementSummary(totalGiven, totalReceived, net),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 21),
            tooltip: 'Export Borrower PDF',
            onPressed: () {
              BorrowerExportDialog.show(
                context,
                allEntries: _entries,
                initialBorrower: widget.borrowerName,
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Hero Summary Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E1B4B), const Color(0xFF312E81)]
                    : [const Color(0xFF4F46E5), const Color(0xFF6366F1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      netLabel.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    if (net.abs() > 0.01 && daysSinceLast > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${daysSinceLast}d since last activity',
                          style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '₹${IndianCurrency.format(net.abs())}',
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (recoveryPct / 100).clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: Colors.white.withValues(alpha: 0.22),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Given: ₹${IndianCurrency.format(totalGiven)}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Received: ₹${IndianCurrency.format(totalReceived)} (${recoveryPct.toStringAsFixed(0)}%)',
                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                if (firstDate != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Active since ${DateFormat('dd MMM yyyy').format(firstDate)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2. Quick Actions Row
          Row(
            children: [
              if (net.abs() > 0.01) ...[
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
                    label: const Text('Settle Up'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      final isReceivable = net > 0;
                      QuickNavController.instance.openEntryWithDraft(
                        EntryDraft(
                          flow: isReceivable ? 'Deposit' : 'Withdraw',
                          purpose: isReceivable ? 'Loan Repayment Received' : 'Loan Settlement',
                          spentFor: 'Split',
                          amount: net.abs(),
                          narration: isReceivable
                              ? 'Settlement from ${widget.borrowerName}'
                              : 'Settlement to ${widget.borrowerName}',
                          splitBorrower: widget.borrowerName,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  label: const Text('Copy'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent.withValues(alpha: 0.45)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _copyStatementSummary(totalGiven, totalReceived, net),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
                  label: const Text('PDF'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    BorrowerExportDialog.show(
                      context,
                      allEntries: _entries,
                      initialBorrower: widget.borrowerName,
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 3. Month-wise Breakdown
          if (monthlyList.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Month-wise Breakdown',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textPrimary),
                  ),
                  const SizedBox(height: 10),
                  ...monthlyList.map((m) {
                    final mNet = m.given - m.received;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 78,
                            child: Text(
                              DateFormat('MMM yyyy').format(m.month),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Given ₹${IndianCurrency.format(m.given)} · Rec ₹${IndianCurrency.format(m.received)}',
                              style: TextStyle(fontSize: 11.5, color: textSecondary),
                            ),
                          ),
                          Text(
                            '${mNet >= 0 ? '+' : '-'}₹${IndianCurrency.format(mNet.abs())}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: mNet >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 4. Category / Type Breakdown
          if (typeList.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Activity Breakdown',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textPrimary),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: typeList.map((t) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${t.key} (${t.value.count}): ₹${IndianCurrency.format(t.value.amount)}',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: textPrimary),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 5. Itemized Timeline
          Text(
            'Itemized Timeline (${_entries.length})',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textPrimary),
          ),
          const SizedBox(height: 10),
          ..._entries.map((entry) {
            final isGiven = entry.isGiven;
            final badgeColor = isGiven ? const Color(0xFFEF4444) : const Color(0xFF10B981);
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openEntryDetails(entry),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isGiven ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 16,
                        color: badgeColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.narration.trim().isNotEmpty
                                ? entry.narration.trim()
                                : (entry.transactionType.isNotEmpty ? entry.transactionType : 'Entry'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${DateFormat('dd MMM yyyy').format(entry.date)}${entry.account.isNotEmpty ? ' · ${entry.account}' : ''}',
                            style: TextStyle(fontSize: 11, color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${isGiven ? '+' : '-'}₹${IndianCurrency.format(entry.amount)}',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: isGiven ? netColor : const Color(0xFF10B981),
                          ),
                        ),
                        Text(
                          isGiven ? 'Given' : 'Received',
                          style: TextStyle(fontSize: 10, color: textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
