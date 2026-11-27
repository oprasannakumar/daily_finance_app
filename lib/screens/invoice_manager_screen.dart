import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../models/invoice_model.dart';
import '../services/google_sheets_service.dart';
import '../services/invoice_extractor_service.dart';
import '../services/storage_service.dart';
import '../widgets/ai_settings_dialog.dart';
import '../widgets/popup_select_field.dart';
import '../widgets/swipe_to_delete_wrapper.dart';

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
      if (_focusNode.hasFocus && !_isOpen) {
        setState(() => _isOpen = true);
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

    return TapRegion(
      onTapOutside: (_) {
        if (_isOpen && mounted) {
          setState(() => _isOpen = false);
        }
      },
      child: Column(
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
      ),
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

  final List<_InvoiceRecipientDraft> _draftRecipients = [];
  List<DealerPriceItem> _dealerPrices = [];
  List<InvoiceSummary> _existingInvoices = [];
  List<String> _knownDealers = [];
  List<String> _knownRecipients = ['Self'];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isExtracting = false;
  bool _isScanFabExpanded = false;
  String? _extractionStatus;
  String _lastOcrText = '';
  List<Uint8List> _extractedPreviewPages = [];

  final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {
          if (_isScanFabExpanded) _isScanFabExpanded = false;
        });
      }
    });
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

  void _showOcrPreviewDialog(String ocrText) {
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Extracted OCR Text', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              ocrText.isEmpty ? '(Empty OCR output)' : ocrText,
              style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _extractFromSource(String mode) async {
    final pages = <Uint8List>[];

    if (mode == 'doc') {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      );
      if (result.isEmpty || !mounted) return;
      final file = result.first;
      final fileBytes = file.path != null ? await File(file.path!).readAsBytes() : null;
      if (fileBytes == null || fileBytes.isEmpty) return;

      final isPdf = (file.extension ?? '').toLowerCase() == 'pdf' ||
          file.name.toLowerCase().endsWith('.pdf');

      if (isPdf) {
        setState(() {
          _isExtracting = true;
          _extractionStatus = 'Rendering PDF pages...';
        });
        try {
          int count = 0;
          await for (final raster in Printing.raster(fileBytes, dpi: 220)) {
            final png = await raster.toPng();
            final opaque = await InvoiceExtractorService.instance.compositeOnWhiteBackground(png);
            pages.add(opaque);
            count++;
            if (count >= 5) break;
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _isExtracting = false;
              _extractionStatus = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to read PDF: $e', textAlign: TextAlign.center)),
            );
          }
          return;
        }
      } else {
        setState(() {
          _isExtracting = true;
          _extractionStatus = 'Preparing image...';
        });
        pages.add(fileBytes);
      }
    } else {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 1800,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _isExtracting = true;
        _extractionStatus = 'Preparing camera photo...';
      });
      pages.add(await picked.readAsBytes());
    }

    if (pages.isEmpty || !mounted) {
      setState(() {
        _isExtracting = false;
        _extractionStatus = null;
      });
      return;
    }

    setState(() {
      _extractedPreviewPages = pages;
      _lastOcrText = '';
      _extractionStatus = 'Step 1/2: Extracting text with OCR...';
    });

    try {
      final ocrText = await InvoiceExtractorService.instance.extractOcrText(pages);
      if (!mounted) return;
      setState(() {
        _lastOcrText = ocrText;
        _extractionStatus = 'Step 2/2: Feeding OCR text to AI agent...';
      });

      final extracted = await InvoiceExtractorService.instance.extractFromOcrText(
        ocrText,
        onStatus: (status) {
          if (mounted) setState(() => _extractionStatus = 'Step 2/2: $status');
        },
      );
      if (!mounted) return;
      setState(() {
        _isExtracting = false;
        _extractionStatus = null;
      });

      if (extracted.items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No items returned by ${extracted.usedProvider}.', textAlign: TextAlign.center),
            duration: const Duration(seconds: 6),
            action: _lastOcrText.isNotEmpty
                ? SnackBarAction(label: 'View OCR', onPressed: () => _showOcrPreviewDialog(_lastOcrText))
                : null,
          ),
        );
        return;
      }

      // Fuzzy-match dealer against known dealers
      String mappedDealer = extracted.dealerName;
      if (mappedDealer.isNotEmpty) {
        final lower = mappedDealer.toLowerCase();
        for (final known in _knownDealers) {
          final kl = known.toLowerCase();
          if (kl == lower || kl.contains(lower) || lower.contains(kl)) {
            mappedDealer = known;
            break;
          }
        }
      }

      final recipientOptions = <String>{
        'Self',
        ..._knownRecipients.where((r) => r.trim().isNotEmpty && r != 'Split'),
      }.toList();

      final mapped = await showDialog<MappedInvoiceResult>(
        context: context,
        builder: (_) => MapExtractedInvoiceDialog(
          extracted: extracted,
          initialDealer: mappedDealer,
          initialBillNo: extracted.invoiceNumber.isNotEmpty
              ? extracted.invoiceNumber
              : _billNoController.text.trim(),
          initialBillingDate: extracted.billingDate ?? _selectedDate,
          knownDealers: _knownDealers,
          recipientOptions: recipientOptions,
          ocrText: _lastOcrText,
        ),
      );

      if (mapped != null && mounted) {
        final grouped = <String, List<_InvoiceItemDraft>>{};
        int mappedEntryCount = 0;
        for (int i = 0; i < extracted.items.length; i++) {
          final it = extracted.items[i];
          final allocs = i < mapped.allocationsPerItem.length
              ? mapped.allocationsPerItem[i]
              : [ItemAllocationSplit(recipient: 'Self', quantity: it.quantity)];
          for (final alloc in allocs) {
            if (alloc.quantity <= 0) continue;
            grouped.putIfAbsent(alloc.recipient, () => []).add(
              _InvoiceItemDraft(
                name: it.name,
                qty: alloc.quantity,
                price: it.unitPrice,
              ),
            );
            mappedEntryCount++;
          }
        }

        setState(() {
          _selectedDate = mapped.billingDate;
          if (mapped.billNo.isNotEmpty) {
            _billNoController.text = mapped.billNo;
          }
          _dealerController.text = mapped.dealer;
          for (final g in _draftRecipients) {
            for (final it in g.items) {
              it.dispose();
            }
          }
          _draftRecipients.clear();
          if (grouped.containsKey('Self')) {
            _draftRecipients.add(_InvoiceRecipientDraft(recipient: 'Self', items: grouped.remove('Self')!));
          } else {
            _draftRecipients.add(_InvoiceRecipientDraft(recipient: 'Self', items: []));
          }
          for (final entry in grouped.entries) {
            _draftRecipients.add(_InvoiceRecipientDraft(recipient: entry.key, items: entry.value));
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Mapped $mappedEntryCount item entries from invoice!', textAlign: TextAlign.center),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExtracting = false;
          _extractionStatus = null;
        });
        final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Extraction failed:\n$msg',
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            duration: const Duration(seconds: 7),
            backgroundColor: const Color(0xFFEF4444),
            action: SnackBarAction(
              label: _lastOcrText.isNotEmpty ? 'Keys / OCR' : 'API Keys',
              textColor: Colors.white,
              onPressed: () {
                if (_lastOcrText.isEmpty) {
                  showAiSettingsDialog(context);
                } else {
                  showDialog(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      title: const Text('Extraction Diagnostics'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(msg, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                              const Divider(height: 16),
                              const Text('OCR Text:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(height: 4),
                              SelectableText(_lastOcrText, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                            ],
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(dCtx);
                            showAiSettingsDialog(context);
                          },
                          child: const Text('API Keys & Models'),
                        ),
                        TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Close')),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      var prices = await GoogleSheetsService.instance.fetchDealerPrices(forceRefresh: forceRefresh);
      var invoices = await GoogleSheetsService.instance.fetchInvoiceItems(forceRefresh: forceRefresh);
      if (!forceRefresh && (prices.isEmpty || invoices.isEmpty)) {
        prices = await GoogleSheetsService.instance.fetchDealerPrices(forceRefresh: true);
        invoices = await GoogleSheetsService.instance.fetchInvoiceItems(forceRefresh: true);
      }
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name group already exists!', textAlign: TextAlign.center)));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot remove Self group', textAlign: TextAlign.center)));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter an Invoice / Bill No.', textAlign: TextAlign.center)));
      return;
    }
    if (shopName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a Dealer / Shop Name.', textAlign: TextAlign.center)));
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
        const SnackBar(content: Text('Please add at least one valid item with a positive total.', textAlign: TextAlign.center)),
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
            content: Text('Invoice $billNo saved successfully!', textAlign: TextAlign.center),
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
          const SnackBar(content: Text('Failed to save invoice. Please check network.', textAlign: TextAlign.center)),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh from Google Sheets',
            onPressed: _isLoading ? null : () => _loadData(forceRefresh: true),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: primaryColor,
          labelColor: primaryColor,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.note_add_outlined), text: 'Create Invoice'),
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'View Invoices'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCreateMode(primaryColor, secondaryColor, purpleColor, isDark),
                    _buildViewMode(primaryColor, secondaryColor, purpleColor, isDark),
                  ],
                ),
                if (_isScanFabExpanded && _tabController.index == 0)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => setState(() => _isScanFabExpanded = false),
                      child: Container(color: Colors.black.withValues(alpha: 0.2)),
                    ),
                  ),
              ],
            ),
      floatingActionButton: _tabController.index == 0
          ? _buildScanFabMenu(primaryColor, secondaryColor, isDark)
          : null,
    );
  }

  Widget _buildScanFabMenu(Color primary, Color secondary, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_isScanFabExpanded) ...[
          FloatingActionButton.extended(
            heroTag: 'invoice_scan_pdf_fab',
            onPressed: _isExtracting
                ? null
                : () {
                    setState(() => _isScanFabExpanded = false);
                    _extractFromSource('doc');
                  },
            backgroundColor: primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.upload_file_rounded, size: 19),
            label: const Text('PDF / Image', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'invoice_scan_camera_fab',
            onPressed: _isExtracting
                ? null
                : () {
                    setState(() => _isScanFabExpanded = false);
                    _extractFromSource('camera');
                  },
            backgroundColor: secondary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.camera_alt_rounded, size: 19),
            label: const Text('Camera', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
          ),
          const SizedBox(height: 12),
        ],
        FloatingActionButton.extended(
          heroTag: 'invoice_scan_main_fab',
          onPressed: _isExtracting ? null : () => setState(() => _isScanFabExpanded = !_isScanFabExpanded),
          backgroundColor: _isScanFabExpanded
              ? (isDark ? const Color(0xFF2D2A4A) : Colors.blueGrey.shade700)
              : primary,
          foregroundColor: Colors.white,
          icon: _isExtracting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Icon(_isScanFabExpanded ? Icons.close_rounded : Icons.document_scanner_rounded, size: 20),
          label: Text(
            _isExtracting ? 'Scanning...' : (_isScanFabExpanded ? 'Close' : 'Scan'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateMode(Color primary, Color secondary, Color purple, bool isDark) {
    final bgInput = isDark ? const Color(0xFF1F1A3A) : const Color(0xFFFFFAF5);
    final borderColor = isDark ? const Color(0xFF2D2A4A) : const Color(0xFFF0E8DC);
    final textLabel = isDark ? const Color(0xFFA89BB8) : const Color(0xFF6B5E7E);
    final textMain = isDark ? const Color(0xFFF0E8F0) : const Color(0xFF2D2A3E);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 92),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isExtracting && _extractionStatus != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: primary)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _extractionStatus!,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_extractedPreviewPages.isNotEmpty || _lastOcrText.isNotEmpty) ...[
            Row(
              children: [
                if (_extractedPreviewPages.isNotEmpty)
                  Expanded(
                    child: SizedBox(
                      height: 60,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _extractedPreviewPages.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, idx) => Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(_extractedPreviewPages[idx], width: 48, height: 60, fit: BoxFit.cover),
                            ),
                            Positioned(
                              bottom: 2,
                              right: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('P${idx + 1}', style: const TextStyle(color: Colors.white, fontSize: 9)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_lastOcrText.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _showOcrPreviewDialog(_lastOcrText),
                    icon: const Icon(Icons.text_snippet_outlined, size: 16),
                    label: const Text('View OCR', style: TextStyle(fontSize: 11.5)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],

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
      elevation: isSelf ? 2 : 0,
      margin: isSelf ? const EdgeInsets.only(bottom: 16) : EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelf ? BorderSide(color: purple.withValues(alpha: 0.3)) : BorderSide.none,
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

    return SwipeToDeleteWrapper(
      key: ValueKey('recipient_${group.recipient}_${group.hashCode}'),
      borderRadius: BorderRadius.circular(16),
      margin: const EdgeInsets.only(bottom: 16),
      border: Border.all(color: purple.withValues(alpha: 0.3)),
      confirmDelete: () async {
        final res = await showDialog<bool>(
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
        return res ?? false;
      },
      onDelete: () => _removeRecipientGroup(group),
      child: card,
    );
  }

  List<String> _availableRecipientOptions() {
    return <String>{
      'Self',
      ..._knownRecipients.where((r) => r.trim().isNotEmpty && r != 'Split'),
      ..._draftRecipients.map((g) => g.recipient.trim()).where((r) => r.isNotEmpty && r != 'Split'),
    }.toList();
  }

  Future<void> _remapDraftItem(_InvoiceRecipientDraft sourceGroup, int index, _InvoiceItemDraft item) async {
    final itemName = item.itemName.isNotEmpty ? item.itemName : 'Item #${index + 1}';
    final totalQty = item.quantity > 0 ? item.quantity : 1.0;
    final unitPrice = item.price;

    final result = await showDialog<List<ItemAllocationSplit>>(
      context: context,
      builder: (_) => RemapItemSplitDialog(
        itemName: itemName,
        billedQty: totalQty,
        unitPrice: unitPrice,
        initialAllocations: [
          ItemAllocationSplit(recipient: sourceGroup.recipient, quantity: totalQty),
        ],
        recipientOptions: _availableRecipientOptions(),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;

    final valid = result.where((a) => a.quantity > 0).toList();
    if (valid.isEmpty) return;

    setState(() {
      final keepSelfIdx = valid.indexWhere(
        (a) => a.recipient.trim().toLowerCase() == sourceGroup.recipient.trim().toLowerCase(),
      );

      if (keepSelfIdx != -1) {
        final selfAlloc = valid[keepSelfIdx];
        item.qtyController.text = _formatCleanQty(selfAlloc.quantity);
        item._onQtyOrPriceChanged();
      } else {
        sourceGroup.items.removeAt(index).dispose();
        if (sourceGroup.recipient.toLowerCase() != 'self' && sourceGroup.items.isEmpty) {
          _draftRecipients.remove(sourceGroup);
        }
      }

      for (int i = 0; i < valid.length; i++) {
        if (i == keepSelfIdx) continue;
        final alloc = valid[i];
        var targetGroup = _draftRecipients.cast<_InvoiceRecipientDraft?>().firstWhere(
              (g) => g!.recipient.trim().toLowerCase() == alloc.recipient.trim().toLowerCase(),
              orElse: () => null,
            );
        if (targetGroup == null) {
          targetGroup = _InvoiceRecipientDraft(recipient: alloc.recipient, items: []);
          _draftRecipients.add(targetGroup);
        }
        targetGroup.items.add(
          _InvoiceItemDraft(
            name: item.itemName,
            qty: alloc.quantity,
            price: unitPrice,
          ),
        );
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Updated mapping for "$itemName".', textAlign: TextAlign.center),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  Future<void> _remapSavedInvoiceItem(InvoiceSummary inv, int itemIndex) async {
    final targetItem = inv.items[itemIndex];
    final totalQty = targetItem.quantity > 0 ? targetItem.quantity : 1.0;

    final result = await showDialog<List<ItemAllocationSplit>>(
      context: context,
      builder: (_) => RemapItemSplitDialog(
        itemName: targetItem.itemName,
        billedQty: totalQty,
        unitPrice: targetItem.price,
        initialAllocations: [
          ItemAllocationSplit(recipient: targetItem.recipient, quantity: totalQty),
        ],
        recipientOptions: _availableRecipientOptions(),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;

    final valid = result.where((a) => a.quantity > 0).toList();
    if (valid.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final updatedItems = <InvoiceItemRecord>[];
      for (int i = 0; i < inv.items.length; i++) {
        if (i != itemIndex) {
          updatedItems.add(inv.items[i]);
          continue;
        }
        for (int s = 0; s < valid.length; s++) {
          final alloc = valid[s];
          final splitQty = alloc.quantity;
          final splitTotal = splitQty * targetItem.price;
          updatedItems.add(
            InvoiceItemRecord(
              id: '${inv.billNo}_${DateTime.now().millisecondsSinceEpoch}_${i}_$s',
              billDate: inv.billDate,
              shopName: inv.shopName,
              billNo: inv.billNo,
              itemName: targetItem.itemName,
              quantity: splitQty,
              price: targetItem.price,
              total: splitTotal,
              recipient: alloc.recipient,
            ),
          );
        }
      }
      await GoogleSheetsService.instance.deleteInvoice(inv.billNo);
      await GoogleSheetsService.instance.appendInvoiceItems(updatedItems);
      await _loadData();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remap item: $e', textAlign: TextAlign.center)),
        );
      }
    }
  }

  Widget _buildItemRow(_InvoiceRecipientDraft group, _InvoiceItemDraft item, int index, Color secondary, bool isDark) {
    final bgInput = isDark ? const Color(0xFF1F1A3A) : const Color(0xFFFFFAF5);
    final borderColor = isDark ? const Color(0xFF2D2A4A) : const Color(0xFFF0E8DC);
    final primaryColor = isDark ? const Color(0xFFA78BFA) : const Color(0xFFFF7A5C);

    final itemWidget = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgInput,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Item #${index + 1}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
              ),
              InkWell(
                onTap: () => _remapDraftItem(group, index, item),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.call_split_rounded, size: 14, color: primaryColor),
                      const SizedBox(width: 4),
                      Text(
                        'Remap / Split',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
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

    return SwipeToDeleteWrapper(
      key: ValueKey('item_${group.recipient}_${item.hashCode}'),
      borderRadius: BorderRadius.circular(12),
      margin: const EdgeInsets.only(bottom: 10),
      border: Border.all(color: secondary.withValues(alpha: 0.3)),
      onDelete: () => _removeItemFromRecipient(group, index),
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
                                ...inv.items.asMap().entries.map((entry) {
                                  final itemIdx = entry.key;
                                  final it = entry.value;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
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
                                        const SizedBox(width: 4),
                                        SizedBox(
                                          width: 28,
                                          height: 28,
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            tooltip: 'Remap / Split Item',
                                            icon: Icon(Icons.call_split_rounded, size: 16, color: purple),
                                            onPressed: () => _remapSavedInvoiceItem(inv, itemIdx),
                                          ),
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
}

String _formatCleanQty(double q) {
  if ((q - q.roundToDouble()).abs() < 0.0001) {
    return q.round().toString();
  }
  var s = q.toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

class ItemAllocationSplit {
  String recipient;
  double quantity;

  ItemAllocationSplit({
    required this.recipient,
    required this.quantity,
  });

  ItemAllocationSplit copy() => ItemAllocationSplit(recipient: recipient, quantity: quantity);
}

class RemapItemSplitDialog extends StatefulWidget {
  final String itemName;
  final double billedQty;
  final double unitPrice;
  final List<ItemAllocationSplit> initialAllocations;
  final List<String> recipientOptions;

  const RemapItemSplitDialog({
    super.key,
    required this.itemName,
    required this.billedQty,
    required this.unitPrice,
    required this.initialAllocations,
    required this.recipientOptions,
  });

  @override
  State<RemapItemSplitDialog> createState() => _RemapItemSplitDialogState();
}

class _RemapItemSplitDialogState extends State<RemapItemSplitDialog> {
  late final List<ItemAllocationSplit> _allocs;
  late final List<TextEditingController> _qtyCtrls;

  @override
  void initState() {
    super.initState();
    _allocs = widget.initialAllocations.isNotEmpty
        ? widget.initialAllocations.map((e) => e.copy()).toList()
        : [ItemAllocationSplit(recipient: 'Self', quantity: widget.billedQty)];
    _qtyCtrls = _allocs.map((a) => TextEditingController(text: _formatCleanQty(a.quantity))).toList();
  }

  @override
  void dispose() {
    for (final c in _qtyCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  double get _allocatedSum => _allocs.fold(0.0, (s, a) => s + a.quantity);
  double get _remainingQty => widget.billedQty - _allocatedSum;

  void _syncQtyControllers() {
    for (int i = 0; i < _allocs.length; i++) {
      _qtyCtrls[i].text = _formatCleanQty(_allocs[i].quantity);
    }
  }

  void _addAllocationRow(double qty) {
    final used = _allocs.map((a) => a.recipient.toLowerCase()).toSet();
    final nextRecip = widget.recipientOptions.firstWhere(
      (r) => !used.contains(r.toLowerCase()),
      orElse: () => 'Self',
    );
    setState(() {
      _allocs.add(ItemAllocationSplit(recipient: nextRecip, quantity: qty));
      _qtyCtrls.add(TextEditingController(text: _formatCleanQty(qty)));
    });
  }

  void _splitEqually() {
    if (_allocs.length < 2) {
      _addAllocationRow(0.0);
    }
    final perPerson = widget.billedQty / _allocs.length;
    setState(() {
      for (int i = 0; i < _allocs.length; i++) {
        _allocs[i].quantity = double.parse(perPerson.toStringAsFixed(3));
      }
      _syncQtyControllers();
    });
  }

  void _removeAllocationRow(int idx) {
    if (_allocs.length <= 1) return;
    setState(() {
      _allocs.removeAt(idx);
      _qtyCtrls.removeAt(idx).dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rem = _remainingQty;
    final isExactMatch = rem.abs() < 0.005;
    final hasRemaining = rem >= 0.005;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.call_split_rounded, color: Color(0xFFFF7A5C), size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Remap / Split Item', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  widget.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: (isExactMatch ? const Color(0xFF10B981) : Colors.amber.shade700).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (isExactMatch ? const Color(0xFF10B981) : Colors.amber.shade700).withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                'Billed Qty: ${_formatCleanQty(widget.billedQty)} × ₹${widget.unitPrice.toStringAsFixed(2)} = ₹${(widget.billedQty * widget.unitPrice).toStringAsFixed(2)}\n'
                '${isExactMatch ? 'Allocated cleanly (${_formatCleanQty(_allocatedSum)} / ${_formatCleanQty(widget.billedQty)})' : (hasRemaining ? 'Remaining to map: ${_formatCleanQty(rem)}' : 'Total mapped: ${_formatCleanQty(_allocatedSum)} (billed: ${_formatCleanQty(widget.billedQty)})')}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isExactMatch ? const Color(0xFF047857) : Colors.amber.shade900,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.balance_rounded, size: 15),
                  label: const Text('Split Equally', style: TextStyle(fontSize: 11.5)),
                  onPressed: _splitEqually,
                ),
                if (hasRemaining)
                  ActionChip(
                    avatar: const Icon(Icons.add_circle_outline_rounded, size: 15),
                    label: Text('+ Map Left (${_formatCleanQty(rem)})', style: const TextStyle(fontSize: 11.5)),
                    onPressed: () => _addAllocationRow(rem),
                  )
                else
                  ActionChip(
                    avatar: const Icon(Icons.person_add_alt_1_rounded, size: 15),
                    label: const Text('+ Add Person', style: TextStyle(fontSize: 11.5)),
                    onPressed: () => _addAllocationRow(0.0),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _allocs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, idx) {
                  final alloc = _allocs[idx];
                  final rowTotal = alloc.quantity * widget.unitPrice;
                  return Row(
                    key: ObjectKey(alloc),
                    children: [
                      Expanded(
                        flex: 5,
                        child: PopupSelectField(
                          key: ValueKey('split_alloc_recip_${idx}_${alloc.recipient}'),
                          label: 'Map To',
                          placeholder: 'Self',
                          items: widget.recipientOptions,
                          selectedValue: alloc.recipient,
                          onSelected: (val) => setState(() => alloc.recipient = val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _qtyCtrls[idx],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            labelText: 'Qty',
                            helperText: '₹${rowTotal.toStringAsFixed(0)}',
                            helperStyle: const TextStyle(fontSize: 10),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onChanged: (v) {
                            setState(() {
                              alloc.quantity = double.tryParse(v.trim()) ?? 0.0;
                            });
                          },
                        ),
                      ),
                      if (_allocs.length > 1)
                        SizedBox(
                          width: 28,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: 'Remove share',
                            icon: const Icon(Icons.close_rounded, size: 18, color: Colors.redAccent),
                            onPressed: () => _removeAllocationRow(idx),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF7A5C)),
          onPressed: _allocatedSum > 0
              ? () => Navigator.pop(
                    context,
                    _allocs.where((a) => a.quantity > 0).map((a) => a.copy()).toList(),
                  )
              : null,
          child: const Text('Apply Remap'),
        ),
      ],
    );
  }
}

class MappedInvoiceResult {
  final String dealer;
  final String billNo;
  final DateTime billingDate;
  final List<List<ItemAllocationSplit>> allocationsPerItem;

  MappedInvoiceResult({
    required this.dealer,
    required this.billNo,
    required this.billingDate,
    required this.allocationsPerItem,
  });

  List<String> get assignments => allocationsPerItem
      .map((list) => list.isNotEmpty ? list.first.recipient : 'Self')
      .toList();
}

class MapExtractedInvoiceDialog extends StatefulWidget {
  final ExtractedInvoiceData extracted;
  final String initialDealer;
  final String initialBillNo;
  final DateTime initialBillingDate;
  final List<String> knownDealers;
  final List<String> recipientOptions;
  final String ocrText;

  const MapExtractedInvoiceDialog({
    super.key,
    required this.extracted,
    required this.initialDealer,
    required this.initialBillNo,
    required this.initialBillingDate,
    required this.knownDealers,
    required this.recipientOptions,
    this.ocrText = '',
  });

  @override
  State<MapExtractedInvoiceDialog> createState() => _MapExtractedInvoiceDialogState();
}

class _MapExtractedInvoiceDialogState extends State<MapExtractedInvoiceDialog> {
  late final TextEditingController _dealerCtrl;
  late final TextEditingController _billNoCtrl;
  late DateTime _mappedDate;
  late final List<List<ItemAllocationSplit>> _allocationsPerItem;

  @override
  void initState() {
    super.initState();
    _dealerCtrl = TextEditingController(text: widget.initialDealer);
    _billNoCtrl = TextEditingController(text: widget.initialBillNo);
    _mappedDate = widget.initialBillingDate;
    _allocationsPerItem = widget.extracted.items
        .map((it) => [ItemAllocationSplit(recipient: 'Self', quantity: it.quantity)])
        .toList();
  }

  @override
  void dispose() {
    _dealerCtrl.dispose();
    _billNoCtrl.dispose();
    super.dispose();
  }

  Future<void> _openSplitRemapForItem(int idx) async {
    final item = widget.extracted.items[idx];
    final result = await showDialog<List<ItemAllocationSplit>>(
      context: context,
      builder: (_) => RemapItemSplitDialog(
        itemName: item.name,
        billedQty: item.quantity,
        unitPrice: item.unitPrice,
        initialAllocations: _allocationsPerItem[idx],
        recipientOptions: widget.recipientOptions,
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _allocationsPerItem[idx] = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.receipt_long_rounded, color: Color(0xFFFF7A5C), size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Map Extracted Invoice', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  'via ${widget.extracted.usedProvider}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
          if (widget.ocrText.isNotEmpty)
            IconButton(
              tooltip: 'View OCR Text',
              icon: const Icon(Icons.text_snippet_outlined, size: 19),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    title: const Text('Extracted OCR Text', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    content: SizedBox(
                      width: double.maxFinite,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          widget.ocrText,
                          style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                    actions: [TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Close'))],
                  ),
                );
              },
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _billNoCtrl,
                    decoration: InputDecoration(
                      labelText: 'Invoice No',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _mappedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null && mounted) {
                        setState(() => _mappedDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Billing Date',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        DateFormat('dd-MMM-yy').format(_mappedDate),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _dealerCtrl,
              decoration: InputDecoration(
                labelText: 'Dealer Name',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (widget.knownDealers.isNotEmpty) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 30,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: widget.knownDealers.take(10).map((d) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(d, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        onPressed: () => setState(() => _dealerCtrl.text = d),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Items (${widget.extracted.items.length}) • Map or Split',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    for (int i = 0; i < _allocationsPerItem.length; i++) {
                      _allocationsPerItem[i] = [
                        ItemAllocationSplit(recipient: 'Self', quantity: widget.extracted.items[i].quantity),
                      ];
                    }
                  }),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('All Self', style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.extracted.items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, idx) {
                  final item = widget.extracted.items[idx];
                  final allocs = _allocationsPerItem[idx];
                  final isSplit = allocs.length > 1 ||
                      (allocs.isNotEmpty && (allocs.first.quantity - item.quantity).abs() > 0.005);
                  final lineTotal = item.quantity * item.unitPrice;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    'Qty ${_formatCleanQty(item.quantity)} × ₹${item.unitPrice.toStringAsFixed(2)} = ₹${lineTotal.toStringAsFixed(2)}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (!isSplit && allocs.length == 1)
                              SizedBox(
                                width: 102,
                                child: PopupSelectField(
                                  key: ValueKey('map_item_${idx}_${allocs.first.recipient}'),
                                  label: 'Assign Item To',
                                  placeholder: 'Self',
                                  items: widget.recipientOptions,
                                  selectedValue: allocs.first.recipient,
                                  onSelected: (val) => setState(() => allocs.first.recipient = val),
                                ),
                              ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Split / Partial Remap',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                              icon: Icon(
                                Icons.call_split_rounded,
                                size: 18,
                                color: isSplit ? const Color(0xFFFF7A5C) : Colors.grey.shade600,
                              ),
                              onPressed: () => _openSplitRemapForItem(idx),
                            ),
                          ],
                        ),
                        if (isSplit)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: InkWell(
                              onTap: () => _openSplitRemapForItem(idx),
                              borderRadius: BorderRadius.circular(8),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: allocs.map((a) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF7A5C).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFFF7A5C).withValues(alpha: 0.35)),
                                    ),
                                    child: Text(
                                      '${a.recipient}: ${_formatCleanQty(a.quantity)} (₹${(a.quantity * item.unitPrice).toStringAsFixed(0)})',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFC2410C),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF7A5C)),
          onPressed: () => Navigator.pop(
            context,
            MappedInvoiceResult(
              dealer: _dealerCtrl.text.trim(),
              billNo: _billNoCtrl.text.trim(),
              billingDate: _mappedDate,
              allocationsPerItem: _allocationsPerItem
                  .map((list) => list.map((a) => a.copy()).toList())
                  .toList(),
            ),
          ),
          child: const Text('Apply to Invoice'),
        ),
      ],
    );
  }
}
