import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account_balance_model.dart';
import '../models/invoice_model.dart';
import '../models/transaction_model.dart';
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

  List<InvoiceItemRecord>? _cachedInvoices;
  List<DealerPriceItem>? _cachedDealerPrices;

  static final StorageService instance = StorageService._internal();
  StorageService._internal();

  final ValueNotifier<int> mastersNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> isDarkModeNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> recurringNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> transactionsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> loansNotifier = ValueNotifier<int>(0);
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
    return LiveAccountBalanceSummary.calculate(
      config: config,
      transactions: transactions,
      categories: categories,
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
  Future<List<FinanceTransaction>> getTransactions({bool forceRefresh = false}) async {
    // 1. In-memory cache hit: zero lag
    if (!forceRefresh && _cachedTransactions != null) {
      return List<FinanceTransaction>.from(_cachedTransactions!);
    }

    final prefs = await SharedPreferences.getInstance();

    // 2. Local mobile storage (SharedPreferences) hit: instantaneous
    if (!forceRefresh && _cachedTransactions == null) {
      final raw = prefs.getStringList(_keyTransactions);
      if (raw != null && raw.isNotEmpty) {
        try {
          _cachedTransactions = raw
              .map((item) => FinanceTransaction.fromJson(jsonDecode(item)))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          GoogleSheetsService.instance.cachedTransactions = _cachedTransactions;

          // Resume any pending background sync operations or silent refresh
          _triggerBackgroundSyncIfNeeded();

          return List<FinanceTransaction>.from(_cachedTransactions!);
        } catch (e) {
          debugPrint('Error parsing cached transactions: $e');
        }
      }
    }

    // 3. Remote fetch from Google Sheets (on forced refresh or cold first launch)
    try {
      final remoteList = await GoogleSheetsService.instance.fetchTransactions(forceRefresh: forceRefresh);
      if (remoteList.isNotEmpty) {
        // Merge with local un-synced items
        final merged = List<FinanceTransaction>.from(remoteList);
        final pendingSaves = await _getPendingSaves(prefs);
        for (final p in pendingSaves) {
          merged.removeWhere((t) => t.id == p.id || t.referenceId == p.referenceId);
          merged.insert(0, p);
        }
        final pendingDeletes = await _getPendingDeletes(prefs);
        merged.removeWhere((t) => pendingDeletes.contains(t.id) || pendingDeletes.contains(t.referenceId));
        merged.sort((a, b) => b.date.compareTo(a.date));

        _cachedTransactions = merged;
        await _persistTransactions(prefs, _cachedTransactions!);
        GoogleSheetsService.instance.cachedTransactions = _cachedTransactions;
        transactionsNotifier.value++;
      } else {
        _cachedTransactions ??= [];
      }
    } catch (e) {
      debugPrint('Error fetching transactions from remote: $e');
      _cachedTransactions ??= [];
    }

    return List<FinanceTransaction>.from(_cachedTransactions!);
  }

  Future<void> saveAllTransactions(List<FinanceTransaction> transactions) async {
    _cachedTransactions = List<FinanceTransaction>.from(transactions);
    final prefs = await SharedPreferences.getInstance();
    await _persistTransactions(prefs, _cachedTransactions!);
    GoogleSheetsService.instance.cachedTransactions = _cachedTransactions;
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
    // 1. Instant in-memory update (< 1ms)
    _cachedTransactions ??= [];
    _cachedTransactions!.removeWhere((t) => t.id == transaction.id || t.referenceId == transaction.referenceId);
    _cachedTransactions!.insert(0, transaction);
    _cachedTransactions!.sort((a, b) => b.date.compareTo(a.date));
    GoogleSheetsService.instance.cachedTransactions = _cachedTransactions;

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
    final prefs = await SharedPreferences.getInstance();
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
      t.id == tid ||
      t.id == idOrReference ||
      (ref.isNotEmpty && t.referenceId == ref) ||
      t.referenceId == idOrReference
    );
    GoogleSheetsService.instance.cachedTransactions = _cachedTransactions;

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
    final prefs = await SharedPreferences.getInstance();
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
    list.removeWhere((t) => t.id == tx.id || t.referenceId == tx.referenceId);
    list.add(tx);
    final encoded = list.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList(_keyPendingSaves, encoded);
    _updatePendingSyncCount(prefs);
  }

  Future<void> _removePendingSave(String idOrRef) async {
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

  void _enqueueBackgroundSync(FinanceTransaction tx) {
    _syncQueue.add(_SyncQueueItem.save(tx));
    final set = Set<String>.from(pendingSyncSetNotifier.value);
    set.add(tx.referenceId);
    set.add(tx.id);
    pendingSyncSetNotifier.value = set;
    pendingSyncNotifier.value = set.length;
    _processSyncQueue();
  }

  void _enqueueBackgroundDelete(String idOrRef) {
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
    _resumePendingSyncQueue();
    Future.microtask(() async {
      try {
        final remote = await GoogleSheetsService.instance.fetchTransactions(forceRefresh: true);
        if (remote.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          _cachedTransactions = remote;
          await _persistTransactions(prefs, remote);
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
      while (_syncQueue.isNotEmpty) {
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

        final prefs = await SharedPreferences.getInstance();
        _updatePendingSyncCount(prefs);
      }
    } finally {
      _isSyncQueueRunning = false;
    }
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
