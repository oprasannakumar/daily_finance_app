import 'package:flutter/material.dart';
import '../models/transaction_model.dart';
import 'calculator_keyboard_sheet.dart';
import 'popup_select_field.dart';
import 'swipe_to_delete_wrapper.dart';

class PaymentBreakdownCard extends StatefulWidget {
  final int index;
  final PaymentBreakdown breakdown;
  final List<String> availableAccounts;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final bool isOnlyMode;

  const PaymentBreakdownCard({
    super.key,
    required this.index,
    required this.breakdown,
    required this.availableAccounts,
    required this.onChanged,
    required this.onDelete,
    this.isOnlyMode = false,
  });

  @override
  State<PaymentBreakdownCard> createState() => _PaymentBreakdownCardState();
}

class _PaymentBreakdownCardState extends State<PaymentBreakdownCard> {
  late TextEditingController _amountController;
  late TextEditingController _otherAccountController;
  final Map<int, TextEditingController> _denomControllers = {};

  static const List<String> paymentTypes = [
    'Cash',
    'Credit',
    'Debit Card',
    'Net',
    'Rewards',
    'UPI',
    'Wallets',
  ];

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.breakdown.amount != 0
          ? (widget.breakdown.amount.truncateToDouble() == widget.breakdown.amount
              ? widget.breakdown.amount.toInt().toString()
              : widget.breakdown.amount.toStringAsFixed(2))
          : '',
    );
    _otherAccountController = TextEditingController(
      text: widget.breakdown.otherAccountText ?? '',
    );

    for (final denom in PaymentBreakdown.supportedDenominations) {
      final count = widget.breakdown.denominations[denom] ?? 0;
      _denomControllers[denom] = TextEditingController(
        text: count != 0 ? count.toString() : '',
      );
    }
  }

  @override
  void didUpdateWidget(covariant PaymentBreakdownCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.breakdown.paymentType == 'Cash') {
      final currentTotal = widget.breakdown.calculatedCashAmount;
      final expectedText = currentTotal.toStringAsFixed(2);
      if (_amountController.text != expectedText) {
        _amountController.text = expectedText;
      }
    } else {
      final currentVal = double.tryParse(_amountController.text) ?? 0.0;
      if ((currentVal - widget.breakdown.amount).abs() > 0.001) {
        if (widget.breakdown.amount != 0) {
          _amountController.text = widget.breakdown.amount.truncateToDouble() == widget.breakdown.amount
              ? widget.breakdown.amount.toInt().toString()
              : widget.breakdown.amount.toStringAsFixed(2);
        } else {
          _amountController.text = '';
        }
      }
    }
    if (_otherAccountController.text != (widget.breakdown.otherAccountText ?? '')) {
      _otherAccountController.text = widget.breakdown.otherAccountText ?? '';
    }
    for (final denom in PaymentBreakdown.supportedDenominations) {
      final count = widget.breakdown.denominations[denom] ?? 0;
      final currentText = _denomControllers[denom]?.text ?? '';
      if (currentText == '-' && count == 0) continue;
      final currentInt = int.tryParse(currentText) ?? 0;
      if (currentInt == count && currentText.isNotEmpty) continue;
      if (count == 0 && currentText.isEmpty) continue;
      final expectedStr = count != 0 ? count.toString() : '';
      if (currentText != expectedStr) {
        _denomControllers[denom]?.text = expectedStr;
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _otherAccountController.dispose();
    for (final ctrl in _denomControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _onDenominationChanged(int denom, int newCount) {
    setState(() {
      widget.breakdown.denominations[denom] = newCount;
      widget.breakdown.recalculateCashAmount();
      _amountController.text = widget.breakdown.amount.toStringAsFixed(2);
    });
    widget.onChanged();
  }

  Future<void> _openCalculator() async {
    FocusScope.of(context).unfocus();
    final result = await CalculatorKeyboardSheet.show(
      context,
      initialAmount: widget.breakdown.amount,
    );
    if (result != null) {
      setState(() {
        widget.breakdown.amount = result;
        _amountController.text = (result == result.roundToDouble())
            ? result.toInt().toString()
            : result.toStringAsFixed(2);
      });
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final type = widget.breakdown.paymentType;
    final isCash = type == 'Cash';
    final hasType = type != null && type.isNotEmpty;
    final showAccount = hasType && !isCash;
    final isOtherAccount = widget.breakdown.account == 'Other';

    final Color amtFillColor = isDark
        ? (isCash ? const Color(0xFF112E2D) : const Color(0xFF1B2042))
        : (isCash ? const Color(0xFFF0FDF4) : Colors.white);
    final Color amtBorderColor = isDark ? const Color(0xFF2C3360) : const Color(0xFFCBD5E1);
    final Color amtTextColor = isDark
        ? (isCash ? const Color(0xFF00E5BE) : const Color(0xFFF1F5F9))
        : (isCash ? const Color(0xFF0F766E) : const Color(0xFF1E293B));

    return SwipeToDeleteWrapper(
      key: ValueKey(widget.breakdown.id),
      enabled: !widget.isOnlyMode,
      borderRadius: BorderRadius.circular(12),
      margin: const EdgeInsets.symmetric(vertical: 3),
      backgroundBorder: Border.all(color: amtBorderColor, width: 1.2),
      onDelete: widget.onDelete,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              // Exact matching 46px height row for Type, Account, and Amount
              SizedBox(
                height: 46,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  // Type Popup Selector (No default value, displays "Select" initially)
                  Expanded(
                    flex: showAccount ? 5 : (isCash ? 6 : 7),
                    child: PopupSelectField(
                      key: ValueKey('type_${widget.breakdown.id}_$type'),
                      label: 'Type',
                      placeholder: 'Select',
                      items: paymentTypes,
                      selectedValue: (type?.toUpperCase() == 'CREDIT' || type == 'Credit Card')
                          ? 'Credit'
                          : ((type?.toUpperCase() == 'REWARDS')
                              ? 'Rewards'
                              : ((type == 'Debit' || type == 'DEBIT') ? 'Debit Card' : type)),
                      validator: (val) => (val == null || val.isEmpty) ? 'Select Type' : null,
                      onSelected: (newType) {
                        setState(() {
                          widget.breakdown.paymentType = newType;
                          if (newType == 'Cash') {
                            widget.breakdown.account = null;
                            widget.breakdown.recalculateCashAmount();
                            _amountController.text = widget.breakdown.amount.toStringAsFixed(2);
                          } else {
                            // Reset account to null so user must explicitly select
                            widget.breakdown.account = null;
                          }
                        });
                        widget.onChanged();
                      },
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Account Popup Selector (Shown for non-cash modes, displays "Select" initially)
                  if (showAccount) ...[
                    Expanded(
                      flex: 6,
                      child: PopupSelectField(
                        key: ValueKey('acc_${widget.breakdown.id}_${type}_${widget.breakdown.account}'),
                        label: 'Account',
                        placeholder: 'Select',
                        items: widget.availableAccounts,
                        selectedValue: widget.breakdown.account,
                        validator: (val) => (val == null || val.isEmpty) ? 'Select Account' : null,
                        onSelected: (acc) {
                          setState(() {
                            widget.breakdown.account = acc;
                          });
                          widget.onChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],

                  // Amount block (Matching exact 46px height, identical to Type and Account)
                  SizedBox(
                    width: isCash ? 100 : 92,
                    height: 46,
                    child: InkWell(
                      onTap: isCash ? null : _openCalculator,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: amtFillColor,
                          constraints: const BoxConstraints(minHeight: 46, maxHeight: 46),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: amtBorderColor, width: 1.2),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: amtBorderColor, width: 1.2),
                          ),
                        ),
                        child: Text(
                          _amountController.text.isNotEmpty && _amountController.text != '0' && _amountController.text != '0.00'
                              ? (_amountController.text.startsWith('-')
                                  ? '-₹ ${_amountController.text.substring(1).trim()}'
                                  : '₹ ${_amountController.text}')
                              : (isCash ? '₹ 0.00' : 'Amt'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.15,
                            fontWeight: FontWeight.bold,
                            color: amtTextColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // If 'Other' is selected in Account: show small custom text box in next row (46px height)
            if (showAccount && isOtherAccount) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 46,
                child: TextFormField(
                  controller: _otherAccountController,
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white : const Color(0xFF1E293B)),
                  decoration: InputDecoration(
                    labelText: 'Enter Custom Account Name',
                    labelStyle: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                    isDense: true,
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1B2042) : Colors.white,
                    constraints: const BoxConstraints(minHeight: 46, maxHeight: 46),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: amtBorderColor, width: 1.2),
                    ),
                  ),
                  onChanged: (val) {
                    widget.breakdown.otherAccountText = val;
                    widget.onChanged();
                  },
                ),
              ),
            ],

            // Cash: EXACT 3x3 Grid design matching reference image
            if (isCash) ...[
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final totalNotesCount = widget.breakdown.denominations.values
                      .fold<int>(0, (sum, count) => sum + count.abs());

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF151932) : const Color(0xFFFAF7F2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? const Color(0xFF2C3360) : const Color(0xFFEBE3D5),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00D2B4).withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.payments_rounded,
                                    size: 14,
                                    color: Color(0xFF00D2B4),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'CASH DENOMINATIONS',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                            if (totalNotesCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00D2B4).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF00D2B4).withValues(alpha: 0.35),
                                    width: 1.0,
                                  ),
                                ),
                                child: Text(
                                  '$totalNotesCount ${totalNotesCount == 1 ? 'note' : 'notes'}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF00D2B4),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 5,
                            crossAxisSpacing: 5,
                            childAspectRatio: 1.75,
                          ),
                          itemCount: PaymentBreakdown.supportedDenominations.length,
                          itemBuilder: (context, idx) {
                            final denom = PaymentBreakdown.supportedDenominations[idx];
                            final count = widget.breakdown.denominations[denom] ?? 0;
                            final hasValue = count != 0;

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? (hasValue ? const Color(0xFF1E284A) : const Color(0xFF1B2042))
                                    : (hasValue ? const Color(0xFFF0FDF4) : Colors.white),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: hasValue
                                      ? (isDark ? const Color(0xFF00D2B4) : const Color(0xFF10B981))
                                      : (isDark ? const Color(0xFF282F5A) : const Color(0xFFE2E8F0)),
                                  width: hasValue ? 1.3 : 0.9,
                                ),
                                boxShadow: hasValue
                                    ? [
                                        BoxShadow(
                                          color: (isDark ? const Color(0xFF00D2B4) : const Color(0xFF10B981))
                                              .withValues(alpha: isDark ? 0.20 : 0.10),
                                          blurRadius: 3,
                                          offset: const Offset(0, 1),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: hasValue
                                          ? (isDark
                                              ? const Color(0xFF00D2B4).withValues(alpha: 0.2)
                                              : const Color(0xFF10B981).withValues(alpha: 0.12))
                                          : (isDark
                                              ? Colors.white.withValues(alpha: 0.06)
                                              : const Color(0xFFF1F5F9)),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      '₹$denom',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: hasValue
                                            ? (isDark ? const Color(0xFF00D2B4) : const Color(0xFF059669))
                                            : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  SizedBox(
                                    height: 22,
                                    child: TextField(
                                      controller: _denomControllers[denom],
                                      keyboardType: const TextInputType.numberWithOptions(signed: true),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                                      ),
                                      decoration: InputDecoration(
                                        hintText: '0',
                                        hintStyle: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                        ),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      onChanged: (val) {
                                        final trimmed = val.trim();
                                        if (trimmed == '-' || trimmed.isEmpty) {
                                          widget.breakdown.denominations[denom] = 0;
                                          widget.breakdown.recalculateCashAmount();
                                          _amountController.text = widget.breakdown.amount.toStringAsFixed(2);
                                          widget.onChanged();
                                          return;
                                        }
                                        final parsed = int.tryParse(trimmed);
                                        if (parsed != null) {
                                          _onDenominationChanged(denom, parsed);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
