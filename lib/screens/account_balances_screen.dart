import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/account_balance_model.dart';
import '../models/transaction_model.dart';
import '../services/storage_service.dart';
import '../utils/currency_formatter.dart';
import 'emi_manager_screen.dart';
import 'financial_health_dashboard_screen.dart';
import 'transaction_history_screen.dart';

class AccountBalancesScreen extends StatefulWidget {
  final bool isInitialSetup;

  const AccountBalancesScreen({
    super.key,
    this.isInitialSetup = false,
  });

  @override
  State<AccountBalancesScreen> createState() => _AccountBalancesScreenState();
}

class _AccountBalancesScreenState extends State<AccountBalancesScreen> with SingleTickerProviderStateMixin {
  final StorageService _storage = StorageService.instance;
  late TabController _tabController;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;

  late AccountBalanceConfig _config;
  LiveAccountBalanceSummary? _liveSummary;
  Map<String, List<String>> _categories = {};

  final Map<String, TextEditingController> _bankControllers = {};
  final Map<String, TextEditingController> _ccTotalControllers = {};
  final Map<String, TextEditingController> _ccUsedControllers = {};
  final Map<String, TextEditingController> _ccGroupControllers = {};
  final Map<String, bool> _ccIsShared = {};
  final Map<String, TextEditingController> _ccBillDayControllers = {};
  final Map<String, TextEditingController> _ccDueDayControllers = {};
  final Map<String, TextEditingController> _ccBilledAmountControllers = {};
  final Map<int, TextEditingController> _cashControllers = {};
  final Map<String, TextEditingController> _walletControllers = {};
  final Map<String, TextEditingController> _rewardControllers = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _storage.emiPlansNotifier.addListener(_onEmiPlansChanged);
    _loadInitialData();
  }

  void _onEmiPlansChanged() {
    if (mounted) {
      _loadInitialData();
    }
  }

  @override
  void dispose() {
    _storage.emiPlansNotifier.removeListener(_onEmiPlansChanged);
    _tabController.dispose();
    for (final c in _bankControllers.values) {
      c.dispose();
    }
    for (final c in _ccTotalControllers.values) {
      c.dispose();
    }
    for (final c in _ccUsedControllers.values) {
      c.dispose();
    }
    for (final c in _ccGroupControllers.values) {
      c.dispose();
    }
    for (final c in _ccBillDayControllers.values) {
      c.dispose();
    }
    for (final c in _ccDueDayControllers.values) {
      c.dispose();
    }
    for (final c in _ccBilledAmountControllers.values) {
      c.dispose();
    }
    for (final c in _cashControllers.values) {
      c.dispose();
    }
    for (final c in _walletControllers.values) {
      c.dispose();
    }
    for (final c in _rewardControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    final config = await _storage.getAccountBalanceConfig();
    final categories = await _storage.getCategoryAccounts();
    final live = await _storage.getLiveAccountBalances();

    _config = config;
    _categories = categories;
    _liveSummary = live;

    _populateControllers();

    if (mounted) {
      setState(() {
        _isLoading = false;
        // Only open directly in edit mode if it's the very first time setup and not configured yet
        _isEditing = widget.isInitialSetup && !_config.isConfigured;
      });
    }
  }

  void _populateControllers() {
    // Clear old controllers or update them
    final bankList = List<String>.from(_categories['Bank Accounts'] ?? []);
    for (final k in _config.bankOpeningBalances.keys) {
      if (!bankList.contains(k)) bankList.add(k);
    }
    for (final acc in bankList) {
      final val = _config.bankOpeningBalances[acc];
      final text = val != null && val > 0 ? val.toStringAsFixed(2) : '';
      if (_bankControllers.containsKey(acc)) {
        _bankControllers[acc]!.text = text;
      } else {
        _bankControllers[acc] = TextEditingController(text: text);
      }
    }

    // Initialize Credit Card Controllers
    final ccList = List<String>.from(_categories['Credit Cards'] ?? []);
    for (final k in _config.creditCardLimits.keys) {
      if (!ccList.contains(k)) ccList.add(k);
    }
    for (final card in ccList) {
      final ccLimit = _config.creditCardLimits[card];
      final totalText = ccLimit != null && ccLimit.totalLimit > 0 ? ccLimit.totalLimit.toStringAsFixed(2) : '';
      final usedText = ccLimit != null && ccLimit.initialUsedAmount > 0 ? ccLimit.initialUsedAmount.toStringAsFixed(2) : '';
      final groupText = ccLimit?.sharedGroupName ?? '';
      final billDayText = ccLimit?.billDay != null ? ccLimit!.billDay.toString() : '';
      final dueDayText = ccLimit?.dueDay != null ? ccLimit!.dueDay.toString() : '';
      final billedText = ccLimit?.statementBilledAmount != null && ccLimit!.statementBilledAmount! > 0
          ? ccLimit.statementBilledAmount!.toStringAsFixed(2)
          : '';

      _ccIsShared[card] = ccLimit?.isShared ?? false;

      if (_ccTotalControllers.containsKey(card)) {
        _ccTotalControllers[card]!.text = totalText;
      } else {
        _ccTotalControllers[card] = TextEditingController(text: totalText);
      }

      if (_ccUsedControllers.containsKey(card)) {
        _ccUsedControllers[card]!.text = usedText;
      } else {
        _ccUsedControllers[card] = TextEditingController(text: usedText);
      }

      if (_ccGroupControllers.containsKey(card)) {
        _ccGroupControllers[card]!.text = groupText;
      } else {
        _ccGroupControllers[card] = TextEditingController(text: groupText);
      }

      if (_ccBillDayControllers.containsKey(card)) {
        _ccBillDayControllers[card]!.text = billDayText;
      } else {
        _ccBillDayControllers[card] = TextEditingController(text: billDayText);
      }

      if (_ccDueDayControllers.containsKey(card)) {
        _ccDueDayControllers[card]!.text = dueDayText;
      } else {
        _ccDueDayControllers[card] = TextEditingController(text: dueDayText);
      }

      if (_ccBilledAmountControllers.containsKey(card)) {
        _ccBilledAmountControllers[card]!.text = billedText;
      } else {
        _ccBilledAmountControllers[card] = TextEditingController(text: billedText);
      }
    }

    // Initialize Cash Controllers (500, 200, 100, 50, 20, 10, 5, 2, 1)
    for (final denom in PaymentBreakdown.supportedDenominations) {
      final count = _config.cashOpeningDenominations[denom] ?? 0;
      final text = count > 0 ? count.toString() : '';
      if (_cashControllers.containsKey(denom)) {
        _cashControllers[denom]!.text = text;
      } else {
        _cashControllers[denom] = TextEditingController(text: text);
      }
    }

    // Initialize Wallet Controllers
    final walletList = List<String>.from(_categories['Wallets'] ?? []);
    for (final k in _config.walletOpeningBalances.keys) {
      if (!walletList.contains(k)) walletList.add(k);
    }
    for (final w in walletList) {
      final val = _config.walletOpeningBalances[w];
      final text = val != null && val > 0 ? val.toStringAsFixed(2) : '';
      if (_walletControllers.containsKey(w)) {
        _walletControllers[w]!.text = text;
      } else {
        _walletControllers[w] = TextEditingController(text: text);
      }
    }

    // Initialize Reward Controllers
    final rewardList = List<String>.from(_categories['Rewards'] ?? []);
    for (final k in _config.rewardOpeningBalances.keys) {
      if (!rewardList.contains(k)) rewardList.add(k);
    }
    for (final r in rewardList) {
      final val = _config.rewardOpeningBalances[r];
      final text = val != null && val > 0 ? val.toStringAsFixed(2) : '';
      if (_rewardControllers.containsKey(r)) {
        _rewardControllers[r]!.text = text;
      } else {
        _rewardControllers[r] = TextEditingController(text: text);
      }
    }
  }

  void _cancelEdit() {
    HapticFeedback.lightImpact();
    _populateControllers();
    setState(() => _isEditing = false);
  }

  double _calculateCurrentEnteredCashTotal() {
    double sum = 0.0;
    for (final denom in PaymentBreakdown.supportedDenominations) {
      final count = int.tryParse(_cashControllers[denom]?.text.trim() ?? '') ?? 0;
      sum += denom * count;
    }
    return sum;
  }

  Future<void> _saveBalances() async {
    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);

    final Map<String, double> bankOpening = {};
    for (final entry in _bankControllers.entries) {
      final amt = double.tryParse(entry.value.text.trim()) ?? 0.0;
      bankOpening[entry.key] = amt;
    }

    final Map<String, CreditCardLimit> ccLimits = {};
    for (final card in _ccTotalControllers.keys) {
      final total = double.tryParse(_ccTotalControllers[card]?.text.trim() ?? '') ?? 0.0;
      final used = double.tryParse(_ccUsedControllers[card]?.text.trim() ?? '') ?? 0.0;
      final isShared = _ccIsShared[card] ?? false;
      final groupName = isShared ? _ccGroupControllers[card]?.text.trim() : null;
      final billDay = int.tryParse(_ccBillDayControllers[card]?.text.trim() ?? '');
      final dueDay = int.tryParse(_ccDueDayControllers[card]?.text.trim() ?? '');
      final billedAmt = double.tryParse(_ccBilledAmountControllers[card]?.text.trim() ?? '');

      final prev = _config.creditCardLimits[card];

      ccLimits[card] = CreditCardLimit(
        totalLimit: total,
        initialUsedAmount: used,
        sharedGroupName: groupName,
        groupTotalLimit: isShared ? total : null,
        billDay: billDay,
        dueDay: dueDay,
        statementBilledAmount: billedAmt,
        manualPaidCycle: prev?.manualPaidCycle,
      );
    }

    // If shared group total was edited on any card, sync groupTotalLimit across all cards in that group
    final Map<String, double> groupLimits = {};
    for (final card in ccLimits.values) {
      if (card.isShared && card.sharedGroupName != null) {
        if (card.totalLimit > 0) {
          groupLimits[card.sharedGroupName!] = card.totalLimit;
        }
      }
    }
    for (final key in ccLimits.keys.toList()) {
      final c = ccLimits[key]!;
      if (c.isShared && c.sharedGroupName != null && groupLimits.containsKey(c.sharedGroupName)) {
        ccLimits[key] = c.copyWith(
          totalLimit: groupLimits[c.sharedGroupName!]!,
          groupTotalLimit: groupLimits[c.sharedGroupName!]!,
        );
      }
    }

    final Map<int, int> cashOpening = {};
    for (final denom in PaymentBreakdown.supportedDenominations) {
      final count = int.tryParse(_cashControllers[denom]?.text.trim() ?? '') ?? 0;
      cashOpening[denom] = count;
    }

    final Map<String, double> walletOpening = {};
    for (final entry in _walletControllers.entries) {
      final text = entry.value.text.trim();
      final val = double.tryParse(text) ?? 0.0;
      walletOpening[entry.key] = val;
    }

    final Map<String, double> rewardOpening = {};
    for (final entry in _rewardControllers.entries) {
      final text = entry.value.text.trim();
      final val = double.tryParse(text) ?? 0.0;
      rewardOpening[entry.key] = val;
    }

    final updatedConfig = _config.copyWith(
      bankOpeningBalances: bankOpening,
      creditCardLimits: ccLimits,
      cashOpeningDenominations: cashOpening,
      walletOpeningBalances: walletOpening,
      rewardOpeningBalances: rewardOpening,
      setupDate: _config.isConfigured ? _config.setupDate : DateTime.now(),
      isConfigured: true,
    );

    await _storage.saveAccountBalanceConfig(updatedConfig);
    final freshLive = await _storage.getLiveAccountBalances();

    if (mounted) {
      setState(() {
        _isSaving = false;
        _config = updatedConfig;
        _liveSummary = freshLive;
        _isEditing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(child: Text('Balances & limits saved successfully!')),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

      if (widget.isInitialSetup) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _removeAccountDialog(String category, String accountName) async {
    String typeLabel = 'Account';
    if (category == 'Credit Cards') typeLabel = 'Card';
    if (category == 'Wallets') typeLabel = 'Wallet';
    if (category == 'Rewards') typeLabel = 'Reward Account';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove $typeLabel?'),
        content: Text(
          'Are you sure you want to remove "$accountName" from your balances and master list?\n\nThis will also remove it from the "Account Balances" sheet in your Google Drive on the next sync.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _storage.removeAccountFromBalances(category, accountName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed "$accountName" successfully', textAlign: TextAlign.center),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        await _loadInitialData();
      }
    }
  }

  Future<void> _addNewAccountDialog(String category) async {
    final textController = TextEditingController();
    String typeLabel = 'Bank Account';
    String hint = 'e.g. Axis Salary A/c';
    if (category == 'Credit Cards') {
      typeLabel = 'Credit Card';
      hint = 'e.g. ICICI Coral Card';
    } else if (category == 'Wallets') {
      typeLabel = 'Wallet';
      hint = 'e.g. Paytm Wallet / PhonePe';
    } else if (category == 'Rewards') {
      typeLabel = 'Reward / Points Account';
      hint = 'e.g. SuperCoins / NeuCoins';
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add New $typeLabel'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '$typeLabel Name',
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                await _storage.addAccountToCategory(category, name);
                if (ctx.mounted) Navigator.of(ctx).pop();
                _loadInitialData();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5);
    final bg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing
                  ? (widget.isInitialSetup ? 'Initial Balances Setup' : 'Edit Balances & Limits')
                  : 'Balances & Limits',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              _isEditing
                  ? 'Set baseline opening balances & limits'
                  : 'Available balances & limits overview',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
            ),
          ],
        ),
        actions: [
          if (_isEditing) ...[
            if (_config.isConfigured)
              TextButton(
                onPressed: _cancelEdit,
                child: Text('Cancel', style: TextStyle(color: textSecondary, fontWeight: FontWeight.w600)),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: _isSaving ? null : _saveBalances,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ] else ...[
            IconButton(
              icon: Icon(Icons.insights_rounded, color: primaryColor),
              tooltip: 'Financial Health & Liquidity',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FinancialHealthDashboardScreen()),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() => _isEditing = true);
                },
                icon: Icon(Icons.edit_rounded, size: 18, color: primaryColor),
                label: Text('Edit', style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor)),
              ),
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: primaryColor,
          unselectedLabelColor: textSecondary,
          indicatorColor: primaryColor,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.account_balance_rounded, size: 20), text: 'Bank Accounts'),
            Tab(icon: Icon(Icons.credit_card_rounded, size: 20), text: 'Credit Cards'),
            Tab(icon: Icon(Icons.payments_rounded, size: 20), text: 'Cash In Hand'),
            Tab(icon: Icon(Icons.account_balance_wallet_rounded, size: 20), text: 'Wallets'),
            Tab(icon: Icon(Icons.stars_rounded, size: 20), text: 'Rewards'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (widget.isInitialSetup && _isEditing)
                  Container(
                    margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: primaryColor, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Enter your opening bank balances, credit card limits, cash in hand, wallet balances, and rewards to enable live balance and running balance calculations.',
                            style: TextStyle(fontSize: 12.5, color: textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _isEditing
                          ? _buildBankEditTab(cardBg, textPrimary, textSecondary, borderColor, isDark, primaryColor)
                          : _buildBankViewTab(cardBg, textPrimary, textSecondary, borderColor, isDark, primaryColor),
                      _isEditing
                          ? _buildCreditCardEditTab(cardBg, textPrimary, textSecondary, borderColor, isDark, primaryColor)
                          : _buildCreditCardViewTab(cardBg, textPrimary, textSecondary, borderColor, isDark, primaryColor),
                      _isEditing
                          ? _buildCashEditTab(cardBg, textPrimary, textSecondary, borderColor, isDark, primaryColor)
                          : _buildCashViewTab(cardBg, textPrimary, textSecondary, borderColor, isDark, primaryColor),
                      _isEditing
                          ? _buildWalletsEditTab(cardBg, textPrimary, textSecondary, borderColor, isDark, primaryColor)
                          : _buildWalletsViewTab(cardBg, textPrimary, textSecondary, borderColor, isDark, primaryColor),
                      _isEditing
                          ? _buildRewardsEditTab(cardBg, textPrimary, textSecondary, borderColor, isDark, primaryColor)
                          : _buildRewardsViewTab(cardBg, textPrimary, textSecondary, borderColor, isDark, primaryColor),
                    ],
                  ),
                ),
                _buildBottomBar(primaryColor, isDark),
              ],
            ),
    );
  }

  // ==========================================
  // TAB 1: BANK ACCOUNTS - VIEW MODE
  // ==========================================
  void _openAccountHistory(String accountName) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'History'),
        builder: (_) => TransactionHistoryScreen(initialAccountFilter: accountName),
      ),
    );
  }

  Widget _buildBankViewTab(Color cardBg, Color textPrimary, Color textSecondary, Color borderColor, bool isDark, Color primaryColor) {
    final bankList = _bankControllers.keys.toList();

    double totalAvailable = 0.0;
    double totalOpening = 0.0;
    for (final acc in bankList) {
      final live = _liveSummary?.bankBalances[acc] ?? (_config.bankOpeningBalances[acc] ?? 0.0);
      final opening = _config.bankOpeningBalances[acc] ?? 0.0;
      totalAvailable += live;
      totalOpening += opening;
    }
    final totalDiff = totalAvailable - totalOpening;

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          // Total Bank Available Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF064E3B).withValues(alpha: 0.3) : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF059669).withValues(alpha: 0.4) : const Color(0xFFA7F3D0),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.account_balance_rounded, color: Color(0xFF059669), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL AVAILABLE IN BANKS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: isDark ? const Color(0xFF34D399) : const Color(0xFF065F46),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${IndianCurrency.format(totalAvailable)}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '${bankList.length} accounts • Opening: ₹${IndianCurrency.format(totalOpening)}',
                            style: TextStyle(fontSize: 11.5, color: textSecondary),
                          ),
                          if (totalDiff != 0) ...[
                            const SizedBox(width: 6),
                            Icon(
                              totalDiff > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                              size: 14,
                              color: totalDiff > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${totalDiff > 0 ? "+" : "-"}₹${IndianCurrency.format(totalDiff.abs())}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: totalDiff > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
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
          ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Bank Accounts (${bankList.length})',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPrimary),
              ),
              Text(
                'Pull to refresh ⟳',
                style: TextStyle(fontSize: 11.5, color: textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (bankList.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.account_balance_outlined, size: 36, color: textSecondary),
                    const SizedBox(height: 8),
                    Text('No bank accounts configured yet', style: TextStyle(color: textSecondary)),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _isEditing = true),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add Accounts in Edit Mode'),
                    ),
                  ],
                ),
              ),
            )
          else
            ...bankList.map((acc) {
              final liveBal = _liveSummary?.bankBalances[acc] ?? (_config.bankOpeningBalances[acc] ?? 0.0);
              final openingBal = _config.bankOpeningBalances[acc] ?? 0.0;
              final diff = liveBal - openingBal;

              return GestureDetector(
                onTap: () => _openAccountHistory(acc),
                child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor, width: 1.1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.account_balance_rounded, color: Color(0xFF059669), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            acc,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: textPrimary),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(
                                'Opening: ₹${IndianCurrency.format(openingBal)}',
                                style: TextStyle(fontSize: 12, color: textSecondary),
                              ),
                              if (diff != 0) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '(${diff > 0 ? "+" : "-"}₹${IndianCurrency.format(diff.abs())})',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: diff > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${IndianCurrency.format(liveBal)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: liveBal >= 0
                                ? (isDark ? const Color(0xFF34D399) : const Color(0xFF047857))
                                : const Color(0xFFEF4444),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Available',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                      tooltip: 'Remove $acc',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeAccountDialog('Bank Accounts', acc),
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

  // ==========================================
  // TAB 1: BANK ACCOUNTS - EDIT MODE
  // ==========================================
  Widget _buildBankEditTab(Color cardBg, Color textPrimary, Color textSecondary, Color borderColor, bool isDark, Color primaryColor) {
    final bankList = _bankControllers.keys.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Savings & Current Accounts (${bankList.length})',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPrimary),
            ),
            TextButton.icon(
              onPressed: () => _addNewAccountDialog('Bank Accounts'),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Account', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...bankList.map((acc) {
          final liveBal = _liveSummary?.bankBalances[acc];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.account_balance_rounded, color: Color(0xFF059669), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        acc,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPrimary),
                      ),
                    ),
                    if (liveBal != null && _config.isConfigured)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'Available: ₹${IndianCurrency.format(liveBal)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                      tooltip: 'Remove Account',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeAccountDialog('Bank Accounts', acc),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: TextField(
                          controller: _bankControllers[acc],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Opening Balance (₹)',
                            hintText: '0.00',
                            prefixIcon: const Icon(Icons.currency_rupee_rounded, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ==========================================
  // TAB 2: CREDIT CARDS - VIEW MODE
  // ==========================================
  Widget _buildCreditCardViewTab(Color cardBg, Color textPrimary, Color textSecondary, Color borderColor, bool isDark, Color primaryColor) {
    final ccList = _ccTotalControllers.keys.toList();

    // Deduplicate shared group totals to compute accurate overall credit metrics
    final Set<String> countedGroups = {};
    double totalCreditLimit = 0.0;
    double totalUsedLimit = 0.0;
    double totalAvailableLimit = 0.0;

    for (final card in ccList) {
      final summary = _liveSummary?.creditCardSummaries[card];
      final limitConfig = _config.creditCardLimits[card];

      if (summary != null) {
        if (summary.isShared && summary.sharedGroupName != null) {
          if (!countedGroups.contains(summary.sharedGroupName)) {
            countedGroups.add(summary.sharedGroupName!);
            totalCreditLimit += summary.groupTotalLimit ?? summary.totalLimit;
            totalUsedLimit += summary.groupTotalUsed ?? summary.usedLimit;
            totalAvailableLimit += summary.availableLimit;
          }
        } else {
          totalCreditLimit += summary.totalLimit;
          totalUsedLimit += summary.usedLimit;
          totalAvailableLimit += summary.availableLimit;
        }
      } else if (limitConfig != null) {
        totalCreditLimit += limitConfig.totalLimit;
        totalUsedLimit += limitConfig.initialUsedAmount;
        totalAvailableLimit += (limitConfig.totalLimit - limitConfig.initialUsedAmount).clamp(0.0, double.infinity);
      }
    }

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          // Total Cards Overview Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF312E81).withValues(alpha: 0.35) : const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF4F46E5).withValues(alpha: 0.4) : const Color(0xFFC7D2FE),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.credit_card_rounded, color: Color(0xFF4F46E5), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOTAL CREDIT CARDS LIMIT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF3730A3),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '₹${IndianCurrency.format(totalCreditLimit)}',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : const Color(0xFF1E1B4B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AVAILABLE LIMIT',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '₹${IndianCurrency.format(totalAvailableLimit)}',
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'USED / OUTSTANDING',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '₹${IndianCurrency.format(totalUsedLimit)}',
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if ((_liveSummary?.totalUnbilledEmiPrincipal ?? 0.0) > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5C38).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFF5C38).withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.pie_chart_outline_rounded, size: 15, color: Color(0xFFFF5C38)),
                            SizedBox(width: 7),
                            Text(
                              'Unbilled Active EMIs',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFFF5C38)),
                            ),
                          ],
                        ),
                        Text(
                          '₹${IndianCurrency.format(_liveSummary!.totalUnbilledEmiPrincipal)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFFF5C38)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Credit Cards (${ccList.length})',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPrimary),
              ),
              Text(
                'Pull to refresh ⟳',
                style: TextStyle(fontSize: 11.5, color: textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Best Card to Use Today Optimizer Banner
          if (_liveSummary != null && ccList.isNotEmpty)
            () {
              final candidates = ccList
                  .map((c) => _liveSummary!.creditCardSummaries[c])
                  .whereType<LiveCreditCardSummary>()
                  .where((s) => s.interestFreeDays != null && s.availableLimit > 0)
                  .toList();
              if (candidates.isEmpty) return const SizedBox.shrink();
              candidates.sort((a, b) {
                final aLowUtil = a.totalLimit > 0 ? (a.usedLimit / a.totalLimit) < 0.5 : true;
                final bLowUtil = b.totalLimit > 0 ? (b.usedLimit / b.totalLimit) < 0.5 : true;
                if (aLowUtil != bLowUtil) return aLowUtil ? -1 : 1;
                return (b.interestFreeDays ?? 0).compareTo(a.interestFreeDays ?? 0);
              });
              final best = candidates.first;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E1B4B), const Color(0xFF312E81)]
                        : [const Color(0xFFEEF2FF), const Color(0xFFE0E7FF)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF6366F1), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BEST CARD TO SWIPE TODAY',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4338CA),
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${best.cardName} · ${best.interestFreeDays}d interest-free',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                          Text(
                            'Avail: ₹${IndianCurrency.format(best.availableLimit)} · Bill Day ${best.billDay}',
                            style: TextStyle(fontSize: 11, color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }(),

          if (ccList.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.credit_card_off_rounded, size: 36, color: textSecondary),
                    const SizedBox(height: 8),
                    Text('No credit cards configured yet', style: TextStyle(color: textSecondary)),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _isEditing = true),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add Cards in Edit Mode'),
                    ),
                  ],
                ),
              ),
            )
          else
            ...ccList.map((card) {
              final liveSummary = _liveSummary?.creditCardSummaries[card];
              final configLimit = _config.creditCardLimits[card];

              final isShared = liveSummary?.isShared ?? (configLimit?.isShared ?? false);
              final sharedGroup = liveSummary?.sharedGroupName ?? configLimit?.sharedGroupName;

              final totalLimit = isShared
                  ? (liveSummary?.groupTotalLimit ?? configLimit?.groupTotalLimit ?? configLimit?.totalLimit ?? 0.0)
                  : (liveSummary?.totalLimit ?? configLimit?.totalLimit ?? 0.0);

              final usedLimit = isShared
                  ? (liveSummary?.groupTotalUsed ?? configLimit?.initialUsedAmount ?? 0.0)
                  : (liveSummary?.usedLimit ?? configLimit?.initialUsedAmount ?? 0.0);
              final individualUsedLimit = liveSummary?.usedLimit ?? configLimit?.initialUsedAmount ?? 0.0;

              final available = liveSummary?.availableLimit ?? (totalLimit - usedLimit).clamp(0.0, double.infinity);
              final utilization = totalLimit > 0 ? (usedLimit / totalLimit).clamp(0.0, 1.0) : 0.0;

              final billDay = liveSummary?.billDay ?? configLimit?.billDay;
              final dueDay = liveSummary?.dueDay ?? configLimit?.dueDay;
              final nextDue = liveSummary?.nextDueDate;
              final dueBill = liveSummary?.dueBill;

              return GestureDetector(
                onTap: () => _openAccountHistory(card),
                child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor, width: 1.1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Card Title & Available Badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.credit_card_rounded, color: Color(0xFF4F46E5), size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                card,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: textPrimary),
                              ),
                              if (isShared && sharedGroup != null && sharedGroup.isNotEmpty) ...[
                                const SizedBox(height: 1),
                                Row(
                                  children: [
                                    const Icon(Icons.group_work_rounded, size: 12, color: Color(0xFF6366F1)),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Shared: $sharedGroup',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF6366F1),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'AVAILABLE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF059669),
                                ),
                              ),
                              Text(
                                '₹${IndianCurrency.format(available)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                          tooltip: 'Remove $card',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _removeAccountDialog('Credit Cards', card),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Utilization Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: utilization,
                        minHeight: 6,
                        backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          utilization > 0.8
                              ? const Color(0xFFEF4444)
                              : (utilization > 0.4 ? const Color(0xFFF59E0B) : const Color(0xFF10B981)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Limits row: Total Limit & Used Limit
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${isShared ? "Group Limit: " : "Limit: "}₹${IndianCurrency.format(totalLimit)}',
                          style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${isShared ? "Group Used: " : "Used: "}₹${IndianCurrency.format(usedLimit)} (${(utilization * 100).toStringAsFixed(1)}%)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: utilization > 0.8
                                ? const Color(0xFFEF4444)
                                : (isDark ? Colors.white70 : const Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                    if (isShared) ...[
                      const SizedBox(height: 5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'This Card Used',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '₹${IndianCurrency.format(individualUsedLimit)}${totalLimit > 0 ? ' (${((individualUsedLimit / totalLimit) * 100).clamp(0.0, 100.0).toStringAsFixed(1)}%)' : ''}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Billed vs Unbilled vs Blocked EMI Split & Interest-Free Days
                    if (liveSummary != null &&
                        (individualUsedLimit > 0.01 || liveSummary.interestFreeDays != null)) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (liveSummary.billedDueAmount > 0.01)
                            _buildCardSplitPill(
                              'Billed: ₹${IndianCurrency.format(liveSummary.billedDueAmount)}',
                              const Color(0xFFEF4444),
                            ),
                          if (liveSummary.unbilledSpendAmount > 0.01)
                            _buildCardSplitPill(
                              'Unbilled: ₹${IndianCurrency.format(liveSummary.unbilledSpendAmount)}',
                              const Color(0xFFF59E0B),
                            ),
                          if (liveSummary.blockedEmiPrincipal > 0.01)
                            _buildCardSplitPill(
                              'EMI: ₹${IndianCurrency.format(liveSummary.blockedEmiPrincipal)}',
                              const Color(0xFF6366F1),
                            ),
                          if (liveSummary.interestFreeDays != null)
                            _buildCardSplitPill(
                              '${liveSummary.interestFreeDays}d interest-free',
                              const Color(0xFF10B981),
                            ),
                        ],
                      ),
                    ],

                    // Billing & Due Cycle Info
                    if (billDay != null || dueDay != null || nextDue != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month_rounded, size: 14, color: textSecondary),
                            const SizedBox(width: 6),
                            if (billDay != null)
                              Text('Bill: ${billDay}th  •  ', style: TextStyle(fontSize: 11.5, color: textSecondary)),
                            if (dueDay != null)
                              Text('Due: ${dueDay}th', style: TextStyle(fontSize: 11.5, color: textSecondary)),
                            const Spacer(),
                            if (nextDue != null)
                              Text(
                                'Next Due: ${DateFormat('dd MMM').format(nextDue)}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],

                    // Active Due Bill Notification Alert
                    if (dueBill != null && dueBill.remainingDue > 0.01) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: (dueBill.isOverdue || dueBill.isDueToday)
                              ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                              : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (dueBill.isOverdue || dueBill.isDueToday)
                                ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                                : const Color(0xFFF59E0B).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              (dueBill.isOverdue || dueBill.isDueToday)
                                  ? Icons.warning_amber_rounded
                                  : Icons.notifications_active_rounded,
                              size: 16,
                              color: (dueBill.isOverdue || dueBill.isDueToday)
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFFD97706),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        dueBill.isOverdue
                                            ? 'BILL OVERDUE'
                                            : (dueBill.isDueToday ? 'BILL DUE TODAY' : 'BILL DUE SOON'),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: (dueBill.isOverdue || dueBill.isDueToday)
                                              ? const Color(0xFFDC2626)
                                              : const Color(0xFFD97706),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        'Due: ₹${IndianCurrency.format(dueBill.remainingDue)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: (dueBill.isOverdue || dueBill.isDueToday)
                                              ? const Color(0xFFDC2626)
                                              : const Color(0xFFD97706),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Billed: ₹${IndianCurrency.format(dueBill.billedAmount)} | Paid: ₹${IndianCurrency.format(dueBill.paidAmount)}',
                                    style: TextStyle(fontSize: 11, color: textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Active EMIs Info Banner on Individual Card
                    if (liveSummary != null && liveSummary.unbilledEmiPrincipal > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF5C38).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFFF5C38).withValues(alpha: 0.3),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF5C38).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.pie_chart_rounded, size: 14, color: Color(0xFFFF5C38)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'ACTIVE EMIs (${liveSummary.activeEmiPlansCount})',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFFF5C38),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        'Unbilled: ₹${IndianCurrency.format(liveSummary.unbilledEmiPrincipal)}',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFFF5C38),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (liveSummary.nextEmiDueDate != null && liveSummary.nextEmiAmount != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Next EMI: ₹${IndianCurrency.format(liveSummary.nextEmiAmount!)} due ${DateFormat('dd MMM').format(liveSummary.nextEmiDueDate!)}',
                                      style: TextStyle(fontSize: 11, color: textSecondary),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const EmiManagerScreen()),
                                );
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFFFF5C38)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: CREDIT CARDS - EDIT MODE
  // ==========================================
  Widget _buildCreditCardEditTab(Color cardBg, Color textPrimary, Color textSecondary, Color borderColor, bool isDark, Color primaryColor) {
    final ccList = _ccTotalControllers.keys.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Credit Cards (${ccList.length})',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPrimary),
            ),
            TextButton.icon(
              onPressed: () => _addNewAccountDialog('Credit Cards'),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Card', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...ccList.map((card) {
          final liveSummary = _liveSummary?.creditCardSummaries[card];
          final isShared = _ccIsShared[card] ?? false;
          final currentTotal = double.tryParse(_ccTotalControllers[card]?.text.trim() ?? '') ?? 0.0;
          final currentUsed = double.tryParse(_ccUsedControllers[card]?.text.trim() ?? '') ?? 0.0;
          final available = liveSummary?.availableLimit ?? (currentTotal - currentUsed).clamp(0.0, double.infinity);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Card Header Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.credit_card_rounded, color: Color(0xFF4F46E5), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPrimary),
                          ),
                          if (isShared && _ccGroupControllers[card]?.text.isNotEmpty == true)
                            Text(
                              'Shared: ${_ccGroupControllers[card]!.text}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6366F1)),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'Available: ₹${IndianCurrency.format(available)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF059669),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                      tooltip: 'Remove Card',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeAccountDialog('Credit Cards', card),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Limit Mode Selector: Standalone vs Shared Group
                Row(
                  children: [
                    Text('Limit Mode:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textSecondary)),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Standalone', style: TextStyle(fontSize: 11)),
                      selected: !isShared,
                      visualDensity: VisualDensity.compact,
                      onSelected: (selected) {
                        setState(() {
                          _ccIsShared[card] = !selected;
                        });
                      },
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('Shared Group', style: TextStyle(fontSize: 11)),
                      selected: isShared,
                      visualDensity: VisualDensity.compact,
                      onSelected: (selected) {
                        setState(() {
                          _ccIsShared[card] = selected;
                          if (selected && (_ccGroupControllers[card]?.text.isEmpty ?? true)) {
                            final parts = card.split(' ');
                            _ccGroupControllers[card]?.text = parts.isNotEmpty ? '${parts.first} Bank Cards' : 'Shared Cards';
                          }
                        });
                      },
                    ),
                  ],
                ),

                if (isShared) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 44,
                    child: TextField(
                      controller: _ccGroupControllers[card],
                      decoration: InputDecoration(
                        labelText: 'Shared Group Name',
                        hintText: 'e.g. Axis Bank Cards',
                        prefixIcon: const Icon(Icons.group_work_rounded, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],

                const SizedBox(height: 10),

                // Total Limit and Used Limit Inputs
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: TextField(
                          controller: _ccTotalControllers[card],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: isShared ? 'Group Total Limit (₹)' : 'Total Limit (₹)',
                            hintText: 'e.g. 150000',
                            prefixIcon: const Icon(Icons.credit_score_rounded, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: TextField(
                          controller: _ccUsedControllers[card],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Initial Used (₹)',
                            hintText: 'e.g. 15000',
                            prefixIcon: const Icon(Icons.money_off_rounded, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Bill Day & Due Day Inputs
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: TextField(
                          controller: _ccBillDayControllers[card],
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Bill Day (1-31)',
                            hintText: 'e.g. 15',
                            prefixIcon: const Icon(Icons.calendar_month_rounded, size: 17),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: TextField(
                          controller: _ccDueDayControllers[card],
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Due Day (1-31)',
                            hintText: 'e.g. 2',
                            prefixIcon: const Icon(Icons.event_available_rounded, size: 17),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Due Cycle Info preview if configured
                if (liveSummary?.nextDueDate != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 13, color: textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'Next Due: ${DateFormat('dd MMM yyyy').format(liveSummary!.nextDueDate!)}'
                        '${liveSummary.dueBill?.isDueToday == true ? " • DUE TODAY ⚠️" : ""}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: liveSummary.dueBill?.isDueToday == true ? const Color(0xFFEF4444) : textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  // ==========================================
  // TAB 3: CASH IN HAND - VIEW MODE
  // ==========================================
  Widget _buildCashViewTab(Color cardBg, Color textPrimary, Color textSecondary, Color borderColor, bool isDark, Color primaryColor) {
    final liveCash = _liveSummary?.totalCashInHand ?? _config.totalCashInHand;
    final openingCash = _config.totalCashInHand;
    final diff = liveCash - openingCash;

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          // Total Cash Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF064E3B).withValues(alpha: 0.3) : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF059669).withValues(alpha: 0.4) : const Color(0xFFA7F3D0),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.payments_rounded, color: Color(0xFF059669), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL CASH IN HAND',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: isDark ? const Color(0xFF34D399) : const Color(0xFF065F46),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${IndianCurrency.format(liveCash)}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'Opening: ₹${IndianCurrency.format(openingCash)}',
                            style: TextStyle(fontSize: 11.5, color: textSecondary),
                          ),
                          if (diff != 0) ...[
                            const SizedBox(width: 6),
                            Icon(
                              diff > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                              size: 14,
                              color: diff > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${diff > 0 ? "+" : "-"}₹${IndianCurrency.format(diff.abs())}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: diff > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
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
          ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cash Denominations (3 × 3 Grid)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textSecondary),
              ),
              Text(
                'Pull to refresh ⟳',
                style: TextStyle(fontSize: 11.5, color: textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.45,
            ),
            itemCount: PaymentBreakdown.supportedDenominations.length,
            itemBuilder: (context, idx) {
              final denom = PaymentBreakdown.supportedDenominations[idx];
              final count = _liveSummary?.cashDenominations[denom] ?? (_config.cashOpeningDenominations[denom] ?? 0);
              final subtotal = denom * count;
              final hasValue = count > 0;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? (hasValue ? const Color(0xFF1E284A) : const Color(0xFF1B2042))
                      : (hasValue ? const Color(0xFFF0FDF4) : Colors.white),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasValue
                        ? (isDark ? const Color(0xFF00D2B4) : const Color(0xFF10B981))
                        : (isDark ? const Color(0xFF282F5A) : const Color(0xFFE2E8F0)),
                    width: hasValue ? 1.4 : 0.9,
                  ),
                  boxShadow: hasValue
                      ? [
                          BoxShadow(
                            color: (isDark ? const Color(0xFF00D2B4) : const Color(0xFF10B981))
                                .withValues(alpha: isDark ? 0.20 : 0.10),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: hasValue
                            ? (isDark
                                ? const Color(0xFF00D2B4).withValues(alpha: 0.2)
                                : const Color(0xFF10B981).withValues(alpha: 0.12))
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '₹$denom',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: hasValue
                              ? (isDark ? const Color(0xFF00D2B4) : const Color(0xFF059669))
                              : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '× $count',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: hasValue
                            ? (isDark ? Colors.white : const Color(0xFF0F172A))
                            : textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${IndianCurrency.format(subtotal)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: hasValue
                            ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                            : textSecondary,
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
  }

  // ==========================================
  // TAB 3: CASH IN HAND - EDIT MODE
  // ==========================================
  Widget _buildCashEditTab(Color cardBg, Color textPrimary, Color textSecondary, Color borderColor, bool isDark, Color primaryColor) {
    final enteredTotal = _calculateCurrentEnteredCashTotal();
    final liveCash = _liveSummary?.totalCashInHand;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3), width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'OPENING CASH IN HAND',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₹${IndianCurrency.format(enteredTotal)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF047857),
                    ),
                  ),
                ],
              ),
              if (liveCash != null && _config.isConfigured)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'CURRENT LIVE CASH',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${IndianCurrency.format(liveCash)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Cash Denomination Counts (3 × 3 Matrix)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textSecondary),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.65,
          ),
          itemCount: PaymentBreakdown.supportedDenominations.length,
          itemBuilder: (context, idx) {
            final denom = PaymentBreakdown.supportedDenominations[idx];
            final controller = _cashControllers[denom];
            final count = int.tryParse(controller?.text.trim() ?? '') ?? 0;
            final hasValue = count > 0;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 22,
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
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
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

// ==========================================
  // TAB 4: WALLETS - VIEW MODE
  // ==========================================
  Widget _buildWalletsViewTab(Color cardBg, Color textPrimary, Color textSecondary, Color borderColor, bool isDark, Color primaryColor) {
    final walletList = _walletControllers.keys.toList();

    double totalAvailable = 0.0;
    double totalOpening = 0.0;
    for (final acc in walletList) {
      final live = _liveSummary?.walletBalances[acc] ?? (_config.walletOpeningBalances[acc] ?? 0.0);
      final opening = _config.walletOpeningBalances[acc] ?? 0.0;
      totalAvailable += live;
      totalOpening += opening;
    }
    final totalDiff = totalAvailable - totalOpening;

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          // Total Wallet Available Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F766E).withValues(alpha: 0.3) : const Color(0xFFF0FDFA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF14B8A6).withValues(alpha: 0.4) : const Color(0xFF99F6E4),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF0D9488), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL AVAILABLE IN WALLETS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF115E59),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${IndianCurrency.format(totalAvailable)}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '${walletList.length} wallets • Opening: ₹${IndianCurrency.format(totalOpening)}',
                            style: TextStyle(fontSize: 11.5, color: textSecondary),
                          ),
                          if (totalDiff != 0) ...[
                            const SizedBox(width: 6),
                            Icon(
                              totalDiff > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                              size: 14,
                              color: totalDiff > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${totalDiff > 0 ? "+" : "-"}₹${IndianCurrency.format(totalDiff.abs())}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: totalDiff > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
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
          ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Digital Wallets (${walletList.length})',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPrimary),
              ),
              Text(
                'Pull to refresh ⟳',
                style: TextStyle(fontSize: 11.5, color: textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (walletList.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined, size: 36, color: textSecondary),
                    const SizedBox(height: 8),
                    Text('No wallets configured yet', style: TextStyle(color: textSecondary)),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _isEditing = true),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add Wallets in Edit Mode'),
                    ),
                  ],
                ),
              ),
            )
          else
            ...walletList.map((acc) {
              final liveBal = _liveSummary?.walletBalances[acc] ?? (_config.walletOpeningBalances[acc] ?? 0.0);
              final openingBal = _config.walletOpeningBalances[acc] ?? 0.0;
              final diff = liveBal - openingBal;

              return GestureDetector(
                onTap: () => _openAccountHistory(acc),
                child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor, width: 1.1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF0D9488), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            acc,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: textPrimary),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(
                                'Opening: ₹${IndianCurrency.format(openingBal)}',
                                style: TextStyle(fontSize: 12, color: textSecondary),
                              ),
                              if (diff != 0) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '(${diff > 0 ? "+" : "-"}₹${IndianCurrency.format(diff.abs())})',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: diff > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${IndianCurrency.format(liveBal)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: liveBal >= 0
                                ? (isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E))
                                : const Color(0xFFEF4444),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Available',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0D9488),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                      tooltip: 'Remove $acc',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeAccountDialog('Wallets', acc),
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

  // ==========================================
  // TAB 4: WALLETS - EDIT MODE
  // ==========================================
  Widget _buildWalletsEditTab(Color cardBg, Color textPrimary, Color textSecondary, Color borderColor, bool isDark, Color primaryColor) {
    final walletList = _walletControllers.keys.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Digital Wallets (${walletList.length})',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPrimary),
            ),
            TextButton.icon(
              onPressed: () => _addNewAccountDialog('Wallets'),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Wallet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...walletList.map((acc) {
          final liveBal = _liveSummary?.walletBalances[acc];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF0D9488), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        acc,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPrimary),
                      ),
                    ),
                    if (liveBal != null && _config.isConfigured)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'Available: ₹${IndianCurrency.format(liveBal)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0D9488),
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                      tooltip: 'Remove Account',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeAccountDialog('Wallets', acc),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: TextField(
                          controller: _walletControllers[acc],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Opening Balance (₹)',
                            hintText: '0.00',
                            prefixIcon: const Icon(Icons.currency_rupee_rounded, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

// ==========================================
  // TAB 5: REWARDS - VIEW MODE
  // ==========================================
  Widget _buildRewardsViewTab(Color cardBg, Color textPrimary, Color textSecondary, Color borderColor, bool isDark, Color primaryColor) {
    final rewardList = _rewardControllers.keys.toList();

    double totalAvailable = 0.0;
    double totalOpening = 0.0;
    for (final acc in rewardList) {
      final live = _liveSummary?.rewardBalances[acc] ?? (_config.rewardOpeningBalances[acc] ?? 0.0);
      final opening = _config.rewardOpeningBalances[acc] ?? 0.0;
      totalAvailable += live;
      totalOpening += opening;
    }
    final totalDiff = totalAvailable - totalOpening;

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          // Total Rewards Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF78350F).withValues(alpha: 0.3) : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFFF59E0B).withValues(alpha: 0.4) : const Color(0xFFFDE68A),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.stars_rounded, color: Color(0xFFD97706), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL REWARD POINTS / BALANCE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${IndianCurrency.format(totalAvailable)} pts',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '${rewardList.length} accounts • Opening: ${IndianCurrency.format(totalOpening)} pts',
                            style: TextStyle(fontSize: 11.5, color: textSecondary),
                          ),
                          if (totalDiff != 0) ...[
                            const SizedBox(width: 6),
                            Icon(
                              totalDiff > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                              size: 14,
                              color: totalDiff > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${totalDiff > 0 ? "+" : "-"}${IndianCurrency.format(totalDiff.abs())}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: totalDiff > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
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
          ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Rewards & Loyalty Programs (${rewardList.length})',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPrimary),
              ),
              Text(
                'Pull to refresh ⟳',
                style: TextStyle(fontSize: 11.5, color: textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (rewardList.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.stars_outlined, size: 36, color: textSecondary),
                    const SizedBox(height: 8),
                    Text('No rewards configured yet', style: TextStyle(color: textSecondary)),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _isEditing = true),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add Rewards in Edit Mode'),
                    ),
                  ],
                ),
              ),
            )
          else
            ...rewardList.map((acc) {
              final liveBal = _liveSummary?.rewardBalances[acc] ?? (_config.rewardOpeningBalances[acc] ?? 0.0);
              final openingBal = _config.rewardOpeningBalances[acc] ?? 0.0;
              final diff = liveBal - openingBal;

              return GestureDetector(
                onTap: () => _openAccountHistory(acc),
                child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor, width: 1.1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.stars_rounded, color: Color(0xFFD97706), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            acc,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: textPrimary),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(
                                'Opening: ${IndianCurrency.format(openingBal)} pts',
                                style: TextStyle(fontSize: 12, color: textSecondary),
                              ),
                              if (diff != 0) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '(${diff > 0 ? "+" : "-"}₹${IndianCurrency.format(diff.abs())})',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: diff > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${IndianCurrency.format(liveBal)} pts',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: liveBal >= 0
                                ? (isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309))
                                : const Color(0xFFEF4444),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Active Points',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                      tooltip: 'Remove $acc',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeAccountDialog('Rewards', acc),
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

  // ==========================================
  // TAB 5: REWARDS - EDIT MODE
  // ==========================================
  Widget _buildRewardsEditTab(Color cardBg, Color textPrimary, Color textSecondary, Color borderColor, bool isDark, Color primaryColor) {
    final rewardList = _rewardControllers.keys.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Rewards & Loyalty Programs (${rewardList.length})',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPrimary),
            ),
            TextButton.icon(
              onPressed: () => _addNewAccountDialog('Rewards'),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Reward', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...rewardList.map((acc) {
          final liveBal = _liveSummary?.rewardBalances[acc];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.stars_rounded, color: Color(0xFFD97706), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        acc,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPrimary),
                      ),
                    ),
                    if (liveBal != null && _config.isConfigured)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'Available: ${IndianCurrency.format(liveBal)} pts',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                      tooltip: 'Remove Account',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeAccountDialog('Rewards', acc),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: TextField(
                          controller: _rewardControllers[acc],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Opening Points / Balance',
                            hintText: '0.00',
                            prefixIcon: const Icon(Icons.stars_rounded, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

    // ==========================================
  // BOTTOM BAR (EDIT BUTTON OR SAVE BUTTON)
  // ==========================================
  Widget _buildBottomBar(Color primaryColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(top: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: _isEditing
              ? ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveBalances,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_rounded, color: Colors.white),
                  label: Text(
                    _isSaving
                        ? 'Saving Balances...'
                        : (widget.isInitialSetup ? 'Save & Start Tracking' : 'Save Balances & Limits'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                  ),
                )
              : ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() => _isEditing = true);
                  },
                  icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                  label: const Text(
                    'Edit Balances & Limits',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCardSplitPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
