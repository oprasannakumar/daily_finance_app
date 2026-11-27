import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account_balance_model.dart';
import '../models/emi_plan_model.dart';
import '../models/invoice_model.dart';
import '../models/transaction_model.dart';
import '../utils/currency_formatter.dart';
import 'google_auth_service.dart';
import 'google_sheets_service.dart';

class StorageService {
  static const String _keyPurposes = 'master_purposes_v2';
  static const String _keySpentFor = 'master_spent_for_v2';
  static const String _keyMasterCategories = 'master_categories_v2';
  static const String _keyTemplates = 'transaction_templates_v1';
  static const String _keyDarkMode = 'is_dark_mode_v1';
  static const String _keyRecurring = 'recurring_transactions_v1';
  static const String _keyTransactions = 'local_transactions_v2';
  static const String _keyLoanEntries = 'cached_loan_entries_v1';
  static const String _keyPendingSaves = 'pending_sync_transactions_v1';
  static const String _keyPendingDeletes = 'pending_delete_references_v1';
  static const String _keyAccountBalanceConfig = 'account_balance_config_v1';
  static const String _keyGroceryDbId = 'grocery_db_spreadsheet_id';
  static const String _keyCachedInvoices = 'cached_grocery_invoices_v2';
  static const String _keyCachedDealerPrices = 'cached_dealer_prices_v1';
  static const String _keyCachedEmiPlans = 'cached_active_emi_plans_v1';
  static const String _keyMonthlyBudgets = 'monthly_purpose_budgets_v1';
  static const String _keyAppLockPin = 'app_lock_pin_v1';
  static const String _keyBiometricLock = 'app_biometric_lock_v1';

  List<InvoiceItemRecord>? _cachedInvoices;
  List<DealerPriceItem>? _cachedDealerPrices;
  List<EmiPlan>? _cachedEmiPlans;

  static final StorageService instance = StorageService._internal();
  StorageService._internal();

  final ValueNotifier<int> mastersNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> isDarkModeNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> recurringNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> transactionsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> loansNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> emiPlansNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> pendingSyncNotifier = ValueNotifier<int>(0);
  final ValueNotifier<Set<String>> pendingSyncSetNotifier = ValueNotifier<Set<String>>({});
  final ValueNotifier<AccountBalanceConfig?> balanceConfigNotifier = ValueNotifier<AccountBalanceConfig?>(null);

  bool isPendingSync(String? ref, [String? id]) {
    final set = pendingSyncSetNotifier.value;
    if (ref != null && ref.isNotEmpty && set.contains(ref)) return true;
    if (id != null && id.isNotEmpty && set.contains(id)) return true;
    for (final item in _syncQueue) {
      if (item.transaction != null) {
        if (ref != null && ref.isNotEmpty && item.transaction!.referenceId == ref) return true;
        if (id != null && id.isNotEmpty && item.transaction!.id == id) return true;
      }
      if (item.idOrReference != null && item.idOrReference!.isNotEmpty) {
        if (ref != null && item.idOrReference == ref) return true;
        if (id != null && item.idOrReference == id) return true;
      }
    }
    return false;
  }

  Future<void> initTheme() async {
    final prefs = await SharedPreferences.getInstance();
    isDarkModeNotifier.value = prefs.getBool(_keyDarkMode) ?? false;
    _cachedTransactions = null;
    _cachedPurposes = null;
    _cachedSpentFors = null;
    _cachedCategoryAccounts = null;
    _cachedTemplates = null;
    _cachedRecurring = null;
    _syncQueue.clear();
    _isSyncQueueRunning = false;
    _hasTriggeredInitialBackgroundSync = false;
    _updatePendingSyncCount(prefs);
  }

