import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../utils/currency_formatter.dart';

/// Modal dialog displaying full Transaction Details matching media_1794925377895_6e40cb46.png
class TransactionDetailsDialog extends StatelessWidget {
  final FinanceTransaction tx;

  const TransactionDetailsDialog({super.key, required this.tx});

  static Future<void> show(BuildContext context, FinanceTransaction tx) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => TransactionDetailsDialog(tx: tx),
    );
  }

  Widget _buildRow(String label, String value, Color textPrimary, Color textSecondary) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: textSecondary),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF151932) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF262C54) : const Color(0xFFF1E5DC);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    const coralAccent = Color(0xFFFF5C38);
    const cyanAccent = Color(0xFF00D2B4);

    double personalShareAmt = 0.0;
    if (tx.splitRecipients != null) {
      for (final r in tx.splitRecipients!) {
        if (r.isPersonal) personalShareAmt += r.amount;
      }
    }

    final isTransfer = tx.isSelfTransfer || tx.flow == 'Transfer';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 720),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: 📄 Transaction Details + ✕ Close
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 6),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, color: Color(0xFF38BDF8), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Transaction Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: textSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(color: isDark ? const Color(0xFF262C54) : const Color(0xFFF1E5DC), height: 1),

            // Details Content (Flexible so height auto-adjusts to data)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildRow('Date', DateFormat('dd-MMM-yyyy').format(tx.date), textPrimary, textSecondary),
                  _buildRow('Narration', tx.narration.isNotEmpty ? tx.narration : '-', textPrimary, textSecondary),
                  _buildRow('Invoice No.', tx.invoice.isNotEmpty ? tx.invoice : '-', textPrimary, textSecondary),
                  _buildRow('Ref', tx.referenceId, textPrimary, textSecondary),
                  if (!isTransfer) ...[
                    _buildRow('Purpose', tx.purpose.isNotEmpty ? tx.purpose : '-', textPrimary, textSecondary),
                    _buildRow('Spent For', tx.spentFor.isNotEmpty ? tx.spentFor : '-', textPrimary, textSecondary),
                    _buildRow('Flow', tx.flow.toLowerCase(), textPrimary, textSecondary),
                    _buildRow('Split Mode', tx.isSplitMode ? 'Enabled' : 'Disabled', textPrimary, textSecondary),
                    if (tx.isSplitMode && personalShareAmt > 0)
                      _buildRow('Personal Share', '₹${IndianCurrency.format(personalShareAmt)}', textPrimary, textSecondary),
                  ] else ...[
                    _buildRow('Flow', 'transfer', textPrimary, textSecondary),
                  ],

                  // Recipients Section (underlined coral header)
                  () {
                    final visibleSplits = (tx.splitRecipients ?? [])
                        .where((r) => !((r.isPersonal || r.name.trim().toLowerCase() == 'personal share') && r.amount <= 0))
                        .toList();
                    if (isTransfer || visibleSplits.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        const Text(
                          'Recipients',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: coralAccent,
                            decoration: TextDecoration.underline,
                            decorationColor: coralAccent,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...visibleSplits.map((r) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(r.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                                  Text('₹${IndianCurrency.format(r.amount)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary)),
                                ],
                              ),
                            )),
                      ],
                    );
                  }(),

                  // Payments Section (underlined coral header)
                  const SizedBox(height: 12),
                  Text(
                    isTransfer ? 'From (Sources)' : 'Payments',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: coralAccent,
                      decoration: TextDecoration.underline,
                      decorationColor: coralAccent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...tx.breakdowns.map((b) {
                    final desc = b.effectiveAccount.isNotEmpty
                        ? '${b.paymentType} (${b.effectiveAccount})'
                        : (b.paymentType ?? 'Payment');
                    final isCash = b.paymentType == 'Cash';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(desc, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                              Text(
                                b.amount < 0
                                    ? '-₹${IndianCurrency.format(b.amount.abs())}'
                                    : '₹${IndianCurrency.format(b.amount)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: b.amount < 0 ? const Color(0xFFEF4444) : textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isCash) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1B2042) : const Color(0xFFFFFDF8),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? const Color(0xFF2C3360) : const Color(0xFFF1E5DC),
                              ),
                            ),
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 4,
                                crossAxisSpacing: 4,
                                childAspectRatio: 2.3,
                              ),
                              itemCount: PaymentBreakdown.supportedDenominations.length,
                              itemBuilder: (context, idx) {
                                final denom = PaymentBreakdown.supportedDenominations[idx];
                                final count = b.denominations[denom] ?? 0;
                                return Container(
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF151932) : Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF262C54) : const Color(0xFFE2E8F0),
                                      width: 0.8,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Text(
                                        '₹$denom',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                          color: textSecondary,
                                        ),
                                      ),
                                      Text(
                                        '$count',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: count != 0
                                              ? (count < 0 ? coralAccent : textPrimary)
                                              : textSecondary.withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ],
                    );
                  }),

                  // To Destinations (if Transfer)
                  if (isTransfer && tx.toBreakdowns != null && tx.toBreakdowns!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'To (Destinations)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: cyanAccent,
                        decoration: TextDecoration.underline,
                        decorationColor: cyanAccent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...tx.toBreakdowns!.map((b) {
                      final desc = b.effectiveAccount.isNotEmpty
                          ? '${b.paymentType} (${b.effectiveAccount})'
                          : (b.paymentType ?? 'Payment');
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(desc, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                            Text('₹${IndianCurrency.format(b.amount)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary)),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),

            // Footer Total
            Divider(color: isDark ? const Color(0xFF262C54) : const Color(0xFFF1E5DC), height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Amount',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: coralAccent,
                    ),
                  ),
                  Text(
                    '₹${IndianCurrency.format(tx.totalAmount)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: coralAccent,
                    ),
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
