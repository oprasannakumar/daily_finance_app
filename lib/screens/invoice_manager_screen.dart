import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/invoice_model.dart';
import '../services/google_sheets_service.dart';
import '../services/storage_service.dart';

class InvoiceManagerScreen extends StatefulWidget {
  final DateTime? initialDate;
  final Function(InvoiceSummary selectedInvoice)? onInvoiceSelected;

  const InvoiceManagerScreen({
    super.key,
    this.initialDate,
    this.onInvoiceSelected,
  });

  @override
  State<InvoiceManagerScreen> createState() => _InvoiceManagerScreenState();
}

class _InvoiceRecipientDraft {
  String recipient;
  List<_InvoiceItemDraft> items;

  _InvoiceRecipientDraft({
    required this.recipient,
    required this.items,
  });

  double get subtotal => items.fold(0.0, (sum, it) => sum + it.total);
}

class _InvoiceItemDraft {
  final TextEditingController nameController;
  final TextEditingController qtyController;
  final TextEditingController priceController;
  final TextEditingController totalController;

  _InvoiceItemDraft({
    String name = '',
    double qty = 1.0,
    double price = 0.0,
    double? total,
  })  : nameController = TextEditingController(text: name),
        qtyController = TextEditingController(text: qty > 0 ? (qty == qty.toInt() ? qty.toInt().toString() : qty.toString()) : '1'),
        priceController = TextEditingController(text: price > 0 ? price.toStringAsFixed(2) : ''),
        totalController = TextEditingController(text: (total ?? (qty * price)) > 0 ? (total ?? (qty * price)).toStringAsFixed(2) : '') {
    qtyController.addListener(_onQtyOrPriceChanged);
    priceController.addListener(_onQtyOrPriceChanged);
  }

  bool _internalUpdating = false;

  void _onQtyOrPriceChanged() {
    if (_internalUpdating) return;
    _internalUpdating = true;
    final q = double.tryParse(qtyController.text.trim()) ?? 0.0;
    final p = double.tryParse(priceController.text.trim()) ?? 0.0;
    final tot = q * p;
    totalController.text = tot > 0 ? tot.toStringAsFixed(2) : '0.00';
    _internalUpdating = false;
  }

  void onTotalManualChanged(String val) {
    if (_internalUpdating) return;
    _internalUpdating = true;
    final tot = double.tryParse(val.trim()) ?? 0.0;
    final q = double.tryParse(qtyController.text.trim()) ?? 1.0;
    if (q > 0) {
      final p = tot / q;
      priceController.text = p.toStringAsFixed(2);
    }
    _internalUpdating = false;
  }

  String get itemName => nameController.text.trim();
  double get quantity => double.tryParse(qtyController.text.trim()) ?? 1.0;
  double get price => double.tryParse(priceController.text.trim()) ?? 0.0;
  double get total => double.tryParse(totalController.text.trim()) ?? (quantity * price);

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    priceController.dispose();
    totalController.dispose();
  }
}

class SearchableDropdownField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? icon;
  final String hintText;
  final List<String> options;
  final ValueChanged<String>? onSelected;
  final ValueChanged<String>? onChanged;
  final bool isDark;
  final Color primaryColor;
  final Color borderColor;
  final Color inputBg;
  final Map<String, double>? priceMap;

  const SearchableDropdownField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    required this.hintText,
    required this.options,
    this.onSelected,
    this.onChanged,
    required this.isDark,
    required this.primaryColor,
    required this.borderColor,
    required this.inputBg,
    this.priceMap,
  });

  @override
  State<SearchableDropdownField> createState() => _SearchableDropdownFieldState();
}

