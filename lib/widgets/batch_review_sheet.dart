import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../services/clipboard_transaction_parser.dart';
import '../services/storage_service.dart';
import '../utils/currency_formatter.dart';

enum BatchReviewResultAction {
  savedAll,
  reviewInForm,
  cancelled,
}

class BatchReviewResult {
  final BatchReviewResultAction action;
  final List<ParsedTransactionDraft> remainingDrafts;
  final int selectedIndex;

  BatchReviewResult({
    required this.action,
    required this.remainingDrafts,
    this.selectedIndex = 0,
  });
}

class BatchReviewSheet extends StatefulWidget {
  final List<ParsedTransactionDraft> initialDrafts;

  const BatchReviewSheet({
    super.key,
    required this.initialDrafts,
  });

  static Future<BatchReviewResult?> show(
    BuildContext context, {
    required List<ParsedTransactionDraft> drafts,
  }) {
    return showModalBottomSheet<BatchReviewResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BatchReviewSheet(initialDrafts: drafts),
    );
  }

  @override
  State<BatchReviewSheet> createState() => _BatchReviewSheetState();
}

class _BatchReviewSheetState extends State<BatchReviewSheet> {
  final StorageService _storage = StorageService.instance;
  late List<ParsedTransactionDraft> _drafts;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _drafts = List.from(widget.initialDrafts);
  }

  double get _totalOutflow {
    double sum = 0.0;
    for (final d in _drafts) {
      if (d.flow == 'Withdraw') {
        sum += d.amount;
      }
    }
    return sum;
  }

  double get _totalInflow {
    double sum = 0.0;
    for (final d in _drafts) {
      if (d.flow == 'Deposit') {
        sum += d.amount;
      }
    }
    return sum;
  }

  Future<void> _saveAll() async {
    if (_drafts.isEmpty) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final categoryAccounts = await _storage.getCategoryAccounts();

      for (final draft in _drafts) {
        String finalAccount = draft.account.isNotEmpty ? draft.account : 'Other';
        String? otherAccountText;

        if (draft.account.isNotEmpty && draft.paymentType.isNotEmpty) {
          String masterCat = 'Bank Accounts';
          if (draft.paymentType.contains('Credit')) {
            masterCat = 'Credit Cards';
          } else if (draft.paymentType.contains('Wallet')) {
            masterCat = 'Wallets';
          } else if (draft.paymentType.contains('Reward')) {
            masterCat = 'Rewards';
          }
          final list = categoryAccounts[masterCat] ?? [];
          final isKnown = list.any((a) => a.toLowerCase() == draft.account.toLowerCase());
          finalAccount = isKnown
              ? list.firstWhere((a) => a.toLowerCase() == draft.account.toLowerCase())
              : 'Other';
          otherAccountText = isKnown ? null : draft.account;
        }

        final List<PaymentBreakdown> breakdowns = [];
        if (draft.charges > 0) {
          final grossAmt = double.parse((draft.amount + draft.charges.abs()).toStringAsFixed(2));
          final rewardAmt = -double.parse(draft.charges.abs().toStringAsFixed(2));
          breakdowns.add(PaymentBreakdown(
            paymentType: draft.paymentType.isNotEmpty ? draft.paymentType : 'Credit',
            account: finalAccount,
            otherAccountText: otherAccountText,
            amount: grossAmt,
          ));
          breakdowns.add(PaymentBreakdown(
            paymentType: 'Rewards',
            account: finalAccount,
            otherAccountText: otherAccountText,
            amount: rewardAmt,
          ));
        } else {
          breakdowns.add(PaymentBreakdown(
            paymentType: draft.paymentType,
            account: finalAccount,
            otherAccountText: otherAccountText,
            amount: draft.amount,
          ));
        }

        final tx = FinanceTransaction(
            date: draft.date,
            referenceId: draft.referenceId.isNotEmpty
                ? draft.referenceId
                : FinanceTransaction.generateReferenceId(draft.date),
            narration: draft.narration,
            flow: draft.flow,
            invoice: draft.invoice,
            purpose: draft.purpose.isNotEmpty ? draft.purpose : 'Others',
            spentFor: 'Self',
            breakdowns: breakdowns,
            totalAmount: draft.amount,
          );

        await _storage.saveTransaction(tx);
      }

      if (mounted) {
        Navigator.of(context).pop(
          BatchReviewResult(
            action: BatchReviewResultAction.savedAll,
            remainingDrafts: _drafts,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _reviewInForm([int index = 0]) {
    Navigator.of(context).pop(
      BatchReviewResult(
        action: BatchReviewResultAction.reviewInForm,
        remainingDrafts: _drafts,
        selectedIndex: index.clamp(0, _drafts.length - 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF151932) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1B2042) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF2C3360) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    const coralAccent = Color(0xFFFF5C38);
    const cyanAccent = Color(0xFF00D2B4);
    const purpleAccent = Color(0xFFA78BFA);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 12, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF261D45) : const Color(0xFFFFF1F2),
                    shape: BoxShape.circle,
                  ),
                  child: const Text('✨', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Batch Review (${_drafts.length} ${ _drafts.length == 1 ? "Item" : "Items"})',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap any row to edit in form, or tap Save All',
                        style: TextStyle(
                          fontSize: 11,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 22),
                  color: textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Summary Badges Banner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: 1.2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        'TOTAL OUT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '-₹${IndianCurrency.format(_totalOutflow)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: coralAccent,
                        ),
                      ),
                    ],
                  ),
                  Container(width: 1, height: 26, color: borderColor),
                  Column(
                    children: [
                      Text(
                        'TOTAL IN',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '+₹${IndianCurrency.format(_totalInflow)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: cyanAccent,
                        ),
                      ),
                    ],
                  ),
                  Container(width: 1, height: 26, color: borderColor),
                  Column(
                    children: [
                      Text(
                        'COUNT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_drafts.length}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Scrollable List of Draft Items
          Expanded(
            child: _drafts.isEmpty
                ? Center(
                    child: Text(
                      'All items removed',
                      style: TextStyle(color: textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: _drafts.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                    itemBuilder: (ctx, idx) {
                      final draft = _drafts[idx];
                      final isOut = draft.flow == 'Withdraw';
                      final amtColor = isOut ? coralAccent : cyanAccent;
                      final dateFormatted = DateFormat('dd-MMM-yyyy').format(draft.date);

                      return InkWell(
                        onTap: () => _reviewInForm(idx),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor, width: 1.1),
                          ),
                          child: Row(
                            children: [
                              // Direction Circle
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: amtColor.withValues(alpha: isDark ? 0.2 : 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Icon(
                                    isOut ? Icons.arrow_outward_rounded : Icons.south_west_rounded,
                                    size: 18,
                                    color: amtColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Description & details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      draft.narration,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '$dateFormatted • ${draft.paymentType} (${draft.account.isNotEmpty ? draft.account : "A/c"})',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (draft.purpose.isNotEmpty && draft.purpose != 'Others') ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Category: ${draft.purpose}',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w500,
                                          color: isDark ? purpleAccent : const Color(0xFF6366F1),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              const SizedBox(width: 8),

                              // Amount & Delete Button
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${isOut ? "-" : "+"}₹${IndianCurrency.format(draft.amount)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: amtColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _drafts.removeAt(idx);
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: coralAccent.withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Bottom Action Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: borderColor, width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _drafts.isEmpty ? null : () => _reviewInForm(0),
                      child: Text(
                        'Review in Form',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 6,
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: isDark ? purpleAccent : coralAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: (_isSaving || _drafts.isEmpty) ? null : _saveAll,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('💾', style: TextStyle(fontSize: 16)),
                                const SizedBox(width: 6),
                                Text(
                                  'Save All (${_drafts.length})',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? const Color(0xFF151932) : Colors.white,
                                  ),
                                ),
                              ],
                            ),
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
}
