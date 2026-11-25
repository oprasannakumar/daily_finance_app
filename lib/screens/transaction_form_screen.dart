import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/transaction_model.dart';
import '../models/account_balance_model.dart';
import '../utils/currency_formatter.dart';
import '../services/storage_service.dart';
import '../services/ai_transaction_service.dart';
import '../services/google_auth_service.dart';
import '../services/google_sheets_service.dart';
import '../services/clipboard_transaction_parser.dart';
import '../widgets/swipeable_date_picker.dart';
import '../widgets/payment_breakdown_card.dart';
import '../widgets/popup_select_field.dart';
import '../widgets/calculator_keyboard_sheet.dart';
import '../widgets/batch_review_sheet.dart';
import '../widgets/theme_action_emojis.dart';
import '../widgets/theme_toggle_button.dart';
import '../theme/app_theme_colors.dart';
import 'transaction_history_screen.dart';
import 'manage_details_screen.dart';
import 'borrowers_ledger_screen.dart';
import 'account_balances_screen.dart';
import 'financial_health_dashboard_screen.dart';
import '../models/invoice_model.dart';
import 'invoice_manager_screen.dart';
import 'emi_manager_screen.dart';

class TransactionFormScreen extends StatefulWidget {
  final VoidCallback? onTransactionSaved;
  final VoidCallback? onTemplateSaved;
  final ValueNotifier<TransactionTemplate?>? templateToLoadNotifier;
  final Listenable? mastersRefreshListenable;

  const TransactionFormScreen({
    super.key,
    this.onTransactionSaved,
    this.onTemplateSaved,
    this.templateToLoadNotifier,
    this.mastersRefreshListenable,
  });

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final StorageService _storage = StorageService.instance;

  DateTime _selectedDate = DateTime.now();
  late String _referenceId;
  late TextEditingController _referenceIdController;
  final TextEditingController _narrationController = TextEditingController();
  final TextEditingController _invoiceController = TextEditingController();
  final TextEditingController _customPurposeController = TextEditingController();
  final TextEditingController _customSpentForController = TextEditingController();

  String? _flow; // Nullable: defaults to "Select"
  String? _selectedPurpose; // Nullable: defaults to "Select"
  String? _selectedSpentFor; // Nullable: defaults to "Select"

  List<String> _purposes = [];
  List<String> _spentFors = [];
  Map<String, List<String>> _categoryAccounts = {};
  List<TransactionTemplate> _allTemplates = [];
  List<TransactionTemplate> _matchingTemplates = [];

  // Multi-transaction clipboard drafts
  List<ParsedTransactionDraft> _draftTransactions = [];
  int _currentDraftIndex = 0;

  final List<PaymentBreakdown> _breakdowns = [];
  final List<PaymentBreakdown> _toBreakdowns = [];
  bool _isLoading = true;

  // Self Transfer Mode State
  bool _isSelfTransferMode = false;

  // Split Mode State
  bool _isSplitModeEnabled = false;
  bool get _isSplitMode => _isSplitModeEnabled && _selectedSpentFor == 'Split';
  String _splitType = 'Value'; // 'Value' or 'Percentage'
  final List<SplitRecipient> _splitRecipients = [];
  Timer? _narrationDebounce;
  Timer? _aiAutoFillDebounce;

  // Recurrence State
  bool _isRecurrenceMode = false;
  String _recurrenceFrequency = 'Month'; // Month, Quarterly, Half-Yearly, Yearly, Custom
  int? _customMonths;
  int? _customDays;
  String? _editingRecurringId;
  String? _executingRecurringId;
  String? _editingTemplateId;
  String? _editingTemplateName;
  List<RecurringTransaction> _recurringTransactions = [];
  LiveAccountBalanceSummary? _liveBalancesSummary;
  bool _suppressTemplateSuggestions = false;