class _SearchableDropdownFieldState extends State<SearchableDropdownField> {
  final FocusNode _focusNode = FocusNode();
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() => _isOpen = true);
      } else {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted && !_focusNode.hasFocus) {
            setState(() => _isOpen = false);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textLabel = widget.isDark ? const Color(0xFFA89BB8) : const Color(0xFF6B5E7E);
    final textMain = widget.isDark ? const Color(0xFFF0E8F0) : const Color(0xFF2D2A3E);
    final cardBg = widget.isDark ? const Color(0xFF16213E) : Colors.white;

    final filterText = widget.controller.text.trim().toLowerCase();
    final matchingOptions = widget.options.where((opt) {
      if (filterText.isEmpty) return true;
      return opt.toLowerCase().contains(filterText);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label.isNotEmpty) ...[
          Row(
            children: [
              if (widget.icon != null) ...[
                Text(widget.icon!, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
              ],
              Text(
                widget.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: textLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        Container(
          height: 46,
          decoration: BoxDecoration(
            color: widget.inputBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isOpen ? widget.primaryColor : widget.borderColor,
              width: _isOpen ? 1.6 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: textMain,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: textLabel.withValues(alpha: 0.7),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: InputBorder.none,
                  ),
                  onTap: () {
                    setState(() => _isOpen = true);
                  },
                  onChanged: (val) {
                    setState(() => _isOpen = true);
                    widget.onChanged?.call(val);
                  },
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  setState(() => _isOpen = !_isOpen);
                  if (_isOpen && !_focusNode.hasFocus) {
                    _focusNode.requestFocus();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Icon(
                    _isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: textLabel,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isOpen && matchingOptions.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 190),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: widget.borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: widget.isDark ? 0.35 : 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Scrollbar(
                thumbVisibility: matchingOptions.length > 4,
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: matchingOptions.length,
                  separatorBuilder: (_, index) => Divider(
                    height: 1,
                    thickness: 1,
                    color: widget.borderColor.withValues(alpha: 0.8),
                  ),
                  itemBuilder: (ctx, idx) {
                    final opt = matchingOptions[idx];
                    final isSelected = widget.controller.text.trim().toLowerCase() == opt.toLowerCase();
                    final price = widget.priceMap != null ? widget.priceMap![opt] : null;

                    return InkWell(
                      onTap: () {
                        widget.controller.text = opt;
                        widget.onSelected?.call(opt);
                        setState(() => _isOpen = false);
                        _focusNode.unfocus();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        color: isSelected
                            ? widget.primaryColor.withValues(alpha: 0.12)
                            : Colors.transparent,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                opt,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? widget.primaryColor : textMain,
                                ),
                              ),
                            ),
                            if (price != null && price > 0)
                              Text(
                                '₹${price.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: widget.primaryColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InvoiceManagerScreenState extends State<InvoiceManagerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DateTime _selectedDate;
  final _billNoController = TextEditingController();
  final _dealerController = TextEditingController();
  final _viewSearchController = TextEditingController();
  String _viewSearchQuery = '';

  // Grocery Price History & Re-order state
  List<InvoiceItemRecord> _rawInvoiceItems = [];
  final _priceSearchController = TextEditingController();
  String _priceSearchQuery = '';
  bool _showOnlyReorder = false;
  final Set<String> _selectedReorderItems = {};
  final Map<String, double> _reorderQuantities = {};
  final Set<String> _expandedHistoryItems = {};

  final List<_InvoiceRecipientDraft> _draftRecipients = [];
  List<DealerPriceItem> _dealerPrices = [];
  List<InvoiceSummary> _existingInvoices = [];
  List<String> _knownDealers = [];
  List<String> _knownRecipients = ['Self'];
  bool _isLoading = false;
  bool _isSaving = false;

  final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _selectedDate = widget.initialDate ?? DateTime.now();

    // Generate initial Bill No suggestion
    _generateDefaultBillNo();

    // Start with Self group and 1 empty item
    _draftRecipients.add(_InvoiceRecipientDraft(
      recipient: 'Self',
      items: [_InvoiceItemDraft()],
    ));

    _loadData();
  }

  void _generateDefaultBillNo() {
    final dateStr = DateFormat('yyyyMMdd').format(_selectedDate);
    final rand = (DateTime.now().millisecondsSinceEpoch % 900) + 100;
    _billNoController.text = 'INV-$dateStr-$rand';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _generateDefaultBillNo();
      });
    }
  }

  List<String> _getRecentBillNumbers() {
    final list = <String>[];
    for (var inv in _existingInvoices) {
      if (inv.billNo.isNotEmpty && !list.contains(inv.billNo)) {
        list.add(inv.billNo);
      }
    }
    return list;
  }

  List<DealerPriceItem> _getItemsForCurrentDealer([String? customDealer]) {
    final targetDealer = (customDealer ?? _dealerController.text).trim().toLowerCase();
    if (targetDealer.isEmpty) return _dealerPrices;
    final matching = _dealerPrices.where((dp) => dp.dealer.trim().toLowerCase() == targetDealer).toList();
    return matching.isNotEmpty ? matching : _dealerPrices;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final prices = await GoogleSheetsService.instance.fetchDealerPrices();
      final invoices = await GoogleSheetsService.instance.fetchInvoiceItems();
      final spentFors = await StorageService.instance.getSpentFors();

      final dealers = <String>{};
      for (var p in prices) {
        if (p.dealer.isNotEmpty) dealers.add(p.dealer);
      }
      for (var inv in invoices) {
        if (inv.shopName.isNotEmpty) dealers.add(inv.shopName);
      }

      final recips = <String>{'Self'};
      for (var sf in spentFors) {
        if (sf.trim().isNotEmpty && sf != 'Other') recips.add(sf.trim());
      }
      for (var inv in invoices) {
        if (inv.recipient.trim().isNotEmpty) recips.add(inv.recipient.trim());
      }

      final grouped = InvoiceSummary.groupItems(invoices);

      if (mounted) {
        setState(() {
          _rawInvoiceItems = invoices;
          _dealerPrices = prices;
          _existingInvoices = grouped;
          _knownDealers = dealers.toList()..sort();
          _knownRecipients = recips.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _billNoController.dispose();
    _dealerController.dispose();
    _viewSearchController.dispose();
    _priceSearchController.dispose();
    for (var r in _draftRecipients) {
      for (var it in r.items) {
        it.dispose();
      }
    }
    super.dispose();
  }

  double get _createGrandTotal {
    return _draftRecipients.fold(0.0, (sum, r) => sum + r.subtotal);
  }

  void _addRecipientGroup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final textCtrl = TextEditingController();
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Add Recipient Group', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Select existing recipient or enter a new one:'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _knownRecipients.where((r) => r.toLowerCase() != 'self').map((r) {
                  return ActionChip(
                    label: Text(r),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _attachNewRecipient(r);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: textCtrl,
                decoration: InputDecoration(
                  labelText: 'Or enter Borrower / Recipient Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: () {
                      final val = textCtrl.text.trim();
                      if (val.isNotEmpty) {
                        Navigator.pop(ctx);
                        _attachNewRecipient(val);
                      }
                    },
                  ),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    Navigator.pop(ctx);
                    _attachNewRecipient(val.trim());
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _attachNewRecipient(String name) {
    if (_draftRecipients.any((r) => r.recipient.toLowerCase() == name.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name group already exists!')));
      return;
    }
    setState(() {
      _draftRecipients.add(_InvoiceRecipientDraft(
        recipient: name,
        items: [_InvoiceItemDraft()],
      ));
    });
  }

  void _addItemToRecipient(_InvoiceRecipientDraft group) {
    setState(() {
      group.items.add(_InvoiceItemDraft());
    });
  }

  void _removeItemFromRecipient(_InvoiceRecipientDraft group, int index) {
    setState(() {
      final item = group.items.removeAt(index);
      item.dispose();
      if (group.items.isEmpty) {
        group.items.add(_InvoiceItemDraft());
      }
    });
  }

  void _removeRecipientGroup(_InvoiceRecipientDraft group) {
    if (group.recipient.toLowerCase() == 'self') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot remove Self group')));
      return;
    }
    setState(() {
      for (var it in group.items) {
        it.dispose();
      }
      _draftRecipients.remove(group);
    });
  }

  Future<void> _saveInvoice() async {
    final billNo = _billNoController.text.trim();
    final shopName = _dealerController.text.trim();

    if (billNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter an Invoice / Bill No.')));
      return;
    }
    if (shopName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a Dealer / Shop Name.')));
      return;
    }

    final itemsToSave = <InvoiceItemRecord>[];
    for (var group in _draftRecipients) {
      for (var it in group.items) {
        if (it.itemName.isNotEmpty && it.total > 0) {
          itemsToSave.add(InvoiceItemRecord(
            id: '${billNo}_${DateTime.now().millisecondsSinceEpoch}_${it.itemName.hashCode}',
            billDate: _selectedDate,
            shopName: shopName,
            billNo: billNo,
            itemName: it.itemName,
            quantity: it.quantity,
            price: it.price,
            total: it.total,
            recipient: group.recipient,
          ));
        }
      }
    }

    if (itemsToSave.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one valid item with a positive total.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Auto-update Dealer_Prices for items under this dealer with price > 0
    final pricesToUpsert = <DealerPriceItem>[];
    for (var it in itemsToSave) {
      if (it.price > 0 && it.itemName.isNotEmpty) {
        pricesToUpsert.add(DealerPriceItem(
          item: it.itemName,
          dealer: shopName,
          price: it.price,
          lastUpdated: DateTime.now(),
        ));
      }
    }
    if (pricesToUpsert.isNotEmpty) {
      await GoogleSheetsService.instance.upsertDealerPrices(pricesToUpsert);
    }

    final success = await GoogleSheetsService.instance.appendInvoiceItems(itemsToSave);
    setState(() => _isSaving = false);

    if (success) {
      final summary = InvoiceSummary(
        billNo: billNo,
        shopName: shopName,
        billDate: _selectedDate,
        items: itemsToSave,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invoice $billNo saved successfully!'),
            backgroundColor: const Color(0xFF4ECDC4),
            action: widget.onInvoiceSelected != null
                ? SnackBarAction(
                    label: 'Use in Form',
                    textColor: Colors.white,
                    onPressed: () {
                      widget.onInvoiceSelected!(summary);
                      Navigator.pop(context, summary);
                    },
                  )
                : null,
          ),
        );

        // Refresh existing list and switch tab
        _loadData();
        _tabController.animateTo(1);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save invoice. Please check network.')),
        );
      }
    }
  }

  void _showAddItemModal(InvoiceSummary summary) {
    String selectedRecip = 'Self';
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();
    final totalCtrl = TextEditingController();

    void updateCalculation() {
      final q = double.tryParse(qtyCtrl.text.trim()) ?? 1.0;
      final p = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
      totalCtrl.text = (q * p).toStringAsFixed(2);
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('➕ Add Item to ${summary.billNo}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedRecip,
                      decoration: const InputDecoration(labelText: 'Recipient'),
                      items: _knownRecipients.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                      onChanged: (val) {
                        if (val != null) setDlgState(() => selectedRecip = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    SearchableDropdownField(
                      controller: nameCtrl,
                      label: 'Item Name',
                      icon: '🛒',
                      hintText: 'Type or select item',
                      options: _getItemsForCurrentDealer(summary.shopName).map((dp) => dp.item).toList(),
                      priceMap: { for (var dp in _getItemsForCurrentDealer(summary.shopName)) dp.item: dp.price },
                      isDark: Theme.of(context).brightness == Brightness.dark,
                      primaryColor: const Color(0xFFFF7A5C),
                      borderColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2D2A4A) : const Color(0xFFF0E8DC),
                      inputBg: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1F1A3A) : const Color(0xFFFFFAF5),
                      onSelected: (val) {
                        final matching = _getItemsForCurrentDealer(summary.shopName).firstWhere(
                          (dp) => dp.item.toLowerCase() == val.toLowerCase(),
                          orElse: () => DealerPriceItem(item: '', dealer: '', price: 0),
                        );
                        if (matching.price > 0) {
                          priceCtrl.text = matching.price.toStringAsFixed(2);
                        }
                        updateCalculation();
                        setDlgState(() {});
                      },
                      onChanged: (val) {
                        final matching = _getItemsForCurrentDealer(summary.shopName).firstWhere(
                          (dp) => dp.item.trim().toLowerCase() == val.trim().toLowerCase(),
                          orElse: () => DealerPriceItem(item: '', dealer: '', price: 0),
                        );
                        if (matching.item.isNotEmpty && (priceCtrl.text.isEmpty || priceCtrl.text == '0.00' || priceCtrl.text == '0')) {
                          priceCtrl.text = matching.price.toStringAsFixed(2);
                          updateCalculation();
                        }
                        setDlgState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: qtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Qty'),
                            onChanged: (_) => setDlgState(updateCalculation),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Price (₹)'),
                            onChanged: (_) => setDlgState(updateCalculation),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: totalCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Total (₹)'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    final itemText = nameCtrl.text.trim();
                    final qty = double.tryParse(qtyCtrl.text.trim()) ?? 1.0;
                    final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                    final total = double.tryParse(totalCtrl.text.trim()) ?? (qty * price);

                    if (itemText.isEmpty || total <= 0) {
                      return;
                    }

                    final newItem = InvoiceItemRecord(
                      id: '${summary.billNo}_${DateTime.now().millisecondsSinceEpoch}',
                      billDate: summary.billDate,
                      shopName: summary.shopName,
                      billNo: summary.billNo,
                      itemName: itemText,
                      quantity: qty,
                      price: price,
                      total: total,
                      recipient: selectedRecip,
                    );

                    Navigator.pop(ctx);
                    setState(() => _isLoading = true);

                    // Auto-update Dealer_Prices for this dealer & item if price > 0
                    if (price > 0) {
                      await GoogleSheetsService.instance.upsertDealerPrices([
                        DealerPriceItem(
                          item: itemText,
                          dealer: summary.shopName,
                          price: price,
                          lastUpdated: DateTime.now(),
                        ),
                      ]);
                    }

                    await GoogleSheetsService.instance.appendInvoiceItems([newItem]);
                    await _loadData();
                  },
                  child: const Text('Save Item'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteInvoice(InvoiceSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Invoice'),
        content: Text('Are you sure you want to delete invoice ${summary.billNo} (${summary.shopName})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      await GoogleSheetsService.instance.deleteInvoice(summary.billNo);
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = const Color(0xFFFF7A5C);
    final secondaryColor = const Color(0xFF4ECDC4);
    final purpleColor = const Color(0xFFA78BFA);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '🧾 Invoice Manager',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: primaryColor,
          labelColor: primaryColor,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.note_add_outlined), text: 'Create Invoice'),
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'View Invoices'),
            Tab(icon: Icon(Icons.insights_outlined), text: 'Price & Re-order'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCreateMode(primaryColor, secondaryColor, purpleColor, isDark),
                _buildViewMode(primaryColor, secondaryColor, purpleColor, isDark),
                _buildPriceAndReorderView(primaryColor, secondaryColor, purpleColor, isDark),
              ],
            ),
    );
  }

  Widget _buildCreateMode(Color primary, Color secondary, Color purple, bool isDark) {
    final bgInput = isDark ? const Color(0xFF1F1A3A) : const Color(0xFFFFFAF5);
    final borderColor = isDark ? const Color(0xFF2D2A4A) : const Color(0xFFF0E8DC);
    final textLabel = isDark ? const Color(0xFFA89BB8) : const Color(0xFF6B5E7E);
    final textMain = isDark ? const Color(0xFFF0E8F0) : const Color(0xFF2D2A3E);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Date & Invoice No
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('📅', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        Text(
                          'DATE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: textLabel,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: bgInput,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor, width: 1.2),
                        ),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          DateFormat('dd-MMM-yyyy').format(_selectedDate),
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: textMain),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: SearchableDropdownField(
                  controller: _billNoController,
                  label: 'INVOICE NO',
                  icon: '🧾',
                  hintText: 'Type / Select',
                  options: _getRecentBillNumbers(),
                  isDark: isDark,
                  primaryColor: primary,
                  borderColor: borderColor,
                  inputBg: bgInput,
                  onChanged: (val) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Row 2: Dealer Name with attached vertical dropdown list
          SearchableDropdownField(
            controller: _dealerController,
            label: 'DEALER NAME',
            icon: '🏪',
            hintText: 'Type dealer name',
            options: _knownDealers,
            isDark: isDark,
            primaryColor: primary,
            borderColor: borderColor,
            inputBg: bgInput,
            onSelected: (val) => setState(() {}),
            onChanged: (val) => setState(() {}),
          ),
          const SizedBox(height: 16),

          // Recipient Groups
          ..._draftRecipients.map((group) => _buildRecipientGroupCard(group, purple, secondary, isDark)),

          // Add Recipient Group Button
          OutlinedButton.icon(
            onPressed: _addRecipientGroup,
            icon: const Icon(Icons.group_add_outlined),
            label: const Text('+ Add Recipient Group (Borrower)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: purple,
              side: BorderSide(color: purple.withValues(alpha: 0.6), style: BorderStyle.solid),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 16),

          // Grand Total Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  secondary.withValues(alpha: 0.12),
                  purple.withValues(alpha: 0.12),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: purple.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '✨ Grand Total:',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: purple,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  _currencyFormat.format(_createGrandTotal),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Save & Generate Button
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveInvoice,
            icon: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? 'Saving...' : '💾 Save & Generate Invoice'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 3,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildRecipientGroupCard(_InvoiceRecipientDraft group, Color purple, Color secondary, bool isDark) {
    final isSelf = group.recipient.toLowerCase() == 'self';

    final card = Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: purple.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header (No delete button icon)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: purple.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(isSelf ? Icons.person : Icons.group, size: 18, color: purple),
                    const SizedBox(width: 6),
                    Text(
                      group.recipient,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: purple),
                    ),
                    if (!isSelf)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          '(swipe left to delete)',
                          style: TextStyle(fontSize: 10, color: purple.withValues(alpha: 0.7), fontStyle: FontStyle.italic),
                        ),
                      ),
                  ],
                ),
                Text(
                  _currencyFormat.format(group.subtotal),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: purple),
                ),
              ],
            ),
          ),

          // Items list
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (int i = 0; i < group.items.length; i++)
                  _buildItemRow(group, group.items[i], i, secondary, isDark),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _addItemToRecipient(group),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Item'),
                    style: TextButton.styleFrom(
                      foregroundColor: secondary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (isSelf) return card;

    return Dismissible(
      key: ValueKey('recipient_${group.recipient}_${group.hashCode}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 16),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 24),
            SizedBox(width: 8),
            Text(
              'Delete Borrower',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
      ),
      confirmDismiss: (dir) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Borrower Group'),
            content: Text('Remove "${group.recipient}" and all items under this group?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => _removeRecipientGroup(group),
      child: card,
    );
  }

  Widget _buildItemRow(_InvoiceRecipientDraft group, _InvoiceItemDraft item, int index, Color secondary, bool isDark) {
    final bgInput = isDark ? const Color(0xFF1F1A3A) : const Color(0xFFFFFAF5);
    final borderColor = isDark ? const Color(0xFF2D2A4A) : const Color(0xFFF0E8DC);
    final primaryColor = isDark ? const Color(0xFFA78BFA) : const Color(0xFFFF7A5C);

    final itemWidget = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgInput,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: secondary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Item Name with attached vertical dropdown list (No delete button icon)
          SearchableDropdownField(
            controller: item.nameController,
            label: '',
            hintText: 'Type or select item',
            options: _getItemsForCurrentDealer().map((dp) => dp.item).toList(),
            priceMap: { for (var dp in _getItemsForCurrentDealer()) dp.item: dp.price },
            isDark: isDark,
            primaryColor: primaryColor,
            borderColor: borderColor,
            inputBg: isDark ? const Color(0xFF16213E) : Colors.white,
            onSelected: (selectedName) {
              final matching = _getItemsForCurrentDealer().firstWhere(
                (dp) => dp.item.toLowerCase() == selectedName.toLowerCase(),
                orElse: () => DealerPriceItem(item: '', dealer: '', price: 0),
              );
              if (matching.price > 0) {
                item.priceController.text = matching.price.toStringAsFixed(2);
              }
              item._onQtyOrPriceChanged();
              setState(() {});
            },
            onChanged: (val) {
              final matching = _getItemsForCurrentDealer().firstWhere(
                (dp) => dp.item.trim().toLowerCase() == val.trim().toLowerCase(),
                orElse: () => DealerPriceItem(item: '', dealer: '', price: 0),
              );
              if (matching.item.isNotEmpty && (item.priceController.text.isEmpty || item.price == 0)) {
                item.priceController.text = matching.price.toStringAsFixed(2);
                item._onQtyOrPriceChanged();
              }
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: item.qtyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Qty',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: item.priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Price',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: item.totalController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Total',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (val) {
                    item.onTotalManualChanged(val);
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Dismissible(
      key: ValueKey('item_${group.recipient}_${item.hashCode}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 20),
            SizedBox(width: 6),
            Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
      onDismissed: (_) {
        _removeItemFromRecipient(group, index);
      },
      child: itemWidget,
    );
  }

  Widget _buildViewMode(Color primary, Color secondary, Color purple, bool isDark) {
    final filtered = _existingInvoices.where((inv) {
      if (_viewSearchQuery.isEmpty) return true;
      final q = _viewSearchQuery.toLowerCase();
      final matchBill = inv.billNo.toLowerCase().contains(q);
      final matchShop = inv.shopName.toLowerCase().contains(q);
      final matchItem = inv.items.any((it) => it.itemName.toLowerCase().contains(q));
      final matchBorrower = inv.items.any((it) => it.recipient.toLowerCase().contains(q));
      final matchDate = DateFormat('dd-MMM-yyyy').format(inv.billDate).toLowerCase().contains(q);
      return matchBill || matchShop || matchItem || matchBorrower || matchDate;
    }).toList();

    return Column(
      children: [
        if (_existingInvoices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _viewSearchController,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search invoices (bill no, shop, item, borrower)...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _viewSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _viewSearchController.clear();
                          setState(() => _viewSearchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (q) => setState(() => _viewSearchQuery = q.trim()),
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long, size: 60, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        _viewSearchQuery.isNotEmpty ? 'No invoices match "$_viewSearchQuery"' : 'No invoices found.',
                        style: const TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      if (_viewSearchQuery.isEmpty) ...[
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => _tabController.animateTo(0),
                          child: const Text('Create New Invoice'),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, index) {
                    final inv = filtered[index];
                    final formattedDate = DateFormat('dd-MMM-yyyy').format(inv.billDate);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                      child: ExpansionTile(
                        shape: const Border(),
                        leading: CircleAvatar(
                          backgroundColor: primary.withValues(alpha: 0.15),
                          child: Text(
                            '🧾',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                        title: Text(
                          inv.billNo.isNotEmpty ? inv.billNo : 'Invoice',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Text(
                          '${inv.shopName} • $formattedDate',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _currencyFormat.format(inv.totalAmount),
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primary),
                            ),
                            if (inv.hasBorrowers)
                              Text(
                                'Split (${inv.recipientTotals.length})',
                                style: TextStyle(fontSize: 11, color: purple, fontWeight: FontWeight.bold),
                              ),
                          ],
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Recipient breakdown badges
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: inv.recipientTotals.entries.map((e) {
                                    return Chip(
                                      label: Text('${e.key}: ${_currencyFormat.format(e.value)}'),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: e.key.toLowerCase() == 'self' ? secondary.withValues(alpha: 0.15) : purple.withValues(alpha: 0.15),
                                    );
                                  }).toList(),
                                ),
                                const Divider(height: 20),

                                // Items list
                                ...inv.items.map((it) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${it.itemName} (${it.recipient})',
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                        ),
                                        Text(
                                          '${it.quantity} × ${_currencyFormat.format(it.price)} = ${_currencyFormat.format(it.total)}',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  );
                                }),

                                const SizedBox(height: 12),
                                // Action Buttons: Add Item, Delete Inv, Use in Form
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _showAddItemModal(inv),
                                        icon: const Icon(Icons.add, size: 14),
                                        label: const Text('Add Item', style: TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: secondary,
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _confirmDeleteInvoice(inv),
                                        icon: const Icon(Icons.delete_outline, size: 14),
                                        label: const Text('Delete', style: TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                        ),
                                      ),
                                    ),
                                    if (widget.onInvoiceSelected != null) ...[
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            widget.onInvoiceSelected!(inv);
                                            Navigator.pop(context, inv);
                                          },
                                          icon: const Icon(Icons.check, size: 14),
                                          label: const Text('Use', style: TextStyle(fontSize: 12)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: primary,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // =========================================================================
  // TAB 3: GROCERY PRICE HISTORY & RE-ORDER TRACKER
  // =========================================================================

  Widget _buildPriceAndReorderView(Color primary, Color secondary, Color purple, bool isDark) {
    final cardBg = isDark ? const Color(0xFF16213E) : Colors.white;
    final textMain = isDark ? const Color(0xFFF0E8F0) : const Color(0xFF2D2A3E);
    final textMuted = isDark ? const Color(0xFFA89BB8) : const Color(0xFF756F86);
    final borderColor = isDark ? const Color(0xFF2C3360) : const Color(0xFFE2E8F0);
    final surfaceBg = isDark ? const Color(0xFF11172A) : const Color(0xFFFBF8F5);

    final allHistory = GroceryItemPriceHistory.computeFrom(
      _rawInvoiceItems,
      catalog: _dealerPrices,
    );

    final query = _priceSearchQuery.trim().toLowerCase();
    final filtered = allHistory.where((h) {
      if (_showOnlyReorder && !h.isDueForReorder && !_selectedReorderItems.contains(h.itemName.toLowerCase())) {
        return false;
      }
      if (query.isEmpty) return true;
      return h.itemName.toLowerCase().contains(query) ||
          h.latestDealer.toLowerCase().contains(query) ||
          h.bestDealer.toLowerCase().contains(query);
    }).toList();

    final totalTracked = allHistory.length;
    final totalHikes = allHistory.where((h) => h.hasPriceHike).length;
    final totalDrops = allHistory.where((h) => h.hasPriceDrop).length;
    final totalDue = allHistory.where((h) => h.isDueForReorder).length;

    // Calculate budget for selected reorder items
    double selectedBudget = 0.0;
    for (final it in allHistory) {
      final key = it.itemName.toLowerCase();
      if (_selectedReorderItems.contains(key)) {
        final q = _reorderQuantities[key] ?? it.typicalQuantity;
        selectedBudget += q * it.latestPrice;
      }
    }

    return Column(
      children: [
        // Mode Selector: Price Trends vs Re-Order Checklist
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: surfaceBg,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _showOnlyReorder = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: !_showOnlyReorder ? primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: !_showOnlyReorder ? primary : borderColor,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.trending_up_rounded,
                              size: 16,
                              color: !_showOnlyReorder ? Colors.white : textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Price Trends',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: !_showOnlyReorder ? Colors.white : textMain,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _showOnlyReorder = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _showOnlyReorder ? const Color(0xFF00D2B4) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _showOnlyReorder ? const Color(0xFF00D2B4) : borderColor,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shopping_cart_checkout_rounded,
                              size: 16,
                              color: _showOnlyReorder ? Colors.white : textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Re-order List',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _showOnlyReorder ? Colors.white : textMain,
                              ),
                            ),
                            if (totalDue > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _showOnlyReorder ? Colors.white.withValues(alpha: 0.25) : const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$totalDue',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Search input
              TextField(
                controller: _priceSearchController,
                onChanged: (val) => setState(() => _priceSearchQuery = val),
                style: TextStyle(fontSize: 13, color: textMain),
                decoration: InputDecoration(
                  hintText: 'Search grocery items or shops...',
                  hintStyle: TextStyle(fontSize: 12, color: textMuted),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _priceSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _priceSearchController.clear();
                            setState(() => _priceSearchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: cardBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderColor),
                  ),
                ),
              ),
            ],
          ),
        ),

        // KPI Summary Ribbon
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildKpiCard(
                  title: 'Tracked Items',
                  value: '$totalTracked',
                  color: primary,
                  icon: Icons.inventory_2_outlined,
                  cardBg: cardBg,
                  textMain: textMain,
                  borderColor: borderColor,
                ),
                const SizedBox(width: 8),
                _buildKpiCard(
                  title: 'Price Hikes',
                  value: '$totalHikes',
                  color: const Color(0xFFEF4444),
                  icon: Icons.arrow_upward_rounded,
                  cardBg: cardBg,
                  textMain: textMain,
                  borderColor: borderColor,
                ),
                const SizedBox(width: 8),
                _buildKpiCard(
                  title: 'Price Drops',
                  value: '$totalDrops',
                  color: const Color(0xFF10B981),
                  icon: Icons.arrow_downward_rounded,
                  cardBg: cardBg,
                  textMain: textMain,
                  borderColor: borderColor,
                ),
                const SizedBox(width: 8),
                _buildKpiCard(
                  title: 'Due Re-orders',
                  value: '$totalDue',
                  color: const Color(0xFFF59E0B),
                  icon: Icons.alarm_on_rounded,
                  cardBg: cardBg,
                  textMain: textMain,
                  borderColor: borderColor,
                ),
              ],
            ),
          ),
        ),

        // Quick Selection Action Bar (when in Re-order mode)
        if (_showOnlyReorder)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      for (var it in allHistory) {
                        if (it.isDueForReorder) {
                          final key = it.itemName.toLowerCase();
                          _selectedReorderItems.add(key);
                          _reorderQuantities[key] ??= it.typicalQuantity;
                        }
                      }
                    });
                  },
                  icon: const Icon(Icons.playlist_add_check_rounded, size: 16, color: Color(0xFFF59E0B)),
                  label: const Text('Select Due Items', style: TextStyle(fontSize: 12, color: Color(0xFFF59E0B))),
                ),
                const Spacer(),
                if (_selectedReorderItems.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _selectedReorderItems.clear()),
                    child: const Text('Clear All', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
              ],
            ),
          ),

        // Item List
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyPriceHistoryState(isDark)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _showOnlyReorder
                        ? _buildReorderChecklistCard(item, cardBg, textMain, textMuted, borderColor, primary)
                        : _buildPriceTrendCard(item, cardBg, textMain, textMuted, borderColor, primary, secondary);
                  },
                ),
        ),

        // Sticky Bottom Re-Order Cart Bar
        if (_showOnlyReorder && _selectedReorderItems.isNotEmpty)
          _buildReorderBottomBar(selectedBudget, allHistory, cardBg, textMain, borderColor, primary),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    required Color cardBg,
    required Color textMain,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: textMain,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceTrendCard(
    GroceryItemPriceHistory item,
    Color cardBg,
    Color textMain,
    Color textMuted,
    Color borderColor,
    Color primary,
    Color secondary,
  ) {
    final key = item.itemName.toLowerCase();
    final isExpanded = _expandedHistoryItems.contains(key);
    final daysAgo = item.daysSinceLastPurchase;

    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    if (item.hasPriceHike) {
      badgeColor = const Color(0xFFEF4444);
      badgeText = '+₹${item.priceDelta.toStringAsFixed(1)} (+${item.percentChange.toStringAsFixed(1)}%)';
      badgeIcon = Icons.arrow_upward_rounded;
    } else if (item.hasPriceDrop) {
      badgeColor = const Color(0xFF10B981);
      badgeText = '-₹${item.priceDelta.abs().toStringAsFixed(1)} (${item.percentChange.toStringAsFixed(1)}%)';
      badgeIcon = Icons.arrow_downward_rounded;
    } else {
      badgeColor = const Color(0xFF64748B);
      badgeText = 'Stable';
      badgeIcon = Icons.remove_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.isDueForReorder ? const Color(0xFFF59E0B).withValues(alpha: 0.5) : borderColor,
          width: item.isDueForReorder ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and Trend Badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('🛍️', style: TextStyle(fontSize: 16)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.itemName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: textMain,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Latest: ${item.latestDealer} • ${DateFormat('dd MMM yyyy').format(item.latestDate)}',
                            style: TextStyle(fontSize: 11, color: textMuted),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, size: 12, color: badgeColor),
                          const SizedBox(width: 4),
                          Text(
                            badgeText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: badgeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Metrics row: Current Price vs Best Historical Deal
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: textMuted.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('CURRENT PRICE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  _currencyFormat.format(item.latestPrice),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: textMain,
                                  ),
                                ),
                                if (item.previousPrice != null) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    _currencyFormat.format(item.previousPrice),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 28, color: borderColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('BEST HISTORICAL DEAL', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                            const SizedBox(height: 2),
                            Text(
                              '${_currencyFormat.format(item.bestPrice)} @ ${item.bestDealer}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: textMain,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Purchase rhythm & status
                Row(
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 12, color: textMuted),
                    const SizedBox(width: 4),
                    Text(
                      daysAgo == 0 ? 'Bought today' : 'Last bought ${daysAgo}d ago',
                      style: TextStyle(fontSize: 11, color: textMuted),
                    ),
                    const SizedBox(width: 8),
                    Text('•', style: TextStyle(color: textMuted)),
                    const SizedBox(width: 8),
                    Text(
                      'Avg cycle: ~${item.averageIntervalDays}d',
                      style: TextStyle(fontSize: 11, color: textMuted),
                    ),
                    const Spacer(),
                    if (item.isDueForReorder)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '⚠️ Due to Re-order',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Expansion Toggle: Past Purchases Ledger
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedHistoryItems.remove(key);
                } else {
                  _expandedHistoryItems.add(key);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Text(
                    'Purchase History (${item.history.length} records • Total: ${_currencyFormat.format(item.totalAmountSpent)})',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primary),
                  ),
                  const Spacer(),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: primary,
                  ),
                ],
              ),
            ),
          ),

          // Expanded Purchase Timeline
          if (isExpanded)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: textMuted.withValues(alpha: 0.03),
              child: Column(
                children: item.history.map((record) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          DateFormat('dd/MM/yy').format(record.billDate),
                          style: TextStyle(fontSize: 11, color: textMuted),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            record.shopName,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: textMain),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${record.quantity} x ${_currencyFormat.format(record.price)}',
                          style: TextStyle(fontSize: 11, color: textMuted),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _currencyFormat.format(record.total),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textMain),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReorderChecklistCard(
    GroceryItemPriceHistory item,
    Color cardBg,
    Color textMain,
    Color textMuted,
    Color borderColor,
    Color primary,
  ) {
    final key = item.itemName.toLowerCase();
    final isSelected = _selectedReorderItems.contains(key);
    final currentQty = _reorderQuantities[key] ?? item.typicalQuantity;
    final itemTotal = currentQty * item.latestPrice;
    final daysAgo = item.daysSinceLastPurchase;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected ? primary.withValues(alpha: 0.08) : cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? primary : borderColor,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Checkbox + Name + Due Badge + Dealer & Unit Price
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: isSelected,
                  activeColor: primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedReorderItems.add(key);
                        _reorderQuantities[key] ??= item.typicalQuantity;
                      } else {
                        _selectedReorderItems.remove(key);
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.itemName,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: textMain,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.isDueForReorder)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '⚠️ Due',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${item.latestDealer} • ${_currencyFormat.format(item.latestPrice)} / unit',
                      style: TextStyle(fontSize: 11.5, color: textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          Container(height: 1, color: borderColor.withValues(alpha: 0.5)),
          const SizedBox(height: 8),

          // Bottom Row: Purchase frequency on left, Stepper & Subtotal on right
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  daysAgo == 0 ? 'Bought today' : 'Last bought ${daysAgo}d ago (cycle ~${item.averageIntervalDays}d)',
                  style: TextStyle(fontSize: 10.5, color: textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: textMuted.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_rounded, size: 16),
                          color: isSelected ? primary : Colors.grey,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () {
                            setState(() {
                              final curr = _reorderQuantities[key] ?? item.typicalQuantity;
                              final next = (curr - 1.0).clamp(0.5, 99.0);
                              _reorderQuantities[key] = next;
                              _selectedReorderItems.add(key);
                            });
                          },
                        ),
                        Container(
                          constraints: const BoxConstraints(minWidth: 24),
                          alignment: Alignment.center,
                          child: Text(
                            currentQty == currentQty.toInt() ? currentQty.toInt().toString() : currentQty.toString(),
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: textMain),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_rounded, size: 16),
                          color: isSelected ? primary : Colors.grey,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () {
                            setState(() {
                              final curr = _reorderQuantities[key] ?? item.typicalQuantity;
                              final next = (curr + 1.0).clamp(0.5, 99.0);
                              _reorderQuantities[key] = next;
                              _selectedReorderItems.add(key);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _currencyFormat.format(itemTotal),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? primary : textMain,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReorderBottomBar(
    double totalBudget,
    List<GroceryItemPriceHistory> allHistory,
    Color cardBg,
    Color textMain,
    Color borderColor,
    Color primary,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_selectedReorderItems.length} items selected',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Text(
                  _currencyFormat.format(totalBudget),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: primary,
                  ),
                ),
              ],
            ),
            const Spacer(),

            // Share / Copy button
            IconButton.filledTonal(
              onPressed: () => _shareShoppingList(allHistory, totalBudget),
              tooltip: 'Share Shopping List',
              icon: const Icon(Icons.share_rounded, size: 18),
            ),
            const SizedBox(width: 8),

            // Create Invoice Draft Button
            ElevatedButton.icon(
              onPressed: () => _createInvoiceFromReorder(allHistory),
              icon: const Icon(Icons.post_add_rounded, size: 18),
              label: const Text('Draft Invoice', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _shareShoppingList(List<GroceryItemPriceHistory> allHistory, double totalBudget) async {
    final buffer = StringBuffer();
    buffer.writeln('🛒 Grocery Shopping List');
    buffer.writeln('Date: ${DateFormat('dd MMM yyyy').format(DateTime.now())}');
    buffer.writeln('-----------------------------');

    for (var it in allHistory) {
      final key = it.itemName.toLowerCase();
      if (_selectedReorderItems.contains(key)) {
        final q = _reorderQuantities[key] ?? it.typicalQuantity;
        final tot = q * it.latestPrice;
        buffer.writeln('• ${it.itemName}: $q x ${_currencyFormat.format(it.latestPrice)} = ${_currencyFormat.format(tot)} (${it.latestDealer})');
      }
    }

    buffer.writeln('-----------------------------');
    buffer.writeln('Estimated Budget: ${_currencyFormat.format(totalBudget)}');

    final text = buffer.toString();
    await Clipboard.setData(ClipboardData(text: text));

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          subject: 'Grocery Shopping List',
        ),
      );
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shopping list copied to clipboard and ready to share!')),
      );
    }
  }

  void _createInvoiceFromReorder(List<GroceryItemPriceHistory> allHistory) {
    final selectedItems = allHistory.where((h) => _selectedReorderItems.contains(h.itemName.toLowerCase())).toList();
    if (selectedItems.isEmpty) return;

    // Determine common dealer if any
    final dealerCounts = <String, int>{};
    for (var it in selectedItems) {
      if (it.latestDealer.isNotEmpty && it.latestDealer != 'Direct') {
        dealerCounts[it.latestDealer] = (dealerCounts[it.latestDealer] ?? 0) + 1;
      }
    }
    String bestDealer = '';
    int maxCount = 0;
    for (var e in dealerCounts.entries) {
      if (e.value > maxCount) {
        maxCount = e.value;
        bestDealer = e.key;
      }
    }

    setState(() {
      if (bestDealer.isNotEmpty) {
        _dealerController.text = bestDealer;
      }
      _generateDefaultBillNo();

      final drafts = selectedItems.map((it) {
        final key = it.itemName.toLowerCase();
        final q = _reorderQuantities[key] ?? it.typicalQuantity;
        return _InvoiceItemDraft(
          name: it.itemName,
          qty: q,
          price: it.latestPrice,
          total: q * it.latestPrice,
        );
      }).toList();

      _draftRecipients.clear();
      _draftRecipients.add(_InvoiceRecipientDraft(
        recipient: 'Self',
        items: drafts,
      ));

      _selectedReorderItems.clear();
      _tabController.animateTo(0);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${selectedItems.length} items added to Invoice Draft! Review and tap Save.'),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  Widget _buildEmptyPriceHistoryState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.storefront_outlined, size: 54, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'No Grocery Items Found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'As you save invoices, price trends and smart re-order intervals will automatically appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _tabController.animateTo(0),
              icon: const Icon(Icons.add),
              label: const Text('Create an Invoice'),
            ),
          ],
        ),
      ),
    );
  }
}