  Future<void> toggleDarkMode() async {
    final newVal = !isDarkModeNotifier.value;
    isDarkModeNotifier.value = newVal;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, newVal);
  }

  // In-memory caches to eliminate disk lag and UI stutter
  List<String>? _cachedPurposes;
  List<String>? _cachedSpentFors;
  Map<String, List<String>>? _cachedCategoryAccounts;
  List<TransactionTemplate>? _cachedTemplates;
  List<RecurringTransaction>? _cachedRecurring;
  List<FinanceTransaction>? _cachedTransactions;
  List<LoanEntry>? _cachedLoanEntries;
  AccountBalanceConfig? _cachedBalanceConfig;
  bool _hasTriggeredInitialBackgroundSync = false;
  bool _isSyncQueueRunning = false;
  final List<_SyncQueueItem> _syncQueue = [];

  void notifyMastersChanged() {
    mastersNotifier.value++;
  }

  static const List<String> defaultPurposes = [
    'Food & Groceries',
    'Rent & Utilities',
    'Medical & Health',
    'Shopping',
    'Entertainment',
    'Salary & Income',
    'Investment & Savings',
    'Fuel & Transport',
    'Education',
    'Donations & Gifts',
    'Loan Given',
    'Loan Received',
    'Other',
  ];

  static const List<String> defaultSpentFors = [
    'Self',
    'Family',
    'Parents',
    'Children',
    'Home',
    'Office / Work',
    'Friends',
    'Pets',
    'Split',
    'Other',
  ];

  static const Map<String, List<String>> defaultCategoryAccounts = {
    'Bank Accounts': [
      'HDFC Bank A/c',
      'SBI Savings A/c',
      'ICICI Bank A/c',
      'Axis Bank A/c',
      'Kotak Bank A/c',
    ],
    'Credit Cards': [
      'HDFC Regalia Card',
      'ICICI Amazon Pay Card',
      'SBI SimplyCLICK Card',
      'Axis Bank Neo Card',
    ],
    'Wallets': [
      'Paytm Wallet',
      'Amazon Pay Balance',
      'PhonePe Wallet',
      'MobiKwik',
    ],
    'Rewards': [
      'Credit Card Reward Points',
      'Flipkart SuperCoins',
      'Amazon CashBack',
      'Tata NeuCoins',
    ],
  };

  static List<TransactionTemplate> get defaultTemplates => [
    TransactionTemplate(
      name: 'Coffee & Breakfast',
      narration: 'Morning coffee & breakfast snacks',
      flow: 'Withdraw',
      purpose: 'Food & Groceries',
      spentFor: 'Self',
      breakdowns: [
        PaymentBreakdown(paymentType: 'UPI', amount: 120.0),
      ],
    ),
    TransactionTemplate(
      name: 'Monthly Rent',
      narration: 'Monthly house rent transfer',
      flow: 'Withdraw',
      purpose: 'Rent & Utilities',
      spentFor: 'Home',
      breakdowns: [
        PaymentBreakdown(paymentType: 'Net', amount: 22000.0),
      ],
    ),
    TransactionTemplate(
      name: 'Fuel & Commute',
      narration: 'Vehicle petrol / fuel refill',
      flow: 'Withdraw',
      purpose: 'Fuel & Transport',
      spentFor: 'Self',
      breakdowns: [
        PaymentBreakdown(paymentType: 'Credit', amount: 2500.0),
      ],
    ),
    TransactionTemplate(
      name: 'Monthly Salary Credit',
      narration: 'Monthly salary credit deposit',
      flow: 'Deposit',
      purpose: 'Salary & Income',
      spentFor: 'Self',
      breakdowns: [
        PaymentBreakdown(paymentType: 'Net', amount: 75000.0),
      ],
    ),
  ];

  // Purposes
  Future<List<String>> getPurposes() async {
    if (_cachedPurposes != null) {
      return List<String>.from(_cachedPurposes!);
    }
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyPurposes);
    if (list == null || list.isEmpty) {
      await prefs.setStringList(_keyPurposes, defaultPurposes);
      _cachedPurposes = List<String>.from(defaultPurposes);
      return List<String>.from(_cachedPurposes!);
    }
    if (!list.contains('Loan Given')) {
      final otherIdx = list.indexOf('Other');
      if (otherIdx != -1) {
        list.insert(otherIdx, 'Loan Given');
      } else {
        list.add('Loan Given');
      }
    }
    if (!list.contains('Loan Received')) {
      final otherIdx = list.indexOf('Other');
      if (otherIdx != -1) {
        list.insert(otherIdx, 'Loan Received');
      } else {
        list.add('Loan Received');
      }
    }
    if (!list.contains('Other')) {
      list.add('Other');
    }
    _cachedPurposes = List<String>.from(list);
    return List<String>.from(_cachedPurposes!);
  }

  Future<void> savePurposes(List<String> purposes) async {
    if (!purposes.contains('Other')) {
      purposes.add('Other');
    }
    _cachedPurposes = List<String>.from(purposes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyPurposes, purposes);
    notifyMastersChanged();
    triggerConfigBackup();
  }

  Future<void> addPurpose(String purpose) async {
    final list = await getPurposes();
    if (!list.contains(purpose.trim())) {
      final otherIdx = list.indexOf('Other');
      if (otherIdx != -1) {
        list.insert(otherIdx, purpose.trim());
      } else {
        list.add(purpose.trim());
        list.add('Other');
      }
      await savePurposes(list);
    }
  }

  Future<void> deletePurpose(String purpose) async {
    if (purpose == 'Other') return;
    final list = await getPurposes();
    list.remove(purpose);
    await savePurposes(list);
  }

  // Spent For
  Future<List<String>> getSpentFors() async {
    if (_cachedSpentFors != null) {
      return List<String>.from(_cachedSpentFors!);
    }
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keySpentFor);
    if (list == null || list.isEmpty) {
      await prefs.setStringList(_keySpentFor, defaultSpentFors);
      _cachedSpentFors = List<String>.from(defaultSpentFors);
      return List<String>.from(_cachedSpentFors!);
    }
    if (!list.contains('Split')) {
      final otherIdx = list.indexOf('Other');
      if (otherIdx != -1) {
        list.insert(otherIdx, 'Split');
      } else {
        list.add('Split');
      }
    }
    if (!list.contains('Other')) {
      list.add('Other');
    }
    _cachedSpentFors = List<String>.from(list);
    return List<String>.from(_cachedSpentFors!);
  }

  Future<void> saveSpentFors(List<String> spentFors) async {
    if (!spentFors.contains('Other')) {
      spentFors.add('Other');
    }
    _cachedSpentFors = List<String>.from(spentFors);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keySpentFor, spentFors);
    notifyMastersChanged();
    triggerConfigBackup();
  }

  Future<void> addSpentFor(String spentFor) async {
    final list = await getSpentFors();
    if (!list.contains(spentFor.trim())) {
      final otherIdx = list.indexOf('Other');
      if (otherIdx != -1) {
        list.insert(otherIdx, spentFor.trim());
      } else {
        list.add(spentFor.trim());
        list.add('Other');
      }
      await saveSpentFors(list);
    }
  }

  Future<void> deleteSpentFor(String spentFor) async {
    if (spentFor == 'Other') return;
    final list = await getSpentFors();
    list.remove(spentFor);
    await saveSpentFors(list);
  }

  // Category Accounts
  Future<Map<String, List<String>>> getCategoryAccounts() async {
    if (_cachedCategoryAccounts != null) {
      return _cachedCategoryAccounts!.map((k, v) => MapEntry(k, List<String>.from(v)));
    }
    final prefs = await SharedPreferences.getInstance();
    final rawString = prefs.getString(_keyMasterCategories);
    if (rawString == null) {
      await prefs.setString(_keyMasterCategories, jsonEncode(defaultCategoryAccounts));
      _cachedCategoryAccounts = defaultCategoryAccounts.map((k, v) => MapEntry(k, List<String>.from(v)));
      return _cachedCategoryAccounts!.map((k, v) => MapEntry(k, List<String>.from(v)));
    }
    try {
      final decoded = jsonDecode(rawString) as Map<String, dynamic>;
      final Map<String, List<String>> result = {};
      decoded.forEach((key, val) {
        if (val is List) {
          result[key] = val.map((e) => e.toString()).toList();
        }
      });
      for (final type in defaultCategoryAccounts.keys) {
        if (!result.containsKey(type) || result[type]!.isEmpty) {
          result[type] = List<String>.from(defaultCategoryAccounts[type]!);
        }
      }
      _cachedCategoryAccounts = result;
      return result.map((k, v) => MapEntry(k, List<String>.from(v)));
    } catch (_) {
      _cachedCategoryAccounts = defaultCategoryAccounts.map((k, v) => MapEntry(k, List<String>.from(v)));
      return _cachedCategoryAccounts!.map((k, v) => MapEntry(k, List<String>.from(v)));
    }
  }

  Future<void> saveCategoryAccounts(Map<String, List<String>> accounts) async {
    _cachedCategoryAccounts = accounts.map((k, v) => MapEntry(k, List<String>.from(v)));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMasterCategories, jsonEncode(accounts));
    notifyMastersChanged();
    triggerConfigBackup();
  }

  List<String> getAccountsForType(String paymentType, Map<String, List<String>> categories) {
    List<String> baseList;
    final ptLower = paymentType.toLowerCase();
    if (ptLower.contains('upi') || ptLower.contains('debit') || ptLower.contains('net')) {
      baseList = List<String>.from(categories['Bank Accounts'] ?? defaultCategoryAccounts['Bank Accounts']!);
    } else if (ptLower.contains('credit')) {
      baseList = List<String>.from(categories['Credit Cards'] ?? defaultCategoryAccounts['Credit Cards']!);
    } else if (ptLower.contains('wallet')) {
      baseList = List<String>.from(categories['Wallets'] ?? defaultCategoryAccounts['Wallets']!);
    } else if (ptLower.contains('reward')) {
      baseList = List<String>.from(categories['Rewards'] ?? defaultCategoryAccounts['Rewards']!);
    } else {
      baseList = [];
    }

    if (!baseList.contains('Other')) {
      baseList.add('Other');
    }
    return baseList;
  }

  Future<void> addAccountToCategory(String category, String accountName) async {
    final accounts = await getCategoryAccounts();
    final list = accounts[category] ?? [];
    if (!list.contains(accountName.trim())) {
      list.add(accountName.trim());
      accounts[category] = list;
      await saveCategoryAccounts(accounts);
    }
  }

  Future<void> deleteAccountFromCategory(String category, String accountName) async {
    if (accountName == 'Other') return;
    final accounts = await getCategoryAccounts();
    final list = accounts[category] ?? [];
    list.remove(accountName);
    accounts[category] = list;
    await saveCategoryAccounts(accounts);
  }

  // =========================================================================
  // BALANCES & LIMITS MANAGEMENT
  // =========================================================================

  Future<AccountBalanceConfig> getAccountBalanceConfig() async {
    if (_cachedBalanceConfig != null) {
      return _cachedBalanceConfig!;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyAccountBalanceConfig);
    if (raw != null && raw.isNotEmpty) {
      try {
        _cachedBalanceConfig = AccountBalanceConfig.fromJson(jsonDecode(raw));
        balanceConfigNotifier.value = _cachedBalanceConfig;
        return _cachedBalanceConfig!;
      } catch (e) {
        debugPrint('Error parsing cached balance config: $e');
      }
    }
    final emptyConfig = AccountBalanceConfig();
    _cachedBalanceConfig = emptyConfig;
    balanceConfigNotifier.value = emptyConfig;
    return emptyConfig;
  }

  Future<void> saveAccountBalanceConfig(AccountBalanceConfig config, {bool syncToSheet = true}) async {
    _cachedBalanceConfig = config;
    balanceConfigNotifier.value = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccountBalanceConfig, jsonEncode(config.toJson()));

    if (syncToSheet) {
      _syncAccountBalancesToSheet(config);
      triggerConfigBackup();
    }
  }

  bool isBalanceConfigured() {
    return _cachedBalanceConfig?.isConfigured ?? false;
  }

  Future<void> markCreditCardBillPaid(String cardName, String cycleKey) async {
    final config = await getAccountBalanceConfig();
    final ccLimits = Map<String, CreditCardLimit>.from(config.creditCardLimits);
    final card = ccLimits[cardName];
    if (card != null) {
      ccLimits[cardName] = card.copyWith(manualPaidCycle: cycleKey);
      final updated = config.copyWith(creditCardLimits: ccLimits);
      await saveAccountBalanceConfig(updated);
    }
  }

  Future<void> markCreditCardBillUnpaid(String cardName) async {
    final config = await getAccountBalanceConfig();
    final ccLimits = Map<String, CreditCardLimit>.from(config.creditCardLimits);
    final card = ccLimits[cardName];
    if (card != null) {
      ccLimits[cardName] = card.copyWith(clearManualPaidCycle: true);
      final updated = config.copyWith(creditCardLimits: ccLimits);
      await saveAccountBalanceConfig(updated);
    }
  }

  Future<void> updateCreditCardBilledAmount(String cardName, double amount) async {
    final config = await getAccountBalanceConfig();
    final ccLimits = Map<String, CreditCardLimit>.from(config.creditCardLimits);
    final card = ccLimits[cardName];
    if (card != null) {
      ccLimits[cardName] = card.copyWith(statementBilledAmount: amount);
      final updated = config.copyWith(creditCardLimits: ccLimits);
      await saveAccountBalanceConfig(updated);
    }
  }

  Future<void> removeAccountFromBalances(String category, String accountName) async {
    // 1. Remove from category accounts list
    await deleteAccountFromCategory(category, accountName);

    // 2. Remove from AccountBalanceConfig
    final config = await getAccountBalanceConfig();
    final banks = Map<String, double>.from(config.bankOpeningBalances)..remove(accountName);
    final cards = Map<String, CreditCardLimit>.from(config.creditCardLimits)..remove(accountName);
    final wallets = Map<String, double>.from(config.walletOpeningBalances)..remove(accountName);
    final rewards = Map<String, double>.from(config.rewardOpeningBalances)..remove(accountName);

    final updated = config.copyWith(
      bankOpeningBalances: banks,
      creditCardLimits: cards,
      walletOpeningBalances: wallets,
      rewardOpeningBalances: rewards,
    );
    await saveAccountBalanceConfig(updated);
    unawaited(_syncAccountBalancesToSheet(updated));
  }

  Future<LiveAccountBalanceSummary> getLiveAccountBalances() async {
    final config = await getAccountBalanceConfig();
    final transactions = await getTransactions();
    final categories = await getCategoryAccounts();
    final emiPlans = await getCachedEmiPlans();
    return LiveAccountBalanceSummary.calculate(
      config: config,
      transactions: transactions,
      categories: categories,
      emiPlans: emiPlans,
    );
  }

  Timer? _backupDebounceTimer;

  void triggerConfigBackup() {
    // Avoid running background debounced timers during unit/widget tests
    final isTesting = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTesting) return;

    _backupDebounceTimer?.cancel();
    _backupDebounceTimer = Timer(const Duration(seconds: 4), () async {
      try {
        if (!await hasNetworkConnection()) return;
        final email = await GoogleAuthService.instance.currentUserEmail;
        if (email != null && email.isNotEmpty) {
          await GoogleSheetsService.instance.backupAllConfigAndMasters();
        }
      } catch (e) {
        debugPrint('Automatic config backup error: $e');
      }
    });
  }

  /// Extracts any new bank accounts, credit cards, or wallets from loaded transactions and adds them to categories.
  Future<void> extractAccountsFromTransactions(List<FinanceTransaction> transactions) async {
    final categories = await getCategoryAccounts();
    final bankList = List<String>.from(categories['Bank Accounts'] ?? []);
    final ccList = List<String>.from(categories['Credit Cards'] ?? []);
    final walletList = List<String>.from(categories['Wallets'] ?? []);
    bool changed = false;

    for (final tx in transactions) {
      final allBreakdowns = [...tx.breakdowns, ...(tx.toBreakdowns ?? [])];
      for (final b in allBreakdowns) {
        final acc = b.effectiveAccount.trim();
        final pt = (b.paymentType ?? '').toLowerCase();
        if (acc.isEmpty || acc == 'None' || acc == 'Other') continue;

        if (pt.contains('credit') || pt.contains('card')) {
          if (!ccList.contains(acc)) {
            ccList.add(acc);
            changed = true;
          }
        } else if (pt.contains('wallet') || acc.toLowerCase().contains('wallet')) {
          if (!walletList.contains(acc)) {
            walletList.add(acc);
            changed = true;
          }
        } else if (!pt.contains('cash')) {
          if (!bankList.contains(acc)) {
            bankList.add(acc);
            changed = true;
          }
        }
      }
    }

    if (changed) {
      categories['Bank Accounts'] = bankList;
      categories['Credit Cards'] = ccList;
      categories['Wallets'] = walletList;
      await saveCategoryAccounts(categories);
    }
  }

  Future<void> _syncAccountBalancesToSheet(AccountBalanceConfig config) async {
    try {
      if (!await hasNetworkConnection()) return;
      final summary = await getLiveAccountBalances();
      await GoogleSheetsService.instance.syncAccountBalances(summary: summary, config: config);
    } catch (e) {
      debugPrint('Background balance sync error: $e');
    }
  }

  // =========================================================================
  // TRANSACTIONS: LOCAL-FIRST WITH ASYNCHRONOUS BACKGROUND GOOGLE SHEETS SYNC
  // =========================================================================

  /// Loads transactions immediately from in-memory cache (< 1ms) or local SharedPreferences (< 5ms).
  /// If forceRefresh is requested or if local storage is completely empty, it fetches from Google Sheets.
  List<FinanceTransaction>? _loadTransactionsFromPrefs(SharedPreferences prefs) {
    final raw = prefs.getStringList(_keyTransactions);
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = raw
          .map((item) => FinanceTransaction.fromJson(jsonDecode(item)))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      // Clean up any legacy EMI reversal transactions to restore card balances
      if (list.any((t) => t.purpose == 'Credit Card EMI Reversal' || t.referenceId.startsWith('EMI-REV-'))) {
        list.removeWhere((t) => t.purpose == 'Credit Card EMI Reversal' || t.referenceId.startsWith('EMI-REV-'));
        unawaited(_persistTransactions(prefs, list));
      }
      return list;
    } catch (e) {
      debugPrint('Error parsing cached transactions: $e');
      return null;
    }
  }

  List<FinanceTransaction>? get cachedTransactionsSync => _cachedTransactions;

  /// Verifies real internet connectivity before attempting any remote server refresh.
  Future<bool> hasNetworkConnection() async {
    final isTesting = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTesting) return true;
    try {
      final socket = await Socket.connect(
        '8.8.8.8',
        53,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<FinanceTransaction>> getTransactions({bool forceRefresh = false}) async {
    // 1. In-memory cache hit: zero lag
    if (!forceRefresh && _cachedTransactions != null) {
      return List<FinanceTransaction>.from(_cachedTransactions!);
    }

    final prefs = await SharedPreferences.getInstance();

    // 2. Local mobile storage (SharedPreferences) hit: instantaneous
    if (!forceRefresh && _cachedTransactions == null) {
      final cached = _loadTransactionsFromPrefs(prefs);
      if (cached != null && cached.isNotEmpty) {
        _cachedTransactions = cached;
        GoogleSheetsService.instance.cachedTransactions =
        List<FinanceTransaction>.from(_cachedTransactions!);

        // Resume any pending background sync operations or silent refresh (only if online)
        _triggerBackgroundSyncIfNeeded();

        return List<FinanceTransaction>.from(_cachedTransactions!);
      }
    }

    // 3. Verify network before attempting remote fetch; if offline, hold refresh and return local cache
    final isOnline = await hasNetworkConnection();
    if (!isOnline) {
      if (_cachedTransactions == null || _cachedTransactions!.isEmpty) {
        _cachedTransactions = _loadTransactionsFromPrefs(prefs) ?? [];
        GoogleSheetsService.instance.cachedTransactions =
        List<FinanceTransaction>.from(_cachedTransactions!);
      }
      return List<FinanceTransaction>.from(_cachedTransactions ?? []);
    }

    // 4. Remote fetch from Google Sheets (when online on forced refresh or cold first launch)
    try {
      if (forceRefresh) {
        await _resumePendingSyncQueue();
      }
      final remoteList = await GoogleSheetsService.instance.fetchTransactions(forceRefresh: forceRefresh);
      if (remoteList.isNotEmpty) {
        // Merge with local un-synced items
        final merged = await _mergeWithPendingLocal(prefs, remoteList);

        _cachedTransactions = merged;
        await _persistTransactions(prefs, _cachedTransactions!);
        GoogleSheetsService.instance.cachedTransactions =
        List<FinanceTransaction>.from(_cachedTransactions!);
        transactionsNotifier.value++;
      } else {
        // Empty remote response: preserve or restore from local cache
        if (_cachedTransactions == null || _cachedTransactions!.isEmpty) {
          _cachedTransactions = _loadTransactionsFromPrefs(prefs) ?? [];
          GoogleSheetsService.instance.cachedTransactions =
        List<FinanceTransaction>.from(_cachedTransactions!);
        }
      }
    } catch (e) {
      debugPrint('Error fetching transactions from remote: $e');
      if (_cachedTransactions == null || _cachedTransactions!.isEmpty) {
        _cachedTransactions = _loadTransactionsFromPrefs(prefs) ?? [];
        GoogleSheetsService.instance.cachedTransactions =
        List<FinanceTransaction>.from(_cachedTransactions!);
      }
    }

    return List<FinanceTransaction>.from(_cachedTransactions ?? []);
  }

  Future<List<FinanceTransaction>> _mergeWithPendingLocal(
    SharedPreferences prefs,
    List<FinanceTransaction> remoteList,
  ) async {
    final merged = List<FinanceTransaction>.from(remoteList);
    final pendingSaves = await _getPendingSaves(prefs);
    for (final p in pendingSaves) {
      merged.removeWhere((t) =>
          (p.id.isNotEmpty && t.id == p.id) ||
          (p.referenceId.isNotEmpty && t.referenceId == p.referenceId));
      merged.insert(0, p);
    }
    final pendingDeletes = await _getPendingDeletes(prefs);
    merged.removeWhere((t) => pendingDeletes.contains(t.id) || pendingDeletes.contains(t.referenceId));
    merged.sort((a, b) => b.date.compareTo(a.date));
    return merged;
  }

  Future<void> saveAllTransactions(List<FinanceTransaction> transactions) async {
    _cachedTransactions = List<FinanceTransaction>.from(transactions);
    final prefs = await SharedPreferences.getInstance();
    await _persistTransactions(prefs, _cachedTransactions!);
    GoogleSheetsService.instance.cachedTransactions =
        List<FinanceTransaction>.from(_cachedTransactions!);
    transactionsNotifier.value++;
  }

  Future<void> clearCachedTransactions() async {
    _cachedTransactions = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyTransactions);
    transactionsNotifier.value++;
  }

  Future<FinanceTransaction?> getLatestTransaction() async {
    final list = await getTransactions();
    return list.isNotEmpty ? list.first : null;
  }

  List<LoanEntry>? get cachedLoanEntriesSync => _cachedLoanEntries;

  /// Loads loan & borrower entries immediately from in-memory cache (< 1ms) or local SharedPreferences (< 5ms).
  /// If forceRefresh is requested or if local storage is completely empty, it fetches from Google Sheets.
  Future<List<LoanEntry>> getLoanEntries({bool forceRefresh = false}) async {
    // 1. In-memory cache hit: zero lag (< 1ms)
    if (!forceRefresh && _cachedLoanEntries != null && _cachedLoanEntries!.isNotEmpty) {
      return List<LoanEntry>.from(_cachedLoanEntries!);
    }

    final prefs = await SharedPreferences.getInstance();

    // 2. Local mobile storage (SharedPreferences) hit: instantaneous (< 5ms)
    if (!forceRefresh) {
      final raw = prefs.getStringList(_keyLoanEntries);
      if (raw != null && raw.isNotEmpty) {
        try {
          _cachedLoanEntries = raw
              .map((item) => LoanEntry.fromJson(jsonDecode(item) as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          GoogleSheetsService.instance.cachedLoanEntries = _cachedLoanEntries;

          // Silent background refresh to keep remote Google Sheets in sync without blocking UI
          _triggerLoanBackgroundSyncIfNeeded();

          return List<LoanEntry>.from(_cachedLoanEntries!);
        } catch (e) {
          debugPrint('Error parsing cached loan entries: $e');
        }
      }

      // If no explicit loan cache yet, derive instantly from local transactions (< 5ms)
      final localTx = await getTransactions();
      final derived = _extractLoanEntriesFromTransactions(localTx);
      if (derived.isNotEmpty) {
        _cachedLoanEntries = derived;
        GoogleSheetsService.instance.cachedLoanEntries = _cachedLoanEntries;
        await saveLocalLoanEntries(derived);
        _triggerLoanBackgroundSyncIfNeeded();
        return List<LoanEntry>.from(derived);
      }
    }

    // 3. Fallback or explicit force refresh: Fetch from Google Sheets live
    try {
      final remoteEntries = await GoogleSheetsService.instance.fetchLoanEntries(forceRefresh: forceRefresh);
      _cachedLoanEntries = remoteEntries;
      await saveLocalLoanEntries(remoteEntries);
      loansNotifier.value++;
      return List<LoanEntry>.from(remoteEntries);
    } catch (e) {
      debugPrint('Error fetching loan entries from remote: $e');
      _cachedLoanEntries ??= [];
    }

    return List<LoanEntry>.from(_cachedLoanEntries!);
  }

  /// Instant local-first loading of loan/borrower entries (< 5ms)
  Future<List<LoanEntry>> getLocalLoanEntries() async {
    return getLoanEntries(forceRefresh: false);
  }

  // --- Grocery DB & Invoice Caching ---
  Future<String?> getGroceryDbId({String? email}) async {
    final active = await getString(_keyGroceryDbId);
    if (active != null && active.isNotEmpty) return active;
    final effectiveEmail = email ?? (await GoogleAuthService.instance.currentUserEmail);
    if (effectiveEmail != null && effectiveEmail.isNotEmpty) {
      return getString('${_keyGroceryDbId}_$effectiveEmail');
    }
    return null;
  }

  Future<void> saveGroceryDbId(String id, {String? email}) async {
    await setString(_keyGroceryDbId, id);
    final effectiveEmail = email ?? (await GoogleAuthService.instance.currentUserEmail);
    if (effectiveEmail != null && effectiveEmail.isNotEmpty) {
      await setString('${_keyGroceryDbId}_$effectiveEmail', id);
    }
  }

  Future<List<InvoiceItemRecord>> getCachedInvoices() async {
    if (_cachedInvoices != null && _cachedInvoices!.isNotEmpty) {
      return List<InvoiceItemRecord>.from(_cachedInvoices!);
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyCachedInvoices);
    if (raw != null && raw.isNotEmpty) {
      try {
        _cachedInvoices = raw.map((item) => InvoiceItemRecord.fromJson(jsonDecode(item) as Map<String, dynamic>)).toList();
        return List<InvoiceItemRecord>.from(_cachedInvoices!);
      } catch (e) {
        debugPrint('Error parsing cached invoices: $e');
      }
    }
    _cachedInvoices = [];
    return [];
  }

  Future<void> saveCachedInvoices(List<InvoiceItemRecord> items) async {
    _cachedInvoices = List<InvoiceItemRecord>.from(items);
    final prefs = await SharedPreferences.getInstance();
    final encoded = items.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_keyCachedInvoices, encoded);
  }

  Future<List<DealerPriceItem>> getCachedDealerPrices() async {
    if (_cachedDealerPrices != null && _cachedDealerPrices!.isNotEmpty) {
      return List<DealerPriceItem>.from(_cachedDealerPrices!);
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyCachedDealerPrices);
    if (raw != null && raw.isNotEmpty) {
      try {
        _cachedDealerPrices = raw.map((item) => DealerPriceItem.fromJson(jsonDecode(item) as Map<String, dynamic>)).toList();
        return List<DealerPriceItem>.from(_cachedDealerPrices!);
      } catch (e) {
        debugPrint('Error parsing cached dealer prices: $e');
      }
    }
    _cachedDealerPrices = [];
    return [];
  }

  Future<void> saveCachedDealerPrices(List<DealerPriceItem> items) async {
    _cachedDealerPrices = List<DealerPriceItem>.from(items);
    final prefs = await SharedPreferences.getInstance();
    final encoded = items.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_keyCachedDealerPrices, encoded);
  }

  Future<List<EmiPlan>> getCachedEmiPlans() async {
    if (_cachedEmiPlans != null && _cachedEmiPlans!.isNotEmpty) {
      return List<EmiPlan>.from(_cachedEmiPlans!);
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyCachedEmiPlans);
    if (raw != null && raw.isNotEmpty) {
      try {
        _cachedEmiPlans = raw
            .map((item) => EmiPlan.fromJson(jsonDecode(item) as Map<String, dynamic>))
            .toList();
        return List<EmiPlan>.from(_cachedEmiPlans!);
      } catch (e) {
        debugPrint('Error parsing cached EMI plans: $e');
      }
    }
    _cachedEmiPlans = [];
    return [];
  }

  Future<void> saveCachedEmiPlans(List<EmiPlan> plans) async {
    _cachedEmiPlans = List<EmiPlan>.from(plans);
    final prefs = await SharedPreferences.getInstance();
    final encoded = plans.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_keyCachedEmiPlans, encoded);
    emiPlansNotifier.value++;
  }

  Future<void> saveEmiPlanLocal(EmiPlan plan) async {
    final list = await getCachedEmiPlans();
    final idx = list.indexWhere((p) => p.id == plan.id);
    if (idx != -1) {
      list[idx] = plan;
    } else {
      list.insert(0, plan);
    }
    await saveCachedEmiPlans(list);
  }

  Future<void> deleteEmiPlanLocal(String id) async {
    final list = await getCachedEmiPlans();
    list.removeWhere((p) => p.id == id);
    await saveCachedEmiPlans(list);
  }

  Future<void> updateEmiInstallmentLocal(
    String planId,
    int installmentNumber,
    bool isPaid, {
    DateTime? paidDate,
    String? paymentReference,
    bool clearPaymentReference = false,
  }) async {
    final list = await getCachedEmiPlans();
    final pIdx = list.indexWhere((p) => p.id == planId);
    if (pIdx != -1) {
      final plan = list[pIdx];
      final newInst = plan.installments.map((it) {
        if (it.installmentNumber == installmentNumber) {
          return it.copyWith(
            isPaid: isPaid,
            paidDate: isPaid ? (paidDate ?? DateTime.now()) : null,
            paymentReference: clearPaymentReference ? null : (paymentReference ?? it.paymentReference),
            clearPaidDate: !isPaid,
            clearPaymentReference: clearPaymentReference,
          );
        }
        return it;
      }).toList();

      final allPaid = newInst.every((it) => it.isPaid);
      final newStatus = allPaid ? 'COMPLETED' : 'ACTIVE';

      list[pIdx] = plan.copyWith(
        installments: newInst,
        status: newStatus,
      );
      await saveCachedEmiPlans(list);
    }
  }

  /// Checks all active EMI plans and automatically posts single combined installment
  /// transactions to the credit card in the ledger for any installment whose billing
  /// date has arrived (billingDate <= today) and has not yet been paid/posted.
  Future<List<AutoPostedEmiInstallment>> processDueEmiInstallments({DateTime? referenceDate}) async {
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Ensure transaction cache is hydrated before any saveTransaction call
    await getTransactions();
    final plans = await getCachedEmiPlans();
    final postedList = <AutoPostedEmiInstallment>[];

    bool anyPlanUpdated = false;

    for (int pIdx = 0; pIdx < plans.length; pIdx++) {
      final plan = plans[pIdx];
      if (plan.status.toUpperCase() != 'ACTIVE') continue;

      bool planChanged = false;
      final updatedInstallments = List<EmiInstallment>.from(plan.installments);

      for (int iIdx = 0; iIdx < updatedInstallments.length; iIdx++) {
        final inst = updatedInstallments[iIdx];
        final instDate = DateTime(inst.billingDate.year, inst.billingDate.month, inst.billingDate.day);

        // Check if billing date has arrived or passed and installment is not yet paid/posted
        if (!inst.isPaid && (inst.paymentReference == null || inst.paymentReference!.isEmpty)) {
          if (today.isAfter(instDate) || today.isAtSameMomentAs(instDate)) {
            final financeCharge = inst.interest + inst.applicableTaxes;
            String refId = '';

            // As in real banking, the billing date charges monthly interest & GST onto the card.
            // The principal is NOT debited again, because it was already swiped in the original purchase.
            if (financeCharge > 0) {
              refId = FinanceTransaction.generateReferenceId(inst.billingDate);
              final narration = 'EMI Interest & GST #${inst.installmentNumber}: ${plan.title} (Int: ₹${IndianCurrency.format(inst.interest)} + GST: ₹${IndianCurrency.format(inst.applicableTaxes)})';
              final instTx = FinanceTransaction(
                date: inst.billingDate,
                referenceId: refId,
                narration: narration,
                flow: 'Withdraw',
                invoice: '',
                purpose: 'Credit Card EMI Interest & GST',
                spentFor: 'Self',
                breakdowns: [
                  PaymentBreakdown(
                    paymentType: 'Credit',
                    account: plan.account,
                    amount: financeCharge,
                  ),
                ],
                totalAmount: financeCharge,
              );

              await saveTransaction(instTx);
            } else {
              refId = 'BILLED-#${inst.installmentNumber}';
            }

            final updatedInst = inst.copyWith(
              isPaid: true,
              paidDate: inst.billingDate,
              paymentReference: refId,
            );
            updatedInstallments[iIdx] = updatedInst;
            planChanged = true;

            postedList.add(AutoPostedEmiInstallment(
              plan: plan,
              installment: updatedInst,
              transactionRef: refId,
            ));
          }
        }
      }

      if (planChanged) {
        final allPaid = updatedInstallments.every((it) => it.isPaid);
        final newStatus = allPaid ? 'COMPLETED' : 'ACTIVE';
        plans[pIdx] = plan.copyWith(
          installments: updatedInstallments,
          status: newStatus,
        );
        anyPlanUpdated = true;
      }
    }

    if (anyPlanUpdated) {
      await saveCachedEmiPlans(plans);
      unawaited(GoogleSheetsService.instance.syncAllEmiPlans(plans));
    }

    return postedList;
  }

  /// Reverts and deletes auto-posted installments when the user taps Undo.
  Future<void> undoAutoPostedEmiInstallments(List<AutoPostedEmiInstallment> postedList) async {
    for (final item in postedList) {
      // 1. Delete posted transaction from ledger
      await deleteTransaction(item.transactionRef, referenceId: item.transactionRef);

      // 2. Mark installment unpaid and clear payment reference
      final plans = await getCachedEmiPlans();
      final pIdx = plans.indexWhere((p) => p.id == item.plan.id);
      if (pIdx != -1) {
        final plan = plans[pIdx];
        final updatedInst = plan.installments.map((it) {
          if (it.installmentNumber == item.installment.installmentNumber) {
            return it.copyWith(
              isPaid: false,
              clearPaidDate: true,
              clearPaymentReference: true,
            );
          }
          return it;
        }).toList();

        plans[pIdx] = plan.copyWith(
          installments: updatedInst,
          status: 'ACTIVE',
        );
        await saveCachedEmiPlans(plans);
        unawaited(GoogleSheetsService.instance.syncAllEmiPlans(plans));
      }
    }
  }

  List<LoanEntry> _extractLoanEntriesFromTransactions(List<FinanceTransaction> txList) {
    final derived = <LoanEntry>[];
    for (final tx in txList) {
      if (tx.splitRecipients != null && tx.splitRecipients!.isNotEmpty) {
        for (final r in tx.splitRecipients!) {
          if (!r.isPersonal && r.amount > 0) {
            final isReceived = tx.flow.toLowerCase().contains('deposit') ||
                tx.flow.toLowerCase().contains('income') ||
                tx.purpose.toLowerCase().contains('received');
            derived.add(LoanEntry(
              id: 'local_${tx.id}_${r.name}',
              date: tx.date,
              borrower: r.name,
              narration: tx.narration,
              invoice: tx.invoice,
              transactionType: tx.breakdowns.map((b) => b.paymentType ?? '').where((s) => s.isNotEmpty).join(', '),
              account: tx.fromSummary,
              givenAmount: isReceived ? 0.0 : r.amount,
              receivedAmount: isReceived ? r.amount : 0.0,
              referenceId: tx.referenceId,
              parentTransaction: tx,
            ));
          }
        }
      }
    }
    derived.sort((a, b) => b.date.compareTo(a.date));
    return derived;
  }

  bool _isLoanBackgroundSyncRunning = false;
  void _triggerLoanBackgroundSyncIfNeeded() {
    if (_isLoanBackgroundSyncRunning) return;
    _isLoanBackgroundSyncRunning = true;
    Future.delayed(const Duration(milliseconds: 300), () async {
      try {
        final remoteEntries = await GoogleSheetsService.instance.fetchLoanEntries(forceRefresh: true);
        if (remoteEntries.isNotEmpty) {
          _cachedLoanEntries = remoteEntries;
          await saveLocalLoanEntries(remoteEntries);
          loansNotifier.value++;
        }
      } catch (e) {
        debugPrint('Silent loan background sync error: $e');
      } finally {
        _isLoanBackgroundSyncRunning = false;
      }
    });
  }

  Future<void> saveLocalLoanEntries(List<LoanEntry> entries) async {
    _cachedLoanEntries = List<LoanEntry>.from(entries);
    final prefs = await SharedPreferences.getInstance();
    final encoded = entries.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_keyLoanEntries, encoded);
  }

  /// Instantly stores or updates the transaction in the mobile device and immediately
  /// returns so the UI resets without any delay, and syncs to Google Sheets in the background.
  Future<void> saveTransaction(FinanceTransaction transaction) async {
    final prefs = await SharedPreferences.getInstance();

    // Hydrate from SharedPreferences first if memory cache is cold so existing offline history is never wiped
    _cachedTransactions ??= _loadTransactionsFromPrefs(prefs) ?? [];
    _cachedTransactions!.removeWhere((t) =>
        (transaction.id.isNotEmpty && t.id == transaction.id) ||
        (transaction.referenceId.isNotEmpty && t.referenceId == transaction.referenceId));
    _cachedTransactions!.insert(0, transaction);
    _cachedTransactions!.sort((a, b) => b.date.compareTo(a.date));
    GoogleSheetsService.instance.cachedTransactions =
        List<FinanceTransaction>.from(_cachedTransactions!);

    // Instant local update for loan entries if split transaction
    if (transaction.splitRecipients != null && transaction.splitRecipients!.isNotEmpty) {
      _cachedLoanEntries ??= [];
      _cachedLoanEntries!.removeWhere((e) => e.referenceId == transaction.referenceId);
      final newLoans = _extractLoanEntriesFromTransactions([transaction]);
      _cachedLoanEntries!.addAll(newLoans);
      _cachedLoanEntries!.sort((a, b) => b.date.compareTo(a.date));
      GoogleSheetsService.instance.cachedLoanEntries = _cachedLoanEntries;
      await saveLocalLoanEntries(_cachedLoanEntries!);
      loansNotifier.value++;
    }

    // 2. Instant local device storage write (< 5ms)
    await _persistTransactions(prefs, _cachedTransactions!);

    // 3. Register in pending sync queue & notify UI
    await _addPendingSave(prefs, transaction);
    transactionsNotifier.value++;

    // 4. Non-blocking asynchronous sync to Google Sheets
    _enqueueBackgroundSync(transaction);

    // 5. Update Account Balances sheet if balances configured
    if (isBalanceConfigured() && _cachedBalanceConfig != null) {
      _syncAccountBalancesToSheet(_cachedBalanceConfig!);
    }
  }

  /// Instantly deletes the transaction from the mobile device and immediately
  /// returns so the UI updates without any delay, and syncs deletion in the background.
  Future<void> deleteTransaction(String idOrReference, {String? referenceId}) async {
    final prefs = await SharedPreferences.getInstance();
    _cachedTransactions ??= _loadTransactionsFromPrefs(prefs) ?? [];
    // 0. Resolve both id and referenceId from current cached transactions
    String ref = referenceId ?? '';
    String tid = idOrReference;
    if (_cachedTransactions != null) {
      for (final t in _cachedTransactions!) {
        if (t.id == idOrReference || t.referenceId == idOrReference || (ref.isNotEmpty && t.referenceId == ref)) {
          if (ref.isEmpty && t.referenceId.isNotEmpty) ref = t.referenceId;
          if (t.id.isNotEmpty) tid = t.id;
          break;
        }
      }
    }

    // 1. Instant in-memory removal (< 1ms)
    _cachedTransactions ??= [];
    _cachedTransactions!.removeWhere((t) =>
      (tid.isNotEmpty && t.id == tid) ||
      (idOrReference.isNotEmpty && t.id == idOrReference) ||
      (ref.isNotEmpty && t.referenceId == ref) ||
      (idOrReference.isNotEmpty && t.referenceId == idOrReference)
    );
    GoogleSheetsService.instance.cachedTransactions =
        List<FinanceTransaction>.from(_cachedTransactions!);

    // Instant local removal for loan entries
    if (_cachedLoanEntries != null) {
      _cachedLoanEntries!.removeWhere((e) =>
        e.referenceId == ref || e.referenceId == tid || e.id == idOrReference
      );
      GoogleSheetsService.instance.cachedLoanEntries = _cachedLoanEntries;
      await saveLocalLoanEntries(_cachedLoanEntries!);
      loansNotifier.value++;
    }

    // 2. Instant local device storage write (< 5ms)
    await _persistTransactions(prefs, _cachedTransactions!);

    // 3. Register in pending deletes & notify UI
    await _addPendingDelete(prefs, tid);
    if (ref.isNotEmpty && ref != tid) {
      await _addPendingDelete(prefs, ref);
    }
    transactionsNotifier.value++;

    // 4. Non-blocking asynchronous deletion on Google Sheets: prioritize referenceId
    final targetRef = ref.isNotEmpty ? ref : tid;
    _enqueueBackgroundDelete(targetRef);

    // 5. Update Account Balances sheet if balances configured
    if (isBalanceConfigured() && _cachedBalanceConfig != null) {
      _syncAccountBalancesToSheet(_cachedBalanceConfig!);
    }
  }

  // --- Internal Helpers for Local Persistence & Background Queue ---

  Future<void> _persistTransactions(SharedPreferences prefs, List<FinanceTransaction> list) async {
    final encoded = list.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList(_keyTransactions, encoded);
  }

  Future<List<FinanceTransaction>> _getPendingSaves(SharedPreferences prefs) async {
    final raw = prefs.getStringList(_keyPendingSaves);
    if (raw == null || raw.isEmpty) return [];
    try {
      return raw.map((item) => FinanceTransaction.fromJson(jsonDecode(item))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _addPendingSave(SharedPreferences prefs, FinanceTransaction tx) async {
    final list = await _getPendingSaves(prefs);
    list.removeWhere((t) =>
        (tx.id.isNotEmpty && t.id == tx.id) ||
        (tx.referenceId.isNotEmpty && t.referenceId == tx.referenceId));
    list.add(tx);
    final encoded = list.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList(_keyPendingSaves, encoded);
    _updatePendingSyncCount(prefs);
  }

  Future<void> _removePendingSave(String idOrRef) async {
    if (idOrRef.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = await _getPendingSaves(prefs);
    list.removeWhere((t) => t.id == idOrRef || t.referenceId == idOrRef);
    final encoded = list.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList(_keyPendingSaves, encoded);
    final set = Set<String>.from(pendingSyncSetNotifier.value);
    set.remove(idOrRef);
    pendingSyncSetNotifier.value = set;
    pendingSyncNotifier.value = set.length;
    _updatePendingSyncCount(prefs);
  }

  Future<List<String>> _getPendingDeletes(SharedPreferences prefs) async {
    return prefs.getStringList(_keyPendingDeletes) ?? [];
  }

  Future<void> _addPendingDelete(SharedPreferences prefs, String idOrRef) async {
    await _removePendingSave(idOrRef);
    final list = await _getPendingDeletes(prefs);
    if (!list.contains(idOrRef)) {
      list.add(idOrRef);
      await prefs.setStringList(_keyPendingDeletes, list);
    }
    _updatePendingSyncCount(prefs);
  }

  Future<void> _removePendingDelete(String idOrRef) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _getPendingDeletes(prefs);
    list.remove(idOrRef);
    await prefs.setStringList(_keyPendingDeletes, list);
    final set = Set<String>.from(pendingSyncSetNotifier.value);
    set.remove(idOrRef);
    pendingSyncSetNotifier.value = set;
    pendingSyncNotifier.value = set.length;
    _updatePendingSyncCount(prefs);
  }

  void _updatePendingSyncCount(SharedPreferences prefs) {
    final savesRaw = prefs.getStringList(_keyPendingSaves) ?? [];
    final deletes = prefs.getStringList(_keyPendingDeletes) ?? [];
    final set = <String>{};
    for (final s in savesRaw) {
      try {
        final map = jsonDecode(s);
        if (map['referenceId'] != null) set.add(map['referenceId'].toString());
        if (map['id'] != null) set.add(map['id'].toString());
      } catch (_) {}
    }
    set.addAll(deletes);
    for (final item in _syncQueue) {
      if (item.transaction != null) {
        set.add(item.transaction!.referenceId);
        set.add(item.transaction!.id);
      }
      if (item.idOrReference != null && item.idOrReference!.isNotEmpty) {
        set.add(item.idOrReference!);
      }
    }
    pendingSyncSetNotifier.value = set;
    pendingSyncNotifier.value = set.length;
  }

  Timer? _offlineRetryTimer;

  void _scheduleOfflineRetry() {
    final isTesting = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTesting) return;
    if (_offlineRetryTimer?.isActive ?? false) return;
    _offlineRetryTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (_syncQueue.isEmpty && pendingSyncNotifier.value == 0) {
        timer.cancel();
        return;
      }
      if (await hasNetworkConnection()) {
        timer.cancel();
        await _resumePendingSyncQueue();
        if (isBalanceConfigured() && _cachedBalanceConfig != null) {
          unawaited(_syncAccountBalancesToSheet(_cachedBalanceConfig!));
        }
      }
    });
  }

  void _enqueueBackgroundSync(FinanceTransaction tx) {
    _syncQueue.removeWhere((item) =>
        item.isSave &&
        item.transaction != null &&
        ((tx.id.isNotEmpty && item.transaction!.id == tx.id) ||
            (tx.referenceId.isNotEmpty && item.transaction!.referenceId == tx.referenceId)));
    _syncQueue.add(_SyncQueueItem.save(tx));
    final set = Set<String>.from(pendingSyncSetNotifier.value);
    if (tx.referenceId.isNotEmpty) set.add(tx.referenceId);
    if (tx.id.isNotEmpty) set.add(tx.id);
    pendingSyncSetNotifier.value = set;
    pendingSyncNotifier.value = set.length;
    _processSyncQueue();
  }

  void _enqueueBackgroundDelete(String idOrRef) {
    if (idOrRef.isEmpty) return;
    _syncQueue.removeWhere((item) => !item.isSave && item.idOrReference == idOrRef);
    _syncQueue.add(_SyncQueueItem.delete(idOrRef));
    final set = Set<String>.from(pendingSyncSetNotifier.value);
    set.add(idOrRef);
    pendingSyncSetNotifier.value = set;
    pendingSyncNotifier.value = set.length;
    _processSyncQueue();
  }

  void _triggerBackgroundSyncIfNeeded() {
    if (_hasTriggeredInitialBackgroundSync) return;
    _hasTriggeredInitialBackgroundSync = true;
    Future.microtask(() async {
      try {
        if (!await hasNetworkConnection()) {
          // Hold background sync until network is available
          _hasTriggeredInitialBackgroundSync = false;
          return;
        }
        await _resumePendingSyncQueue();
        final remote = await GoogleSheetsService.instance.fetchTransactions(forceRefresh: true);
        if (remote.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final merged = await _mergeWithPendingLocal(prefs, remote);
          _cachedTransactions = merged;
          await _persistTransactions(prefs, merged);
          GoogleSheetsService.instance.cachedTransactions = merged;
          transactionsNotifier.value++;
        }
      } catch (_) {}
    });
  }

  Future<void> _resumePendingSyncQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingDeletes = await _getPendingDeletes(prefs);
      for (final ref in pendingDeletes) {
        if (!_syncQueue.any((item) => !item.isSave && item.idOrReference == ref)) {
          _syncQueue.add(_SyncQueueItem.delete(ref));
        }
      }
      final pendingSaves = await _getPendingSaves(prefs);
      for (final tx in pendingSaves) {
        if (!_syncQueue.any((item) => item.isSave && item.transaction?.referenceId == tx.referenceId)) {
          _syncQueue.add(_SyncQueueItem.save(tx));
        }
      }
      _processSyncQueue();
    } catch (e) {
      debugPrint('Error resuming pending sync queue: $e');
    }
  }

  Future<void> _processSyncQueue() async {
    if (_isSyncQueueRunning) return;
    _isSyncQueueRunning = true;

    try {
      if (!await hasNetworkConnection()) {
        GoogleSheetsService.instance.isSyncingNotifier.value = false;
        if (_syncQueue.isNotEmpty) {
          GoogleSheetsService.instance.syncStatusNotifier.value =
              'Offline — ${_syncQueue.length} item(s) queued';
          _scheduleOfflineRetry();
        }
        return;
      }
      while (_syncQueue.isNotEmpty) {
        if (!await hasNetworkConnection()) {
          _scheduleOfflineRetry();
          break;
        }
        final item = _syncQueue.removeAt(0);
        bool ok = false;
        try {
          if (item.isSave && item.transaction != null) {
            ok = await GoogleSheetsService.instance.saveTransaction(item.transaction!);
            if (ok) {
              await _removePendingSave(item.transaction!.referenceId);
              if (item.transaction!.id.isNotEmpty) {
                await _removePendingSave(item.transaction!.id);
              }
            }
          } else if (!item.isSave && item.idOrReference != null) {
            ok = await GoogleSheetsService.instance.deleteTransaction(item.idOrReference!);
            if (ok) {
              await _removePendingDelete(item.idOrReference!);
            }
          }
        } catch (e) {
          debugPrint('Sync queue execution error: $e');
        }

        if (!ok) {
          // Hold item in queue until network / server is reachable again
          _syncQueue.insert(0, item);
          _scheduleOfflineRetry();
          break;
        }

        final prefs = await SharedPreferences.getInstance();
        _updatePendingSyncCount(prefs);
      }
      if (_syncQueue.isEmpty) {
        _offlineRetryTimer?.cancel();
      }
    } finally {
      _isSyncQueueRunning = false;
    }
  }

  // Monthly Category Budgets
  Future<Map<String, double>> getMonthlyBudgets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyMonthlyBudgets);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveMonthlyBudgets(Map<String, double> budgets) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = <String, double>{};
    budgets.forEach((k, v) {
      if (k.trim().isNotEmpty && v > 0) cleaned[k.trim()] = v;
    });
    await prefs.setString(_keyMonthlyBudgets, jsonEncode(cleaned));
  }

  // App PIN Lock
  Future<String?> getAppLockPin() async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString(_keyAppLockPin);
    return (pin != null && pin.length == 4) ? pin : null;
  }

  Future<void> setAppLockPin(String? pin) async {
    final prefs = await SharedPreferences.getInstance();
    if (pin == null || pin.isEmpty) {
      await prefs.remove(_keyAppLockPin);
    } else {
      await prefs.setString(_keyAppLockPin, pin);
    }
  }

  Future<bool> getBiometricLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBiometricLock) ?? false;
  }

  Future<void> setBiometricLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBiometricLock, enabled);
  }

  // Pending Sync Queue Details & Manual Trigger
  Future<({List<FinanceTransaction> saves, List<String> deletes})> getPendingSyncDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final saves = await _getPendingSaves(prefs);
    final deletes = await _getPendingDeletes(prefs);
    return (saves: saves, deletes: deletes);
  }

  Future<bool> syncPendingNow() async {
    if (!await hasNetworkConnection()) return false;
    await _resumePendingSyncQueue();
    final details = await getPendingSyncDetails();
    return details.saves.isEmpty && details.deletes.isEmpty;
  }

  Future<void> clearAllLocalData() async {
    _offlineRetryTimer?.cancel();
    _syncQueue.clear();
    _cachedTransactions = [];
    _cachedLoanEntries = [];
    _cachedTemplates = null;
    _cachedRecurring = null;
    _cachedBalanceConfig = null;
    _cachedEmiPlans = null;
    _cachedInvoices = null;
    _cachedDealerPrices = null;
    pendingSyncSetNotifier.value = {};
    pendingSyncNotifier.value = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    transactionsNotifier.value++;
    loansNotifier.value++;
    balanceConfigNotifier.value = null;
    emiPlansNotifier.value++;
    recurringNotifier.value++;
    mastersNotifier.value++;
  }

  // Templates
  Future<List<TransactionTemplate>> getTemplates() async {
    if (_cachedTemplates != null) {
      return List<TransactionTemplate>.from(_cachedTemplates!);
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyTemplates);
    if (raw == null || raw.isEmpty) {
      final initial = defaultTemplates;
      await saveAllTemplates(initial);
      _cachedTemplates = List<TransactionTemplate>.from(initial);
      return List<TransactionTemplate>.from(_cachedTemplates!);
    }
    try {
      final list = raw.map((item) => TransactionTemplate.fromJson(jsonDecode(item))).toList();
      _cachedTemplates = list;
      return List<TransactionTemplate>.from(_cachedTemplates!);
    } catch (_) {
      _cachedTemplates = List<TransactionTemplate>.from(defaultTemplates);
      return List<TransactionTemplate>.from(_cachedTemplates!);
    }
  }

  Future<void> saveAllTemplates(List<TransactionTemplate> templates) async {
    _cachedTemplates = List<TransactionTemplate>.from(templates);
    final prefs = await SharedPreferences.getInstance();
    final encoded = templates.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList(_keyTemplates, encoded);
    notifyMastersChanged();
    triggerConfigBackup();
  }

  Future<void> saveTemplate(TransactionTemplate template) async {
    final templates = await getTemplates();
    templates.removeWhere((t) => t.id == template.id);
    templates.insert(0, template);
    await saveAllTemplates(templates);
  }

  Future<void> deleteTemplate(String id) async {
    final templates = await getTemplates();
    templates.removeWhere((t) => t.id == id);
    await saveAllTemplates(templates);
  }

  // Recurring Transactions
  Future<List<RecurringTransaction>> getRecurringTransactions() async {
    if (_cachedRecurring != null) {
      return List<RecurringTransaction>.from(_cachedRecurring!);
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyRecurring);
    if (raw == null || raw.isEmpty) {
      _cachedRecurring = [];
      return [];
    }
    try {
      final list = raw.map((item) => RecurringTransaction.fromJson(jsonDecode(item))).toList()
        ..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));
      _cachedRecurring = list;
      return List<RecurringTransaction>.from(_cachedRecurring!);
    } catch (_) {
      _cachedRecurring = [];
      return [];
    }
  }

  Future<void> saveAllRecurringTransactions(List<RecurringTransaction> list) async {
    _cachedRecurring = List<RecurringTransaction>.from(list);
    final prefs = await SharedPreferences.getInstance();
    final encoded = list.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList(_keyRecurring, encoded);
    recurringNotifier.value++;
    triggerConfigBackup();
  }

  Future<void> saveRecurringTransaction(RecurringTransaction tx) async {
    final list = await getRecurringTransactions();
    list.removeWhere((t) => t.id == tx.id);
    list.add(tx);
    list.sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));
    await saveAllRecurringTransactions(list);
  }

  Future<void> deleteRecurringTransaction(String id) async {
    final list = await getRecurringTransactions();
    list.removeWhere((t) => t.id == id);
    await saveAllRecurringTransactions(list);
  }

  Future<void> togglePauseRecurringTransaction(String id) async {
    final list = await getRecurringTransactions();
    final idx = list.indexWhere((r) => r.id == id);
    if (idx != -1) {
      list[idx] = list[idx].copyWith(isPaused: !list[idx].isPaused);
      await saveAllRecurringTransactions(list);
    }
  }
  static const String _keyGrokApiKey = 'grok_api_key';
  static const String _keyGeminiApiKey = 'gemini_api_key';
  static const String _keyGrokModel = 'selected_grok_model';
  static const String _keyGeminiModel = 'selected_gemini_model';
  static const String _keyCachedGrokModels = 'cached_grok_models';
  static const String _keyCachedGeminiModels = 'cached_gemini_models';
  String? _cachedGrokKey;
  String? _cachedGeminiKey;

  Future<String?> getGrokApiKey() async {
    if (_cachedGrokKey != null) return _cachedGrokKey;
    final prefs = await SharedPreferences.getInstance();
    _cachedGrokKey = prefs.getString(_keyGrokApiKey);
    return _cachedGrokKey;
  }

  Future<void> setGrokApiKey(String key) async {
    _cachedGrokKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGrokApiKey, _cachedGrokKey!);
  }

  Future<String?> getGeminiApiKey() async {
    if (_cachedGeminiKey != null) return _cachedGeminiKey;
    final prefs = await SharedPreferences.getInstance();
    _cachedGeminiKey = prefs.getString(_keyGeminiApiKey);
    return _cachedGeminiKey;
  }

  Future<void> setGeminiApiKey(String key) async {
    _cachedGeminiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGeminiApiKey, _cachedGeminiKey!);
  }

  Future<String?> getSelectedGrokModel() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_keyGrokModel)?.trim();
    return (val != null && val.isNotEmpty) ? val : null;
  }

  Future<void> setSelectedGrokModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGrokModel, model.trim());
  }

  Future<String?> getSelectedGeminiModel() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_keyGeminiModel)?.trim();
    return (val != null && val.isNotEmpty) ? val : null;
  }

  Future<void> setSelectedGeminiModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGeminiModel, model.trim());
  }

  Future<List<String>> getCachedGrokModels() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyCachedGrokModels) ?? const [];
  }

  Future<void> setCachedGrokModels(List<String> models) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyCachedGrokModels, models);
  }

  Future<List<String>> getCachedGeminiModels() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyCachedGeminiModels) ?? const [];
  }

  Future<void> setCachedGeminiModels(List<String> models) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyCachedGeminiModels, models);
  }

  Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

class _SyncQueueItem {
  final bool isSave;
  final FinanceTransaction? transaction;
  final String? idOrReference;
  _SyncQueueItem.save(this.transaction) : isSave = true, idOrReference = null;
  _SyncQueueItem.delete(this.idOrReference) : isSave = false, transaction = null;
}

class AutoPostedEmiInstallment {
  final EmiPlan plan;
  final EmiInstallment installment;
  final String transactionRef;

  AutoPostedEmiInstallment({
    required this.plan,
    required this.installment,
    required this.transactionRef,
  });
}