  // AI and Speech Recognition State
  late stt.SpeechToText _speech;
  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isAiProcessing = false;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
    _referenceId = FinanceTransaction.generateReferenceId(_selectedDate);
    _referenceIdController = TextEditingController(text: _referenceId);
    _breakdowns.add(PaymentBreakdown());
    _toBreakdowns.add(PaymentBreakdown());
    _loadMasters();
    _loadRecurringTransactions();
    _loadBalancesSummary();
    GoogleAuthService.instance.init();
    _narrationController.addListener(_onNarrationChanged);
    widget.templateToLoadNotifier?.addListener(_onTemplateToLoadChanged);
    widget.mastersRefreshListenable?.addListener(_loadMasters);
    StorageService.instance.mastersNotifier.addListener(_loadMasters);
    StorageService.instance.recurringNotifier.addListener(_loadRecurringTransactions);
    StorageService.instance.balanceConfigNotifier.addListener(_loadBalancesSummary);
    StorageService.instance.transactionsNotifier.addListener(_refreshFloatingStats);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleStartupFlow();
      _checkDueEmiInstallmentsOnStartup();
    });
  }

  Future<void> _checkDueEmiInstallmentsOnStartup() async {
    final isTesting = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTesting) return;

    try {
      final posted = await _storage.processDueEmiInstallments();
      if (posted.isNotEmpty && mounted) {
        final totalFeeAmt = posted.fold(0.0, (sum, p) => sum + p.installment.interest + p.installment.applicableTaxes);
        final firstItem = posted.first;
        final firstFee = firstItem.installment.interest + firstItem.installment.applicableTaxes;
        final msg = posted.length == 1
            ? 'Logged Interest & GST for Installment #${firstItem.installment.installmentNumber} of "${firstItem.plan.title}" (₹${IndianCurrency.format(firstFee)}) on ${firstItem.plan.account}'
            : 'Logged Interest & GST for ${posted.length} due EMI installments (₹${IndianCurrency.format(totalFeeAmt)}) on credit cards';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E293B),
            duration: const Duration(seconds: 6),
            content: Row(
              children: [
                const Icon(Icons.credit_card_rounded, color: Color(0xFFFF5C38), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    msg,
                    style: const TextStyle(fontSize: 12.5, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'Undo',
              textColor: const Color(0xFFFF5C38),
              onPressed: () async {
                await _storage.undoAutoPostedEmiInstallments(posted);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Auto-posted EMI installment(s) undone.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error processing due EMI installments on startup: $e');
    }
  }

  Future<void> _handleStartupFlow() async {
    // Skip automated prompts in test environments so unit/widget tests aren't obscured
    final isTesting = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTesting) return;

    final prefs = await SharedPreferences.getInstance();
    final hasInitialSynced = prefs.getBool('has_initial_drive_synced_v1') ?? false;
    final config = await _storage.getAccountBalanceConfig();
    final localTxs = await _storage.getTransactions();

    // If local data already exists or initial startup sync was already completed,
    // do NOT check Google Drive or show any prompts on app open.
    if (hasInitialSynced || config.isConfigured || localTxs.isNotEmpty) {
      await prefs.setBool('has_initial_drive_synced_v1', true);
      return;
    }

    // Only on brand-new fresh installation with no local data:
    // Initialize Google Auth (checks cached tokens / silent sign-in)
    await GoogleAuthService.instance.init();

    final isSignedIn = GoogleAuthService.instance.isSignedIn;
    if (!isSignedIn) {
      if (!mounted) return;
      final didConnect = await _showGoogleConnectPrompt();
      if (!didConnect) {
        // User skipped or failed Google Connect. Fall back to manual balances setup if not configured.
        await prefs.setBool('has_initial_drive_synced_v1', true);
        _checkFallbackBalancesConfig();
        return;
      }
    }

    // Google account is connected on fresh setup. Silently check Drive without any snackbars or prompts.
    if (!mounted) return;
    await _checkAndSyncGoogleDriveData(silent: true);
    await prefs.setBool('has_initial_drive_synced_v1', true);
  }

  Future<bool> _showGoogleConnectPrompt() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final result = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        bool isConnecting = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Cloud Sync Icon Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.cloud_sync_rounded, size: 40, color: primaryColor),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Connect Google Account',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Connect your Google Drive to automatically restore your transactions, bank accounts, balances, credit card limits, templates, and recurring payments from your Account Ledger.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: textSecondary,
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          errorMessage!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // "Sign in with Google" button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1E293B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                          ),
                          elevation: 1,
                        ),
                        onPressed: isConnecting
                            ? null
                            : () async {
                                setSheetState(() {
                                  isConnecting = true;
                                  errorMessage = null;
                                });
                                try {
                                  final user = await GoogleAuthService.instance.signIn();
                                  if (user != null) {
                                    if (sheetCtx.mounted) {
                                      Navigator.of(sheetCtx).pop(true);
                                    }
                                  } else {
                                    final err = GoogleAuthService.instance.errorMessageNotifier.value;
                                    setSheetState(() {
                                      isConnecting = false;
                                      errorMessage = err ?? 'Sign in was cancelled or failed. Please try again.';
                                    });
                                  }
                                } catch (e) {
                                  setSheetState(() {
                                    isConnecting = false;
                                    errorMessage = 'Connection error: $e';
                                  });
                                }
                              },
                        child: isConnecting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'G',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF4285F4),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Sign in with Google',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // "Skip & Set Up Manually" button
                    TextButton(
                      onPressed: isConnecting
                          ? null
                          : () {
                              Navigator.of(sheetCtx).pop(false);
                            },
                      child: Text(
                        'Skip & Set Up Manually',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return result ?? false;
  }

  Future<void> _checkAndSyncGoogleDriveData({bool silent = false}) async {
    final token = await GoogleAuthService.instance.getAccessToken();
    if (token == null) {
      _checkFallbackBalancesConfig();
      return;
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!silent) {
      messenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(child: Text('Checking Google Drive for existing Account Ledger...')),
            ],
          ),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final sheetId = await GoogleSheetsService.instance.findExistingLedger(token);

    if (sheetId != null && sheetId.isNotEmpty) {
      // Existing spreadsheet file was found on Google Drive! Grab and restore all data!
      debugPrint('Found existing ledger on Google Drive ($sheetId). Restoring data...');

      final txs = await _storage.getTransactions(forceRefresh: true);

      await GoogleSheetsService.instance.restoreAllFromSheet(token, sheetId);
      await _storage.extractAccountsFromTransactions(txs);

      await _loadMasters();
      await _loadRecurringTransactions();
      await _loadBalancesSummary();
      _refreshFloatingStats();

      final config = await _storage.getAccountBalanceConfig();

      if (mounted) {
        if (!silent) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '✅ Restored ${txs.length} transactions, bank accounts, and card limits from Google Drive!',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }

        // If the restored spreadsheet didn't contain balances, prompt user to configure them
        if (!config.isConfigured) {
          _checkFallbackBalancesConfig();
        }
      }
    } else {
      // No existing file found on Drive
      debugPrint('No existing account ledger found on Google Drive.');
      _checkFallbackBalancesConfig();
    }
  }

  Future<void> _checkFallbackBalancesConfig() async {
    final isConfigured = _storage.isBalanceConfigured();
    if (!isConfigured) {
      final config = await _storage.getAccountBalanceConfig();
      if (!config.isConfigured && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AccountBalancesScreen(isInitialSetup: true),
          ),
        );
      }
    }
  }

  @override
  void didUpdateWidget(covariant TransactionFormScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mastersRefreshListenable != oldWidget.mastersRefreshListenable) {
      oldWidget.mastersRefreshListenable?.removeListener(_loadMasters);
      widget.mastersRefreshListenable?.addListener(_loadMasters);
    }
    if (widget.templateToLoadNotifier != oldWidget.templateToLoadNotifier) {
      oldWidget.templateToLoadNotifier?.removeListener(_onTemplateToLoadChanged);
      widget.templateToLoadNotifier?.addListener(_onTemplateToLoadChanged);
    }
  }

  void _onTemplateToLoadChanged() {
    final t = widget.templateToLoadNotifier?.value;
    if (t != null) {
      _applyTemplate(t);
    }
  }

  @override
  void dispose() {
    try {
      _speech.stop();
    } catch (_) {}
    _narrationDebounce?.cancel();
    _aiAutoFillDebounce?.cancel();
    widget.templateToLoadNotifier?.removeListener(_onTemplateToLoadChanged);
    widget.mastersRefreshListenable?.removeListener(_loadMasters);
    StorageService.instance.mastersNotifier.removeListener(_loadMasters);
    StorageService.instance.recurringNotifier.removeListener(_loadRecurringTransactions);
    StorageService.instance.balanceConfigNotifier.removeListener(_loadBalancesSummary);
    StorageService.instance.transactionsNotifier.removeListener(_refreshFloatingStats);
    _referenceIdController.dispose();
    _narrationController.removeListener(_onNarrationChanged);
    _narrationController.dispose();
    _invoiceController.dispose();
    _customPurposeController.dispose();
    _customSpentForController.dispose();
    super.dispose();
  }

  String? _editingTransactionId;
  List<FinanceTransaction> _multiEditTransactions = [];
  int _currentMultiEditIndex = 0;

  Future<void> _navigateToInvoiceManager() async {
    HapticFeedback.lightImpact();
    final result = await Navigator.of(context).push<InvoiceSummary>(
      MaterialPageRoute(
        builder: (_) => InvoiceManagerScreen(
          initialDate: _selectedDate,
          onInvoiceSelected: _onInvoiceSelected,
        ),
      ),
    );
    if (result != null) {
      _onInvoiceSelected(result);
    }
  }

  void _onInvoiceSelected(InvoiceSummary inv) {
    setState(() {
      _invoiceController.text = inv.billNo;
      
      final total = inv.totalAmount;
      if (_flow == null || _flow == 'Select') {
        _flow = 'Withdraw';
      }

      if (_breakdowns.isEmpty) {
        _breakdowns.add(PaymentBreakdown());
      }
      _breakdowns[0].amount = total;

      if (_narrationController.text.trim().isEmpty && inv.shopName.isNotEmpty) {
        _narrationController.text = inv.shopName;
      }

      if (inv.hasBorrowers) {
        _isSplitModeEnabled = true;
        _isSelfTransferMode = false;
        _selectedSpentFor = 'Split';
        
        final loanGivenPurpose = _purposes.firstWhere(
          (p) => p.toLowerCase().replaceAll(' ', '') == 'loangiven' || p.toLowerCase().contains('loan given'),
          orElse: () => 'Loan Given',
        );
        _selectedPurpose = loanGivenPurpose;

        _splitRecipients.clear();
        
        final selfAmount = inv.selfShare;
        final selfPct = total > 0 ? (selfAmount / total) * 100 : 0.0;
        _splitRecipients.add(SplitRecipient(
          name: 'Personal Share',
          isPersonal: true,
          amount: selfAmount,
          percentage: selfPct,
        ));

        for (final entry in inv.borrowerShares.entries) {
          final bAmount = entry.value;
          final bPct = total > 0 ? (bAmount / total) * 100 : 0.0;
          _splitRecipients.add(SplitRecipient(
            name: entry.key,
            isPersonal: false,
            amount: bAmount,
            percentage: bPct,
          ));
        }
      } else {
        _isSplitModeEnabled = false;
        _splitRecipients.clear();
        if (_selectedSpentFor == 'Split') {
          _selectedSpentFor = 'Self';
        }
        final groceryPurpose = _purposes.firstWhere(
          (p) => p.toLowerCase().contains('groc') || p.toLowerCase().contains('food'),
          orElse: () => _purposes.firstWhere((p) => p != 'Select', orElse: () => 'Grocery'),
        );
        _selectedPurpose = groceryPurpose;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          inv.hasBorrowers
              ? '🧾 Loaded ${inv.billNo} with borrower splits (${inv.borrowerShares.keys.join(", ")})'
              : '🧾 Loaded ${inv.billNo} (${inv.shopName})',
        ),
        backgroundColor: const Color(0xFF4ECDC4),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showInvoicePickerBottomSheet() async {
    HapticFeedback.lightImpact();
    final dateStr = DateFormat('dd-MMM-yyyy').format(_selectedDate);

    String searchFilter = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return FutureBuilder<List<InvoiceItemRecord>>(
              future: GoogleSheetsService.instance.fetchInvoiceItems(forceRefresh: true, filterDate: _selectedDate),
              builder: (ctx, snapshot) {
                final isLoading = snapshot.connectionState == ConnectionState.waiting;
                final rawItems = snapshot.data ?? [];
                final items = rawItems.where((it) =>
                  it.billDate.year == _selectedDate.year &&
                  it.billDate.month == _selectedDate.month &&
                  it.billDate.day == _selectedDate.day
                ).toList();
                final allInvoices = InvoiceSummary.groupItems(items);

                final invoices = allInvoices.where((inv) {
                  if (searchFilter.isEmpty) return true;
                  final q = searchFilter.toLowerCase();
                  final matchBill = inv.billNo.toLowerCase().contains(q);
                  final matchShop = inv.shopName.toLowerCase().contains(q);
                  final matchItem = inv.items.any((it) => it.itemName.toLowerCase().contains(q));
                  final matchBorrower = inv.items.any((it) => it.recipient.toLowerCase().contains(q));
                  return matchBill || matchShop || matchItem || matchBorrower;
                }).toList();

                return Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '🧾 Select Invoice',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'For $dateStr',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      if (!isLoading && allInvoices.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Search invoice (bill, dealer, item, borrower)...',
                              hintStyle: const TextStyle(fontSize: 12),
                              prefixIcon: const Icon(Icons.search, size: 18),
                              suffixIcon: searchFilter.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 16),
                                      onPressed: () => setModalState(() => searchFilter = ''),
                                    )
                                  : null,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              filled: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            ),
                            onChanged: (val) => setModalState(() => searchFilter = val.trim()),
                          ),
                        ),
                      if (isLoading)
                        const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (invoices.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24.0),
                          child: Column(
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text(
                                searchFilter.isNotEmpty
                                    ? 'No invoices match "$searchFilter" for $dateStr.'
                                    : 'No invoices found for $dateStr.',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _navigateToInvoiceManager();
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('Create Invoice in Manager'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF7A5C),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: invoices.length,
                        itemBuilder: (ctx, index) {
                          final inv = invoices[index];
                          final isSelected = _invoiceController.text.trim() == inv.billNo.trim();

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSelected ? const Color(0xFFFF7A5C) : Colors.grey.withValues(alpha: 0.2),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFFF7A5C).withValues(alpha: 0.15),
                                child: const Text('🧾', style: TextStyle(fontSize: 16)),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      inv.billNo.isNotEmpty ? inv.billNo : 'Invoice',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Text(
                                    '₹${IndianCurrency.format(inv.totalAmount)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFF7A5C),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (inv.shopName.isNotEmpty)
                                    Text('Shop: ${inv.shopName}', style: const TextStyle(fontSize: 12)),
                                  if (inv.hasBorrowers)
                                    Wrap(
                                      spacing: 4,
                                      children: inv.borrowerShares.entries.map((e) {
                                        return Text(
                                          '${e.key}: ₹${IndianCurrency.format(e.value)}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFFA78BFA),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                ],
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle, color: Color(0xFFFF7A5C))
                                  : null,
                              onTap: () {
                                Navigator.pop(ctx);
                                _onInvoiceSelected(inv);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_invoiceController.text.isNotEmpty)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() => _invoiceController.clear());
                              Navigator.pop(ctx);
                            },
                            child: const Text('Clear Selection'),
                          ),
                        ),
                      if (_invoiceController.text.isNotEmpty) const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _navigateToInvoiceManager();
                          },
                          icon: const Icon(Icons.tune, size: 16),
                          label: const Text('Invoice Manager'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4ECDC4),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  },
);
}

  Future<void> _navigateToHistory() async {
    HapticFeedback.mediumImpact();
    final result = await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const TransactionHistoryScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;
          final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
        transitionDuration: const Duration(milliseconds: 280),
      ),
    );
    if (result != null) {
      if (result is List<FinanceTransaction> && result.isNotEmpty) {
        if (result.length == 1) {
          _loadTransactionForEditing(result[0]);
        } else {
          _loadMultipleTransactionsForEditing(result);
        }
      } else if (result is FinanceTransaction) {
        _loadTransactionForEditing(result);
      }
    }
  }

  void _loadMultipleTransactionsForEditing(List<FinanceTransaction> list) {
    if (list.isEmpty) return;
    setState(() {
      _multiEditTransactions = List<FinanceTransaction>.from(list);
      _currentMultiEditIndex = 0;
      _draftTransactions.clear();
      _currentDraftIndex = 0;
    });
    _loadTransactionForEditing(_multiEditTransactions[0], showSnackbar: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loaded ${list.length} transactions for editing'),
        backgroundColor: const Color(0xFF3B82F6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _refreshFloatingStats() async {
    await _loadBalancesSummary();
    await _loadRecurringTransactions();
  }

  Future<void> _loadBalancesSummary() async {
    try {
      final summary = await _storage.getLiveAccountBalances();
      if (mounted) {
        setState(() {
          _liveBalancesSummary = summary;
        });
      }
    } catch (e) {
      debugPrint('Error loading balances summary: $e');
    }
  }

  Future<void> _loadMasters() async {
    final purposes = await _storage.getPurposes();
    final spentFors = await _storage.getSpentFors();
    final categoryAccounts = await _storage.getCategoryAccounts();
    final templates = await _storage.getTemplates();

    if (mounted) {
      setState(() {
        _purposes = purposes;
        _spentFors = spentFors;
        _categoryAccounts = categoryAccounts;
        _allTemplates = templates;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadRecurringTransactions() async {
    final list = await _storage.getRecurringTransactions();
    if (mounted) {
      setState(() {
        _recurringTransactions = list;
      });
    }
  }

  void _applyAccountToBreakdown(PaymentBreakdown b, String? accName, String paymentType) {
    if (accName == null || accName.trim().isEmpty || paymentType == 'Cash') {
      b.account = null;
      b.otherAccountText = null;
      return;
    }
    final clean = accName.trim();
    final catKey = (paymentType == 'Credit' || paymentType == 'Credit Card')
        ? 'Credit Cards'
        : (paymentType == 'Wallets' || paymentType == 'Wallet')
            ? 'Wallets'
            : (paymentType == 'Rewards' || paymentType == 'Reward')
                ? 'Rewards'
                : 'Bank Accounts';
    final accounts = _categoryAccounts[catKey] ?? [];

    String? matched;
    for (final a in accounts) {
      if (a != 'Other' && a.toLowerCase() == clean.toLowerCase()) {
        matched = a;
        break;
      }
    }
    if (matched == null) {
      for (final a in accounts) {
        if (a != 'Other' &&
            (a.toLowerCase().contains(clean.toLowerCase()) ||
             clean.toLowerCase().contains(a.toLowerCase()))) {
          matched = a;
          break;
        }
      }
    }

    if (matched != null) {
      b.account = matched;
      b.otherAccountText = null;
    } else {
      b.account = clean;
      b.otherAccountText = null;
    }
  }

  void _applyPurpose(String? rawPurpose) {
    if (rawPurpose == null || rawPurpose.trim().isEmpty) return;
    final clean = rawPurpose.trim();

    String? matched;
    for (final p in _purposes) {
      if (p != 'Other' && p != 'Others' && p.toLowerCase() == clean.toLowerCase()) {
        matched = p;
        break;
      }
    }
    if (matched == null) {
      for (final p in _purposes) {
        if (p != 'Other' && p != 'Others' &&
            (p.toLowerCase().contains(clean.toLowerCase()) ||
             clean.toLowerCase().contains(p.toLowerCase()))) {
          matched = p;
          break;
        }
      }
    }

    if (matched != null) {
      _selectedPurpose = matched;
      _customPurposeController.clear();
    } else {
      _selectedPurpose = 'Other';
      _customPurposeController.text = clean;
    }
  }

  void _applySpentFor(String? rawSf) {
    if (rawSf == null || rawSf.trim().isEmpty) {
      _selectedSpentFor = null;
      _customSpentForController.clear();
      return;
    }
    final cleanSf = rawSf.trim();

    String? matched;
    for (final sf in _spentFors) {
      if (sf != 'Other' && sf.toLowerCase() == cleanSf.toLowerCase()) {
        matched = sf;
        break;
      }
    }
    if (matched == null) {
      for (final sf in _spentFors) {
        if (sf != 'Other' &&
            (sf.toLowerCase().contains(cleanSf.toLowerCase()) ||
             cleanSf.toLowerCase().contains(sf.toLowerCase()))) {
          matched = sf;
          break;
        }
      }
    }

    if (matched != null) {
      _selectedSpentFor = matched;
      _customSpentForController.clear();
    } else {
      _selectedSpentFor = 'Other';
      _customSpentForController.text =
          cleanSf[0].toUpperCase() + cleanSf.substring(1).toLowerCase();
    }
  }

  bool _userEditedToAmount = false;

  void _syncFromAmountToToAmountIfClearedCardBill({bool force = false}) {
    if (!_isSelfTransferMode) return;
    final narrLower = _narrationController.text.toLowerCase().trim();
    final isClearedCardBill = narrLower.contains('cleared card bill') ||
        narrLower.contains('clared card bill') ||
        narrLower.contains('clear card bill') ||
        narrLower.contains('cleared card') ||
        narrLower.contains('card bill');
    if (isClearedCardBill && _toBreakdowns.isNotEmpty && _breakdowns.isNotEmpty) {
      if (_toBreakdowns.length == 1) {
        if (force || !_userEditedToAmount || _toBreakdowns.first.amount == 0) {
          _toBreakdowns.first.amount = _totalFromAmount;
        }
      }
    }
  }

  void _onNarrationChanged() {
    _syncFromAmountToToAmountIfClearedCardBill();
    if (_suppressTemplateSuggestions) {
      return;
    }
    _narrationDebounce?.cancel();
    _narrationDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _suppressTemplateSuggestions) return;
      final query = _narrationController.text.trim().toLowerCase();
      setState(() {
        if (query.isEmpty) {
          _matchingTemplates = [];
        } else {
          _matchingTemplates = _allTemplates.where((t) {
            return t.name.toLowerCase().contains(query) ||
                t.narration.toLowerCase().contains(query);
          }).toList();
        }
      });
    });
  }

  void _toggleDedicatedSplitMode(bool enabled) {
    setState(() {
      _isSplitModeEnabled = enabled;
      if (enabled) {
        _isSelfTransferMode = false;
        _selectedSpentFor = 'Split';
        _selectedPurpose = (_flow == 'Deposit') ? 'Loan Received' : 'Loan Given';
        if (_splitRecipients.isEmpty) {
          _initDefaultSplitRecipients();
        }
      } else {
        if (_selectedSpentFor == 'Split') {
          _selectedSpentFor = null;
        }
      }
    });
  }

  void _toggleSelfTransferMode(bool enabled) {
    setState(() {
      _isSelfTransferMode = enabled;
      _userEditedToAmount = false;
      if (enabled) {
        _isSplitModeEnabled = false;
        if (_toBreakdowns.isEmpty) {
          _toBreakdowns.add(PaymentBreakdown());
        }
      }
    });
  }

  void _initDefaultSplitRecipients() {
    _splitRecipients.clear();
    final defaultRecipient = _spentFors.firstWhere(
      (s) => s != 'Split' && s != 'Other',
      orElse: () => 'Friends',
    );
    final count = 2;
    final equalAmount = _totalAmount > 0 ? (_totalAmount / count) : 0.0;
    _splitRecipients.add(SplitRecipient(
      name: 'Personal Share',
      isPersonal: true,
      amount: equalAmount,
      percentage: 50.0,
    ));
    _splitRecipients.add(SplitRecipient(
      name: defaultRecipient,
      isPersonal: false,
      amount: equalAmount,
      percentage: 50.0,
    ));
  }

  List<String> get _availableSpentFors {
    if (!_isSplitModeEnabled) {
      return _spentFors.where((s) => s != 'Split').toList();
    }
    if (!_spentFors.contains('Split')) {
      final list = List<String>.from(_spentFors);
      final otherIdx = list.indexOf('Other');
      if (otherIdx != -1) {
        list.insert(otherIdx, 'Split');
      } else {
        list.add('Split');
      }
      return list;
    }
    return _spentFors;
  }

  void _onFlowSelected(String val) {
    setState(() {
      _flow = val;
      if (_isSplitModeEnabled) {
        _selectedPurpose = (val == 'Deposit') ? 'Loan Received' : 'Loan Given';
      }
    });
  }

  void _onSpentForSelected(String val) {
    setState(() {
      _selectedSpentFor = val;
      if (val == 'Split' && _isSplitModeEnabled) {
        _selectedPurpose = (_flow == 'Deposit') ? 'Loan Received' : 'Loan Given';
        if (_splitRecipients.isEmpty) {
          _initDefaultSplitRecipients();
        }
      }
    });
  }

  void _toggleSplitType() {
    setState(() {
      _splitType = _splitType == 'Value' ? 'Percentage' : 'Value';
      if (_splitType == 'Percentage') {
        if (_totalAmount > 0) {
          for (final r in _splitRecipients) {
            r.percentage = (r.amount / _totalAmount) * 100;
          }
        }
      } else {
        for (final r in _splitRecipients) {
          r.amount = (_totalAmount * r.percentage) / 100;
        }
      }
    });
  }

  void _splitEqually() {
    if (_splitRecipients.isEmpty) return;
    setState(() {
      final count = _splitRecipients.length;
      final equalAmount = count > 0 ? (_totalAmount / count) : 0.0;
      final equalPercentage = count > 0 ? (100.0 / count) : 0.0;
      for (final r in _splitRecipients) {
        r.amount = equalAmount;
        r.percentage = equalPercentage;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Split ₹${IndianCurrency.format(_totalAmount)} equally among ${_splitRecipients.length} members'),
        backgroundColor: const Color(0xFF0F766E),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _addPersonalShare() {
    setState(() {
      _splitRecipients.insert(
        0,
        SplitRecipient(
          name: 'Personal Share',
          isPersonal: true,
          amount: 0.0,
          percentage: 0.0,
        ),
      );
      _splitEqually();
    });
  }

  void _addRecipientShare() {
    setState(() {
      final availableNames = _spentFors.where((s) => s != 'Split' && s != 'Other').toList();
      final defaultName = availableNames.isNotEmpty ? availableNames.first : 'Friends';
      _splitRecipients.add(SplitRecipient(
        name: defaultName,
        isPersonal: false,
        amount: 0.0,
        percentage: 0.0,
      ));
      _splitEqually();
    });
  }

  Future<void> _onAddSplitPressed() async {
    final hasPersonalShare = _splitRecipients.any((r) => r.isPersonal);

    if (hasPersonalShare) {
      // Personal Share is available: directly add recipient row
      _addRecipientShare();
    } else {
      // Personal Share is NOT available: ask user for Personal Share or Recipient Share
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.call_split_rounded, color: Color(0xFF0F766E), size: 22),
              SizedBox(width: 8),
              Text(
                'Add to Split',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select the type of share to add:',
                style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFF99F6E4), width: 1.2),
                ),
                tileColor: const Color(0xFFF0FDFA),
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_rounded, color: Color(0xFF0F766E), size: 20),
                ),
                title: const Text(
                  'Personal Share',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F766E)),
                ),
                subtitle: const Text(
                  'Add your own share',
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF0F766E)),
                onTap: () => Navigator.of(ctx).pop('personal'),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
                ),
                tileColor: const Color(0xFFF8FAFC),
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF64748B).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.group_outlined, color: Color(0xFF334155), size: 20),
                ),
                title: const Text(
                  'Recipient Share',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                ),
                subtitle: const Text(
                  'Add a friend or recipient member',
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B)),
                onTap: () => Navigator.of(ctx).pop('recipient'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
          ],
        ),
      );

      if (choice == 'personal') {
        _addPersonalShare();
      } else if (choice == 'recipient') {
        _addRecipientShare();
      }
    }
  }

  void _removeSplitRecipient(int index) {
    if (index < 0 || index >= _splitRecipients.length) return;
    final removed = _splitRecipients[index];
    setState(() {
      _splitRecipients.removeAt(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed ${removed.isPersonal ? "My Share" : removed.name} from split'),
        backgroundColor: const Color(0xFF6366F1),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _openCalculatorForRecipient(int index) async {
    FocusScope.of(context).unfocus();
    final recipient = _splitRecipients[index];
    final initial = _splitType == 'Value' ? recipient.amount : recipient.percentage;
    final result = await CalculatorKeyboardSheet.show(
      context,
      initialAmount: initial,
    );
    if (result != null) {
      setState(() {
        if (_splitType == 'Value') {
          recipient.amount = result;
          if (_totalAmount > 0) {
            recipient.percentage = (result / _totalAmount) * 100;
          }
        } else {
          recipient.percentage = result;
          recipient.amount = (_totalAmount * result) / 100;
        }
      });
    }
  }

  void _loadTransactionForEditing(FinanceTransaction tx, {bool showSnackbar = true}) {
    setState(() {
      _editingTransactionId = tx.id;
      _selectedDate = tx.date;
      _referenceId = tx.referenceId;
      _referenceIdController.text = tx.referenceId;
      _narrationController.text = tx.narration;
      _invoiceController.text = tx.invoice;
      _flow = tx.flow;

      if (_purposes.contains(tx.purpose)) {
        _selectedPurpose = tx.purpose;
        _customPurposeController.clear();
      } else {
        _selectedPurpose = 'Other';
        _customPurposeController.text = tx.purpose;
      }

      if (_spentFors.contains(tx.spentFor)) {
        _selectedSpentFor = tx.spentFor;
        _customSpentForController.clear();
      } else {
        _selectedSpentFor = 'Other';
        _customSpentForController.text = tx.spentFor;
      }

      _breakdowns.clear();
      if (tx.breakdowns.isNotEmpty) {
        for (final b in tx.breakdowns) {
          _breakdowns.add(b.copy());
        }
      } else {
        _breakdowns.add(PaymentBreakdown());
      }

      _isSelfTransferMode = tx.isSelfTransfer || tx.flow == 'Transfer';
      _toBreakdowns.clear();
      if (_isSelfTransferMode && tx.toBreakdowns != null && tx.toBreakdowns!.isNotEmpty) {
        for (final b in tx.toBreakdowns!) {
          _toBreakdowns.add(b.copy());
        }
      } else {
        _toBreakdowns.add(PaymentBreakdown());
      }

      _splitRecipients.clear();
      _isSplitModeEnabled = !_isSelfTransferMode && (tx.isSplitMode || tx.spentFor == 'Split' || (tx.splitRecipients != null && tx.splitRecipients!.isNotEmpty));
      if (!_isSelfTransferMode && tx.splitRecipients != null && tx.splitRecipients!.isNotEmpty) {
        for (final s in tx.splitRecipients!) {
          _splitRecipients.add(s.copy());
        }
      } else if (_isSplitModeEnabled && tx.spentFor == 'Split') {
        _initDefaultSplitRecipients();
      }

      _matchingTemplates = [];
    });

    if (showSnackbar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loaded for editing: ${tx.referenceId}'),
          backgroundColor: const Color(0xFF3B82F6),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _applyTemplate(TransactionTemplate t, {bool isForEdit = false}) {
    _aiAutoFillDebounce?.cancel();
    setState(() {
      if (isForEdit) {
        _editingTemplateId = t.id;
        _editingTemplateName = t.name;
      } else {
        _editingTemplateId = null;
        _editingTemplateName = null;
      }
      _suppressTemplateSuggestions = true;
      _narrationController.text = t.narration;
      _flow = t.flow;

      if (_purposes.contains(t.purpose)) {
        _selectedPurpose = t.purpose;
        _customPurposeController.clear();
      } else {
        _selectedPurpose = 'Other';
        _customPurposeController.text = t.purpose;
      }

      if (_spentFors.contains(t.spentFor)) {
        _selectedSpentFor = t.spentFor;
        _customSpentForController.clear();
      } else {
        _selectedSpentFor = 'Other';
        _customSpentForController.text = t.spentFor;
      }

      _breakdowns.clear();
      if (t.breakdowns.isNotEmpty) {
        for (final b in t.breakdowns) {
          _breakdowns.add(b.copy());
        }
      } else {
        _breakdowns.add(PaymentBreakdown());
      }

      _isSelfTransferMode = t.isSelfTransfer;
      _toBreakdowns.clear();
      if (t.isSelfTransfer && t.toBreakdowns != null && t.toBreakdowns!.isNotEmpty) {
        for (final b in t.toBreakdowns!) {
          _toBreakdowns.add(b.copy());
        }
      } else {
        _toBreakdowns.add(PaymentBreakdown());
      }

      _splitRecipients.clear();
      _isSplitModeEnabled = !_isSelfTransferMode && (t.isSplitMode || t.spentFor == 'Split' || (t.splitRecipients != null && t.splitRecipients!.isNotEmpty));
      if (!_isSelfTransferMode && t.splitRecipients != null && t.splitRecipients!.isNotEmpty) {
        for (final s in t.splitRecipients!) {
          _splitRecipients.add(s.copy());
        }
      } else if (_isSplitModeEnabled && t.spentFor == 'Split') {
        _initDefaultSplitRecipients();
      }

      _matchingTemplates = [];
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isForEdit
            ? 'Loaded template for edit: "${t.name}"'
            : 'Loaded template: "${t.name}"'),
        backgroundColor: const Color(0xFF0F766E),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _loadRecurringIntoForm(RecurringTransaction r, {required bool isEdit}) {
    _aiAutoFillDebounce?.cancel();
    setState(() {
      _editingTemplateId = null;
      _editingTemplateName = null;
      _suppressTemplateSuggestions = true;
      _matchingTemplates = [];
      if (isEdit) {
        _isRecurrenceMode = true;
        _editingRecurringId = r.id;
        _executingRecurringId = null;
        _recurrenceFrequency = r.frequency;
        _customMonths = r.customMonths;
        _customDays = r.customDays;
        _selectedDate = r.nextDueDate;
      } else {
        // Exclude recurrence mode as requested when logging due recurrence
        _isRecurrenceMode = false;
        _editingRecurringId = null;
        _executingRecurringId = r.id;
        _selectedDate = DateTime.now();
      }

      _referenceId = FinanceTransaction.generateReferenceId(_selectedDate);
      _referenceIdController.text = _referenceId;
      _narrationController.text = r.narration;
      _invoiceController.text = r.invoice;
      _flow = r.flow;

      if (_purposes.contains(r.purpose)) {
        _selectedPurpose = r.purpose;
        _customPurposeController.clear();
      } else {
        _selectedPurpose = 'Other';
        _customPurposeController.text = r.purpose;
      }

      if (_spentFors.contains(r.spentFor)) {
        _selectedSpentFor = r.spentFor;
        _customSpentForController.clear();
      } else {
        _selectedSpentFor = 'Other';
        _customSpentForController.text = r.spentFor;
      }

      _breakdowns.clear();
      if (r.breakdowns.isNotEmpty) {
        for (final b in r.breakdowns) {
          _breakdowns.add(b.copy());
        }
      } else {
        _breakdowns.add(PaymentBreakdown());
      }

      _isSelfTransferMode = r.isSelfTransfer;
      _toBreakdowns.clear();
      if (r.isSelfTransfer && r.toBreakdowns != null && r.toBreakdowns!.isNotEmpty) {
        for (final b in r.toBreakdowns!) {
          _toBreakdowns.add(b.copy());
        }
      } else {
        _toBreakdowns.add(PaymentBreakdown());
      }

      _splitRecipients.clear();
      _isSplitModeEnabled = !_isSelfTransferMode && (r.isSplitMode || r.spentFor == 'Split' || (r.splitRecipients != null && r.splitRecipients!.isNotEmpty));
      if (!_isSelfTransferMode && r.splitRecipients != null && r.splitRecipients!.isNotEmpty) {
        for (final s in r.splitRecipients!) {
          _splitRecipients.add(s.copy());
        }
      } else if (_isSplitModeEnabled && r.spentFor == 'Split') {
        _initDefaultSplitRecipients();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isEdit
              ? 'Loaded recurrence for edit: "${r.narration}"'
              : 'Loaded "${r.narration}". Hit Save to record & advance schedule.',
        ),
        backgroundColor: isEdit ? const Color(0xFFF59E0B) : const Color(0xFF0F766E),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleAutoFill() async {
    String textToParse = '';
    if (_narrationController.text.trim().isNotEmpty) {
      final narrText = _narrationController.text.trim();
      final draftsFromNarr = ClipboardTransactionParser.parse(narrText);
      if (draftsFromNarr.isNotEmpty) {
        textToParse = narrText;
      } else {
        await _processAiAutoFill(narrText, updateNarration: true, isSilent: false);
        return;
      }
    }

    if (textToParse.isEmpty) {
      try {
        final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
        textToParse = clipboardData?.text ?? '';
      } catch (_) {}
    }

    if (textToParse.isNotEmpty) {
      final drafts = ClipboardTransactionParser.parse(textToParse);
      if (drafts.isNotEmpty) {
        if (drafts.length > 1) {
          if (!mounted) return;
          // Option 1: 1-Click Batch Review & Save All Sheet
          final result = await BatchReviewSheet.show(context, drafts: drafts);
          if (result == null || result.action == BatchReviewResultAction.cancelled) {
            return;
          }

          if (result.action == BatchReviewResultAction.savedAll) {
            setState(() {
              _draftTransactions.clear();
              _currentDraftIndex = 0;
              _resetEntireForm();
            });
            _refreshFloatingStats();
            widget.onTransactionSaved?.call();

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Saved ${result.remainingDrafts.length} transactions!',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  backgroundColor: const Color(0xFF10B981),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            return;
          }

          if (result.action == BatchReviewResultAction.reviewInForm) {
            setState(() {
              _draftTransactions = result.remainingDrafts;
              _currentDraftIndex = result.selectedIndex;
            });
            await _applyDraft(_draftTransactions[_currentDraftIndex]);
            return;
          }
        } else {
          // Exactly 1 transaction: load directly into form (no prev/next/remove buttons)
          setState(() {
            _draftTransactions = drafts;
            _currentDraftIndex = 0;
          });
          await _applyDraft(_draftTransactions[0]);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Loaded 1 transaction from clipboard',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                backgroundColor: const Color(0xFFFF5C38),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }
      }
    }

    // Fallback if clipboard doesn't contain matching transaction format
    if (_allTemplates.isNotEmpty) {
      _applyTemplate(_allTemplates.first);
    } else {
      _showQuickTemplatesSheet();
    }
  }

  Future<void> _applyDraft(ParsedTransactionDraft draft) async {
    setState(() {
      _selectedDate = draft.date;
      _referenceId = draft.referenceId.isNotEmpty
          ? draft.referenceId
          : FinanceTransaction.generateReferenceId(_selectedDate);
      _referenceIdController.text = _referenceId;
      _narrationController.text = draft.narration;
      _flow = draft.flow;
      _invoiceController.text = draft.invoice.isNotEmpty ? draft.invoice : '';

      // Purpose
      if (_purposes.contains(draft.purpose)) {
        _selectedPurpose = draft.purpose;
        _customPurposeController.clear();
      } else {
        _selectedPurpose = 'Other';
        _customPurposeController.text = draft.purpose;
      }

      // Spent For
      if (draft.spentFor == 'Select' || draft.spentFor.isEmpty) {
        _selectedSpentFor = _spentFors.contains('Self') ? 'Self' : null;
        _customSpentForController.clear();
      } else if (_spentFors.contains(draft.spentFor)) {
        _selectedSpentFor = draft.spentFor;
        _customSpentForController.clear();
      } else {
        _selectedSpentFor = 'Other';
        _customSpentForController.text = draft.spentFor;
      }

      _isSelfTransferMode = false;
      _isSplitModeEnabled = false;
      _splitRecipients.clear();

      // Payment Breakdown: If charges exist, generate 2 modes (Gross + Negative Reward)
      _breakdowns.clear();
      final modeType = draft.paymentType.isNotEmpty ? draft.paymentType : 'Credit';

      if (draft.charges > 0) {
        final grossAmt = double.parse((draft.amount + draft.charges.abs()).toStringAsFixed(2));
        final rewardAmt = -double.parse(draft.charges.abs().toStringAsFixed(2));

        final b1 = PaymentBreakdown();
        b1.paymentType = modeType;
        _applyAccountToBreakdown(b1, draft.account, modeType);
        b1.amount = grossAmt;
        _breakdowns.add(b1);

        final b2 = PaymentBreakdown();
        b2.paymentType = 'Rewards';
        _applyAccountToBreakdown(b2, draft.account, 'Rewards');
        if (draft.account.isNotEmpty) {
          b2.account = b1.account ?? draft.account;
          b2.otherAccountText = b1.otherAccountText;
        }
        b2.amount = rewardAmt;
        _breakdowns.add(b2);
      } else {
        final b = PaymentBreakdown();
        b.paymentType = modeType;
        _applyAccountToBreakdown(b, draft.account, modeType);
        b.amount = draft.amount;
        _breakdowns.add(b);
      }
    });
  }

  Future<void> _repeatLastTransaction() async {
    final latest = await _storage.getLatestTransaction();
    if (latest == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No previous transaction to repeat'),
            backgroundColor: Color(0xFFE11D48),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() {
      _referenceId = FinanceTransaction.generateReferenceId(_selectedDate);
      _referenceIdController.text = _referenceId;
      _narrationController.text = latest.narration;
      _flow = latest.flow;
      _invoiceController.text = latest.invoice;

      if (_purposes.contains(latest.purpose)) {
        _selectedPurpose = latest.purpose;
        _customPurposeController.clear();
      } else {
        _selectedPurpose = 'Other';
        _customPurposeController.text = latest.purpose;
      }

      if (_spentFors.contains(latest.spentFor)) {
        _selectedSpentFor = latest.spentFor;
        _customSpentForController.clear();
      } else {
        _selectedSpentFor = 'Other';
        _customSpentForController.text = latest.spentFor;
      }

      _breakdowns.clear();
      if (latest.breakdowns.isNotEmpty) {
        for (final b in latest.breakdowns) {
          _breakdowns.add(b.copy());
        }
      } else {
        _breakdowns.add(PaymentBreakdown());
      }

      _isSelfTransferMode = latest.isSelfTransfer;
      _toBreakdowns.clear();
      if (latest.isSelfTransfer && latest.toBreakdowns != null && latest.toBreakdowns!.isNotEmpty) {
        for (final b in latest.toBreakdowns!) {
          _toBreakdowns.add(b.copy());
        }
      } else {
        _toBreakdowns.add(PaymentBreakdown());
      }

      _splitRecipients.clear();
      _isSplitModeEnabled = !_isSelfTransferMode && (latest.isSplitMode || latest.spentFor == 'Split' || (latest.splitRecipients != null && latest.splitRecipients!.isNotEmpty));
      if (!_isSelfTransferMode && latest.splitRecipients != null && latest.splitRecipients!.isNotEmpty) {
        for (final s in latest.splitRecipients!) {
          _splitRecipients.add(s.copy());
        }
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Repeated transaction (${FinanceTransaction.formatDate(latest.date)})'),
          backgroundColor: const Color(0xFF0F766E),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _resetEntireForm() {
    setState(() {
      _editingTransactionId = null;
      _editingRecurringId = null;
      _executingRecurringId = null;
      _editingTemplateId = null;
      _editingTemplateName = null;
      _isRecurrenceMode = false;
      _recurrenceFrequency = 'Month';
      _customMonths = null;
      _customDays = null;
      _suppressTemplateSuggestions = false;
      _selectedDate = DateTime.now();
      _referenceId = FinanceTransaction.generateReferenceId(_selectedDate);
      _referenceIdController.text = _referenceId;
      _narrationController.clear();
      _invoiceController.clear();
      _customPurposeController.clear();
      _customSpentForController.clear();
      _flow = null;
      _selectedPurpose = null;
      _selectedSpentFor = null;
      _breakdowns.clear();
      _breakdowns.add(PaymentBreakdown());
      _toBreakdowns.clear();
      _toBreakdowns.add(PaymentBreakdown());
      _isSelfTransferMode = false;
      _splitRecipients.clear();
      _splitType = 'Value';
      _isSplitModeEnabled = false;
      _matchingTemplates = [];
      _multiEditTransactions.clear();
      _currentMultiEditIndex = 0;
    });
  }

  Future<void> _showSaveAsTemplateDialog() async {
    if (_selectedSpentFor == 'Split') {
      if (!_validateSplitAmounts()) return;
    }
    final isEditing = _editingTemplateId != null;
    final nameCtrl = TextEditingController(
      text: isEditing
          ? (_editingTemplateName ?? _narrationController.text.trim())
          : (_narrationController.text.trim().isNotEmpty
              ? _narrationController.text.trim()
              : 'My Template'),
    );
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(isEditing ? Icons.edit_note_rounded : Icons.bookmark_add_rounded,
                color: const Color(0xFF0F766E), size: 22),
            const SizedBox(width: 8),
            Text(isEditing ? 'Update Template' : 'Save as Template',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEditing
                    ? 'Update the template "$_editingTemplateName" with current form details.'
                    : 'Save the current form fields as a template for quick autofill while typing narration.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nameCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Template Name',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter a template name' : null,
              ),
            ],
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
            child: Text(isEditing ? 'Update' : 'Save'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final effectivePurpose = (_selectedPurpose == 'Other' && _customPurposeController.text.trim().isNotEmpty)
          ? _customPurposeController.text.trim()
          : (_selectedPurpose ?? 'Others');

      final effectiveSpentFor = (_selectedSpentFor == 'Other' && _customSpentForController.text.trim().isNotEmpty)
          ? _customSpentForController.text.trim()
          : (_selectedSpentFor ?? 'Self');

      // Exclude Date, Reference ID, and Invoice from template
      List<SplitRecipient>? templateSplits;
      if (!_isSelfTransferMode && (_isSplitModeEnabled || _selectedSpentFor == 'Split')) {
        if (_selectedSpentFor == 'Split') {
          templateSplits = _splitRecipients.map((s) => s.copy()).toList();
        } else {
          templateSplits = [
            SplitRecipient(
              name: effectiveSpentFor,
              isPersonal: false,
              amount: _totalAmount,
              percentage: 100.0,
            ),
          ];
        }
      }

      final newTemplate = _isSelfTransferMode
          ? TransactionTemplate(
              id: isEditing ? _editingTemplateId : null,
              name: nameCtrl.text.trim(),
              narration: _narrationController.text.trim().isNotEmpty
                  ? _narrationController.text.trim()
                  : 'Self Transfer',
              flow: 'Transfer',
              purpose: 'Self Transfer',
              spentFor: 'Self',
              breakdowns: _breakdowns.map((b) => b.copy()).toList(),
              toBreakdowns: _toBreakdowns.map((b) => b.copy()).toList(),
              isSelfTransfer: true,
            )
          : TransactionTemplate(
              id: isEditing ? _editingTemplateId : null,
              name: nameCtrl.text.trim(),
              narration: _narrationController.text.trim().isNotEmpty
                  ? _narrationController.text.trim()
                  : effectivePurpose,
              flow: _flow ?? 'Withdraw',
              purpose: effectivePurpose,
              spentFor: effectiveSpentFor,
              breakdowns: _breakdowns.map((b) => b.copy()).toList(),
              splitRecipients: templateSplits,
              isSplitMode: _isSplitModeEnabled,
            );

      final duplicate = _allTemplates.cast<TransactionTemplate?>().firstWhere(
        (existing) =>
            existing != null &&
            existing.id != _editingTemplateId &&
            newTemplate.matchesDataExceptNarration(existing),
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

      await _storage.saveTemplate(newTemplate);
      final refreshed = await _storage.getTemplates();
      setState(() {
        _allTemplates = refreshed;
        _editingTemplateId = null;
        _editingTemplateName = null;
      });
      widget.onTemplateSaved?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing
                ? 'Template "${newTemplate.name}" updated successfully!'
                : 'Template "${newTemplate.name}" saved!'),
            backgroundColor: const Color(0xFF0F766E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Reset entire form immediately upon saving template!
      _resetEntireForm();
    }
  }

  void _regenerateReferenceId() {
    setState(() {
      _referenceId = FinanceTransaction.generateReferenceId(_selectedDate);
      _referenceIdController.text = _referenceId;
    });
  }

  Future<void> _pickDate() async {
    final picked = await SwipeableDatePickerDialog.show(
      context: context,
      initialDate: _selectedDate,
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _referenceId = FinanceTransaction.generateReferenceId(picked);
        _referenceIdController.text = _referenceId;
      });
    }
  }

  void _addPaymentMode() {
    setState(() {
      _breakdowns.add(PaymentBreakdown());
    });
  }

  void _removePaymentMode(int index) {
    if (_breakdowns.length <= 1) return;
    setState(() {
      _breakdowns.removeAt(index);
      if (_breakdowns.isEmpty) {
        _breakdowns.add(PaymentBreakdown());
      }
    });
  }

  void _addToPaymentMode() {
    setState(() {
      _toBreakdowns.add(PaymentBreakdown());
    });
  }

  void _removeToPaymentMode(int index) {
    if (_toBreakdowns.length <= 1) return;
    setState(() {
      _toBreakdowns.removeAt(index);
      if (_toBreakdowns.isEmpty) {
        _toBreakdowns.add(PaymentBreakdown());
      }
    });
  }

  double get _totalFromAmount => _totalAmount;

  double get _totalToAmount {
    double sum = 0.0;
    for (final b in _toBreakdowns) {
      if (b.paymentType == 'Cash') {
        sum += b.calculatedCashAmount;
      } else {
        sum += b.amount;
      }
    }
    return sum;
  }

  double get _totalAmount {
    double sum = 0.0;
    for (final b in _breakdowns) {
      if (b.paymentType == 'Cash') {
        sum += b.calculatedCashAmount;
      } else {
        sum += b.amount;
      }
    }
    return sum;
  }

  Future<void> _pickContactForSpentFor() async {
    try {
      final contact = await FlutterContacts.native.showPicker();
      final name = contact?.displayName;
      if (name != null && name.trim().isNotEmpty) {
        setState(() {
          _customSpentForController.text = name.trim();
        });
      }
    } catch (_) {}
  }

  bool _validateSplitAmounts() {
    if (_selectedSpentFor != 'Split') return true;

    if (_splitRecipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Split mode requires at least one split member'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }

    double splitSum = 0.0;
    for (final r in _splitRecipients) {
      splitSum += r.amount;
    }

    final double diff = (_totalAmount - splitSum).abs();
    debugPrint('DBG _validateSplitAmounts: count=${_splitRecipients.length}, splitSum=$splitSum, totalAmount=$_totalAmount, diff=$diff');
    if (diff > 0.01) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Split amount mismatch! Total recipient shares (₹${IndianCurrency.format(splitSum)}) must equal Total Amount (₹${IndianCurrency.format(_totalAmount)})',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    }

    return true;
  }

  Future<void> _saveTransaction() async {
    debugPrint('DBG _saveTransaction: ref=${_referenceIdController.text}, spentFor=$_selectedSpentFor, totalAmount=$_totalAmount');
    // If currently editing a template, prompt user
    if (_editingTemplateId != null) {
      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: Color(0xFF0F766E), size: 22),
              SizedBox(width: 8),
              Text('Update Template?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'You are currently editing the template "$_editingTemplateName".\n\n'
            'Do you want to update this template with your changes, or save as a new transaction?',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Save Transaction'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Update Template'),
            ),
          ],
        ),
      );

      if (shouldUpdate == null) return;
      if (shouldUpdate == true) {
        if (!mounted) return;
        await _showSaveAsTemplateDialog();
        return;
      }
      if (!mounted) return;
      // If user selected "Save Transaction", clear editing template and proceed
      setState(() {
        _editingTemplateId = null;
        _editingTemplateName = null;
      });
    }

    // Validate custom requirements
    if (_referenceIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reference ID cannot be empty'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final effectiveRefId = _referenceIdController.text.trim();

    // Validate split amounts match total amount if in Split mode
    if (_selectedSpentFor == 'Split') {
      if (!_validateSplitAmounts()) return;
    }

    // ==========================================
    // Handle Recurrence Mode Saving (Optional fields allowed)
    // ==========================================
    if (_isRecurrenceMode) {
      final effectivePurpose = (_selectedPurpose == 'Other' && _customPurposeController.text.trim().isNotEmpty)
          ? _customPurposeController.text.trim()
          : (_selectedPurpose ?? (_isSelfTransferMode ? 'Self Transfer' : 'Others'));

      final effectiveSpentFor = (_selectedSpentFor == 'Other' && _customSpentForController.text.trim().isNotEmpty)
          ? _customSpentForController.text.trim()
          : (_selectedSpentFor ?? 'Self');

      final effectiveAmount = _isSelfTransferMode ? _totalFromAmount : _totalAmount;

      List<SplitRecipient>? recipientsToSave;
      if (!_isSelfTransferMode && (_isSplitModeEnabled || _selectedSpentFor == 'Split')) {
        if (_selectedSpentFor == 'Split') {
          recipientsToSave = _splitRecipients.map((s) => s.copy()).toList();
        } else {
          recipientsToSave = [
            SplitRecipient(
              name: effectiveSpentFor,
              isPersonal: false,
              amount: effectiveAmount,
              percentage: 100.0,
            ),
          ];
        }
      }

      final recurringTx = RecurringTransaction(
        id: _editingRecurringId,
        narration: _narrationController.text.trim().isNotEmpty
            ? _narrationController.text.trim()
            : effectivePurpose,
        nextDueDate: _selectedDate,
        frequency: _recurrenceFrequency,
        customMonths: _customMonths,
        customDays: _customDays,
        totalAmount: effectiveAmount,
        flow: _isSelfTransferMode ? 'Transfer' : (_flow ?? 'Withdraw'),
        purpose: effectivePurpose,
        spentFor: effectiveSpentFor,
        invoice: _invoiceController.text.trim(),
        breakdowns: _breakdowns.map((b) => b.copy()).toList(),
        toBreakdowns: _isSelfTransferMode ? _toBreakdowns.map((b) => b.copy()).toList() : null,
        splitRecipients: recipientsToSave,
        isSplitMode: _isSplitModeEnabled,
        isSelfTransfer: _isSelfTransferMode,
      );

      await _storage.saveRecurringTransaction(recurringTx);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_editingRecurringId != null
                ? 'Updated recurrence: ${recurringTx.narration}'
                : 'Saved recurring transaction: ${recurringTx.narration}'),
            backgroundColor: const Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _editingRecurringId = null;
        _isRecurrenceMode = false;
        _resetEntireForm();
        await _loadRecurringTransactions();
        _refreshFloatingStats();
      }
      return;
    }

    // ==========================================
    // Handle Self Transfer Mode Saving
    // ==========================================
    if (_isSelfTransferMode) {
      // Validate From breakdowns
      for (int i = 0; i < _breakdowns.length; i++) {
        final b = _breakdowns[i];
        if (b.paymentType == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please select Payment Type for "From" mode #${i + 1}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        if (b.paymentType != 'Cash' && (b.account == null || b.account!.isEmpty)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please select Account for "From" mode #${i + 1} (${b.paymentType})'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }

      // Validate To breakdowns
      for (int i = 0; i < _toBreakdowns.length; i++) {
        final b = _toBreakdowns[i];
        if (b.paymentType == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please select Payment Type for "To" mode #${i + 1}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        if (b.paymentType != 'Cash' && (b.account == null || b.account!.isEmpty)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please select Account for "To" mode #${i + 1} (${b.paymentType})'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }

      for (final b in _breakdowns) {
        if (b.paymentType == 'Cash') {
          b.recalculateCashAmount();
        }
      }
      for (final b in _toBreakdowns) {
        if (b.paymentType == 'Cash') {
          b.recalculateCashAmount();
        }
      }

      if (_totalFromAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('"From" amount must be greater than zero'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      if ((_totalFromAmount - _totalToAmount).abs() > 0.05) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Transfer mismatch! "From" total (₹${IndianCurrency.format(_totalFromAmount)}) must equal "To" total (₹${IndianCurrency.format(_totalToAmount)})',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final isUpdate = _editingTransactionId != null;
      final transaction = FinanceTransaction(
        id: _editingTransactionId,
        date: _selectedDate,
        referenceId: effectiveRefId,
        narration: _narrationController.text.trim().isNotEmpty
          ? _narrationController.text.trim()
          : 'Self Transfer',
        flow: 'Transfer',
        invoice: '',
        purpose: 'Self Transfer',
        spentFor: 'Self',
        breakdowns: _breakdowns.map((b) => b.copy()).toList(),
        toBreakdowns: _toBreakdowns.map((b) => b.copy()).toList(),
        isSelfTransfer: true,
        totalAmount: _totalFromAmount,
      );

      await _storage.saveTransaction(transaction);

      if (_executingRecurringId != null) {
        final recurrences = await _storage.getRecurringTransactions();
        final idx = recurrences.indexWhere((item) => item.id == _executingRecurringId);
        if (idx != -1) {
          final existing = recurrences[idx];
          final forwardedDate = existing.computeNextDate(existing.nextDueDate);
          final updatedRecurrence = existing.copyWith(nextDueDate: forwardedDate);
          await _storage.saveRecurringTransaction(updatedRecurrence);
        }
        _executingRecurringId = null;
        await _loadRecurringTransactions();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isUpdate ? 'Updated Transfer [$effectiveRefId]' : 'Saved Transfer [$effectiveRefId]'),
            backgroundColor: const Color(0xFF6366F1),
            behavior: SnackBarBehavior.floating,
          ),
        );

        _resetEntireForm();
        _refreshFloatingStats();
        widget.onTransactionSaved?.call();
      }
      return;
    }

    // ==========================================
    // Regular / Split Transaction Saving
    // ==========================================
    if (_flow == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Flow (Withdraw or Deposit)'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_selectedPurpose == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Purpose'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_selectedSpentFor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Spent For'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    for (int i = 0; i < _breakdowns.length; i++) {
      final b = _breakdowns[i];
      if (b.paymentType == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please select Payment Type for mode #${i + 1}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (b.paymentType != 'Cash' && (b.account == null || b.account!.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please select Account for mode #${i + 1} (${b.paymentType})'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    if (!_formKey.currentState!.validate()) return;

    if (_totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Overall total amount must be positive (currently ₹${IndianCurrency.format(_totalAmount)})'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Split Mode: strictly validate that total of all recipient shares matches total amount
    if (_selectedSpentFor == 'Split') {
      if (!_validateSplitAmounts()) return;
    }

    for (final b in _breakdowns) {
      if (b.paymentType == 'Cash') {
        b.recalculateCashAmount();
      }
    }

    final effectivePurpose = (_selectedPurpose == 'Other' && _customPurposeController.text.trim().isNotEmpty)
        ? _customPurposeController.text.trim()
        : (_selectedPurpose ?? 'Others');

    final effectiveSpentFor = (_selectedSpentFor == 'Other' && _customSpentForController.text.trim().isNotEmpty)
        ? _customSpentForController.text.trim()
        : (_selectedSpentFor ?? 'Self');

    final isSplitActive = !_isSelfTransferMode && (_isSplitModeEnabled || _selectedSpentFor == 'Split');
    List<SplitRecipient>? recipientsToSave;
    if (isSplitActive) {
      if (_selectedSpentFor == 'Split') {
        if (_splitRecipients.isNotEmpty) {
          recipientsToSave = _splitRecipients
              .where((s) => !((s.isPersonal || s.name.trim().toLowerCase() == 'personal share') && s.amount <= 0))
              .map((s) => s.copy())
              .toList();
        }
      } else {
        // When split mode is enabled and spent for is not 'Split',
        // assign 100% of total amount to the person in spent for and treat it as a split transaction
        recipientsToSave = [
          SplitRecipient(
            name: effectiveSpentFor,
            isPersonal: false,
            amount: _totalAmount,
            percentage: 100.0,
          ),
        ];
      }
    }

    final isUpdate = _editingTransactionId != null;
    final transaction = FinanceTransaction(
      id: _editingTransactionId,
      date: _selectedDate,
      referenceId: effectiveRefId,
      narration: _narrationController.text.trim().isNotEmpty
          ? _narrationController.text.trim()
          : effectivePurpose,
      flow: _flow!,
      invoice: _invoiceController.text.trim(), // Invoice is optional!
      purpose: effectivePurpose,
      spentFor: effectiveSpentFor,
      breakdowns: _breakdowns.map((b) => b.copy()).toList(),
      totalAmount: _totalAmount,
      splitRecipients: recipientsToSave,
      isSplitMode: isSplitActive,
    );

    await _storage.saveTransaction(transaction);

    if (_executingRecurringId != null) {
      final recurrences = await _storage.getRecurringTransactions();
      final idx = recurrences.indexWhere((item) => item.id == _executingRecurringId);
      if (idx != -1) {
        final existing = recurrences[idx];
        final forwardedDate = existing.computeNextDate(existing.nextDueDate);
        final updatedRecurrence = existing.copyWith(nextDueDate: forwardedDate);
        await _storage.saveRecurringTransaction(updatedRecurrence);
      }
      _executingRecurringId = null;
      await _loadRecurringTransactions();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isUpdate ? 'Updated [$effectiveRefId]' : 'Saved [$effectiveRefId]'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Advance draft or multi-edit transaction, otherwise reset form
      if (_multiEditTransactions.isNotEmpty) {
        _multiEditTransactions.removeAt(_currentMultiEditIndex);
        if (_multiEditTransactions.isNotEmpty) {
          if (_currentMultiEditIndex >= _multiEditTransactions.length) {
            _currentMultiEditIndex = _multiEditTransactions.length - 1;
          }
          _loadTransactionForEditing(_multiEditTransactions[_currentMultiEditIndex], showSnackbar: false);
        } else {
          _resetEntireForm();
        }
      } else if (_draftTransactions.isNotEmpty) {
        _draftTransactions.removeAt(_currentDraftIndex);
        if (_draftTransactions.isNotEmpty) {
          if (_currentDraftIndex >= _draftTransactions.length) {
            _currentDraftIndex = _draftTransactions.length - 1;
          }
          _applyDraft(_draftTransactions[_currentDraftIndex]);
        } else {
          _resetEntireForm();
        }
      } else {
        _resetEntireForm();
      }
      _refreshFloatingStats();
      widget.onTransactionSaved?.call();
    }
  }

  void _showQuickTemplatesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF151932)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text('✨', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Text(
                            'Saved Templates',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_allTemplates.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No templates saved yet.\nTap "⭐ Save as Template" below to create one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _allTemplates.length,
                        separatorBuilder: (_, index) => Divider(
                          color: isDark ? const Color(0xFF262C54) : const Color(0xFFF1E5DC),
                        ),
                        itemBuilder: (_, idx) {
                          final t = _allTemplates[idx];
                          return Dismissible(
                            key: ValueKey('quick_template_${t.id}'),
                            direction: DismissDirection.horizontal,
                            background: Container(
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              padding: const EdgeInsets.only(left: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F766E),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.centerLeft,
                              child: const Row(
                                children: [
                                  Icon(Icons.edit_note_rounded, color: Colors.white, size: 22),
                                  SizedBox(width: 6),
                                  Text(
                                    'Load & Edit',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            secondaryBackground: Container(
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              padding: const EdgeInsets.only(right: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.centerRight,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 22),
                                ],
                              ),
                            ),
                            confirmDismiss: (direction) async {
                              if (direction == DismissDirection.startToEnd) {
                                Navigator.of(ctx).pop();
                                _applyTemplate(t, isForEdit: true);
                                return false;
                              }
                              return true;
                            },
                            onDismissed: (direction) async {
                              if (direction == DismissDirection.endToStart) {
                                await _storage.deleteTemplate(t.id);
                                setState(() {
                                  _allTemplates.removeWhere((item) => item.id == t.id);
                                });
                                setSheetState(() {});
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Deleted template: "${t.name}"'),
                                      backgroundColor: const Color(0xFFEF4444),
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                }
                              }
                            },
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFA78BFA).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Text('⭐', style: TextStyle(fontSize: 16)),
                              ),
                              title: Text(
                                t.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                                ),
                              ),
                              subtitle: Text(
                                '${t.flow} • ${t.purpose} • ${t.spentFor} • ₹${IndianCurrency.formatSmart(t.totalAmount)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                ),
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _applyTemplate(t, isForEdit: false);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCustomRecurrenceDialog() async {
    final monthsCtrl = TextEditingController(
      text: (_customMonths != null && _customMonths! > 0) ? _customMonths.toString() : '',
    );
    final daysCtrl = TextEditingController(
      text: (_customDays != null && _customDays! > 0) ? _customDays.toString() : '',
    );
    String? errorText;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1B2042) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Text('⏳', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Text(
                    'Custom Recurrence',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter custom days and/or months. Both are optional, but at least one must be entered.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: monthsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Months (Optional)',
                      hintText: 'e.g. 1',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: daysCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Days (Optional)',
                      hintText: 'e.g. 15',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (_customMonths == null && _customDays == null) {
                      setState(() => _recurrenceFrequency = 'Month');
                    }
                    Navigator.of(ctx).pop();
                  },
                  child: Text('Cancel', style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    final m = int.tryParse(monthsCtrl.text.trim()) ?? 0;
                    final d = int.tryParse(daysCtrl.text.trim()) ?? 0;
                    if (m <= 0 && d <= 0) {
                      setDialogState(() {
                        errorText = 'Please enter at least 1 month or 1 day.';
                      });
                      return;
                    }
                    setState(() {
                      _customMonths = m > 0 ? m : null;
                      _customDays = d > 0 ? d : null;
                      _recurrenceFrequency = 'Custom';
                    });
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showNotificationsPopup() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF151932) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final isDarkInner = Theme.of(ctx).brightness == Brightness.dark;
            final currentDue = _recurringTransactions
                .where((r) => !r.isPaused && !r.nextDueDate.isAfter(endOfToday))
                .toList();
            final dueBills = _liveBalancesSummary?.dueBills ?? [];
            final totalCount = currentDue.length + dueBills.length;

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.82,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Text('🔔', style: TextStyle(fontSize: 20)),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  dueBills.isNotEmpty && currentDue.isNotEmpty
                                      ? 'Due Notifications'
                                      : (dueBills.isNotEmpty ? 'Credit Card Bills' : 'Recurring Transactions'),
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: isDarkInner ? Colors.white : const Color(0xFF1E293B),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (totalCount > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$totalCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (totalCount == 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Center(
                          child: Column(
                            children: [
                              const Text('🎉', style: TextStyle(fontSize: 32)),
                              const SizedBox(height: 8),
                              Text(
                                'All caught up!\nNo pending credit card bills or recurring transactions.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDarkInner ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ==========================================
                              // 1. CREDIT CARD BILLS DUE SECTION
                              // ==========================================
                              if (dueBills.isNotEmpty) ...[
                                Row(
                                  children: [
                                    const Text('💳', style: TextStyle(fontSize: 16)),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Credit Card Bills Due (${dueBills.length})',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: isDarkInner ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...dueBills.map((bill) {
                                  final isOverdue = bill.isOverdue;
                                  final isDueToday = bill.isDueToday;

                                  final statusBgColor = isOverdue
                                      ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                                      : (isDueToday
                                          ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                          : const Color(0xFF3B82F6).withValues(alpha: 0.12));

                                  final statusTextColor = isOverdue
                                      ? const Color(0xFFEF4444)
                                      : (isDueToday ? const Color(0xFFF59E0B) : const Color(0xFF3B82F6));

                                  final statusLabel = isOverdue
                                      ? 'Overdue'
                                      : (isDueToday ? 'Due Today' : 'Due in ${bill.daysUntilDue}d');

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: isDarkInner ? const Color(0xFF1E2342) : Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isOverdue
                                            ? const Color(0xFFEF4444).withValues(alpha: 0.6)
                                            : (isDarkInner ? const Color(0xFF2E365E) : const Color(0xFFE2E8F0)),
                                        width: isOverdue ? 1.5 : 1.0,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: isDarkInner ? 0.3 : 0.05),
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
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      bill.cardName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.bold,
                                                        color: isDarkInner ? Colors.white : const Color(0xFF1E293B),
                                                      ),
                                                    ),
                                                  ),
                                                  if (bill.sharedGroupName != null && bill.sharedGroupName!.isNotEmpty) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: isDarkInner ? const Color(0xFF312E81) : const Color(0xFFEEF2FF),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        bill.sharedGroupName!,
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: Color(0xFF6366F1),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: statusBgColor,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                statusLabel,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: statusTextColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: isDarkInner ? const Color(0xFF151932) : const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Billed Amount',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: isDarkInner ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '₹${IndianCurrency.format(bill.billedAmount)}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: isDarkInner ? Colors.white70 : const Color(0xFF334155),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (bill.paidAmount > 0)
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Paid So Far',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: isDarkInner ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '₹${IndianCurrency.format(bill.paidAmount)}',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                        color: Color(0xFF10B981),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  const Text(
                                                    'Remaining Due',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFFEF4444),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '₹${IndianCurrency.format(bill.remainingDue)}',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFFEF4444),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Text(
                                              'Due Date: ${FinanceTransaction.formatDate(bill.dueDate)}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDarkInner ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                visualDensity: VisualDensity.compact,
                                                side: BorderSide(
                                                  color: isDarkInner ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                                                ),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              icon: const Icon(Icons.check_circle_outline_rounded, size: 15, color: Color(0xFF10B981)),
                                              label: Text(
                                                'Mark Paid',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDarkInner ? Colors.white70 : const Color(0xFF334155),
                                                ),
                                              ),
                                              onPressed: () async {
                                                await _storage.markCreditCardBillPaid(bill.cardName, bill.cycleKey);
                                                await _loadBalancesSummary();
                                                setSheetState(() {});
                                                if (mounted) {
                                                  setState(() {});
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text('✅ Marked ${bill.cardName} bill as paid'),
                                                      backgroundColor: const Color(0xFF10B981),
                                                      behavior: SnackBarBehavior.floating,
                                                      duration: const Duration(seconds: 2),
                                                    ),
                                                  );
                                                }
                                                if ((_liveBalancesSummary?.totalDueBillsCount ?? 0) + currentDue.length == 0) {
                                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                                }
                                              },
                                            ),
                                            const SizedBox(width: 8),
                                            ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF0F766E),
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                visualDensity: VisualDensity.compact,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              icon: const Icon(Icons.flash_on_rounded, size: 15, color: Colors.amber),
                                              label: const Text(
                                                'Pay Bill',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                              ),
                                              onPressed: () {
                                                Navigator.of(ctx).pop();
                                                setState(() {
                                                  _isSelfTransferMode = true;
                                                  _isSplitModeEnabled = false;
                                                  _flow = 'Transfer';
                                                  _selectedPurpose = 'Self Transfer';
                                                  _narrationController.text = 'Cleared card bill';
                                                  _userEditedToAmount = true;

                                                  if (_breakdowns.isEmpty) {
                                                    _breakdowns.add(PaymentBreakdown(amount: bill.remainingDue));
                                                  } else {
                                                    _breakdowns[0].amount = bill.remainingDue;
                                                  }

                                                  _toBreakdowns.clear();
                                                  _toBreakdowns.add(
                                                    PaymentBreakdown(
                                                      paymentType: 'Credit',
                                                      account: bill.cardName,
                                                      amount: bill.remainingDue,
                                                    ),
                                                  );
                                                });
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('⚡ Pre-filled Self Transfer to pay bill for ${bill.cardName}'),
                                                    backgroundColor: const Color(0xFF0F766E),
                                                    behavior: SnackBarBehavior.floating,
                                                    duration: const Duration(seconds: 2),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],

                              // ==========================================
                              // 2. RECURRING TRANSACTIONS SECTION
                              // ==========================================
                              if (currentDue.isNotEmpty) ...[
                                if (dueBills.isNotEmpty) const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Text('⏰', style: TextStyle(fontSize: 16)),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Recurring Transactions (${currentDue.length})',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: isDarkInner ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ListView.separated(
                                  physics: const NeverScrollableScrollPhysics(),
                                  shrinkWrap: true,
                                  itemCount: currentDue.length,
                                  separatorBuilder: (_, index) => Divider(
                                    color: isDarkInner ? const Color(0xFF262C54) : const Color(0xFFF1E5DC),
                                  ),
                                  itemBuilder: (itemCtx, idx) {
                          final r = currentDue[idx];
                          final isDue = !r.nextDueDate.isAfter(endOfToday);

                          return Dismissible(
                            key: ValueKey('recurring_${r.id}'),
                            direction: DismissDirection.horizontal,
                            background: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.only(left: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F766E),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.centerLeft,
                              child: const Row(
                                children: [
                                  Icon(Icons.edit_note_rounded, color: Colors.white, size: 22),
                                  SizedBox(width: 6),
                                  Text(
                                    'Edit Recurrence',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            secondaryBackground: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.only(right: 16),
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
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 22),
                                ],
                              ),
                            ),
                            confirmDismiss: (direction) async {
                              if (direction == DismissDirection.startToEnd) {
                                Navigator.of(ctx).pop();
                                _loadRecurringIntoForm(r, isEdit: true);
                                return false;
                              }
                              return true;
                            },
                            onDismissed: (direction) async {
                              if (direction == DismissDirection.endToStart) {
                                await _storage.deleteRecurringTransaction(r.id);
                                setState(() {
                                  _recurringTransactions.removeWhere((item) => item.id == r.id);
                                });
                                setSheetState(() {});
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Deleted recurrence: "${r.narration}"'),
                                      backgroundColor: const Color(0xFFEF4444),
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                }
                              }
                            },
                            child: InkWell(
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _loadRecurringIntoForm(r, isEdit: false);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isDarkInner
                                      ? (isDue ? const Color(0xFF262C54) : const Color(0xFF1E2442))
                                      : (isDue ? const Color(0xFFFEF3C7).withValues(alpha: 0.5) : Colors.white),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDue
                                        ? (isDarkInner ? const Color(0xFFF59E0B) : const Color(0xFFFCD34D))
                                        : (isDarkInner ? const Color(0xFF2C3360) : const Color(0xFFE2E8F0)),
                                    width: isDue ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: isDue
                                        ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                        : const Color(0xFF64748B).withValues(alpha: 0.15),
                                      child: Text(
                                        isDue ? '⏰' : '⏳',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Narration & Date ONLY
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            r.narration.isNotEmpty ? r.narration : 'Recurring Payment',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: isDarkInner ? Colors.white : const Color(0xFF1E293B),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              Text(
                                                FinanceTransaction.formatDate(r.nextDueDate),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDue
                                                      ? (isDarkInner ? const Color(0xFFFCD34D) : const Color(0xFFB45309))
                                                      : (isDarkInner ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                                ),
                                              ),
                                              if (isDue) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFEF4444),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text(
                                                    'DUE',
                                                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Amount ONLY
                                    Text(
                                      '₹${IndianCurrency.formatSmart(r.totalAmount)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: isDarkInner ? const Color(0xFF34D399) : const Color(0xFF059669),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGoogleFallbackAvatar(GoogleUserProfile user) {
    final initial = (user.displayName != null && user.displayName!.isNotEmpty)
        ? user.displayName![0].toUpperCase()
        : 'G';
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
          color: Color(0xFF4285F4),
        ),
      ),
    );
  }

  void _showGoogleAccountSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1B2042) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return Container(
              margin: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
                left: 12,
                right: 12,
                top: 40,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: ValueListenableBuilder<GoogleUserProfile?>(
                  valueListenable: GoogleAuthService.instance.currentUserNotifier,
                  builder: (context, user, _) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white24 : Colors.black12,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFF4285F4).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Text('📊', style: TextStyle(fontSize: 18)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Google Account & Sheets',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.of(sheetCtx).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        if (user != null) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF242A56) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF10B981).withValues(alpha: 0.4),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: const Color(0xFF4285F4).withValues(alpha: 0.2),
                                  backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
                                  child: user.photoUrl == null
                                      ? Text(
                                          (user.displayName != null && user.displayName!.isNotEmpty)
                                              ? user.displayName![0].toUpperCase()
                                              : 'G',
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF4285F4),
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user.displayName ?? 'Google User',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        user.email,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF10B981)),
                                            SizedBox(width: 4),
                                            Text(
                                              'Connected to Google Sheets',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF10B981),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          ValueListenableBuilder<bool>(
                            valueListenable: GoogleSheetsService.instance.isSyncingNotifier,
                            builder: (_, isSyncing, _) {
                              return SizedBox(
                                width: double.infinity,
                                height: 46,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4285F4),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    elevation: 0,
                                  ),
                                  onPressed: isSyncing
                                      ? null
                                      : () async {
                                          final messenger = ScaffoldMessenger.of(sheetCtx);
                                          final txs = await _storage.getTransactions(forceRefresh: true);
                                          if (mounted) {
                                            _refreshFloatingStats();
                                          }
                                          if (!sheetCtx.mounted) return;
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text('✅ Loaded ${txs.length} transactions live from Google Sheets!'),
                                              backgroundColor: const Color(0xFF10B981),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        },
                                  icon: isSyncing
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.refresh_rounded, size: 20),
                                  label: Text(
                                    isSyncing ? 'Refreshing...' : 'Refresh Live from Google Sheets',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF10B981),
                                    side: const BorderSide(color: Color(0xFF10B981)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  onPressed: () async {
                                    final messenger = ScaffoldMessenger.of(sheetCtx);
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text('Backing up Masters, Templates, Balances & Recurring...'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                    final ok = await GoogleSheetsService.instance.backupAllConfigAndMasters();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(ok ? '✅ Backup completed successfully to Google Drive!' : '❌ Backup failed. Check connection.'),
                                        backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                                  label: const Text('Backup to Drive', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF6366F1),
                                    side: const BorderSide(color: Color(0xFF6366F1)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  onPressed: () async {
                                    final messenger = ScaffoldMessenger.of(sheetCtx);
                                    final token = await GoogleAuthService.instance.getAccessToken();
                                    final sheetId = await GoogleSheetsService.instance.getSpreadsheetId();
                                    if (token != null && sheetId != null) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text('Restoring Masters, Templates & Balances from Google Drive...'),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      await GoogleSheetsService.instance.restoreAllFromSheet(token, sheetId);
                                      await _loadMasters();
                                      await _loadRecurringTransactions();
                                      await _loadBalancesSummary();
                                      _refreshFloatingStats();
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text('✅ Restored all configurations from Google Drive!'),
                                          backgroundColor: Color(0xFF10B981),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.cloud_download_rounded, size: 18),
                                  label: const Text('Restore Data', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(color: Colors.redAccent, width: 1.2),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: () async {
                                await GoogleAuthService.instance.signOut();
                                setSheetState(() {});
                              },
                              icon: const Icon(Icons.logout_rounded, size: 18),
                              label: const Text('Disconnect Google Account', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF242A56) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDark ? const Color(0xFF2C3360) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'Sign in with your Google account to automatically store transaction logs to Google Sheets.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 13, height: 1.4),
                                ),
                                const SizedBox(height: 16),
                                ValueListenableBuilder<bool>(
                                  valueListenable: GoogleAuthService.instance.isLoadingNotifier,
                                  builder: (_, isLoading, _) {
                                    return SizedBox(
                                      width: double.infinity,
                                      height: 48,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: const Color(0xFF1E293B),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                                          ),
                                          elevation: 1,
                                        ),
                                        onPressed: isLoading
                                            ? null
                                            : () async {
                                                final messenger = ScaffoldMessenger.of(sheetCtx);
                                                final res = await GoogleAuthService.instance.signIn();
                                                setSheetState(() {});
                                                if (!sheetCtx.mounted) return;
                                                if (res != null) {
                                                  messenger.showSnackBar(
                                                    SnackBar(
                                                      content: Text('✅ Connected as ${res.displayName ?? res.email}! Checking Google Sheet...'),
                                                      backgroundColor: const Color(0xFF10B981),
                                                      behavior: SnackBarBehavior.floating,
                                                    ),
                                                  );
                                                  final token = await GoogleAuthService.instance.getAccessToken();
                                                  if (token != null) {
                                                    await GoogleSheetsService.instance.findOrCreateLedger(token);
                                                    await StorageService.instance.getTransactions(forceRefresh: true);
                                                    if (sheetCtx.mounted) setSheetState(() {});
                                                  }
                                                } else {
                                                  final err = GoogleAuthService.instance.errorMessageNotifier.value;
                                                  if (err != null && err.isNotEmpty) {
                                                    messenger.showSnackBar(
                                                      SnackBar(
                                                        content: Text(err),
                                                        backgroundColor: const Color(0xFFEF4444),
                                                        behavior: SnackBarBehavior.floating,
                                                      ),
                                                    );
                                                  }
                                                }
                                              },
                                        child: isLoading
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    'G',
                                                    style: TextStyle(
                                                      fontSize: 22,
                                                      fontWeight: FontWeight.w900,
                                                      color: Color(0xFF4285F4),
                                                    ),
                                                  ),
                                                  SizedBox(width: 12),
                                                  Text(
                                                    'Sign in with Google',
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFF1E293B),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    );
                                  },
                                ),
                                ValueListenableBuilder<String?>(
                                  valueListenable: GoogleAuthService.instance.errorMessageNotifier,
                                  builder: (_, err, _) {
                                    if (err == null || err.isEmpty) return const SizedBox.shrink();
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.error_outline, size: 16, color: Color(0xFFEF4444)),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                err,
                                                style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showTopMenu() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1B2042) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2C3360) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);

    final row1 = [
      {'emoji': '📊', 'label': 'Dashboard'},
      {'emoji': '💰', 'label': 'Balances'},
    ];
    final row2 = [
      {'emoji': '🤝', 'label': 'Borrowers'},
      {'emoji': '🔑', 'label': 'API Keys'},
    ];
    final row3 = [
      {'emoji': '⌛', 'label': 'Recurring'},
      {'emoji': '📋', 'label': 'Templates'},
    ];
    final row4 = [
      {'emoji': '📜', 'label': 'History'},
      {'emoji': '🧾', 'label': 'Invoices'},
    ];
    final row5 = [
      {'emoji': '💳', 'label': 'EMIs'},
      {'emoji': '⚙️', 'label': 'Masters'},
    ];

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'TopMenu',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, anim1, anim2) {
        Widget buildMenuItem(Map<String, String> item, {bool fullWidth = false}) {
          return InkWell(
            onTap: () {
              Navigator.of(ctx).pop();
              _handleMenuItemClick(item['label']!);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF222852) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0xFF2E376E) : const Color(0xFFE2E8F0),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisAlignment: fullWidth ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  Text(item['emoji']!, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      item['label']!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 55,
                right: 14,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 236,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(child: buildMenuItem(row1[0])),
                            const SizedBox(width: 6),
                            Expanded(child: buildMenuItem(row1[1])),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: buildMenuItem(row2[0])),
                            const SizedBox(width: 6),
                            Expanded(child: buildMenuItem(row2[1])),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: buildMenuItem(row3[0])),
                            const SizedBox(width: 6),
                            Expanded(child: buildMenuItem(row3[1])),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: buildMenuItem(row4[0])),
                            const SizedBox(width: 6),
                            Expanded(child: buildMenuItem(row4[1])),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: buildMenuItem(row5[0])),
                            const SizedBox(width: 6),
                            Expanded(child: buildMenuItem(row5[1])),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            alignment: Alignment.topRight,
            child: child,
          ),
        );
      },
    );
  }

  void _handleMenuItemClick(String label) {
    switch (label) {
      case 'Dashboard':
      case 'Financial Health':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FinancialHealthDashboardScreen()),
        );
        break;
      case 'History':
        _navigateToHistory();
        break;
      case 'Invoices':
      case 'Invoice Manager':
        _navigateToInvoiceManager();
        break;
      case 'Masters':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ManageDetailsScreen(
              onSelectTemplate: (t) => _applyTemplate(t, isForEdit: false),
              onEditTemplate: (t) => _applyTemplate(t, isForEdit: true),
              onSelectRecurring: (r) => _loadRecurringIntoForm(r, isEdit: false),
              onEditRecurring: (r) => _loadRecurringIntoForm(r, isEdit: true),
            ),
          ),
        );
        break;
      case 'Templates':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ManageDetailsScreen(
              initialCategory: 'Templates',
              onSelectTemplate: (t) => _applyTemplate(t, isForEdit: false),
              onEditTemplate: (t) => _applyTemplate(t, isForEdit: true),
              onSelectRecurring: (r) => _loadRecurringIntoForm(r, isEdit: false),
              onEditRecurring: (r) => _loadRecurringIntoForm(r, isEdit: true),
            ),
          ),
        );
        break;
      case 'Recurring':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ManageDetailsScreen(
              initialCategory: 'Recurring',
              onSelectTemplate: (t) => _applyTemplate(t, isForEdit: false),
              onEditTemplate: (t) => _applyTemplate(t, isForEdit: true),
              onSelectRecurring: (r) => _loadRecurringIntoForm(r, isEdit: false),
              onEditRecurring: (r) => _loadRecurringIntoForm(r, isEdit: true),
            ),
          ),
        );
        break;
      case 'Borrowers':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BorrowersLedgerScreen()),
        );
        break;
      case 'Balances':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AccountBalancesScreen()),
        );
        break;
      case 'EMIs':
      case 'Credit Card EMIs':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EmiManagerScreen()),
        );
        break;
      case 'Google Sheets':
        _showGoogleAccountSheet();
        break;
      case 'API Keys':
        _showApiKeysDialog();
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label: Coming soon in future update!'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            duration: const Duration(seconds: 1),
          ),
        );
    }
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (val) {
          if (mounted) setState(() => _isListening = false);
        },
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            if (mounted) {
              setState(() => _isListening = false);
            }
          }
        },
      );
    } catch (e) {
      debugPrint('Speech init error: $e');
    }
  }

  Future<void> _toggleVoiceInput() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    try {
      if (!_speechAvailable) {
        _speechAvailable = await _speech.initialize();
      }

      if (_speechAvailable) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (result) {
            if (mounted) {
              setState(() {
                _narrationController.text = result.recognizedWords;
                _narrationController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _narrationController.text.length),
                );
              });
              if (result.finalResult) {
                setState(() => _isListening = false);
              }
            }
          },
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎙️ Listening... Speak your transaction'),
              backgroundColor: Color(0xFF6366F1),
              duration: Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Speech recognition unavailable or microphone permission denied.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Microphone error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _processAiAutoFill(
    String input, {
    bool updateNarration = true,
    bool isSilent = false,
  }) async {
    _aiAutoFillDebounce?.cancel();
    final clean = input.trim();
    if (clean.isEmpty) return;
    if (!isSilent) {
      setState(() => _isAiProcessing = true);
    }

    try {
      final parsed = await AiTransactionService.instance.parse(
        text: clean,
        availablePurposes: _purposes,
        availableSpentFors: _spentFors,
        categoryAccounts: _categoryAccounts,
      );

      if (!mounted) return;

      if (parsed.action == 'reset_form') {
        setState(() {
          _resetEntireForm();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🧹 Form Cleared'),
              backgroundColor: Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (parsed.action == 'load_template') {
        if (parsed.templateName != null && parsed.templateName!.isNotEmpty) {
          final q = parsed.templateName!.toLowerCase();
          final matchIdx = _allTemplates.indexWhere((t) => t.name.toLowerCase().contains(q));
          if (matchIdx != -1) {
            _applyTemplate(_allTemplates[matchIdx]);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✨ \'${_allTemplates[matchIdx].name}\' Loaded'),
                  backgroundColor: const Color(0xFF10B981),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            return;
          }
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ManageDetailsScreen(
              initialCategory: 'Templates',
              onSelectTemplate: (t) => _applyTemplate(t, isForEdit: false),
              onEditTemplate: (t) => _applyTemplate(t, isForEdit: true),
              onSelectRecurring: (r) => _loadRecurringIntoForm(r, isEdit: false),
              onEditRecurring: (r) => _loadRecurringIntoForm(r, isEdit: true),
            ),
          ),
        );
        return;
      }

      if (parsed.action == 'set_mode') {
        final target = (parsed.modeTarget ?? '').toLowerCase();
        setState(() {
          if (target.contains('recurring')) {
            _isRecurrenceMode = true;
          } else if (target.contains('split')) {
            _isSplitModeEnabled = true;
            _selectedSpentFor = 'Split';
          } else if (target.contains('self')) {
            _isSelfTransferMode = true;
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚙️ Mode Switched'),
              backgroundColor: Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      setState(() {
        if (parsed.isSelfTransfer) {
          _isSelfTransferMode = true;
          _isSplitModeEnabled = false;
          _flow = 'Transfer';
          _selectedPurpose = 'Self Transfer';
          _selectedSpentFor = null;

          if (updateNarration && parsed.narration.isNotEmpty) {
            _narrationController.value = TextEditingValue(
              text: parsed.narration,
              selection: TextSelection.collapsed(offset: parsed.narration.length),
            );
          }

          // FROM
          final fromPaymentType = parsed.fromPaymentType ?? 'UPI';
          final fromAmount = parsed.fromAmount ?? parsed.amount;

          if (_breakdowns.isNotEmpty) {
            final b = _breakdowns.first;
            b.paymentType = fromPaymentType;
            b.amount = fromAmount;
            _applyAccountToBreakdown(b, parsed.fromAccount, fromPaymentType);
            if (fromPaymentType == 'Cash') {
              b.denominations = parsed.denominations != null ? Map.from(parsed.denominations!) : {};
              b.recalculateCashAmount();
            } else {
              b.denominations = {};
            }
            if (_breakdowns.length > 1) {
              _breakdowns.removeRange(1, _breakdowns.length);
            }
          } else {
            final fromBd = PaymentBreakdown(
              paymentType: fromPaymentType,
              amount: fromAmount,
            );
            _applyAccountToBreakdown(fromBd, parsed.fromAccount, fromPaymentType);
            if (fromPaymentType == 'Cash') {
              fromBd.denominations = parsed.denominations != null ? Map.from(parsed.denominations!) : {};
              fromBd.recalculateCashAmount();
            }
            _breakdowns.add(fromBd);
          }

          // TO
          final toPaymentType = parsed.toPaymentType ?? 'Credit';
          final toAmount = parsed.toAmount ?? parsed.amount;

          if (_toBreakdowns.isNotEmpty) {
            final b = _toBreakdowns.first;
            b.paymentType = toPaymentType;
            b.amount = toAmount;
            _applyAccountToBreakdown(b, parsed.toAccount, toPaymentType);
            if (toPaymentType == 'Cash') {
              b.denominations = parsed.denominations != null ? Map.from(parsed.denominations!) : {};
              b.recalculateCashAmount();
            } else {
              b.denominations = {};
            }
            if (_toBreakdowns.length > 1) {
              _toBreakdowns.removeRange(1, _toBreakdowns.length);
            }
          } else {
            final toBd = PaymentBreakdown(
              paymentType: toPaymentType,
              amount: toAmount,
            );
            _applyAccountToBreakdown(toBd, parsed.toAccount, toPaymentType);
            if (toPaymentType == 'Cash') {
              toBd.denominations = parsed.denominations != null ? Map.from(parsed.denominations!) : {};
              toBd.recalculateCashAmount();
            }
            _toBreakdowns.add(toBd);
          }

        } else {
          // Regular or Split transaction
          _isSelfTransferMode = false;
          _flow = parsed.flow;

          // Narration
          if (updateNarration && parsed.narration.isNotEmpty) {
            _narrationController.value = TextEditingValue(
              text: parsed.narration,
              selection: TextSelection.collapsed(offset: parsed.narration.length),
            );
          }

          // Purpose
          _applyPurpose(parsed.purpose);

          // Spent For & Split Handling
          if (parsed.isLoanOrSplit || parsed.isSplitEqually) {
            _isSplitModeEnabled = true;
            _selectedSpentFor = 'Split';
            if (parsed.isSplitEqually) {
              final includeSelf = parsed.includesSelfInSplit;
              final totalPeople = parsed.splitRecipientNames.length + (includeSelf ? 1 : 0);
              final splitAmount = totalPeople > 0 ? (parsed.amount / totalPeople) : parsed.amount;
              final splitPct = totalPeople > 0 ? (100.0 / totalPeople) : 0.0;
              _splitRecipients.clear();
              if (includeSelf) {
                _splitRecipients.add(
                  SplitRecipient(
                    name: 'Personal Share',
                    isPersonal: true,
                    amount: splitAmount,
                    percentage: splitPct,
                  ),
                );
              }
              for (final name in parsed.splitRecipientNames) {
                _splitRecipients.add(
                  SplitRecipient(
                    name: name,
                    isPersonal: false,
                    amount: splitAmount,
                    percentage: splitPct,
                  ),
                );
              }
            } else {
              _splitRecipients.clear();
              final count = parsed.splitRecipientNames.isEmpty ? 1 : parsed.splitRecipientNames.length;
              for (final name in parsed.splitRecipientNames) {
                _splitRecipients.add(
                  SplitRecipient(
                    name: name,
                    isPersonal: false,
                    amount: parsed.amount / count,
                    percentage: 100.0 / count,
                  ),
                );
              }
            }
          } else {
            _applySpentFor(parsed.spentFor);
          }

          // Breakdowns
          _breakdowns.clear();
          final paymentType = parsed.paymentType ?? 'UPI';
          final amount = parsed.amount;

          final bd = PaymentBreakdown(
            paymentType: paymentType,
            amount: amount,
          );
          _applyAccountToBreakdown(bd, parsed.account, paymentType);
          if (paymentType == 'Cash') {
            bd.denominations = parsed.denominations != null ? Map.from(parsed.denominations!) : {};
            bd.recalculateCashAmount();
          } else {
            bd.denominations = {};
          }
          _breakdowns.add(bd);
        }
      });

      if (!isSilent) {
        final grokKey = await _storage.getGrokApiKey() ?? '';
        final geminiKey = await _storage.getGeminiApiKey() ?? '';
        final hasKeys = grokKey.trim().isNotEmpty || geminiKey.trim().isNotEmpty;

        final sourceLabel = parsed.source == 'local_rules'
            ? (hasKeys ? 'Local Rules (Cloud AI fallback)' : 'Local Engine (No API keys set)')
            : parsed.source;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                parsed.isSelfTransfer
                    ? '✨ Auto-filled [$sourceLabel]: Self Transfer • From ${parsed.fromAccount ?? parsed.fromPaymentType} to ${parsed.toAccount ?? parsed.toPaymentType} (₹${IndianCurrency.formatSmart(parsed.amount)})'
                    : '✨ Auto-filled [$sourceLabel]: ₹${IndianCurrency.formatSmart(parsed.amount)} • ${parsed.flow} • ${parsed.purpose ?? ""} • ${parsed.account ?? ""}',
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('AI Auto-fill error: $e');
    } finally {
      if (mounted) {
        setState(() => _isAiProcessing = false);
      }
    }
  }

  Future<void> _showApiKeysDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1B2042) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final inputBg = isDark ? const Color(0xFF10132B) : const Color(0xFFF8FAFC);
    final inputBorder = isDark ? const Color(0xFF2C3360) : const Color(0xFFCBD5E1);

    final currentGrok = await _storage.getGrokApiKey() ?? '';
    final currentGemini = await _storage.getGeminiApiKey() ?? '';

    final grokController = TextEditingController(text: currentGrok);
    final geminiController = TextEditingController(text: currentGemini);
    bool obscureGrok = true;
    bool obscureGemini = true;
    bool isTesting = false;
    String? testResult;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              backgroundColor: cardBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Text('🔑', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Text(
                    'AI API Keys',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'When API keys are configured, Cloud AI is forced and used directly! Local engine acts only as fallback if offline.',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    const SizedBox(height: 16),

                    // Grok field
                    Row(
                      children: [
                        Text('⚡ Grok API Key', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('MAIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Model: qwen/qwen3.8-27b', style: TextStyle(fontSize: 11, color: textSecondary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: grokController,
                      obscureText: obscureGrok,
                      style: TextStyle(fontSize: 13, color: textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Enter Grok / OpenRouter API Key',
                        hintStyle: TextStyle(fontSize: 12, color: textSecondary.withValues(alpha: 0.6)),
                        filled: true,
                        fillColor: inputBg,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: inputBorder),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(obscureGrok ? Icons.visibility_off : Icons.visibility, size: 18, color: textSecondary),
                          onPressed: () => setDlgState(() => obscureGrok = !obscureGrok),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Gemini field
                    Row(
                      children: [
                        Text('✨ Gemini API Key', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('FALLBACK', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Model: gemini-3.6-flash', style: TextStyle(fontSize: 11, color: textSecondary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: geminiController,
                      obscureText: obscureGemini,
                      style: TextStyle(fontSize: 13, color: textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Enter Gemini API Key',
                        hintStyle: TextStyle(fontSize: 12, color: textSecondary.withValues(alpha: 0.6)),
                        filled: true,
                        fillColor: inputBg,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: inputBorder),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(obscureGemini ? Icons.visibility_off : Icons.visibility, size: 18, color: textSecondary),
                          onPressed: () => setDlgState(() => obscureGemini = !obscureGemini),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Test Connection Button
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF6366F1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: isTesting
                          ? null
                          : () async {
                              setDlgState(() {
                                isTesting = true;
                                testResult = 'Testing API connections...';
                              });
                              final res = await AiTransactionService.instance.testConnection(
                                grokKey: grokController.text.trim(),
                                geminiKey: geminiController.text.trim(),
                              );
                              setDlgState(() {
                                isTesting = false;
                                if (res.isEmpty) {
                                  testResult = '⚠️ Enter at least one API key to test.';
                                } else {
                                  final lines = <String>[];
                                  res.forEach((k, v) {
                                    lines.add('${k.toUpperCase()}: $v');
                                  });
                                  testResult = lines.join('\n');
                                }
                              });
                            },
                      icon: isTesting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)),
                            )
                          : const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF6366F1)),
                      label: Text(
                        isTesting ? 'Testing...' : 'Test Connection',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6366F1), fontWeight: FontWeight.bold),
                      ),
                    ),

                    if (testResult != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF161A36) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: testResult!.contains('Connected')
                                ? const Color(0xFF10B981)
                                : const Color(0xFF6366F1),
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          testResult!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: testResult!.contains('Connected')
                                ? const Color(0xFF10B981)
                                : (testResult!.contains('Error') || testResult!.contains('failed')
                                    ? const Color(0xFFEF4444)
                                    : textPrimary),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF161A36) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF6366F1)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Grok runs as primary model (qwen/qwen3.8-27b). Gemini serves as automatic fallback.',
                              style: TextStyle(fontSize: 11, color: textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: TextStyle(color: textSecondary)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    await _storage.setGrokApiKey(grokController.text.trim());
                    await _storage.setGeminiApiKey(geminiController.text.trim());
                    if (context.mounted) {
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('API Keys saved! Cloud AI will be used for auto-fill.'),
                          backgroundColor: Color(0xFF10B981),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  child: const Text('Save Keys'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildModeCard({
    required String emoji,
    required bool isSelected,
    required bool isDark,
    Color? activeColor,
    Color? activeBg,
    required VoidCallback onTap,
  }) {
    final borderColor = isSelected
        ? (activeColor ?? const Color(0xFFF43F5E))
        : (isDark ? const Color(0xFF262C54) : const Color(0xFFF1E5DC));
    final bgColor = isSelected
        ? (activeBg ?? (isDark ? const Color(0xFF381A2D) : const Color(0xFFFFF1F2)))
        : (isDark ? const Color(0xFF1B2042) : Colors.white);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 1.6 : 1.2,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: (activeColor ?? const Color(0xFFF43F5E)).withValues(alpha: 0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              emoji,
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.extension<AppThemeColors>() ?? (isDark ? AppThemeColors.dark : AppThemeColors.light);

    final pageBg = colors.pageBg;
    final cardBg = colors.cardBg;
    final cardBorder = colors.cardBorder;
    final inputBg = colors.inputBg;
    final inputBorder = colors.inputBorder;
    final textPrimary = colors.textPrimary;
    final textSecondary = colors.textSecondary;
    final purpleAccent = colors.purpleAccent;
    const coralAccent = Color(0xFFFF5C38);
    const cyanAccent = Color(0xFF00D2B4);

    final isOtherPurpose = _selectedPurpose == 'Other';
    final isOtherSpentFor = _selectedSpentFor == 'Other';

    double splitSum = 0.0;
    for (final r in _splitRecipients) {
      splitSum += r.amount;
    }
    final double splitDiff = (_totalAmount - splitSum).abs();
    final double transferDiff = (_totalFromAmount - _totalToAmount).abs();

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: RefreshIndicator(
                  color: coralAccent,
                  backgroundColor: isDark ? const Color(0xFF1B2042) : Colors.white,
                  onRefresh: () async {
                    setState(() {
                      _resetEntireForm();
                      _draftTransactions.clear();
                      _currentDraftIndex = 0;
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Form cleared',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          backgroundColor: isDark ? const Color(0xFF2C3360) : const Color(0xFF64748B),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                    children: [
                    // Main Container Card matching reference image
                    Container(
                      clipBehavior: Clip.antiAlias,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: cardBorder, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? Colors.black.withValues(alpha: 0.4)
                                : const Color(0xFFE2D6CE).withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Top Bar: 🟢 🧾 | ✨ Smart Entry | 🔗 🌙/☀️
                            Row(
                              children: [
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: const BoxDecoration(
                                    color: cyanAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: _navigateToInvoiceManager,
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1B2042) : const Color(0xFFF0FDFA),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isDark ? const Color(0xFF2C3360) : const Color(0xFFCCFBF1),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: const Center(
                                      child: Text('🧾', style: TextStyle(fontSize: 16)),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '✨ ',
                                          style: TextStyle(
                                            fontSize: 18,
                                            color: isDark ? const Color(0xFFC084FC) : const Color(0xFFA855F7),
                                          ),
                                        ),
                                        Text(
                                          'Smart Entry',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? const Color(0xFFC084FC) : const Color(0xFFA855F7),
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                ThemeToggleRotatingButton(
                                  isDark: isDark,
                                  onToggle: () => StorageService.instance.toggleDarkMode(),
                                ),
                                const SizedBox(width: 8),
                                ValueListenableBuilder<GoogleUserProfile?>(
                                  valueListenable: GoogleAuthService.instance.currentUserNotifier,
                                  builder: (context, gUser, _) {
                                    return InkWell(
                                      onTap: _showGoogleAccountSheet,
                                      borderRadius: BorderRadius.circular(18),
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF1B2042) : const Color(0xFFF8FAFC),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: gUser != null
                                                ? const Color(0xFF10B981)
                                                : (isDark ? const Color(0xFF2C3360) : const Color(0xFFE2E8F0)),
                                            width: gUser != null ? 1.8 : 1.2,
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: gUser?.photoUrl != null
                                            ? Image.network(
                                                gUser!.photoUrl!,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) => _buildGoogleFallbackAvatar(gUser),
                                              )
                                            : (gUser != null
                                                ? _buildGoogleFallbackAvatar(gUser)
                                                : const Center(
                                                    child: Text(
                                                      'G',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 16,
                                                        color: Color(0xFF4285F4),
                                                      ),
                                                    ),
                                                  )),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: _showTopMenu,
                                  borderRadius: BorderRadius.circular(18),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1B2042) : const Color(0xFFF8FAFC),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isDark ? const Color(0xFF2C3360) : const Color(0xFFE2E8F0),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.more_vert_rounded,
                                      size: 20,
                                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // 2. 5-Mode Selector Card Row
                            Row(
                              children: [
                                _buildModeCard(
                                  emoji: '🏍️',
                                  isSelected: false,
                                  isDark: isDark,
                                  onTap: () {
                                    setState(() => _selectedPurpose = 'Fuel');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Purpose set to Fuel / Travel'),
                                        behavior: SnackBarBehavior.floating,
                                        duration: Duration(milliseconds: 900),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 6),
                                _buildModeCard(
                                  emoji: '☁️',
                                  isSelected: false,
                                  isDark: isDark,
                                  onTap: () {
                                    setState(() => _selectedPurpose = 'Subscription');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Purpose set to Cloud / Online'),
                                        behavior: SnackBarBehavior.floating,
                                        duration: Duration(milliseconds: 900),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 6),
                                _buildModeCard(
                                  emoji: '⌛',
                                  isSelected: _isRecurrenceMode,
                                  isDark: isDark,
                                  activeColor: const Color(0xFFF59E0B),
                                  activeBg: isDark ? const Color(0xFF382914) : const Color(0xFFFEF3C7),
                                  onTap: () {
                                    setState(() {
                                      _isRecurrenceMode = !_isRecurrenceMode;
                                      if (_isRecurrenceMode) {
                                        _editingRecurringId = null;
                                      }
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(_isRecurrenceMode ? 'Recurrence mode enabled (⏳)' : 'Recurrence mode disabled'),
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(milliseconds: 900),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 6),
                                _buildModeCard(
                                  emoji: '💸',
                                  isSelected: _isSplitModeEnabled,
                                  isDark: isDark,
                                  activeColor: const Color(0xFFF43F5E),
                                  activeBg: isDark ? const Color(0xFF381A2D) : const Color(0xFFFFF1F2),
                                  onTap: () => _toggleDedicatedSplitMode(!_isSplitModeEnabled),
                                ),
                                const SizedBox(width: 6),
                                _buildModeCard(
                                  emoji: '🏦',
                                  isSelected: _isSelfTransferMode,
                                  isDark: isDark,
                                  activeColor: const Color(0xFFA78BFA),
                                  activeBg: isDark ? const Color(0xFF231C48) : const Color(0xFFF5F3FF),
                                  onTap: () => _toggleSelfTransferMode(!_isSelfTransferMode),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // 3. ✨ Auto-Fill Button
                            InkWell(
                              onTap: _handleAutoFill,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                height: 38,
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1F1B36) : const Color(0xFFFFF8F6),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF4C3A6E) : const Color(0xFFFFC5B8),
                                    width: 1.2,
                                  ),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '✨',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark ? const Color(0xFFA78BFA) : coralAccent,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Auto-Fill',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? const Color(0xFFA78BFA) : coralAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Template Editing Banner
                            if (_editingTemplateId != null) ...[
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF22C55E).withValues(alpha: 0.6),
                                    width: 1.2,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.edit_note_rounded, color: Color(0xFF16A34A), size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Editing Template: $_editingTemplateName',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Cancel template edit',
                                      onPressed: () {
                                        setState(() {
                                          _editingTemplateId = null;
                                          _editingTemplateName = null;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // Recurrence Frequency Dropdown (Visible when ⏳ is active)
                            if (_isRecurrenceMode) ...[
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF262C54) : const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark ? const Color(0xFFF59E0B).withValues(alpha: 0.5) : const Color(0xFFFCD34D),
                                    width: 1.2,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: _buildFieldLabel('⏳ RECURRENCE FREQUENCY', color: isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309)),
                                        ),
                                        if (_recurrenceFrequency == 'Custom')
                                          InkWell(
                                            onTap: _showCustomRecurrenceDialog,
                                            borderRadius: BorderRadius.circular(6),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                (_customMonths != null || _customDays != null)
                                                    ? '${_customMonths ?? 0}m, ${_customDays ?? 0}d ✏️'
                                                    : 'Set interval ✏️',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      height: 44,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: inputBg,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: inputBorder, width: 1.2),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _recurrenceFrequency,
                                          isExpanded: true,
                                          dropdownColor: isDark ? const Color(0xFF1E2442) : Colors.white,
                                          items: ['Month', 'Quarterly', 'Half-Yearly', 'Yearly', 'Custom'].map((freq) {
                                            return DropdownMenuItem<String>(
                                              value: freq,
                                              child: Text(
                                                freq == 'Custom' && (_customMonths != null || _customDays != null)
                                                    ? 'Custom (${_customMonths ?? 0} months, ${_customDays ?? 0} days)'
                                                    : freq,
                                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            if (val == null) return;
                                            setState(() => _recurrenceFrequency = val);
                                            if (val == 'Custom') {
                                              _showCustomRecurrenceDialog();
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // 4. 📅 DATE & 🔖 REFERENCE Row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildFieldLabel('📅 DATE', color: textSecondary),
                                      SizedBox(
                                        height: 46,
                                        child: InkWell(
                                          onTap: _pickDate,
                                          borderRadius: BorderRadius.circular(12),
                                          child: InputDecorator(
                                            decoration: InputDecoration(
                                              isDense: true,
                                              constraints: const BoxConstraints(minHeight: 46, maxHeight: 46),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                              filled: true,
                                              fillColor: inputBg,
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide(color: inputBorder, width: 1.2),
                                              ),
                                            ),
                                            child: Text(
                                              FinanceTransaction.formatDate(_selectedDate),
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: textPrimary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 6,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildFieldLabel('🔖 REFERENCE', color: textSecondary),
                                      SizedBox(
                                        height: 46,
                                        child: TextFormField(
                                          controller: _referenceIdController,
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textPrimary),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            constraints: const BoxConstraints(minHeight: 46, maxHeight: 46),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                            filled: true,
                                            fillColor: inputBg,
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(color: inputBorder, width: 1.2),
                                            ),
                                            suffixIconConstraints: const BoxConstraints(minWidth: 26, minHeight: 26, maxWidth: 26, maxHeight: 26),
                                            suffixIcon: IconButton(
                                              icon: const Icon(Icons.autorenew, size: 16, color: cyanAccent),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                              onPressed: _regenerateReferenceId,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // 5. 📝 NARRATION Row
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildFieldLabel('📝 NARRATION', color: textSecondary),
                                Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 46,
                                        child: TextFormField(
                                          controller: _narrationController,
                                          maxLines: 1,
                                          onChanged: (val) {
                                            _suppressTemplateSuggestions = false;
                                            _onNarrationChanged();
                                          },
                                          style: TextStyle(fontSize: 13, color: textPrimary),
                                          decoration: InputDecoration(
                                            hintText: 'Type command & tap ✨',
                                            hintStyle: TextStyle(
                                              fontSize: 12,
                                              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                            ),
                                            isDense: true,
                                            constraints: const BoxConstraints(minHeight: 46, maxHeight: 46),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                            filled: true,
                                            fillColor: inputBg,
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(color: inputBorder, width: 1.2),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(color: isDark ? purpleAccent : cyanAccent, width: 1.8),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // ✨ AI Auto-fill Button
                                    InkWell(
                                      onTap: () {
                                        _aiAutoFillDebounce?.cancel();
                                        if (_narrationController.text.trim().isNotEmpty) {
                                          _processAiAutoFill(_narrationController.text.trim(), updateNarration: true, isSilent: false);
                                        } else {
                                          _handleAutoFill();
                                        }
                                      },
                                      onLongPress: _showApiKeysDialog,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF261D4A) : const Color(0xFFF5F3FF),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isDark ? const Color(0xFF7C3AED) : const Color(0xFFC084FC),
                                            width: 1.3,
                                          ),
                                        ),
                                        child: Center(
                                          child: _isAiProcessing
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Color(0xFFC084FC),
                                                  ),
                                                )
                                              : const Text('✨', style: TextStyle(fontSize: 18)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    // 🎤 Mic Voice Input Button
                                    InkWell(
                                      onTap: _toggleVoiceInput,
                                      borderRadius: BorderRadius.circular(10),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        width: 40,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: _isListening
                                              ? const Color(0xFFEF4444)
                                              : inputBg,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: _isListening
                                                ? const Color(0xFFEF4444)
                                                : inputBorder,
                                            width: 1.2,
                                          ),
                                          boxShadow: _isListening
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                                                    blurRadius: 8,
                                                    spreadRadius: 1,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Center(
                                          child: _isListening
                                              ? const Icon(Icons.mic, size: 20, color: Colors.white)
                                              : const Text('🎤', style: TextStyle(fontSize: 16)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            // Live Template Suggestions while typing narration
                            if (_matchingTemplates.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              SizedBox(
                                height: 34,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _matchingTemplates.length,
                                  itemBuilder: (ctx, idx) {
                                    final t = _matchingTemplates[idx];
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ActionChip(
                                        avatar: const Icon(Icons.auto_awesome, size: 14, color: cyanAccent),
                                        label: Text(
                                          t.name,
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cyanAccent),
                                        ),
                                        backgroundColor: isDark ? const Color(0xFF142C35) : const Color(0xFFF0FDFA),
                                        side: const BorderSide(color: cyanAccent, width: 1.0),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _applyTemplate(t),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),

                            // 6. Conditional Section: Self Transfer vs Normal / Split Mode
                            if (_isSelfTransferMode) ...[
                              // 🏦 FROM (SOURCES)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildFieldLabel('🏦 FROM (SOURCES)', color: coralAccent),
                                  InkWell(
                                    onTap: _addPaymentMode,
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: coralAccent,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Text(
                                        '+ Add',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ..._breakdowns.asMap().entries.map((entry) {
                                final index = entry.key;
                                final breakdown = entry.value;
                                final accountsForThisType = breakdown.paymentType != null
                                    ? _storage.getAccountsForType(breakdown.paymentType!, _categoryAccounts)
                                    : <String>[];
                                if (breakdown.account != null && breakdown.account!.isNotEmpty && !accountsForThisType.contains(breakdown.account)) {
                                  accountsForThisType.insert(0, breakdown.account!);
                                }
                                return PaymentBreakdownCard(
                                  key: ValueKey('from_${breakdown.id}'),
                                  index: index,
                                  breakdown: breakdown,
                                  availableAccounts: accountsForThisType,
                                  isOnlyMode: _breakdowns.length <= 1,
                                  onChanged: () {
                                    _syncFromAmountToToAmountIfClearedCardBill();
                                    setState(() {});
                                  },
                                  onDelete: () => _removePaymentMode(index),
                                );
                              }),
                              const SizedBox(height: 14),

                              // 🏦 TO (DESTINATIONS)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildFieldLabel('🏦 TO (DESTINATIONS)', color: cyanAccent),
                                  InkWell(
                                    onTap: _addToPaymentMode,
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: coralAccent,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Text(
                                        '+ Add',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ..._toBreakdowns.asMap().entries.map((entry) {
                                final index = entry.key;
                                final breakdown = entry.value;
                                final accountsForThisType = breakdown.paymentType != null
                                    ? _storage.getAccountsForType(breakdown.paymentType!, _categoryAccounts)
                                    : <String>[];
                                if (breakdown.account != null && breakdown.account!.isNotEmpty && !accountsForThisType.contains(breakdown.account)) {
                                  accountsForThisType.insert(0, breakdown.account!);
                                }
                                return PaymentBreakdownCard(
                                  key: ValueKey('to_${breakdown.id}'),
                                  index: index,
                                  breakdown: breakdown,
                                  availableAccounts: accountsForThisType,
                                  isOnlyMode: _toBreakdowns.length <= 1,
                                  onChanged: () {
                                    _userEditedToAmount = true;
                                    setState(() {});
                                  },
                                  onDelete: () => _removeToPaymentMode(index),
                                );
                              }),
                              const SizedBox(height: 14),

                              // ⚖️ BALANCE SUMMARY
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1B2042) : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isDark ? const Color(0xFF262C54) : const Color(0xFFF1E5DC), width: 1.2),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildFieldLabel('⚖️ BALANCE SUMMARY', color: coralAccent),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Total Out:', style: TextStyle(fontSize: 12, color: textSecondary)),
                                        Text('₹${IndianCurrency.format(_totalFromAmount)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Total In:', style: TextStyle(fontSize: 12, color: textSecondary)),
                                        Text('₹${IndianCurrency.format(_totalToAmount)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Difference:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary)),
                                        Text('₹${IndianCurrency.format(transferDiff)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cyanAccent)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              // 💧 FLOW & 🧾 INVOICE (OPT)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildFieldLabel('💧 FLOW', color: textSecondary),
                                        SizedBox(
                                          height: 44,
                                          child: PopupSelectField(
                                            key: ValueKey('flow_$_flow'),
                                            label: 'Flow',
                                            placeholder: 'Select',
                                            items: const ['Withdraw', 'Deposit'],
                                            selectedValue: _flow,
                                            validator: (val) => (val == null || val.isEmpty) ? 'Select Flow' : null,
                                            onSelected: _onFlowSelected,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 5,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildFieldLabel('🧾 INVOICE (OPT)', color: textSecondary),
                                        SizedBox(
                                          height: 44,
                                          child: InkWell(
                                            onTap: _showInvoicePickerBottomSheet,
                                            borderRadius: BorderRadius.circular(12),
                                            child: InputDecorator(
                                              decoration: InputDecoration(
                                                isDense: true,
                                                filled: true,
                                                fillColor: isDark ? const Color(0xFF1B2042) : Colors.white,
                                                constraints: const BoxConstraints(minHeight: 44, maxHeight: 44),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: BorderSide(
                                                    color: isDark ? const Color(0xFF2C3360) : const Color(0xFFCBD5E1),
                                                    width: 1.2,
                                                  ),
                                                ),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: BorderSide(
                                                    color: isDark ? const Color(0xFF2C3360) : const Color(0xFFCBD5E1),
                                                    width: 1.2,
                                                  ),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: BorderSide(
                                                    color: isDark ? const Color(0xFFA78BFA) : const Color(0xFFFF5C38),
                                                    width: 1.8,
                                                  ),
                                                ),
                                                suffixIconConstraints: const BoxConstraints(minWidth: 26, minHeight: 26, maxWidth: 26, maxHeight: 26),
                                                suffixIcon: Icon(
                                                  Icons.arrow_drop_down,
                                                  size: 20,
                                                  color: isDark ? const Color(0xFF818CF8) : const Color(0xFF64748B),
                                                ),
                                              ),
                                              child: Text(
                                                _invoiceController.text.isNotEmpty ? _invoiceController.text : 'Select invoice',
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  height: 1.15,
                                                  fontWeight: _invoiceController.text.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                                                  color: _invoiceController.text.isNotEmpty
                                                      ? (isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B))
                                                      : (isDark ? const Color(0xFF8E9AC2) : const Color(0xFF94A3B8)),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // 🎯 PURPOSE Row
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildFieldLabel('🎯 PURPOSE', color: textSecondary),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: isOtherPurpose ? 5 : 10,
                                        child: SizedBox(
                                          height: 44,
                                          child: PopupSelectField(
                                            key: ValueKey('purpose_${_selectedPurpose}_${_flow}_$_isSplitModeEnabled'),
                                            label: 'Purpose',
                                            placeholder: 'Select',
                                            items: _purposes,
                                            selectedValue: _selectedPurpose,
                                            enableSearch: true,
                                            validator: (val) => (val == null || val.isEmpty) ? 'Select Purpose' : null,
                                            onSelected: (val) => setState(() => _selectedPurpose = val),
                                          ),
                                        ),
                                      ),
                                      if (isOtherPurpose) ...[
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 5,
                                          child: SizedBox(
                                            height: 44,
                                            child: TextFormField(
                                              controller: _customPurposeController,
                                              style: TextStyle(fontSize: 13, color: textPrimary),
                                              decoration: InputDecoration(
                                                hintText: 'Enter Purpose',
                                                isDense: true,
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                filled: true,
                                                fillColor: inputBg,
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                  borderSide: BorderSide(color: inputBorder, width: 1.2),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // 👤 SPENT FOR Row
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildFieldLabel('👤 SPENT FOR', color: textSecondary),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: isOtherSpentFor ? 4 : 10,
                                        child: SizedBox(
                                          height: 44,
                                          child: PopupSelectField(
                                            key: ValueKey('spentFor_${_selectedSpentFor}_$_isSplitModeEnabled'),
                                            label: 'Spent For',
                                            placeholder: 'Select',
                                            items: _availableSpentFors,
                                            selectedValue: _selectedSpentFor,
                                            enableSearch: true,
                                            validator: (val) => (val == null || val.isEmpty) ? 'Select Spent For' : null,
                                            onSelected: _onSpentForSelected,
                                          ),
                                        ),
                                      ),
                                      if (isOtherSpentFor) ...[
                                        const SizedBox(width: 6),
                                        Expanded(
                                          flex: 6,
                                          child: SizedBox(
                                            height: 44,
                                            child: TextFormField(
                                              controller: _customSpentForController,
                                              style: TextStyle(fontSize: 13, color: textPrimary),
                                              decoration: InputDecoration(
                                                hintText: 'Name / Contact',
                                                isDense: true,
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                filled: true,
                                                fillColor: inputBg,
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                  borderSide: BorderSide(color: inputBorder, width: 1.2),
                                                ),
                                                suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                                suffixIcon: IconButton(
                                                  icon: const Icon(Icons.contacts_rounded, size: 18, color: cyanAccent),
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                                  tooltip: 'Pick Contact',
                                                  onPressed: _pickContactForSpentFor,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // 💳 PAYMENT BREAKDOWN Section
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildFieldLabel('💳 PAYMENT BREAKDOWN', color: textSecondary),
                                  InkWell(
                                    onTap: _addPaymentMode,
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: cyanAccent,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Text(
                                        '+ Add Mode',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ..._breakdowns.asMap().entries.map((entry) {
                                final index = entry.key;
                                final breakdown = entry.value;
                                final accountsForThisType = breakdown.paymentType != null
                                    ? _storage.getAccountsForType(breakdown.paymentType!, _categoryAccounts)
                                    : <String>[];
                                if (breakdown.account != null && breakdown.account!.isNotEmpty && !accountsForThisType.contains(breakdown.account)) {
                                  accountsForThisType.insert(0, breakdown.account!);
                                }
                                return PaymentBreakdownCard(
                                  key: ValueKey('reg_${breakdown.id}'),
                                  index: index,
                                  breakdown: breakdown,
                                  availableAccounts: accountsForThisType,
                                  isOnlyMode: _breakdowns.length <= 1,
                                  onChanged: () {
                                    setState(() {});
                                    if (_isSplitMode) {
                                      _splitEqually();
                                    }
                                  },
                                  onDelete: () => _removePaymentMode(index),
                                );
                              }),

                              // 💸 SPLIT / LOAN Section (Only visible when Split mode is enabled at top AND selected in Spent For)
                              if (_isSplitModeEnabled && _selectedSpentFor == 'Split') ...[
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _buildFieldLabel('💸 SPLIT / LOAN', color: textSecondary),
                                    Row(
                                      children: [
                                        InkWell(
                                          onTap: _toggleSplitType,
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF142B30) : const Color(0xFFF0FDFA),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: cyanAccent, width: 1.2),
                                            ),
                                            child: Text(
                                              _splitType,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: cyanAccent,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        InkWell(
                                          onTap: _splitEqually,
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF381A2D) : const Color(0xFFFFF1F2),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: coralAccent, width: 1.2),
                                            ),
                                            child: const Text(
                                              'Equal',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: coralAccent,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        InkWell(
                                          onTap: _onAddSplitPressed,
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF1B2042) : const Color(0xFFF8FAFC),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: inputBorder, width: 1.2),
                                            ),
                                            child: Center(
                                              child: Icon(
                                                Icons.add,
                                                size: 18,
                                                color: textPrimary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                ..._splitRecipients.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final recipient = entry.value;
                                  final isPersonal = recipient.isPersonal;

                                  final rowWidget = Container(
                                    margin: const EdgeInsets.symmetric(vertical: 3),
                                    height: 44,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 7,
                                          child: isPersonal
                                              ? Container(
                                                  height: 46,
                                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: isDark
                                                          ? [const Color(0xFF064E3B).withValues(alpha: 0.5), const Color(0xFF042F2E).withValues(alpha: 0.5)]
                                                          : [const Color(0xFFECFDF5), const Color(0xFFF0FDFA)],
                                                    ),
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(
                                                      color: isDark ? const Color(0xFF10B981) : const Color(0xFF059669),
                                                      width: 1.4,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.all(3),
                                                        decoration: BoxDecoration(
                                                          color: (isDark ? const Color(0xFF10B981) : const Color(0xFF059669)).withValues(alpha: 0.15),
                                                          shape: BoxShape.circle,
                                                        ),
                                                        child: const Icon(
                                                          Icons.person_pin_rounded,
                                                          size: 18,
                                                          color: Color(0xFF10B981),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          'My Share (You)',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.bold,
                                                            color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                                                            letterSpacing: 0.2,
                                                          ),
                                                        ),
                                                      ),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: (isDark ? const Color(0xFF10B981) : const Color(0xFF059669)).withValues(alpha: 0.18),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          'Self',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w700,
                                                            color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              : PopupSelectField(
                                                  key: ValueKey('split_rep_${recipient.id}_${recipient.name}'),
                                                  label: 'Spent For',
                                                  placeholder: 'Select Member',
                                                  items: _spentFors.where((s) => s != 'Split').toList(),
                                                  selectedValue: recipient.name,
                                                  onSelected: (val) {
                                                    setState(() {
                                                      recipient.name = val;
                                                    });
                                                  },
                                                ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 100,
                                          height: 46,
                                          child: InkWell(
                                            onTap: () => _openCalculatorForRecipient(idx),
                                            borderRadius: BorderRadius.circular(12),
                                            child: InputDecorator(
                                              decoration: InputDecoration(
                                                isDense: true,
                                                constraints: const BoxConstraints(minHeight: 46, maxHeight: 46),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                                filled: true,
                                                fillColor: inputBg,
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                  borderSide: BorderSide(color: inputBorder, width: 1.2),
                                                ),
                                              ),
                                              child: Text(
                                                _splitType == 'Percentage'
                                                    ? '${recipient.percentage.toStringAsFixed(1)}%'
                                                    : recipient.amount.toStringAsFixed(2),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: textPrimary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 3),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Dismissible(
                                        key: ValueKey('split_dismiss_${recipient.id}'),
                                        direction: DismissDirection.endToStart,
                                        background: Container(
                                          padding: const EdgeInsets.only(right: 16),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEF4444),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          alignment: Alignment.centerRight,
                                          child: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 22),
                                        ),
                                        onDismissed: (_) => _removeSplitRecipient(idx),
                                        child: rowWidget,
                                      ),
                                    ),
                                  );
                                }),
                              ],

                              const SizedBox(height: 14),

                              // TOTAL AMOUNT & DIFFERENCE Box
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1B2042) : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: (_selectedSpentFor == 'Split' && splitDiff > 0.01)
                                        ? const Color(0xFFEF4444)
                                        : (isDark ? const Color(0xFF262C54) : const Color(0xFFF1E5DC)),
                                    width: (_selectedSpentFor == 'Split' && splitDiff > 0.01) ? 1.5 : 1.2,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        _buildFieldLabel('TOTAL AMOUNT:', color: textSecondary),
                                        Text(
                                          '₹${IndianCurrency.format(_totalAmount)}',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? purpleAccent : coralAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_selectedSpentFor == 'Split') ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          _buildFieldLabel('DIFFERENCE:', color: textSecondary),
                                          Text(
                                            '₹${IndianCurrency.format(splitDiff)}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: splitDiff > 0.01 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (splitDiff > 0.01) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 14),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                'Split sum (₹${IndianCurrency.format(splitSum)}) does not match main total (₹${IndianCurrency.format(_totalAmount)})',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFFEF4444),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 14),

                            // Multi-transaction Draft / Multi-Edit Switcher
                            if (_multiEditTransactions.length > 1 || _draftTransactions.length > 1) ...[
                              Row(
                                children: [
                                  Text(
                                    _multiEditTransactions.length > 1
                                        ? 'Editing ${_currentMultiEditIndex + 1} of ${_multiEditTransactions.length}'
                                        : 'Draft ${_currentDraftIndex + 1} of ${_draftTransactions.length}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  // ◀ Prev
                                  Expanded(
                                    child: InkWell(
                                      onTap: (_multiEditTransactions.length > 1 ? _currentMultiEditIndex > 0 : _currentDraftIndex > 0)
                                          ? () {
                                              setState(() {
                                                if (_multiEditTransactions.length > 1) {
                                                  _currentMultiEditIndex--;
                                                  _loadTransactionForEditing(_multiEditTransactions[_currentMultiEditIndex], showSnackbar: false);
                                                } else {
                                                  _currentDraftIndex--;
                                                  _applyDraft(_draftTransactions[_currentDraftIndex]);
                                                }
                                              });
                                            }
                                          : null,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF102830) : const Color(0xFFF0FDFA),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: (_multiEditTransactions.length > 1 ? _currentMultiEditIndex > 0 : _currentDraftIndex > 0)
                                                ? cyanAccent
                                                : cyanAccent.withValues(alpha: 0.3),
                                            width: 1.2,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '◀ Prev',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: (_multiEditTransactions.length > 1 ? _currentMultiEditIndex > 0 : _currentDraftIndex > 0)
                                                ? cyanAccent
                                                : cyanAccent.withValues(alpha: 0.3),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // 🗑️ Remove
                                  Expanded(
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          if (_multiEditTransactions.length > 1) {
                                            _multiEditTransactions.removeAt(_currentMultiEditIndex);
                                            if (_multiEditTransactions.isEmpty) {
                                              _resetEntireForm();
                                            } else {
                                              if (_currentMultiEditIndex >= _multiEditTransactions.length) {
                                                _currentMultiEditIndex = _multiEditTransactions.length - 1;
                                              }
                                              _loadTransactionForEditing(_multiEditTransactions[_currentMultiEditIndex], showSnackbar: false);
                                            }
                                          } else {
                                            _draftTransactions.removeAt(_currentDraftIndex);
                                            if (_draftTransactions.isEmpty) {
                                              _resetEntireForm();
                                            } else {
                                              if (_currentDraftIndex >= _draftTransactions.length) {
                                                _currentDraftIndex = _draftTransactions.length - 1;
                                              }
                                              _applyDraft(_draftTransactions[_currentDraftIndex]);
                                            }
                                          }
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF2A1620) : const Color(0xFFFFF1F2),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: coralAccent,
                                            width: 1.2,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text('🗑️', style: TextStyle(fontSize: 13)),
                                            SizedBox(width: 4),
                                            Text(
                                              'Remove',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: coralAccent,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Next ▶
                                  Expanded(
                                    child: InkWell(
                                      onTap: (_multiEditTransactions.length > 1
                                              ? _currentMultiEditIndex < _multiEditTransactions.length - 1
                                              : _currentDraftIndex < _draftTransactions.length - 1)
                                          ? () {
                                              setState(() {
                                                if (_multiEditTransactions.length > 1) {
                                                  _currentMultiEditIndex++;
                                                  _loadTransactionForEditing(_multiEditTransactions[_currentMultiEditIndex], showSnackbar: false);
                                                } else {
                                                  _currentDraftIndex++;
                                                  _applyDraft(_draftTransactions[_currentDraftIndex]);
                                                }
                                              });
                                            }
                                          : null,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF102830) : const Color(0xFFF0FDFA),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: (_multiEditTransactions.length > 1
                                                    ? _currentMultiEditIndex < _multiEditTransactions.length - 1
                                                    : _currentDraftIndex < _draftTransactions.length - 1)
                                                ? cyanAccent
                                                : cyanAccent.withValues(alpha: 0.3),
                                            width: 1.2,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          'Next ▶',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: (_multiEditTransactions.length > 1
                                                    ? _currentMultiEditIndex < _multiEditTransactions.length - 1
                                                    : _currentDraftIndex < _draftTransactions.length - 1)
                                                ? cyanAccent
                                                : cyanAccent.withValues(alpha: 0.3),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],

                            // 7. Action Buttons: Save & Repeat
                            Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: SizedBox(
                                    height: 46,
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: isDark ? const Color(0xFFA78BFA) : coralAccent,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                        padding: EdgeInsets.zero,
                                      ),
                                      onPressed: _saveTransaction,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const SaveThemeEmoji(size: 20),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Save',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? const Color(0xFF151932) : Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 5,
                                  child: SizedBox(
                                    height: 46,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: isDark ? const Color(0xFF1B2042) : Colors.white,
                                        side: BorderSide(
                                          color: isDark ? const Color(0xFF2C3360) : const Color(0xFFE2E8F0),
                                          width: 1.2,
                                        ),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                        padding: EdgeInsets.zero,
                                      ),
                                      onPressed: _repeatLastTransaction,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          RepeatThemeEmoji(
                                            size: 18,
                                            color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0F766E),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Repeat',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // 8. Save as Template Button
                            SizedBox(
                              height: 42,
                              width: double.infinity,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: isDark ? const Color(0xFF1E1A3C) : const Color(0xFFF5F3FF),
                                  side: BorderSide(
                                    color: isDark ? const Color(0xFF6D28D9) : const Color(0xFFDDD6FE),
                                    width: 1.2,
                                  ),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                onPressed: _showSaveAsTemplateDialog,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(_editingTemplateId != null ? '💾' : '⭐', style: const TextStyle(fontSize: 14)),
                                    const SizedBox(width: 6),
                                    Text(
                                      _editingTemplateId != null
                                          ? 'Update Template'
                                          : 'Save as Template',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? const Color(0xFFC084FC) : const Color(0xFF7C3AED),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ),

            // Multi-purpose Floating Bell with due notifications badge (recurring + credit card bills)
            Builder(
              builder: (context) {
                final now = DateTime.now();
                final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
                final dueRecurringCount = _recurringTransactions.where((r) => !r.isPaused && !r.nextDueDate.isAfter(endOfToday)).length;
                final dueBillsCount = _liveBalancesSummary?.totalDueBillsCount ?? 0;
                final totalDueCount = dueRecurringCount + dueBillsCount;

                if (totalDueCount <= 0) return const SizedBox.shrink();

                return Positioned(
                  bottom: 18,
                  right: 14,
                  child: InkWell(
                    onTap: _showNotificationsPopup,
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF3B2E6A) : const Color(0xFFDDD6FE),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (isDark ? const Color(0xFF7C3AED) : const Color(0xFF8B5CF6)).withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text('🔔', style: TextStyle(fontSize: 22)),
                          ),
                        ),
                        if (totalDueCount > 0)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$totalDueCount',
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}
}
