import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/emi_plan_model.dart';
import '../models/transaction_model.dart';
import '../services/google_sheets_service.dart';
import '../utils/currency_formatter.dart';

class EmiConversionSheet extends StatefulWidget {
  final FinanceTransaction? transaction;
  final EmiPlan? existingPlan;

  const EmiConversionSheet({
    super.key,
    this.transaction,
    this.existingPlan,
  });

  static Future<EmiPlan?> show(
    BuildContext context, {
    FinanceTransaction? transaction,
    EmiPlan? existingPlan,
  }) {
    return showModalBottomSheet<EmiPlan>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EmiConversionSheet(
        transaction: transaction,
        existingPlan: existingPlan,
      ),
    );
  }

  @override
  State<EmiConversionSheet> createState() => _EmiConversionSheetState();
}

class _EmiConversionSheetState extends State<EmiConversionSheet> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _accountController;
  late TextEditingController _totalAmountController;
  late TextEditingController _bookingPrincipalController;
  late TextEditingController _roiController;
  late TextEditingController _tenureController;
  late TextEditingController _processingFeeController;
  late TextEditingController _processingFeeGstController;
  late TextEditingController _notesController;

  late DateTime _transactionDate;
  late DateTime _firstEmiDate;
  bool _isPartialConversion = false;
  bool _isSaving = false;

  List<EmiInstallment> _installments = [];

  final List<int> _commonTenures = [3, 6, 9, 12, 18, 24, 36];

  @override
  void initState() {
    super.initState();

    final tx = widget.transaction;
    final plan = widget.existingPlan;

    if (plan != null) {
      _titleController = TextEditingController(text: plan.title);
      _accountController = TextEditingController(text: plan.account);
      _totalAmountController = TextEditingController(text: plan.totalTransactionAmount.toStringAsFixed(2));
      _bookingPrincipalController = TextEditingController(text: plan.bookingPrincipal.toStringAsFixed(2));
      _roiController = TextEditingController(text: plan.annualInterestRate.toStringAsFixed(2));
      _tenureController = TextEditingController(text: plan.tenureMonths.toString());
      _processingFeeController = TextEditingController(text: plan.processingFee.toStringAsFixed(2));
      _processingFeeGstController = TextEditingController(text: plan.processingFeeGst.toStringAsFixed(2));
      _notesController = TextEditingController(text: plan.notes ?? '');
      _transactionDate = plan.transactionDate;
      _firstEmiDate = plan.firstEmiDate;
      _isPartialConversion = plan.isPartialConversion;
      _installments = plan.installments.map((it) => it.copyWith()).toList();
    } else if (tx != null) {
      final title = tx.narration.isNotEmpty ? tx.narration : 'Credit Card EMI';
      final account = tx.fromSummary.isNotEmpty ? tx.fromSummary : 'Credit Card';
      final total = tx.totalAmount;

      _titleController = TextEditingController(text: title);
      _accountController = TextEditingController(text: account);
      _totalAmountController = TextEditingController(text: total.toStringAsFixed(2));
      _bookingPrincipalController = TextEditingController(text: total.toStringAsFixed(2));
      _roiController = TextEditingController(text: '17.0');
      _tenureController = TextEditingController(text: '6');
      _processingFeeController = TextEditingController(text: '45.00');
      _processingFeeGstController = TextEditingController(text: '8.10');
      _notesController = TextEditingController(text: 'Converted from Tx: ${tx.referenceId}');
      _transactionDate = tx.date;
      _firstEmiDate = EmiPlan.addMonthsClamped(tx.date, 1);
      _isPartialConversion = false;
      _recalculateMathematicalSchedule();
    } else {
      _titleController = TextEditingController(text: 'Credit Card EMI');
      _accountController = TextEditingController(text: 'Credit Card');
      _totalAmountController = TextEditingController(text: '10000.00');
      _bookingPrincipalController = TextEditingController(text: '10000.00');
      _roiController = TextEditingController(text: '17.0');
      _tenureController = TextEditingController(text: '6');
      _processingFeeController = TextEditingController(text: '45.00');
      _processingFeeGstController = TextEditingController(text: '8.10');
      _notesController = TextEditingController();
      _transactionDate = DateTime.now();
      _firstEmiDate = EmiPlan.addMonthsClamped(DateTime.now(), 1);
      _isPartialConversion = false;
      _recalculateMathematicalSchedule();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _accountController.dispose();
    _totalAmountController.dispose();
    _bookingPrincipalController.dispose();
    _roiController.dispose();
    _tenureController.dispose();
    _processingFeeController.dispose();
    _processingFeeGstController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _totalTxAmount => double.tryParse(_totalAmountController.text.trim()) ?? 0.0;
  double get _bookingPrincipal {
    if (!_isPartialConversion) return _totalTxAmount;
    return double.tryParse(_bookingPrincipalController.text.trim()) ?? _totalTxAmount;
  }
  double get _nonEmiBalance => (_totalTxAmount - _bookingPrincipal).clamp(0.0, double.infinity);
  double get _roi => double.tryParse(_roiController.text.trim()) ?? 17.0;
  int get _tenure => int.tryParse(_tenureController.text.trim()) ?? 6;
  double get _processingFee => double.tryParse(_processingFeeController.text.trim()) ?? 0.0;
  double get _processingFeeGst => double.tryParse(_processingFeeGstController.text.trim()) ?? 0.0;

  void _recalculateMathematicalSchedule() {
    final principal = _bookingPrincipal;
    if (principal <= 0 || _tenure <= 0) {
      setState(() => _installments = []);
      return;
    }

    final newSchedule = EmiPlan.calculateSchedule(
      principal: principal,
      annualInterestRate: _roi,
      tenureMonths: _tenure,
      firstEmiDate: _firstEmiDate,
    );

    setState(() {
      _installments = newSchedule;
    });
  }

  void _onFeeChanged(String val) {
    final fee = double.tryParse(val.trim()) ?? 0.0;
    final gst = fee * 0.18;
    _processingFeeGstController.text = gst.toStringAsFixed(2);
    setState(() {});
  }

  Future<void> _pickDate({required bool isTxDate}) async {
    final initial = isTxDate ? _transactionDate : _firstEmiDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (picked != null) {
      setState(() {
        if (isTxDate) {
          _transactionDate = picked;
        } else {
          _firstEmiDate = picked;
          _recalculateMathematicalSchedule();
        }
      });
    }
  }

  void _editInstallment(int index) {
    final inst = _installments[index];
    final dateCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd').format(inst.billingDate));
    final emiCtrl = TextEditingController(text: inst.emiAmount.toStringAsFixed(2));
    final principalCtrl = TextEditingController(text: inst.principal.toStringAsFixed(2));
    final interestCtrl = TextEditingController(text: inst.interest.toStringAsFixed(2));
    final taxCtrl = TextEditingController(text: inst.applicableTaxes.toStringAsFixed(2));

    DateTime editDate = inst.billingDate;

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E2240) : Colors.white,
              title: Text('Edit Installment #${inst.installmentNumber}',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Billing Date', style: TextStyle(fontSize: 13, color: Colors.grey)),
                      subtitle: Text(DateFormat('dd/MM/yyyy').format(editDate),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      trailing: const Icon(Icons.calendar_month, color: Color(0xFFFF5C38)),
                      onTap: () async {
                        final p = await showDatePicker(
                          context: ctx,
                          initialDate: editDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2040),
                        );
                        if (p != null) {
                          setDlgState(() {
                            editDate = p;
                            dateCtrl.text = DateFormat('yyyy-MM-dd').format(p);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emiCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'EMI / MRA (₹)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: principalCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Principal Portion (₹)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: interestCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Interest Portion (₹)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        final iVal = double.tryParse(val) ?? 0.0;
                        taxCtrl.text = (iVal * 0.18).toStringAsFixed(2);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: taxCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Applicable Tax / GST (₹)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5C38)),
                  onPressed: () {
                    final newEmi = double.tryParse(emiCtrl.text.trim()) ?? inst.emiAmount;
                    final newPrincipal = double.tryParse(principalCtrl.text.trim()) ?? inst.principal;
                    final newInterest = double.tryParse(interestCtrl.text.trim()) ?? inst.interest;
                    final newTax = double.tryParse(taxCtrl.text.trim()) ?? inst.applicableTaxes;

                    setState(() {
                      _installments[index] = inst.copyWith(
                        billingDate: editDate,
                        emiAmount: newEmi,
                        principal: newPrincipal,
                        interest: newInterest,
                        applicableTaxes: newTax,
                      );
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Apply', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _savePlan() async {
    if (!_formKey.currentState!.validate()) return;

    if (_installments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please generate or provide an EMI schedule before saving.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final planId = widget.existingPlan?.id ?? 'EMI-${DateTime.now().millisecondsSinceEpoch}';
      final plan = EmiPlan(
        id: planId,
        title: _titleController.text.trim(),
        account: _accountController.text.trim(),
        transactionDate: _transactionDate,
        totalTransactionAmount: _totalTxAmount,
        bookingPrincipal: _bookingPrincipal,
        annualInterestRate: _roi,
        tenureMonths: _tenure,
        processingFee: _processingFee,
        processingFeeGst: _processingFeeGst,
        firstEmiDate: _firstEmiDate,
        installments: _installments,
        status: widget.existingPlan?.status ?? 'ACTIVE',
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      );

      await GoogleSheetsService.instance.saveEmiPlan(plan);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF00B074),
            content: Text('EMI plan "${plan.title}" saved successfully!'),
          ),
        );
        Navigator.of(context).pop(plan);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving EMI plan: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF13172E) : const Color(0xFFF8F9FA);
    final cardBg = isDark ? const Color(0xFF1B203D) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2C3258) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    const coral = Color(0xFFFF5C38);
    const teal = Color(0xFF00B074);

    final totalInterest = _installments.fold(0.0, (sum, it) => sum + it.interest);
    final totalGst = _installments.fold(0.0, (sum, it) => sum + it.applicableTaxes) + _processingFeeGst;
    final totalRepayable = _installments.fold(0.0, (sum, it) => sum + it.totalDueWithTax) + _processingFee + _processingFeeGst;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: coral.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.credit_card_outlined, color: coral, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.existingPlan != null ? 'Edit Credit Card EMI' : 'Credit Card EMI Conversion',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: textPrimary),
                      ),
                      Text(
                        'Amortization schedule & bank fee customization',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Form Body
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // Plan Title & Account
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _titleController,
                          style: TextStyle(color: textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'EMI Plan Title',
                            hintText: 'e.g. HP Victus Laptop',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: cardBg,
                            isDense: true,
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _accountController,
                          style: TextStyle(color: textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Card / Account',
                            hintText: 'Credit Card',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: cardBg,
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Dates Row
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _pickDate(isTxDate: true),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: cardBg,
                              border: Border.all(color: borderColor),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.event, size: 18, color: coral),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Tx Date', style: TextStyle(fontSize: 10, color: textSecondary)),
                                    Text(DateFormat('dd/MM/yyyy').format(_transactionDate),
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () => _pickDate(isTxDate: false),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: cardBg,
                              border: Border.all(color: borderColor),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 18, color: teal),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('First EMI Date', style: TextStyle(fontSize: 10, color: textSecondary)),
                                    Text(DateFormat('dd/MM/yyyy').format(_firstEmiDate),
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Swipe Amount & Partial Conversion Toggle Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      border: Border.all(color: borderColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _totalAmountController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: TextStyle(color: textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  labelText: 'Total Swipe Amount (₹)',
                                  prefixIcon: const Icon(Icons.currency_rupee, size: 18),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  isDense: true,
                                ),
                                onChanged: (v) {
                                  if (!_isPartialConversion) {
                                    _bookingPrincipalController.text = v;
                                  }
                                  _recalculateMathematicalSchedule();
                                },
                                validator: (v) {
                                  final num = double.tryParse(v?.trim() ?? '');
                                  if (num == null || num <= 0) return 'Enter valid amount';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Switch for partial conversion
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Partial Conversion',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary)),
                                Text('Only convert a portion into EMI',
                                    style: TextStyle(fontSize: 11, color: textSecondary)),
                              ],
                            ),
                            Switch(
                              value: _isPartialConversion,
                              activeThumbColor: coral,
                              onChanged: (val) {
                                setState(() {
                                  _isPartialConversion = val;
                                  if (!val) {
                                    _bookingPrincipalController.text = _totalAmountController.text;
                                  }
                                  _recalculateMathematicalSchedule();
                                });
                              },
                            ),
                          ],
                        ),

                        if (_isPartialConversion) ...[
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _bookingPrincipalController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              labelText: 'Booking Principal (Converted to EMI) (₹)',
                              prefixIcon: const Icon(Icons.pie_chart, size: 18, color: coral),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                            onChanged: (_) => _recalculateMathematicalSchedule(),
                            validator: (v) {
                              if (!_isPartialConversion) return null;
                              final val = double.tryParse(v?.trim() ?? '');
                              if (val == null || val <= 0) return 'Enter booking principal';
                              if (val > _totalTxAmount) return 'Cannot exceed total swipe amount';
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, size: 16, color: Colors.amber),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Non-EMI Balance: ₹${IndianCurrency.formatSmart(_nonEmiBalance)} (due on immediate statement)',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.amber),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Tenure Selector Chips
                  Text('Tenure (Months)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _commonTenures.map((m) {
                        final isSel = _tenure == m;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('$m M'),
                            selected: isSel,
                            selectedColor: coral,
                            labelStyle: TextStyle(
                              color: isSel ? Colors.white : textPrimary,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              fontSize: 12,
                            ),
                            onSelected: (_) {
                              setState(() {
                                _tenureController.text = m.toString();
                                _recalculateMathematicalSchedule();
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ROI & Processing Fee Row
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _roiController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(color: textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Interest Rate (% p.a.)',
                            suffixText: '%',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: cardBg,
                            isDense: true,
                          ),
                          onChanged: (_) => _recalculateMathematicalSchedule(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _processingFeeController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(color: textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Proc. Fee (₹)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: cardBg,
                            isDense: true,
                          ),
                          onChanged: _onFeeChanged,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _processingFeeGstController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(color: textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Fee GST 18%',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: cardBg,
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Financial Summary KPI Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF261E38), const Color(0xFF1E2648)]
                            : [const Color(0xFFFFF5F2), const Color(0xFFF0FDF4)],
                      ),
                      border: Border.all(color: borderColor),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Booking Principal', style: TextStyle(fontSize: 11, color: textSecondary)),
                                Text('₹${IndianCurrency.formatSmart(_bookingPrincipal)}',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('Total Repayable', style: TextStyle(fontSize: 11, color: textSecondary)),
                                Text('₹${IndianCurrency.formatSmart(totalRepayable)}',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: coral)),
                              ],
                            ),
                          ],
                        ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total Interest: ₹${IndianCurrency.formatSmart(totalInterest)}',
                                style: TextStyle(fontSize: 11.5, color: textSecondary)),
                            Text('GST (18%): ₹${IndianCurrency.formatSmart(totalGst)}',
                                style: TextStyle(fontSize: 11.5, color: textSecondary)),
                            Text('Fee: ₹${IndianCurrency.formatSmart(_processingFee + _processingFeeGst)}',
                                style: TextStyle(fontSize: 11.5, color: textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Amortization Schedule Header with Manual Edit Notice
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Amortization Schedule',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textPrimary)),
                          Text('Tap any row to edit bank-exact amounts or dates',
                              style: TextStyle(fontSize: 11, color: textSecondary)),
                        ],
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.refresh, size: 16, color: coral),
                        label: const Text('Reset', style: TextStyle(fontSize: 12, color: coral)),
                        onPressed: _recalculateMathematicalSchedule,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Schedule List
                  if (_installments.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      alignment: Alignment.center,
                      child: Text('No schedule available. Enter valid amount and tenure.',
                          style: TextStyle(color: textSecondary, fontSize: 13)),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        border: Border.all(color: borderColor),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          // Table Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(width: 24, child: Text('#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                Expanded(flex: 3, child: Text('Due Date', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                Expanded(flex: 3, child: Text('MRA (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                Expanded(flex: 3, child: Text('Principal', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Text('Int+Tax', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                SizedBox(width: 28),
                              ],
                            ),
                          ),
                          const Divider(height: 1),

                          // Table Rows
                          ..._installments.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final it = entry.value;
                            return InkWell(
                              onTap: () => _editInstallment(idx),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                decoration: BoxDecoration(
                                  border: idx < _installments.length - 1
                                      ? Border(bottom: BorderSide(color: borderColor.withValues(alpha: 0.6)))
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      child: Text('${it.installmentNumber}',
                                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textSecondary)),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(DateFormat('dd/MM/yyyy').format(it.billingDate),
                                          style: TextStyle(fontSize: 12, color: textPrimary)),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text('₹${IndianCurrency.formatSmart(it.emiAmount)}',
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: coral)),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text('₹${IndianCurrency.formatSmart(it.principal)}',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(fontSize: 11.5, color: textSecondary)),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text('₹${IndianCurrency.formatSmart(it.interest + it.applicableTaxes)}',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(fontSize: 11, color: textSecondary)),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),

                  // Notes
                  TextFormField(
                    controller: _notesController,
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Notes / Reference',
                      hintText: 'e.g. HP Victus 6-month no-cost EMI / bank offer',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: cardBg,
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cardBg,
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Cancel', style: TextStyle(color: textPrimary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _savePlan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: coral,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isSaving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(widget.existingPlan != null ? 'Update EMI Plan' : 'Save EMI Plan',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
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
