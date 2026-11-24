import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../models/transaction_model.dart';
import '../utils/currency_formatter.dart';

class ManageDetailsScreen extends StatefulWidget {
  final String? initialCategory;
  final Listenable? refreshListenable;
  final ValueChanged<TransactionTemplate>? onSelectTemplate;
  final ValueChanged<TransactionTemplate>? onEditTemplate;
  final ValueChanged<RecurringTransaction>? onSelectRecurring;
  final ValueChanged<RecurringTransaction>? onEditRecurring;

  const ManageDetailsScreen({
    super.key,
    this.initialCategory,
    this.refreshListenable,
    this.onSelectTemplate,
    this.onEditTemplate,
    this.onSelectRecurring,
    this.onEditRecurring,
  });

  @override
  State<ManageDetailsScreen> createState() => _ManageDetailsScreenState();
}

class _ManageDetailsScreenState extends State<ManageDetailsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final StorageService _storage = StorageService.instance;

  List<String> _purposes = [];
  List<String> _spentFors = [];
  Map<String, List<String>> _categoryAccounts = {};
  List<TransactionTemplate> _templates = [];
  List<RecurringTransaction> _recurring = [];
  bool _isLoading = true;

  // Categories: Bank Accounts is common for UPI, Debit cards, and Net banking
  final List<String> _categories = [
    'Purpose',
    'Spent For',
    'Bank Accounts', // Common for UPI, Debit & Net
    'Credit Cards',
    'Wallets',
    'Rewards',
    'Templates',
    'Recurring',
  ];

  @override
  void initState() {
    super.initState();
    int initialIndex = 0;
    if (widget.initialCategory != null) {
      final idx = _categories.indexWhere(
        (c) => c.toLowerCase().contains(widget.initialCategory!.toLowerCase()),
      );
      if (idx != -1) initialIndex = idx;
    }

    _tabController = TabController(
      length: _categories.length,
      vsync: this,
      initialIndex: initialIndex,
    );
    _loadData();
    widget.refreshListenable?.addListener(_loadData);
  }

  @override
  void didUpdateWidget(covariant ManageDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshListenable != oldWidget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_loadData);
      widget.refreshListenable?.addListener(_loadData);
    }
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_loadData);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_purposes.isEmpty) {
      setState(() => _isLoading = true);
    }
    final purposes = await _storage.getPurposes();
    final spentFors = await _storage.getSpentFors();
    final categoryAccounts = await _storage.getCategoryAccounts();
    final templates = await _storage.getTemplates();
    final recurring = await _storage.getRecurringTransactions();

    if (mounted) {
      setState(() {
        _purposes = purposes;
        _spentFors = spentFors;
        _categoryAccounts = categoryAccounts;
        _templates = templates;
        _recurring = recurring;
        _isLoading = false;
      });
    }
  }

  /// Adds one or multiple items separated by comma (',')
  Future<void> _showAddItemDialog(String category) async {
    if (category == 'Templates') {
      _showAddTemplateDialog();
      return;
    }

    if (category == 'Recurring') {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Text('⏳', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text('Recurring Transactions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'To set up a new recurring transaction:\n\n'
            '1. Go to the transaction form\n'
            '2. Tap the ⏳ sand timer icon to switch to recurrence mode\n'
            '3. Choose your frequency and preferred date\n'
            '4. Tap Save',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }

    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add to $category'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Name(s)',
                  hintText: 'e.g. Item 1, Item 2, Item 3',
                  helperText: 'Separate multiple items with a comma (,)',
                  helperMaxLines: 2,
                  isDense: false,
                  constraints: const BoxConstraints(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.8),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter at least one name';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      // Split by comma to support multiple items at the same time
      final itemsToAdd = result
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      for (final item in itemsToAdd) {
        if (category == 'Purpose') {
          await _storage.addPurpose(item);
        } else if (category == 'Spent For') {
          await _storage.addSpentFor(item);
        } else {
          await _storage.addAccountToCategory(category, item);
        }
      }

      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              itemsToAdd.length == 1
                  ? 'Added "${itemsToAdd.first}"'
                  : 'Added ${itemsToAdd.length} items to $category',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF0F766E),
          ),
        );
      }
    }
  }

  Future<void> _showAddTemplateDialog() async {
    final nameCtrl = TextEditingController();
    final narrationCtrl = TextEditingController();
    String flow = 'Withdraw';
    String purpose = _purposes.isNotEmpty ? _purposes.first : 'Others';
    String spentFor = _spentFors.isNotEmpty ? _spentFors.first : 'Self';
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('New Template'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Template Name',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Name required' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: narrationCtrl,
                    decoration: InputDecoration(
                      labelText: 'Narration',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Narration required' : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: flow,
                    decoration: InputDecoration(
                      labelText: 'Flow',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Withdraw', child: Text('Withdraw')),
                      DropdownMenuItem(value: 'Deposit', child: Text('Deposit')),
                    ],
                    onChanged: (v) => setDlgState(() => flow = v ?? 'Withdraw'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _purposes.contains(purpose) ? purpose : _purposes.firstOrNull,
                    decoration: InputDecoration(
                      labelText: 'Purpose',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: _purposes
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) => setDlgState(() => purpose = v ?? purpose),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _spentFors.contains(spentFor) ? spentFor : _spentFors.firstOrNull,
                    decoration: InputDecoration(
                      labelText: 'Spent For',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: _spentFors
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setDlgState(() => spentFor = v ?? spentFor),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(ctx).pop(true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      final t = TransactionTemplate(
        name: nameCtrl.text.trim(),
        narration: narrationCtrl.text.trim(),
        flow: flow,
        purpose: purpose,
        spentFor: spentFor,
        breakdowns: [
          PaymentBreakdown(paymentType: 'Cash'),
        ],
      );

      final duplicate = _templates.cast<TransactionTemplate?>().firstWhere(
        (existing) => existing != null && t.matchesDataExceptNarration(existing),
        orElse: () => null,
      );

      if (duplicate != null) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFE11D48), size: 24),
                  SizedBox(width: 8),
                  Text('Duplicate Template', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text(
                'A template with identical transaction details already exists ("${duplicate.name}").\n\n'
                'Duplicate templates matching all fields except narration are not allowed.',
                style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
              ),
              actions: [
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      await _storage.saveTemplate(t);
      await _loadData();
    }
  }

  Future<void> _onSwipeDelete(String category, String item) async {
    if (category == 'Purpose') {
      await _storage.deletePurpose(item);
    } else if (category == 'Spent For') {
      await _storage.deleteSpentFor(item);
    } else {
      await _storage.deleteAccountFromCategory(category, item);
    }
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "$item"'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onSwipeDeleteTemplate(TransactionTemplate template) async {
    await _storage.deleteTemplate(template.id);
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed template "${template.name}"'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _sortCurrentCategory(String direction) async {
    final currentCat = _categories[_tabController.index];
    if (currentCat == 'Recurring') {
      if (direction == 'asc') {
        _recurring.sort((a, b) => a.narration.toLowerCase().compareTo(b.narration.toLowerCase()));
      } else {
        _recurring.sort((a, b) => b.narration.toLowerCase().compareTo(a.narration.toLowerCase()));
      }
      await _storage.saveAllRecurringTransactions(_recurring);
    } else if (currentCat == 'Templates') {
      if (direction == 'asc') {
        _templates.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else {
        _templates.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      }
      await _storage.saveAllTemplates(_templates);
    } else {
      List<String> list;
      if (currentCat == 'Purpose') {
        list = List<String>.from(_purposes);
      } else if (currentCat == 'Spent For') {
        list = List<String>.from(_spentFors);
      } else {
        list = List<String>.from(_categoryAccounts[currentCat] ?? []);
      }

      final hasOther = list.remove('Other');
      final hasSplit = list.remove('Split');

      if (direction == 'asc') {
        list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      } else {
        list.sort((a, b) => b.toLowerCase().compareTo(a.toLowerCase()));
      }

      if (hasSplit) list.add('Split');
      if (hasOther) list.add('Other');

      if (currentCat == 'Purpose') {
        await _storage.savePurposes(list);
      } else if (currentCat == 'Spent For') {
        await _storage.saveSpentFors(list);
      } else {
        _categoryAccounts[currentCat] = list;
        await _storage.saveCategoryAccounts(_categoryAccounts);
      }
    }

    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sorted $currentCat ${direction == "asc" ? "A to Z" : "Z to A"}'),
          backgroundColor: const Color(0xFF0F766E),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Widget _buildTemplatesList() {
    if (_templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border_rounded, size: 54, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No templates saved yet',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      itemCount: _templates.length,
      onReorderItem: (int oldIndex, int newIndex) async {
        final t = _templates.removeAt(oldIndex);
        _templates.insert(newIndex, t);
        await _storage.saveAllTemplates(_templates);
        await _loadData();
      },
      itemBuilder: (context, index) {
        final t = _templates[index];

        return Container(
          key: ValueKey('template_box_${t.id}'),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Dismissible(
            key: ValueKey('template_dismiss_${t.id}'),
            direction: DismissDirection.horizontal,
            background: Container(
              padding: const EdgeInsets.only(left: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF0F766E),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerLeft,
              child: const Row(
                children: [
                  Icon(Icons.edit_note_rounded, color: Colors.white, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Load in Form',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
            secondaryBackground: Container(
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerRight,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Delete',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 24),
                ],
              ),
            ),
            confirmDismiss: (direction) async => true,
            onDismissed: (direction) {
              if (direction == DismissDirection.startToEnd) {
                widget.onEditTemplate?.call(t);
                if (mounted) Navigator.of(context).pop();
              } else if (direction == DismissDirection.endToStart) {
                _onSwipeDeleteTemplate(t);
              }
            },
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: ListTile(
                dense: true,
                onTap: () {
                  if (widget.onSelectTemplate != null) {
                    widget.onSelectTemplate!(t);
                  } else {
                    widget.onEditTemplate?.call(t);
                  }
                  if (mounted) Navigator.of(context).pop();
                },
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: const Color(0xFF0F766E).withValues(alpha: 0.12),
                  child: const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF0F766E)),
                ),
                title: Text(
                  t.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  '${t.flow} • ${t.purpose} • ${t.spentFor}\n${t.narration}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF0F766E)),
                    const SizedBox(width: 8),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.drag_handle, color: Color(0xFF94A3B8), size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    },
  );
  }

  Widget _buildRecurringList() {
    if (_recurring.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.update_disabled_rounded, size: 54, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No recurring transactions configured',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap the ⏳ sand timer in the transaction form to set one up.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      itemCount: _recurring.length,
      onReorderItem: (int oldIndex, int newIndex) async {
        final r = _recurring.removeAt(oldIndex);
        _recurring.insert(newIndex, r);
        await _storage.saveAllRecurringTransactions(_recurring);
        await _loadData();
      },
      itemBuilder: (context, index) {
        final r = _recurring[index];
        final isDue = !r.isPaused && !r.nextDueDate.isAfter(endOfToday);

        return Container(
          key: ValueKey('recurring_box_${r.id}'),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Dismissible(
            key: ValueKey('recurring_dismiss_${r.id}'),
            direction: DismissDirection.horizontal,
            background: Container(
              padding: const EdgeInsets.only(left: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF0F766E),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerLeft,
              child: const Row(
                children: [
                  Icon(Icons.edit_note_rounded, color: Colors.white, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Edit in Form',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
            secondaryBackground: Container(
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerRight,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Delete',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 24),
                ],
              ),
            ),
            confirmDismiss: (direction) async => true,
            onDismissed: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                widget.onEditRecurring?.call(r);
                if (mounted) Navigator.of(context).pop();
              } else if (direction == DismissDirection.endToStart) {
                await _storage.deleteRecurringTransaction(r.id);
                await _loadData();
              }
            },
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isDue
                      ? const Color(0xFFF59E0B)
                      : (r.isPaused ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0)),
                  width: isDue ? 1.5 : 1.0,
                ),
              ),
              child: ListTile(
                dense: true,
                onTap: () {
                  if (widget.onSelectRecurring != null) {
                    widget.onSelectRecurring!(r);
                  } else {
                    widget.onEditRecurring?.call(r);
                  }
                  if (mounted) Navigator.of(context).pop();
                },
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: r.isPaused
                      ? const Color(0xFF94A3B8).withValues(alpha: 0.15)
                      : (isDue
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.18)
                          : const Color(0xFF0F766E).withValues(alpha: 0.12)),
                  child: Text(
                    r.isPaused ? '⏸️' : (isDue ? '⏰' : '⏳'),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.narration.isNotEmpty ? r.narration : 'Recurring',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: r.isPaused ? const Color(0xFF64748B) : Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: r.isPaused
                            ? const Color(0xFF64748B).withValues(alpha: 0.15)
                            : (isDue
                                ? const Color(0xFFF59E0B).withValues(alpha: 0.18)
                                : const Color(0xFF0F766E).withValues(alpha: 0.15)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        r.isPaused ? 'PAUSED' : (isDue ? 'DUE' : 'ACTIVE'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: r.isPaused
                              ? const Color(0xFF64748B)
                              : (isDue ? const Color(0xFFB45309) : const Color(0xFF0F766E)),
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  '${r.frequency} • Next: ${FinanceTransaction.formatDate(r.nextDueDate)}${r.totalAmount > 0 ? " • ₹${IndianCurrency.format(r.totalAmount)}" : ""}',
                  style: TextStyle(
                    fontSize: 12,
                    color: r.isPaused ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        r.isPaused ? Icons.play_circle_fill_rounded : Icons.pause_circle_filled_rounded,
                        color: r.isPaused ? const Color(0xFF0F766E) : const Color(0xFFF59E0B),
                        size: 26,
                      ),
                      tooltip: r.isPaused ? 'Resume recurrence' : 'Pause recurrence',
                      onPressed: () async {
                        await _storage.togglePauseRecurringTransaction(r.id);
                        await _loadData();
                      },
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.drag_handle, color: Color(0xFF94A3B8), size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildListForCategory(String category) {
    if (category == 'Templates') {
      return _buildTemplatesList();
    }
    if (category == 'Recurring') {
      return _buildRecurringList();
    }

    List<String> items = [];
    if (category == 'Purpose') {
      items = _purposes;
    } else if (category == 'Spent For') {
      items = _spentFors;
    } else {
      items = _categoryAccounts[category] ?? [];
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 54, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No items in $category',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      itemCount: items.length,
      onReorderItem: (int oldIndex, int newIndex) async {
        final item = items.removeAt(oldIndex);
        items.insert(newIndex, item);

        if (category == 'Purpose') {
          await _storage.savePurposes(items);
        } else if (category == 'Spent For') {
          await _storage.saveSpentFors(items);
        } else {
          _categoryAccounts[category] = items;
          await _storage.saveCategoryAccounts(_categoryAccounts);
        }
        await _loadData();
      },
      itemBuilder: (context, index) {
        final item = items[index];
        final isOther = item == 'Other';

        if (isOther) {
          // Cannot delete 'Other'
          return Container(
            key: ValueKey('${category}_$item'),
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.lock_outline, size: 18, color: Colors.grey),
              title: Text(item, style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_handle, color: Color(0xFF94A3B8), size: 20),
                ),
              ),
            ),
          );
        }

        return Dismissible(
          key: ValueKey('${category}_$item'),
          direction: DismissDirection.endToStart, // Swipe right-to-left ONLY
          background: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.centerRight,
            child: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 24),
          ),
          onDismissed: (_) => _onSwipeDelete(category, item),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 12,
                backgroundColor: const Color(0xFF0F766E).withValues(alpha: 0.12),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F766E),
                  ),
                ),
              ),
              title: Text(item, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              trailing: ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_handle, color: Color(0xFF94A3B8), size: 20),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Masters'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_by_alpha, size: 22),
            tooltip: 'Sort items in tab',
            onSelected: (val) => _sortCurrentCategory(val),
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'asc',
                child: Row(
                  children: [
                    Icon(Icons.arrow_upward, size: 18, color: Color(0xFF0F766E)),
                    SizedBox(width: 8),
                    Text('Sort A to Z'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'desc',
                child: Row(
                  children: [
                    Icon(Icons.arrow_downward, size: 18, color: Color(0xFF0F766E)),
                    SizedBox(width: 8),
                    Text('Sort Z to A'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 22),
            tooltip: 'Refresh Masters',
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _categories.map((c) => Tab(text: c)).toList(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: _categories.map((c) => _buildListForCategory(c)).toList(),
            ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        onPressed: () {
          final currentCategory = _categories[_tabController.index];
          _showAddItemDialog(currentCategory);
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
