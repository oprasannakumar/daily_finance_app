import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/account_balance_model.dart';
import '../models/emi_plan_model.dart';
import '../models/invoice_model.dart';
import '../models/transaction_model.dart';
import 'google_auth_service.dart';
import 'storage_service.dart';

class GoogleSheetsService {
  static final GoogleSheetsService instance = GoogleSheetsService._internal();
  factory GoogleSheetsService() => instance;
  GoogleSheetsService._internal();

  static const String _keySpreadsheetId = 'google_sheet_id';
  static const String _keySpreadsheetUrl = 'google_sheet_url';
  static const String _keySheetGid = 'google_sheet_gid';
  static const String _keyWebAppUrl = 'google_sheets_web_app_url';

  final ValueNotifier<bool> isSyncingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> syncStatusNotifier = ValueNotifier<String?>(null);

  // In-memory runtime session cache
  List<FinanceTransaction>? cachedTransactions;
  List<LoanEntry>? cachedLoanEntries;

  Future<String?> getSpreadsheetId({String? email}) async {
    final active = await StorageService.instance.getString(_keySpreadsheetId);
    if (active != null && active.isNotEmpty) return active;
    final effectiveEmail = email ?? (await GoogleAuthService.instance.currentUserEmail);
    if (effectiveEmail != null && effectiveEmail.isNotEmpty) {
      return StorageService.instance.getString('${_keySpreadsheetId}_$effectiveEmail');
    }
    return null;
  }

  Future<String?> getSpreadsheetUrl({String? email}) async {
    final active = await StorageService.instance.getString(_keySpreadsheetUrl);
    if (active != null && active.isNotEmpty) return active;
    final effectiveEmail = email ?? (await GoogleAuthService.instance.currentUserEmail);
    if (effectiveEmail != null && effectiveEmail.isNotEmpty) {
      return StorageService.instance.getString('${_keySpreadsheetUrl}_$effectiveEmail');
    }
    return null;
  }

  Future<int?> getSheetGid() async {
    final str = await StorageService.instance.getString(_keySheetGid);
    return str != null ? int.tryParse(str) : null;
  }
  Future<String?> getWebAppUrl() => StorageService.instance.getString(_keyWebAppUrl);

  Future<void> setSpreadsheetId(String id, {String? email}) async {
    _sheetsEnsured = false;
    await StorageService.instance.setString(_keySpreadsheetId, id);
    final effectiveEmail = email ?? (await GoogleAuthService.instance.currentUserEmail);
    if (effectiveEmail != null && effectiveEmail.isNotEmpty) {
      await StorageService.instance.setString('${_keySpreadsheetId}_$effectiveEmail', id);
    }
  }

  Future<void> setSpreadsheetUrl(String url, {String? email}) async {
    await StorageService.instance.setString(_keySpreadsheetUrl, url);
    final effectiveEmail = email ?? (await GoogleAuthService.instance.currentUserEmail);
    if (effectiveEmail != null && effectiveEmail.isNotEmpty) {
      await StorageService.instance.setString('${_keySpreadsheetUrl}_$effectiveEmail', url);
    }
  }

  Future<void> setSheetGid(int gid) => StorageService.instance.setString(_keySheetGid, gid.toString());
  Future<void> setWebAppUrl(String url) => StorageService.instance.setString(_keyWebAppUrl, url);

  Future<void> clearActiveSpreadsheetInfo() async {
    await StorageService.instance.remove(_keySpreadsheetId);
    await StorageService.instance.remove(_keySpreadsheetUrl);
    await StorageService.instance.remove(_keySheetGid);
    _sheetsEnsured = false;
    clearSessionCache();
  }

  // =========================================================================
  // HEADERS FOR ALL 7 SHEETS IN THE ARCHITECTURE
  // =========================================================================

  /// 1. Transactions / Full Statement (Master ledger)
  static const List<String> requiredHeaders = [
    'Date',
    'Narration',
    'Invoice No.',
    'Purpose',
    'Spent for/Earned by',
    'Transaction Type',
    'From/ To',
    'Withdrawn Amount',
    'Deposit Amount',
    'Reference',
  ];

  /// 2. Monthly Transaction (Personal P&L, strictly excludes self-transfers)
  static const List<String> requiredMonthlyHeaders = [
    'Date',
    'Narration',
    'Invoice No.',
    'Purpose',
    'Spent for/Earned by',
    'Transaction Type',
    'From/ To',
    'Withdrawn Amount',
    'Deposit Amount',
    'Reference',
  ];

  /// 3. Self Transfer (Audit ledger for internal movements - 8 columns)
  static const List<String> requiredSelfTransferHeaders = [
    'Date',
    'Narration',
    'From Type',
    'From Acccount',
    'To Type',
    'To Account',
    'Amount',
    'Reference ID',
  ];

  /// 4. loan (Borrower ledger for split bills & loans)
  static const List<String> requiredLoanHeaders = [
    'Date',
    'Borrower',
    'Narration',
    'Invoice No.',
    'Transaction Type',
    'Account',
    'Given Amount',
    'Received Amount',
    'Reference',
  ];

  /// 5. Cash Entries (The Cash Matrix with bill counts)
  static const List<String> requiredCashHeaders = [
    'Date',
    '500',
    '200',
    '100',
    '50',
    '20',
    '10',
    '5',
    '2',
    '1',
    'Reference ID',
  ];

  /// 6. Credit (The Liability Tracker for credit card usage)
  static const List<String> requiredCreditHeaders = [
    'Date',
    'Narration',
    'Account',
    'Deposited Amount',
    'Withdrawn Amount',
    'Reference ID',
  ];

  /// 7. Billing (Automated card billing updates)
  static const List<String> requiredBillingHeaders = [
    'Account',
    'Bill Date',
    'Due Date',
    'Amount',
    'Status',
    'Paid Date',
    'Reference',
  ];

  /// 8. Account Balances & Limits
  static const List<String> requiredBalancesHeaders = [
    'Account / Card',
    'Type',
    'Total Limit',
    'Used Limit',
    'Available Balance',
    'Shared Group',
    'Bill Day',
    'Due Day',
    'Statement Billed',
    'Last Updated',
  ];

  /// 9. App Config & Masters (Purposes, Spent For, Categories, Templates, Recurring, Config)
  static const List<String> requiredConfigHeaders = [
    'Type',
    'Key / Name',
    'Summary / Details',
    'JSON Payload',
    'Last Updated',
  ];

  /// 10. Active EMIs (Credit card EMI conversions and schedules)
  static const List<String> requiredEmiHeaders = [
    'EMI ID',
    'Title',
    'Account',
    'Tx Date',
    'Total Tx Amount',
    'Principal Converted',
    'Tenure',
    'ROI',
    'Processing Fee',
    'Processing Fee GST',
    'First EMI Date',
    'Status',
    'Notes',
    'Schedule JSON',
  ];

  // Resolved titles and GIDs cached during session
  String _txTitle = 'Full Statement';
  int _txGid = 0;
  String _monthlyTitle = 'Monthly Transaction';
  int _monthlyGid = 1;
  String _selfTransferTitle = 'Self Transfer';
  int _selfTransferGid = 2;
  String _loanTitle = 'Loan';
  int _loanGid = 3;
  String _cashTitle = 'Cash Entries';
  int _cashGid = 4;
  String _creditTitle = 'Credit';
  int _creditGid = 5;
  String _billingTitle = 'Billing';
  int _billingGid = 6;
  String _balancesTitle = 'Account Balances';
  int _balancesGid = 7;
  String _configTitle = 'App Config & Masters';
  int _configGid = 8;
  String _emiTitle = 'Active_EMIs';
  int _emiGid = 9;

  // =========================================================================
  // ROW FORMATTERS
  // =========================================================================

  /// Formats transaction into standard 10-column row (Transactions / Monthly / Self Transfer).
  List<dynamic> formatTransactionRow(FinanceTransaction tx) {
    final dateFormatted = DateFormat('dd/MMM/yyyy').format(tx.date);

    String transactionType = '';
    if (tx.isSelfTransfer) {
      transactionType = 'Self Transfer';
    } else {
      final types = tx.breakdowns
          .map((b) => b.paymentType ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
      transactionType = types.isNotEmpty ? types.join(', ') : tx.flow;
    }

    String fromTo = tx.isSelfTransfer
        ? '${tx.fromSummary} -> ${tx.toSummary}'
        : tx.fromSummary;

    dynamic withdrawnAmount = '';
    dynamic depositAmount = '';

    final flowLower = tx.flow.toLowerCase();
    if (tx.isSelfTransfer) {
      withdrawnAmount = tx.totalAmount;
      depositAmount = tx.totalAmount;
    } else if (flowLower.contains('deposit') || flowLower.contains('income')) {
      depositAmount = tx.totalAmount;
    } else {
      withdrawnAmount = tx.totalAmount;
    }

    return [
      dateFormatted,
      tx.narration,
      tx.invoice,
      tx.purpose,
      tx.spentFor,
      transactionType,
      fromTo,
      withdrawnAmount,
      depositAmount,
      tx.referenceId,
    ];
  }

  /// Formats individual leg of a Self Transfer (withdrawal or deposit).
  List<dynamic> formatTransferLegRow({
    required FinanceTransaction tx,
    required bool isWithdrawal,
    required String account,
    required String paymentType,
  }) {
    final dateFormatted = DateFormat('dd/MMM/yyyy').format(tx.date);
    final legNarration = isWithdrawal
        ? '${tx.narration} (From)'
        : '${tx.narration} (To)';

    return [
      dateFormatted,
      legNarration,
      tx.invoice,
      'Self Transfer',
      'Self',
      paymentType.isNotEmpty ? paymentType : 'Transfer',
      account,
      isWithdrawal ? tx.totalAmount : '',
      !isWithdrawal ? tx.totalAmount : '',
      tx.referenceId,
    ];
  }

  /// Formats individual leg of a Self Transfer for the "Self Transfer" sheet (8 columns):
  /// Date | Narration | From Type | From Acccount | To Type | To Account | Amount | Reference ID
  List<dynamic> formatSelfTransferSheetRow({
    required FinanceTransaction tx,
    required bool isWithdrawal,
    required String account,
    required String paymentType,
    double? amount,
  }) {
    final dateFormatted = DateFormat('dd-MMM-yy').format(tx.date);
    final legNarration = isWithdrawal
        ? '${tx.narration} (From)'
        : '${tx.narration} (To)';

    final effectiveAmount = amount ?? tx.totalAmount;

    return [
      dateFormatted,
      legNarration,
      isWithdrawal ? paymentType : '', // From Type (Col C)
      isWithdrawal ? account : '',     // From Acccount (Col D)
      !isWithdrawal ? paymentType : '', // To Type (Col E)
      !isWithdrawal ? account : '',     // To Account (Col F)
      effectiveAmount,
      tx.referenceId,                   // Pure Reference ID (Col H)
    ];
  }

  /// Formats personal share into Monthly Transaction sheet (10 columns).
  List<dynamic> formatMonthlyTransactionRow(FinanceTransaction tx, SplitRecipient personalShare) {
    final dateFormatted = DateFormat('dd/MMM/yyyy').format(tx.date);

    String transactionType = '';
    final types = tx.breakdowns
        .map((b) => b.paymentType ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();
    transactionType = types.isNotEmpty ? types.join(', ') : tx.flow;

    dynamic withdrawnAmount = '';
    dynamic depositAmount = '';

    final flowLower = tx.flow.toLowerCase();
    if (flowLower.contains('deposit') || flowLower.contains('income')) {
      depositAmount = personalShare.amount;
    } else {
      withdrawnAmount = personalShare.amount;
    }

    return [
      dateFormatted,
      tx.narration,
      tx.invoice,
      tx.purpose,
      'Self',
      transactionType,
      tx.fromSummary,
      withdrawnAmount,
      depositAmount,
      tx.referenceId,
    ];
  }

  /// Formats an individual payment breakdown row (10 columns) for Full Statement / Monthly.
  List<dynamic> formatTransactionBreakdownRow(FinanceTransaction tx, PaymentBreakdown b) {
    final dateFormatted = DateFormat('dd/MMM/yyyy').format(tx.date);
    final txType = b.paymentType ?? 'Account';
    final acc = b.effectiveAccount.isNotEmpty ? b.effectiveAccount : tx.fromSummary;

    dynamic withdrawnAmount = '';
    dynamic depositAmount = '';

    final flowLower = tx.flow.toLowerCase();
    if (flowLower.contains('deposit') || flowLower.contains('income')) {
      depositAmount = b.amount;
    } else {
      withdrawnAmount = b.amount;
    }

    return [
      dateFormatted,
      tx.narration,
      tx.invoice,
      tx.purpose,
      tx.spentFor,
      txType,
      acc,
      withdrawnAmount,
      depositAmount,
      tx.referenceId,
    ];
  }

  /// Formats borrower loan share into loan sheet (9 columns):
  /// Date | Borrower | Narration | Invoice No. | Transaction Type | Account | Given Amount | Received Amount | Reference
  List<dynamic> formatLoanRow(FinanceTransaction tx, SplitRecipient borrower, [int? index]) {
    final dateFormatted = DateFormat('dd/MMM/yyyy').format(tx.date);

    String transactionType = '';
    final types = tx.breakdowns
        .map((b) => b.paymentType ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();
    transactionType = types.isNotEmpty ? types.join(', ') : tx.flow;

    final account = tx.fromSummary;

    dynamic givenAmount = '';
    dynamic receivedAmount = '';

    final flowLower = tx.flow.toLowerCase();
    if (flowLower.contains('deposit') || flowLower.contains('income') || tx.purpose.toLowerCase().contains('received')) {
      receivedAmount = borrower.amount;
    } else {
      givenAmount = borrower.amount;
    }

    return [
      dateFormatted,
      borrower.name,
      tx.narration,
      tx.invoice,
      transactionType,
      account,
      givenAmount,
      receivedAmount,
      tx.referenceId,
    ];
  }

  /// Formats Cash Entries row: Date | 500 | 200 | 100 | 50 | 20 | 10 | 5 | 2 | 1 | Reference ID
  /// Denominations are multiplied with negative sign for outflow (withdraw), else positive sign.
  List<dynamic> formatCashEntryRow({
    required FinanceTransaction tx,
    required PaymentBreakdown breakdown,
    required bool isOutflow,
    String? customNarration,
    String? suffix,
  }) {
    final dateFormatted = DateFormat('dd-MMM-yy').format(tx.date);

    final d = breakdown.denominations;
    final sign = isOutflow ? -1 : 1;
    final c500 = (d[500] ?? 0) * sign;
    final c200 = (d[200] ?? 0) * sign;
    final c100 = (d[100] ?? 0) * sign;
    final c50 = (d[50] ?? 0) * sign;
    final c20 = (d[20] ?? 0) * sign;
    final c10 = (d[10] ?? 0) * sign;
    final c5 = (d[5] ?? 0) * sign;
    final c2 = (d[2] ?? 0) * sign;
    final c1 = (d[1] ?? 0) * sign;

    // Strictly save pure reference ID with NO suffixes anywhere
    final ref = tx.referenceId;

    return [
      dateFormatted,
      c500,
      c200,
      c100,
      c50,
      c20,
      c10,
      c5,
      c2,
      c1,
      ref,
    ];
  }

  /// Formats Credit entry row (6 columns):
  /// Date | Narration | Account | Deposited Amount | Withdrawn Amount | Reference ID
  List<dynamic> formatCreditRow({
    required FinanceTransaction tx,
    required PaymentBreakdown breakdown,
    required bool isWithdrawal,
    String? customNarration,
    String? suffix,
  }) {
    final dateFormatted = DateFormat('dd-MMM-yy').format(tx.date);
    final amt = breakdown.amount != 0.0 ? breakdown.amount : tx.totalAmount;
    final narration = customNarration ?? tx.narration;
    final ref = tx.referenceId;
    final acc = breakdown.effectiveAccount.isNotEmpty && breakdown.effectiveAccount != 'None'
        ? breakdown.effectiveAccount
        : (tx.fromSummary.isNotEmpty && tx.fromSummary != 'None' ? tx.fromSummary : 'Credit Card');

    return [
      dateFormatted,
      narration,
      acc,
      !isWithdrawal ? amt : '', // Deposited Amount
      isWithdrawal ? amt : '',  // Withdrawn Amount
      ref,                      // Reference ID
    ];
  }

  /// Parses a 10-column row from Google Sheets into a FinanceTransaction.
  FinanceTransaction? parseRowToTransaction(List<dynamic> row) {
    if (row.isEmpty) return null;
    final dateStr = row.isNotEmpty ? row[0]?.toString() ?? '' : '';
    final narration = row.length > 1 ? row[1]?.toString() ?? '' : '';
    final invoice = row.length > 2 ? row[2]?.toString() ?? '' : '';
    final purpose = row.length > 3 ? row[3]?.toString() ?? '' : '';
    final spentFor = row.length > 4 ? row[4]?.toString() ?? '' : '';
    final transactionType = row.length > 5 ? row[5]?.toString() ?? '' : '';
    final fromTo = row.length > 6 ? row[6]?.toString() ?? '' : '';
    final withdrawnStr = row.length > 7 ? row[7]?.toString() ?? '' : '';
    final depositStr = row.length > 8 ? row[8]?.toString() ?? '' : '';
    final referenceId = row.length > 9 ? row[9]?.toString() ?? '' : '';

    DateTime date = DateTime.now();
    if (dateStr.isNotEmpty) {
      date = parseDateSafe(dateStr);
    }

    double withdrawn = parseDoubleSafe(withdrawnStr);
    double deposit = parseDoubleSafe(depositStr);

    final isTransfer = transactionType.toLowerCase().contains('transfer') || fromTo.contains('->');
    final flow = isTransfer
        ? 'Transfer'
        : (deposit > 0 && withdrawn <= 0 ? 'Deposit' : 'Withdraw');
    final totalAmount = isTransfer
        ? (withdrawn != 0.0 ? withdrawn : deposit)
        : (flow == 'Deposit' ? deposit : withdrawn);

    List<PaymentBreakdown> breakdowns = [];
    List<PaymentBreakdown>? toBreakdowns;

    if (isTransfer) {
      final parts = fromTo.split('->').map((s) => s.trim()).toList();
      final fromAcc = parts.isNotEmpty ? parts[0] : '';
      final toAcc = parts.length > 1 ? parts[1] : '';

      breakdowns.add(PaymentBreakdown(
        paymentType: 'UPI',
        account: fromAcc,
        amount: totalAmount,
      ));
      toBreakdowns = [
        PaymentBreakdown(
          paymentType: 'Credit',
          account: toAcc,
          amount: totalAmount,
        )
      ];
    } else {
      breakdowns.add(PaymentBreakdown(
        paymentType: transactionType.isNotEmpty ? transactionType : (flow == 'Withdraw' ? 'UPI' : 'Account'),
        account: fromTo,
        amount: totalAmount,
      ));
    }

    return FinanceTransaction(
      id: referenceId.isNotEmpty ? referenceId : UniqueKey().toString(),
      date: date,
      referenceId: referenceId,
      narration: narration,
      flow: flow,
      invoice: invoice,
      purpose: purpose,
      spentFor: spentFor,
      breakdowns: breakdowns,
      totalAmount: totalAmount,
      isSelfTransfer: isTransfer,
      toBreakdowns: toBreakdowns,
    );
  }

  // =========================================================================
  // REFERENCE & ROW PARSING HELPERS
  // =========================================================================

  /// Strips sheet-specific sub-suffixes so related rows across sheets resolve to the same base reference.
  /// E.g., 'REF-20261119-ABCD-BORROWER-1' -> 'REF-20261119-ABCD'
  /// 'REF-20261119-ABCD-CASH-FROM' -> 'REF-20261119-ABCD'
  /// 'REF-20261119-ABCD-CREDIT' -> 'REF-20261119-ABCD'
  /// 'REF-20261119-ABCD-SELF' -> 'REF-20261119-ABCD'
  static String normalizeReferenceId(String? rawRef) {
    if (rawRef == null) return '';
    final trimmed = rawRef.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(
      RegExp(r'-(BORROWER(-\d+)?|CASH(-FROM|-TO)?|CREDIT(-FROM|-TO)?|FROM|TO|SELF)$', caseSensitive: false),
      '',
    );
  }

  /// Extracts reference ID from a row, prioritizing the expected column index
  /// and falling back to scanning for 'REF-' prefix.
  static String extractReference(List<dynamic> row, {int defaultIdx = -1}) {
    if (defaultIdx >= 0 && defaultIdx < row.length) {
      final val = row[defaultIdx]?.toString().trim() ?? '';
      if (val.isNotEmpty) return val;
    }
    for (final cell in row.reversed) {
      final str = cell?.toString().trim() ?? '';
      if (str.toUpperCase().startsWith('REF-') || str.toUpperCase().contains('REF-')) {
        return str;
      }
    }
    return '';
  }

  static final Map<String, int> _monthMap = {
    'jan': 1, 'january': 1,
    'feb': 2, 'february': 2,
    'mar': 3, 'march': 3,
    'apr': 4, 'april': 4,
    'may': 5,
    'jun': 6, 'june': 6,
    'jul': 7, 'july': 7,
    'aug': 8, 'august': 8,
    'sep': 9, 'september': 9, 'sept': 9,
    'oct': 10, 'october': 10,
    'nov': 11, 'november': 11,
    'dec': 12, 'december': 12,
  };

  static DateTime parseDateSafe(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return DateTime.now();
    final trimmed = dateStr.trim();

    // 1. Check numeric Google Sheets / Excel serial date (e.g. 45618 or 46348)
    final numVal = double.tryParse(trimmed);
    if (numVal != null && numVal > 30000 && numVal < 70000) {
      final base = DateTime(1899, 12, 30);
      final days = numVal.floor();
      final ms = ((numVal - days) * 86400000).round();
      return base.add(Duration(days: days, milliseconds: ms));
    }

    try {
      // 2. Check if string contains month names (e.g. 22/Nov/2026, 22-Nov-26, 22 Nov 2026, 22/Nov/0026)
      if (RegExp(r'[a-zA-Z]').hasMatch(trimmed)) {
        final tokens = trimmed.split(RegExp(r'[-/.\s,]+')).where((s) => s.isNotEmpty).toList();
        if (tokens.length >= 3) {
          int? day;
          int? month;
          int? year;

          for (final t in tokens) {
            final lower = t.toLowerCase();
            if (_monthMap.containsKey(lower)) {
              month = _monthMap[lower];
            } else {
              final n = int.tryParse(t);
              if (n != null) {
                if (day == null) {
                  day = n;
                } else {
                  year = n;
                }
              }
            }
          }

          if (day != null && month != null && year != null) {
            if (year < 100) {
              year = year < 70 ? year + 2000 : year + 1900;
            }
            return DateTime(year, month, day);
          }
        }
      }

      // 3. Pure numeric parts (e.g. 2026-11-22, 22/11/2026, 22-11-26, 22.11.26)
      final parts = trimmed.split(RegExp(r'[-/.\s,]+')).where((s) => s.isNotEmpty).toList();
      if (parts.length >= 3) {
        int year;
        int month;
        int day;

        if (parts[0].length == 4) {
          // YYYY-MM-DD
          year = int.parse(parts[0]);
          month = int.parse(parts[1]);
          day = int.parse(parts[2].split('T')[0]);
        } else {
          // DD-MM-YYYY or DD-MM-YY
          day = int.parse(parts[0]);
          month = int.parse(parts[1]);
          final rawYear = int.parse(parts[2].split('T')[0]);
          year = (rawYear < 100) ? (rawYear < 70 ? rawYear + 2000 : rawYear + 1900) : rawYear;
        }

        if (year < 100) {
          year = year < 70 ? year + 2000 : year + 1900;
        }
        return DateTime(year, month, day);
      }
    } catch (_) {}

    try {
      final dt = DateTime.parse(trimmed.replaceAll('/', '-'));
      return sanitizeDateYear(dt);
    } catch (_) {}

    return DateTime.now();
  }

  /// Safely parses a dynamic numeric value or string, preserving negative signs.
  /// Handles negative numbers like "-9.47", "(9.47)", "-₹9.47", "₹-9.47", and num objects.
  static double parseDoubleSafe(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    final s = val.toString().trim();
    if (s.isEmpty) return 0.0;
    final isNegative = s.contains('-') || (s.contains('(') && s.contains(')'));
    final cleaned = s.replaceAll(RegExp(r'[^\d.]'), '');
    final parsed = double.tryParse(cleaned) ?? 0.0;
    return isNegative ? -parsed : parsed;
  }

  bool _matchesSheetTitle(String rangeName, String title) {
    final cleanRange = rangeName.replaceAll("'", "").toLowerCase();
    final cleanTitle = title.replaceAll("'", "").toLowerCase();
    return cleanRange.startsWith('$cleanTitle!') || cleanRange.startsWith(cleanTitle);
  }

  Future<List<List<dynamic>>> _fetchSheetValues(String token, String sheetId, String range) async {
    try {
      final encodedRange = Uri.encodeComponent(range);
      final url = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$encodedRange');
      final res = await http.get(url, headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final raw = (data['values'] as List<dynamic>?) ?? [];
        return raw.whereType<List<dynamic>>().toList();
      }
    } catch (e) {
      debugPrint('Error fetching range $range: $e');
    }
    return [];
  }

  // =========================================================================
  // 1. FETCH TRANSACTIONS DIRECTLY FROM GOOGLE SHEETS (DEEP MULTI-SHEET MERGE)
  // =========================================================================
  Future<List<FinanceTransaction>> fetchTransactions({bool forceRefresh = false}) async {
    if (!forceRefresh && cachedTransactions != null) {
      return List<FinanceTransaction>.from(cachedTransactions!);
    }

    try {
      final token = await GoogleAuthService.instance.getAccessToken();
      if (token == null) {
        cachedTransactions ??= [];
        return List<FinanceTransaction>.from(cachedTransactions!);
      }

      final sheetId = await findOrCreateLedger(token);
      if (sheetId == null || sheetId.isEmpty) {
        cachedTransactions ??= [];
        return List<FinanceTransaction>.from(cachedTransactions!);
      }

      await _ensureAllSheetsAndHeaders(token, sheetId);

      List<List<dynamic>> txRows = [];
      List<List<dynamic>> cashRows = [];
      List<List<dynamic>> loanRows = [];
      List<List<dynamic>> monthlyRows = [];
      List<List<dynamic>> creditRows = [];
      List<List<dynamic>> selfTransferRows = [];

      final ranges = [
        "'$_txTitle'!A2:J",
        "'$_cashTitle'!A2:K",
        "'$_loanTitle'!A2:I",
        "'$_monthlyTitle'!A2:J",
        "'$_creditTitle'!A2:F",
        "'$_selfTransferTitle'!A2:H",
      ];
      final queryString = ranges.map((r) => 'ranges=${Uri.encodeQueryComponent(r)}').join('&');
      final batchUrl = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values:batchGet?$queryString');

      bool batchSuccess = false;
      try {
        final res = await http.get(
          batchUrl,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final valueRanges = (data['valueRanges'] as List<dynamic>?) ?? [];
          if (valueRanges.isNotEmpty) {
            batchSuccess = true;
            for (final vr in valueRanges) {
              if (vr is! Map<String, dynamic>) continue;
              final rangeName = vr['range']?.toString() ?? '';
              final values = ((vr['values'] as List<dynamic>?) ?? []).whereType<List<dynamic>>().toList();

              if (_matchesSheetTitle(rangeName, _txTitle)) {
                txRows = values;
              } else if (_matchesSheetTitle(rangeName, _cashTitle)) {
                cashRows = values;
              } else if (_matchesSheetTitle(rangeName, _loanTitle)) {
                loanRows = values;
              } else if (_matchesSheetTitle(rangeName, _monthlyTitle)) {
                monthlyRows = values;
              } else if (_matchesSheetTitle(rangeName, _creditTitle)) {
                creditRows = values;
              } else if (_matchesSheetTitle(rangeName, _selfTransferTitle)) {
                selfTransferRows = values;
              }
            }
          }
        } else {
          debugPrint('batchGet failed (${res.statusCode}): ${res.body}');
        }
      } catch (e) {
        debugPrint('batchGet exception: $e');
      }

      if (!batchSuccess) {
        // Fallback to parallel individual GET requests
        final fetched = await Future.wait([
          _fetchSheetValues(token, sheetId, "'$_txTitle'!A2:J"),
          _fetchSheetValues(token, sheetId, "'$_cashTitle'!A2:K"),
          _fetchSheetValues(token, sheetId, "'$_loanTitle'!A2:I"),
          _fetchSheetValues(token, sheetId, "'$_monthlyTitle'!A2:J"),
          _fetchSheetValues(token, sheetId, "'$_creditTitle'!A2:H"),
          _fetchSheetValues(token, sheetId, "'$_selfTransferTitle'!A2:H"),
        ]);
        txRows = fetched[0];
        cashRows = fetched[1];
        loanRows = fetched[2];
        monthlyRows = fetched[3];
        creditRows = fetched[4];
        selfTransferRows = fetched[5];
      }

      // =======================================================================
      // INDEX SECONDARY SHEETS BY NORMALIZED BASE REFERENCE ID
      // =======================================================================

      // 1. Index Cash Entries (matrix with bill counts)
      final Map<String, List<_ParsedCashEntry>> cashEntriesByRef = {};
      const denomList = [500, 200, 100, 50, 20, 10, 5, 2, 1];

      for (final r in cashRows) {
        if (r.isEmpty) continue;
        if (r[0]?.toString().toLowerCase() == 'date') continue;
        final rawRef = extractReference(r, defaultIdx: r.length <= 11 ? 10 : 15);
        final baseRef = normalizeReferenceId(rawRef);
        if (baseRef.isEmpty) continue;

        final date = parseDateSafe(r[0]?.toString());
        String narration = '';
        String invoice = '';
        String account = '';

        final Map<int, int> denoms = {
          500: 0, 200: 0, 100: 0, 50: 0, 20: 0, 10: 0, 5: 0, 2: 0, 1: 0,
        };

        if (r.length <= 11) {
          // 11-column format: Date | 500 | 200 | 100 | 50 | 20 | 10 | 5 | 2 | 1 | Reference ID
          for (int i = 0; i < denomList.length; i++) {
            final colIdx = 1 + i;
            if (r.length > colIdx) {
              final valStr = r[colIdx]?.toString() ?? '';
              final count = (double.tryParse(valStr.replaceAll(RegExp(r'[^\d.-]'), '')) ?? 0).toInt();
              denoms[denomList[i]] = count;
            }
          }
        } else {
          // Legacy 16-column format
          narration = r.length > 1 ? r[1]?.toString() ?? '' : '';
          invoice = r.length > 2 ? r[2]?.toString() ?? '' : '';
          account = r.length > 4 ? r[4]?.toString().trim() ?? '' : '';
          for (int i = 0; i < denomList.length; i++) {
            final colIdx = 5 + i;
            if (r.length > colIdx) {
              final valStr = r[colIdx]?.toString() ?? '';
              final count = (double.tryParse(valStr.replaceAll(RegExp(r'[^\d.-]'), '')) ?? 0).toInt();
              denoms[denomList[i]] = count;
            }
          }
        }

        double totalCash = 0.0;
        bool isOutflow = false;
        if (r.length > 14) {
          final amtVal = parseDoubleSafe(r[14]);
          isOutflow = amtVal < 0;
          totalCash = amtVal.abs();
        }
        if (totalCash == 0) {
          final signedTotal = denoms.entries.fold<double>(0.0, (sum, e) => sum + e.key * e.value);
          isOutflow = signedTotal < 0;
          totalCash = signedTotal.abs();
        }

        final Map<int, int> appDenoms = {};
        final readSign = isOutflow ? -1 : 1;
        denoms.forEach((k, v) {
          appDenoms[k] = v * readSign;
        });

        final upperRef = rawRef.toUpperCase();
        final narrationLower = narration.toLowerCase();
        final isTo = upperRef.endsWith('-TO') || upperRef.contains('CASH-TO') || narrationLower.contains('(to');
        final isFrom = upperRef.endsWith('-FROM') || upperRef.contains('CASH-FROM') || narrationLower.contains('(from') || isOutflow;

        cashEntriesByRef.putIfAbsent(baseRef, () => []).add(_ParsedCashEntry(
          rawRef: rawRef,
          baseRef: baseRef,
          narration: narration,
          invoice: invoice,
          account: account,
          amount: totalCash,
          isOutflow: isOutflow,
          isFrom: isFrom,
          isTo: isTo,
          denominations: appDenoms,
          date: date,
        ));
      }

      // 2. Index Loan Entries (borrowers & loan shares)
      final Map<String, List<SplitRecipient>> loansByRef = {};
      for (final r in loanRows) {
        if (r.isEmpty) continue;
        if (r[0]?.toString().toLowerCase() == 'date') continue;
        final rawRef = extractReference(r, defaultIdx: 8);
        final baseRef = normalizeReferenceId(rawRef);
        if (baseRef.isEmpty) continue;

        final borrowerName = r.length > 1 ? r[1]?.toString().trim() ?? '' : '';
        if (borrowerName.isEmpty || borrowerName.toLowerCase() == 'borrower') continue;

        final givenStr = r.length > 6 ? r[6]?.toString() ?? '' : '';
        final receivedStr = r.length > 7 ? r[7]?.toString() ?? '' : '';
        final givenAmt = parseDoubleSafe(givenStr);
        final receivedAmt = parseDoubleSafe(receivedStr);
        final amount = givenAmt != 0.0 ? givenAmt : receivedAmt;

        loansByRef.putIfAbsent(baseRef, () => []).add(SplitRecipient(
          name: borrowerName,
          amount: amount,
          isPersonal: false,
        ));
      }

      // 3. Index Monthly Transaction Personal Shares
      final Map<String, double> personalSharesByRef = {};
      for (final r in monthlyRows) {
        if (r.isEmpty) continue;
        if (r[0]?.toString().toLowerCase() == 'date') continue;
        final rawRef = extractReference(r, defaultIdx: 9);
        final baseRef = normalizeReferenceId(rawRef);
        if (baseRef.isEmpty) continue;

        final withdrawnStr = r.length > 7 ? r[7]?.toString() ?? '' : '';
        final depositStr = r.length > 8 ? r[8]?.toString() ?? '' : '';
        final withdrawn = parseDoubleSafe(withdrawnStr);
        final deposit = parseDoubleSafe(depositStr);
        final amount = withdrawn != 0.0 ? withdrawn : deposit;

        final upperRef = rawRef.toUpperCase();
        final spentFor = r.length > 4 ? r[4]?.toString().trim().toLowerCase() ?? '' : '';
        if (upperRef.endsWith('-SELF') || (loansByRef.containsKey(baseRef) && (spentFor == 'self' || spentFor.isEmpty))) {
          personalSharesByRef[baseRef] = amount;
        }
      }

      // 4. Index Credit Entries (liability records with exact card account names)
      final Map<String, List<_ParsedCreditEntry>> creditEntriesByRef = {};
      for (final r in creditRows) {
        if (r.isEmpty) continue;
        if (r[0]?.toString().toLowerCase() == 'date') continue;
        final rawRef = extractReference(r, defaultIdx: r.length >= 8 ? 7 : (r.length <= 6 ? 5 : 9));
        final baseRef = normalizeReferenceId(rawRef);
        if (baseRef.isEmpty) continue;

        final date = parseDateSafe(r[0]?.toString());
        String narration = '';
        String invoice = '';
        String purpose = '';
        String spentFor = '';
        String account = '';
        double amount = 0.0;
        bool isWithdrawal = false;

        if (r.length >= 8) {
          // 8-column format: Date | Narration | From Type | From Acccount | To Type | To Account | Amount | Reference ID
          narration = r.length > 1 ? r[1]?.toString() ?? '' : '';
          final fromType = r.length > 2 ? r[2]?.toString() ?? '' : '';
          final fromAcc = r.length > 3 ? r[3]?.toString().trim() ?? '' : '';
          final toAcc = r.length > 5 ? r[5]?.toString().trim() ?? '' : '';
          amount = parseDoubleSafe(r.length > 6 ? r[6]?.toString() : '0');
          account = fromAcc.isNotEmpty ? fromAcc : toAcc;
          isWithdrawal = fromType.toLowerCase().contains('credit') || fromType.toLowerCase().contains('card');
        } else if (r.length <= 6) {
          // 6-column format: Date | Narration | Account | Deposited Amount | Withdrawn Amount | Reference ID
          narration = r.length > 1 ? r[1]?.toString() ?? '' : '';
          account = r.length > 2 ? r[2]?.toString().trim() ?? '' : '';
          final depStr = r.length > 3 ? r[3]?.toString() ?? '' : '';
          final withStr = r.length > 4 ? r[4]?.toString() ?? '' : '';
          final deposit = parseDoubleSafe(depStr);
          final withdrawn = parseDoubleSafe(withStr);
          isWithdrawal = withdrawn != 0.0 || deposit == 0.0;
          amount = withdrawn != 0.0 ? withdrawn : deposit;
        } else {
          // Legacy 10-column format
          narration = r.length > 1 ? r[1]?.toString() ?? '' : '';
          invoice = r.length > 2 ? r[2]?.toString() ?? '' : '';
          purpose = r.length > 3 ? r[3]?.toString() ?? '' : '';
          spentFor = r.length > 4 ? r[4]?.toString() ?? '' : '';
          account = r.length > 6 ? r[6]?.toString().trim() ?? '' : '';
          final withdrawnStr = r.length > 7 ? r[7]?.toString() ?? '' : '';
          final depositStr = r.length > 8 ? r[8]?.toString() ?? '' : '';
          final withdrawn = parseDoubleSafe(withdrawnStr);
          final deposit = parseDoubleSafe(depositStr);
          isWithdrawal = deposit <= 0;
          amount = withdrawn != 0.0 ? withdrawn : deposit;
        }

        final upperRef = rawRef.toUpperCase();
        final narrationLower = narration.toLowerCase();
        final isTo = upperRef.endsWith('-TO') || upperRef.contains('CREDIT-TO') || narrationLower.contains('(to');
        final isFrom = upperRef.endsWith('-FROM') || upperRef.contains('CREDIT-FROM') || narrationLower.contains('(from') || isWithdrawal;

        creditEntriesByRef.putIfAbsent(baseRef, () => []).add(_ParsedCreditEntry(
          rawRef: rawRef,
          baseRef: baseRef,
          narration: narration,
          invoice: invoice,
          purpose: purpose,
          spentFor: spentFor,
          account: account,
          amount: amount,
          isWithdrawal: isWithdrawal,
          isFrom: isFrom,
          isTo: isTo,
          date: date,
        ));
      }

      // 5. Index Self Transfer Sheet Legs
      final Map<String, List<_ParsedTransferLeg>> selfTransfersByRef = {};
      for (final r in selfTransferRows) {
        if (r.isEmpty) continue;
        if (r[0]?.toString().toLowerCase() == 'date') continue;
        final rawRef = extractReference(r, defaultIdx: r.length >= 10 ? 9 : 7);
        final baseRef = normalizeReferenceId(rawRef);
        if (baseRef.isEmpty) continue;

        final date = parseDateSafe(r[0]?.toString());
        final narration = r.length > 1 ? r[1]?.toString() ?? '' : '';
        final narrationLower = narration.toLowerCase();

        String paymentType = '';
        String account = '';
        bool isWithdrawal = false;
        double amount = 0.0;

        if (r.length <= 8) {
          // 8-column format: Date | Narration | To Type | To Acccount | From Type | From Account | Amount | Reference ID
          final toType = r.length > 2 ? r[2]?.toString().trim() ?? '' : '';
          final toAcc = r.length > 3 ? r[3]?.toString().trim() ?? '' : '';
          final fromType = r.length > 4 ? r[4]?.toString().trim() ?? '' : '';
          final fromAcc = r.length > 5 ? r[5]?.toString().trim() ?? '' : '';
          amount = parseDoubleSafe(r.length > 6 ? r[6] : null);

          final hasFrom = fromType.isNotEmpty || fromAcc.isNotEmpty;
          final hasTo = toType.isNotEmpty || toAcc.isNotEmpty;

          if (narrationLower.contains('(from') || (hasFrom && !hasTo)) {
            isWithdrawal = true;
            paymentType = fromType.isNotEmpty ? fromType : toType;
            account = fromAcc.isNotEmpty ? fromAcc : toAcc;
          } else {
            isWithdrawal = false;
            paymentType = toType.isNotEmpty ? toType : fromType;
            account = toAcc.isNotEmpty ? toAcc : fromAcc;
          }
        } else {
          // Legacy 10-column format
          paymentType = r.length > 5 ? r[5]?.toString() ?? '' : '';
          account = r.length > 6 ? r[6]?.toString().trim() ?? '' : '';
          final withdrawnStr = r.length > 7 ? r[7]?.toString() ?? '' : '';
          final depositStr = r.length > 8 ? r[8]?.toString() ?? '' : '';
          final withdrawn = parseDoubleSafe(withdrawnStr);
          final deposit = parseDoubleSafe(depositStr);
          isWithdrawal = withdrawn > 0 || rawRef.toUpperCase().endsWith('-FROM') || narrationLower.contains('(from');
          amount = withdrawn != 0.0 ? withdrawn : deposit;
        }

        selfTransfersByRef.putIfAbsent(baseRef, () => []).add(_ParsedTransferLeg(
          rawRef: rawRef,
          baseRef: baseRef,
          narration: narration,
          invoice: '',
          account: account,
          paymentType: paymentType,
          amount: amount,
          isWithdrawal: isWithdrawal,
          date: date,
        ));
      }

      // =======================================================================
      // GROUP MASTER TRANSACTIONS ROWS & MERGE ACROSS ALL SHEETS
      // =======================================================================
      final Map<String, List<List<dynamic>>> txRowsByRef = {};
      final List<List<dynamic>> unreferencedRows = [];
      for (final r in txRows) {
        if (r.isEmpty) continue;
        if (r[0]?.toString().toLowerCase() == 'date') continue;
        final rawRef = extractReference(r, defaultIdx: 9);
        final baseRef = normalizeReferenceId(rawRef);
        if (baseRef.isNotEmpty) {
          txRowsByRef.putIfAbsent(baseRef, () => []).add(r);
        } else {
          unreferencedRows.add(r);
        }
      }

      final allRefs = <String>{
        ...txRowsByRef.keys,
        ...selfTransfersByRef.keys,
        ...cashEntriesByRef.keys,
        ...creditEntriesByRef.keys,
      };

      final List<FinanceTransaction> parsedList = [];

      for (final ref in allRefs) {
        final txRowsForRef = txRowsByRef[ref] ?? [];

        // Determine if this is a Self Transfer
        bool isSelfTransfer = selfTransfersByRef.containsKey(ref);
        if (!isSelfTransfer && txRowsForRef.isNotEmpty) {
          if (txRowsForRef.length >= 2) {
            final hasFrom = txRowsForRef.any((r) {
              final refStr = extractReference(r, defaultIdx: 9).toUpperCase();
              final narr = r.length > 1 ? r[1]?.toString().toLowerCase() ?? '' : '';
              final w = r.length > 7 ? parseDoubleSafe(r[7]) : 0.0;
              return refStr.endsWith('-FROM') || narr.contains('(from') || w > 0;
            });
            final hasTo = txRowsForRef.any((r) {
              final refStr = extractReference(r, defaultIdx: 9).toUpperCase();
              final narr = r.length > 1 ? r[1]?.toString().toLowerCase() ?? '' : '';
              final d = r.length > 8 ? parseDoubleSafe(r[8]) : 0.0;
              return refStr.endsWith('-TO') || narr.contains('(to') || d > 0;
            });
            if (hasFrom && hasTo) isSelfTransfer = true;
          }
          if (!isSelfTransfer) {
            final firstRow = txRowsForRef.first;
            final purpose = firstRow.length > 3 ? firstRow[3]?.toString().toLowerCase() ?? '' : '';
            final txType = firstRow.length > 5 ? firstRow[5]?.toString().toLowerCase() ?? '' : '';
            final fromTo = firstRow.length > 6 ? firstRow[6]?.toString() ?? '' : '';
            if (purpose.contains('self transfer') || txType.contains('transfer') || fromTo.contains('->')) {
              isSelfTransfer = true;
            }
          }
        }

        if (isSelfTransfer) {
          // -------------------------------------------------------------------
          // A. MERGE SELF TRANSFER (From & To legs, accounts, cash denoms)
          // -------------------------------------------------------------------
          DateTime date = DateTime.now();
          String narration = '';
          String invoice = '';
          double totalAmount = 0.0;
          String fromAcc = '';
          String toAcc = '';
          String fromPaymentType = 'Transfer';
          String toPaymentType = 'Transfer';

          if (txRowsForRef.isNotEmpty) {
            final fromRow = txRowsForRef.firstWhere(
              (r) {
                final refStr = extractReference(r, defaultIdx: 9).toUpperCase();
                final narr = r.length > 1 ? r[1]?.toString().toLowerCase() ?? '' : '';
                final w = r.length > 7 ? parseDoubleSafe(r[7]) : 0.0;
                return refStr.endsWith('-FROM') || narr.contains('(from') || w > 0;
              },
              orElse: () => txRowsForRef.first,
            );
            final toRow = txRowsForRef.firstWhere(
              (r) {
                final refStr = extractReference(r, defaultIdx: 9).toUpperCase();
                final narr = r.length > 1 ? r[1]?.toString().toLowerCase() ?? '' : '';
                final d = r.length > 8 ? parseDoubleSafe(r[8]) : 0.0;
                return refStr.endsWith('-TO') || narr.contains('(to') || d > 0;
              },
              orElse: () => txRowsForRef.last,
            );

            date = parseDateSafe(fromRow[0]?.toString());
            narration = fromRow.length > 1 ? fromRow[1]?.toString() ?? '' : '';
            invoice = fromRow.length > 2 ? fromRow[2]?.toString() ?? '' : '';

            final wStr = fromRow.length > 7 ? fromRow[7]?.toString() ?? '' : '';
            final dStr = toRow.length > 8 ? toRow[8]?.toString() ?? '' : '';
            final w = parseDoubleSafe(wStr);
            final d = parseDoubleSafe(dStr);
            totalAmount = w > 0 ? w : (d > 0 ? d : 0.0);

            final ft = fromRow.length > 6 ? fromRow[6]?.toString().trim() ?? '' : '';
            if (ft.contains('->')) {
              final parts = ft.split('->').map((s) => s.trim()).toList();
              fromAcc = parts.isNotEmpty ? parts[0] : '';
              toAcc = parts.length > 1 ? parts[1] : '';
            } else {
              fromAcc = ft;
              toAcc = toRow.length > 6 ? toRow[6]?.toString().trim() ?? '' : '';
            }

            fromPaymentType = fromRow.length > 5 ? fromRow[5]?.toString().trim() ?? 'Transfer' : 'Transfer';
            toPaymentType = toRow.length > 5 ? toRow[5]?.toString().trim() ?? 'Transfer' : 'Transfer';
          } else if (selfTransfersByRef.containsKey(ref)) {
            final legs = selfTransfersByRef[ref]!;
            final fromLeg = legs.firstWhere((l) => l.isWithdrawal, orElse: () => legs.first);
            final toLeg = legs.firstWhere((l) => !l.isWithdrawal, orElse: () => legs.last);

            date = fromLeg.date;
            narration = fromLeg.narration;
            invoice = fromLeg.invoice;
            totalAmount = fromLeg.amount > 0 ? fromLeg.amount : toLeg.amount;
            fromAcc = fromLeg.account;
            toAcc = toLeg.account;
            fromPaymentType = fromLeg.paymentType.isNotEmpty ? fromLeg.paymentType : 'Transfer';
            toPaymentType = toLeg.paymentType.isNotEmpty ? toLeg.paymentType : 'Transfer';
          }

          // Clean narration by removing " (From ...)" and " (To ...)"
          narration = narration.replaceAll(RegExp(r'\s*\((From|To)[^)]*\)', caseSensitive: false), '').trim();

          // Check Cash entries for FROM or TO
          Map<int, int>? fromDenoms;
          Map<int, int>? toDenoms;
          if (cashEntriesByRef.containsKey(ref)) {
            for (final c in cashEntriesByRef[ref]!) {
              if (c.isTo) {
                toPaymentType = 'Cash';
                toDenoms = c.denominations;
                if (c.account.isNotEmpty) toAcc = c.account;
              } else if (c.isFrom || c.isOutflow) {
                fromPaymentType = 'Cash';
                fromDenoms = c.denominations;
                if (c.account.isNotEmpty) fromAcc = c.account;
              } else {
                if (fromDenoms == null) {
                  fromPaymentType = 'Cash';
                  fromDenoms = c.denominations;
                  if (c.account.isNotEmpty) fromAcc = c.account;
                } else {
                  toPaymentType = 'Cash';
                  toDenoms = c.denominations;
                  if (c.account.isNotEmpty) toAcc = c.account;
                }
              }
            }
          }

          // Check Credit entries for FROM or TO
          if (creditEntriesByRef.containsKey(ref)) {
            for (final cr in creditEntriesByRef[ref]!) {
              if (cr.isTo) {
                toPaymentType = 'Credit';
                if (cr.account.isNotEmpty) toAcc = cr.account;
              } else {
                fromPaymentType = 'Credit';
                if (cr.account.isNotEmpty) fromAcc = cr.account;
              }
            }
          }

          final fromBreakdown = PaymentBreakdown(
            paymentType: fromPaymentType.isNotEmpty ? fromPaymentType : 'UPI',
            account: fromAcc,
            amount: totalAmount,
            denominations: fromDenoms,
          );
          final toBreakdown = PaymentBreakdown(
            paymentType: toPaymentType.isNotEmpty ? toPaymentType : 'Account',
            account: toAcc,
            amount: totalAmount,
            denominations: toDenoms,
          );

          parsedList.add(FinanceTransaction(
            id: ref,
            date: date,
            referenceId: ref,
            narration: narration,
            flow: 'Transfer',
            invoice: invoice,
            purpose: 'Self Transfer',
            spentFor: 'Self',
            breakdowns: [fromBreakdown],
            toBreakdowns: [toBreakdown],
            totalAmount: totalAmount,
            isSelfTransfer: true,
            isSplitMode: false,
          ));
        } else {
          // -------------------------------------------------------------------
          // B. MERGE STANDARD OR SPLIT TRANSACTION
          // -------------------------------------------------------------------
          DateTime date = DateTime.now();
          String narration = '';
          String invoice = '';
          String purpose = '';
          String spentFor = '';
          String txType = '';
          String fromTo = '';
          double totalAmount = 0.0;
          String flow = 'Withdraw';

          if (txRowsForRef.isNotEmpty) {
            final row = txRowsForRef.first;
            date = parseDateSafe(row[0]?.toString());
            narration = row.length > 1 ? row[1]?.toString() ?? '' : '';
            invoice = row.length > 2 ? row[2]?.toString() ?? '' : '';
            purpose = row.length > 3 ? row[3]?.toString() ?? '' : '';
            spentFor = row.length > 4 ? row[4]?.toString() ?? '' : '';
            txType = row.length > 5 ? row[5]?.toString() ?? '' : '';
            fromTo = row.length > 6 ? row[6]?.toString() ?? '' : '';

            double sumW = 0.0;
            double sumD = 0.0;
            for (final r in txRowsForRef) {
              sumW += parseDoubleSafe(r.length > 7 ? r[7] : null);
              sumD += parseDoubleSafe(r.length > 8 ? r[8] : null);
            }

            if (sumD > 0 && sumW <= 0) {
              flow = 'Deposit';
              totalAmount = sumD;
            } else {
              flow = 'Withdraw';
              totalAmount = sumW;
            }
          } else {
            // Reconstruct from secondary sheets
            if (cashEntriesByRef.containsKey(ref)) {
              final c = cashEntriesByRef[ref]!.first;
              date = c.date;
              narration = c.narration;
              invoice = c.invoice;
              totalAmount = c.amount;
              flow = c.isOutflow ? 'Withdraw' : 'Deposit';
              fromTo = c.account;
              txType = 'Cash';
            } else if (creditEntriesByRef.containsKey(ref)) {
              final cr = creditEntriesByRef[ref]!.first;
              date = cr.date;
              narration = cr.narration;
              invoice = cr.invoice;
              purpose = cr.purpose;
              spentFor = cr.spentFor;
              totalAmount = cr.amount;
              flow = cr.isWithdrawal ? 'Withdraw' : 'Deposit';
              fromTo = cr.account;
              txType = 'Credit';
            }
          }

          // Check Split / Loan integration
          final hasBorrowers = loansByRef.containsKey(ref) && loansByRef[ref]!.isNotEmpty;
          final isSplitMode = hasBorrowers || spentFor.trim().toLowerCase() == 'split';

          List<SplitRecipient>? splitRecipients;
          if (isSplitMode) {
            if (spentFor.trim().isEmpty || spentFor.trim().toLowerCase() == 'self') {
              spentFor = 'Split';
            }
            final borrowers = loansByRef[ref] ?? [];
            final borrowerSum = borrowers.fold<double>(0.0, (sum, b) => sum + b.amount);

            if (totalAmount == 0.0) {
              totalAmount = borrowerSum + (personalSharesByRef[ref] ?? 0.0);
            }

            double personalAmt = 0.0;
            if (personalSharesByRef.containsKey(ref)) {
              personalAmt = personalSharesByRef[ref]!;
            } else if (totalAmount > borrowerSum) {
              personalAmt = totalAmount - borrowerSum;
            } else if (borrowers.isEmpty) {
              personalAmt = totalAmount;
            }

            final allRecipients = <SplitRecipient>[];
            if (personalAmt > 0) {
              allRecipients.add(SplitRecipient(
                name: 'Personal Share',
                amount: personalAmt,
                isPersonal: true,
              ));
            }
            allRecipients.addAll(borrowers);

            for (final r in allRecipients) {
              r.percentage = totalAmount > 0
                  ? double.parse(((r.amount / totalAmount) * 100).toStringAsFixed(2))
                  : 0.0;
            }
            splitRecipients = allRecipients;
          }

          // Payment breakdowns (Cash / Credit / UPI / Multi-row)
          List<PaymentBreakdown> breakdowns = [];
          final cashEntries = cashEntriesByRef[ref] ?? [];
          final creditEntries = creditEntriesByRef[ref] ?? [];

          if (txRowsForRef.length > 1) {
            // Multiple payment breakdown rows in Full Statement (Source of Truth)
            for (final r in txRowsForRef) {
              final rTxType = r.length > 5 ? r[5]?.toString().trim() ?? '' : '';
              final rFromTo = r.length > 6 ? r[6]?.toString().trim() ?? '' : '';
              final rW = parseDoubleSafe(r.length > 7 ? r[7] : null);
              final rD = parseDoubleSafe(r.length > 8 ? r[8] : null);
              final rAmt = (rW != 0.0) ? rW : rD;

              Map<int, int> denoms = {500: 0, 200: 0, 100: 0, 50: 0, 20: 0, 10: 0, 5: 0, 2: 0, 1: 0};
              if (rTxType.toLowerCase().contains('cash') && cashEntries.isNotEmpty) {
                denoms = cashEntries.first.denominations;
              }

              breakdowns.add(PaymentBreakdown(
                paymentType: rTxType.isNotEmpty ? rTxType : (flow == 'Withdraw' ? 'UPI' : 'Account'),
                account: rFromTo,
                amount: rAmt,
                denominations: denoms,
              ));
            }
          } else if (cashEntries.isNotEmpty && creditEntries.isNotEmpty) {
            // Multi-payment mode: Cash + Credit (+ optional remainder)
            final cashEntry = cashEntries.first;
            final creditEntry = creditEntries.first;
            final cashAmt = cashEntry.amount > 0 ? cashEntry.amount : (totalAmount - creditEntry.amount);
            final creditAmt = creditEntry.amount > 0 ? creditEntry.amount : (totalAmount - cashAmt);

            final bCash = PaymentBreakdown(
              paymentType: 'Cash',
              account: cashEntry.account.isNotEmpty ? cashEntry.account : 'Cash Pool',
              amount: cashAmt,
              denominations: cashEntry.denominations,
            );
            final bCredit = PaymentBreakdown(
              paymentType: 'Credit',
              account: creditEntry.account.isNotEmpty ? creditEntry.account : 'Credit Card',
              amount: creditAmt,
            );
            breakdowns = [bCash, bCredit];

            final covered = cashAmt + creditAmt;
            if (totalAmount > covered + 0.01) {
              breakdowns.add(PaymentBreakdown(
                paymentType: txType.isNotEmpty ? txType : 'UPI',
                account: fromTo,
                amount: totalAmount - covered,
              ));
            }
          } else if (cashEntries.isNotEmpty) {
            final cashEntry = cashEntries.first;
            final cashAmt = cashEntry.amount;
            final cashAccount = cashEntry.account.isNotEmpty ? cashEntry.account : (fromTo.isNotEmpty ? fromTo : 'Cash Pool');

            if (cashAmt >= totalAmount || txType.toLowerCase().contains('cash') || fromTo.toLowerCase().contains('cash')) {
              breakdowns.add(PaymentBreakdown(
                paymentType: 'Cash',
                account: cashAccount,
                amount: totalAmount != 0.0 ? totalAmount : cashAmt,
                denominations: cashEntry.denominations,
              ));
            } else {
              breakdowns.add(PaymentBreakdown(
                paymentType: 'Cash',
                account: cashAccount,
                amount: cashAmt,
                denominations: cashEntry.denominations,
              ));
              final rem = totalAmount - cashAmt;
              if (rem > 0) {
                breakdowns.add(PaymentBreakdown(
                  paymentType: txType.isNotEmpty && !txType.toLowerCase().contains('cash') ? txType : 'UPI',
                  account: fromTo,
                  amount: rem,
                ));
              }
            }
          } else if (creditEntries.isNotEmpty) {
            final creditEntry = creditEntries.first;
            breakdowns.add(PaymentBreakdown(
              paymentType: 'Credit',
              account: creditEntry.account.isNotEmpty ? creditEntry.account : fromTo,
              amount: totalAmount != 0.0 ? totalAmount : creditEntry.amount,
            ));
          } else {
            // Standard single payment breakdown
            breakdowns.add(PaymentBreakdown(
              paymentType: txType.isNotEmpty ? txType : (flow == 'Withdraw' ? 'UPI' : 'Account'),
              account: fromTo,
              amount: totalAmount,
            ));
          }

          if (totalAmount == 0.0 && breakdowns.isNotEmpty) {
            totalAmount = breakdowns.fold<double>(0.0, (sum, b) => sum + b.amount);
          }

          parsedList.add(FinanceTransaction(
            id: ref,
            date: date,
            referenceId: ref,
            narration: narration,
            flow: flow,
            invoice: invoice,
            purpose: purpose,
            spentFor: spentFor,
            breakdowns: breakdowns,
            totalAmount: totalAmount,
            isSplitMode: isSplitMode,
            splitRecipients: splitRecipients,
            isSelfTransfer: false,
          ));
        }
      }

      // Add any unreferenced rows
      for (final r in unreferencedRows) {
        final tx = parseRowToTransaction(r);
        if (tx != null) {
          parsedList.add(tx);
        }
      }

      parsedList.sort((a, b) => b.date.compareTo(a.date));
      cachedTransactions = parsedList;
      syncStatusNotifier.value = 'Loaded ${parsedList.length} transactions merged from Google Sheet';
      return List<FinanceTransaction>.from(cachedTransactions!);
    } catch (e) {
      debugPrint('Fetch transactions exception: $e');
    }

    cachedTransactions ??= [];
    return List<FinanceTransaction>.from(cachedTransactions!);
  }

  /// Fetches all loan & borrower ledger entries from the 'loan' sheet, enriched
  /// with local transaction details and split borrower allocations.
  Future<List<LoanEntry>> fetchLoanEntries({bool forceRefresh = false}) async {
    if (!forceRefresh && cachedLoanEntries != null && cachedLoanEntries!.isNotEmpty) {
      return List<LoanEntry>.from(cachedLoanEntries!);
    }

    final localTxList = await StorageService.instance.getTransactions();
    final Map<String, FinanceTransaction> txByRef = {};
    for (final tx in localTxList) {
      if (tx.referenceId.isNotEmpty) {
        txByRef[normalizeReferenceId(tx.referenceId)] = tx;
      }
    }

    List<LoanEntry> entries = [];
    final token = await GoogleAuthService.instance.getAccessToken();
    String? sheetId;
    if (token != null) {
      sheetId = await findOrCreateLedger(token);
    }

    if (token != null && sheetId != null && sheetId.isNotEmpty) {
      try {
        if (!_sheetsEnsured) {
          await _ensureAllSheetsAndHeaders(token, sheetId);
        }
        final rows = await _fetchSheetValues(token, sheetId, "'$_loanTitle'!A2:I");
        for (int i = 0; i < rows.length; i++) {
          final r = rows[i];
          if (r.isEmpty) continue;
          if (r[0]?.toString().toLowerCase() == 'date') continue;

          final borrowerName = r.length > 1 ? r[1]?.toString().trim() ?? '' : '';
          if (borrowerName.isEmpty || borrowerName.toLowerCase() == 'borrower') continue;

          final dateStr = r[0]?.toString();
          final parsedDate = parseDateSafe(dateStr);
          final narration = r.length > 2 ? r[2]?.toString().trim() ?? '' : '';
          final invoice = r.length > 3 ? r[3]?.toString().trim() ?? '' : '';
          final txType = r.length > 4 ? r[4]?.toString().trim() ?? '' : '';
          final account = r.length > 5 ? r[5]?.toString().trim() ?? '' : '';

          final givenStr = r.length > 6 ? r[6]?.toString() ?? '' : '';
          final receivedStr = r.length > 7 ? r[7]?.toString() ?? '' : '';
          final givenAmt = parseDoubleSafe(givenStr);
          final receivedAmt = parseDoubleSafe(receivedStr);

          final rawRef = extractReference(r, defaultIdx: 8);
          final baseRef = normalizeReferenceId(rawRef);
          final parentTx = baseRef.isNotEmpty ? txByRef[baseRef] : null;

          entries.add(LoanEntry(
            id: 'loan_${i}_$baseRef',
            date: parsedDate,
            borrower: borrowerName,
            narration: narration,
            invoice: invoice,
            transactionType: txType,
            account: account,
            givenAmount: givenAmt,
            receivedAmount: receivedAmt,
            referenceId: baseRef.isNotEmpty ? baseRef : (parentTx?.referenceId ?? ''),
            parentTransaction: parentTx,
          ));
        }
      } catch (e) {
        debugPrint('Error fetching loan rows: $e');
      }
    }

    // Merge in any local split transactions that might not yet be in the sheet
    final existingRefBorrowers = entries.map((e) => '${e.referenceId}_${e.borrower.toLowerCase()}').toSet();
    for (final tx in localTxList) {
      if ((tx.isSplitMode || (tx.splitRecipients != null && tx.splitRecipients!.isNotEmpty)) && tx.splitRecipients != null) {
        for (final recipient in tx.splitRecipients!) {
          if (!recipient.isPersonal && recipient.amount > 0) {
            final key = '${tx.referenceId}_${recipient.name.toLowerCase()}';
            if (!existingRefBorrowers.contains(key)) {
              final isReceived = tx.flow.toLowerCase().contains('deposit') ||
                  tx.flow.toLowerCase().contains('income') ||
                  tx.purpose.toLowerCase().contains('received');
              entries.add(LoanEntry(
                id: 'local_${tx.id}_${recipient.name}',
                date: tx.date,
                borrower: recipient.name,
                narration: tx.narration,
                invoice: tx.invoice,
                transactionType: tx.breakdowns.map((b) => b.paymentType ?? '').where((s) => s.isNotEmpty).join(', '),
                account: tx.fromSummary,
                givenAmount: isReceived ? 0.0 : recipient.amount,
                receivedAmount: isReceived ? recipient.amount : 0.0,
                referenceId: tx.referenceId,
                parentTransaction: tx,
              ));
              existingRefBorrowers.add(key);
            }
          }
        }
      }
    }

    // Sort descending by date
    entries.sort((a, b) => b.date.compareTo(a.date));
    cachedLoanEntries = entries;
    await StorageService.instance.saveLocalLoanEntries(entries);
    return List<LoanEntry>.from(cachedLoanEntries!);
  }

  // =========================================================================
  // 2. SAVE OR UPDATE TRANSACTION DIRECTLY IN GOOGLE SHEETS
  // =========================================================================
  Future<bool> saveTransaction(FinanceTransaction tx) async {
    isSyncingNotifier.value = true;
    syncStatusNotifier.value = 'Saving transaction to Google Sheet...';

    // Update in-memory session state immediately
    cachedTransactions ??= [];
    cachedTransactions!.removeWhere((t) => t.id == tx.id || t.referenceId == tx.referenceId);
    cachedTransactions!.insert(0, tx);

    try {
      // 1. Try Web App if configured
      final webAppUrl = await getWebAppUrl();
      if (webAppUrl != null && webAppUrl.trim().isNotEmpty) {
        await _postToWebApp(webAppUrl.trim(), tx);
      }

      // 2. Google Sheets v4 API
      final token = await GoogleAuthService.instance.getAccessToken();
      if (token == null) {
        syncStatusNotifier.value = 'Saved in session. Sign in to sync live to Google Sheets.';
        isSyncingNotifier.value = false;
        return true;
      }

      final sheetId = await findOrCreateLedger(token);
      if (sheetId == null || sheetId.isEmpty) {
        syncStatusNotifier.value = 'Failed to initialize Google Sheet.';
        isSyncingNotifier.value = false;
        return false;
      }

      // -----------------------------------------------------------------------
      // PRE-STEP: Clean existing rows with this reference ID across ALL sheets
      // (ensures clean updates with no stale or duplicate records)
      // -----------------------------------------------------------------------
      final matchTargets = <String>{};
      if (tx.referenceId.isNotEmpty) matchTargets.add(tx.referenceId);
      if (tx.id.isNotEmpty) matchTargets.add(tx.id);

      if (matchTargets.isNotEmpty) {
        await _deleteMatchingRows(token: token, spreadsheetId: sheetId, sheetTitle: _txTitle, gid: _txGid, colLetter: 'J', targetsToMatch: matchTargets);
        await _deleteMatchingRows(token: token, spreadsheetId: sheetId, sheetTitle: _monthlyTitle, gid: _monthlyGid, colLetter: 'J', targetsToMatch: matchTargets);
        await _deleteMatchingRows(token: token, spreadsheetId: sheetId, sheetTitle: _selfTransferTitle, gid: _selfTransferGid, colLetter: 'H', targetsToMatch: matchTargets);
        await _deleteMatchingRows(token: token, spreadsheetId: sheetId, sheetTitle: _loanTitle, gid: _loanGid, colLetter: 'I', targetsToMatch: matchTargets);
        await _deleteMatchingRows(token: token, spreadsheetId: sheetId, sheetTitle: _cashTitle, gid: _cashGid, colLetter: 'K', targetsToMatch: matchTargets);
        await _deleteMatchingRows(token: token, spreadsheetId: sheetId, sheetTitle: _creditTitle, gid: _creditGid, colLetter: 'F', targetsToMatch: matchTargets);
      }

      final isSelfTransfer = tx.isSelfTransfer ||
          tx.flow == 'Transfer' ||
          tx.purpose.toLowerCase().contains('self transfer') ||
          tx.narration.contains('(From)') ||
          tx.narration.contains('(To)');

      final isSplit = !isSelfTransfer && (tx.isSplitMode || (tx.splitRecipients != null && tx.splitRecipients!.isNotEmpty));

      // =======================================================================
      // FLOW B: SELF TRANSFER (Internal Movement)
      // =======================================================================
      if (isSelfTransfer) {
        final fromAcc = tx.fromSummary;
        final toAcc = tx.toSummary;
        final fromPaymentType = tx.breakdowns.isNotEmpty ? (tx.breakdowns.first.paymentType ?? 'Transfer') : 'Transfer';
        final toPaymentType = (tx.toBreakdowns != null && tx.toBreakdowns!.isNotEmpty)
            ? (tx.toBreakdowns!.first.paymentType ?? 'Transfer')
            : 'Transfer';

        final fromLeg = formatTransferLegRow(
          tx: tx,
          isWithdrawal: true,
          account: fromAcc,
          paymentType: fromPaymentType,
        );
        final toLeg = formatTransferLegRow(
          tx: tx,
          isWithdrawal: false,
          account: toAcc,
          paymentType: toPaymentType,
        );

        // 1. Full Statement: Logs both withdrawal and deposit legs (10 columns)
        await _appendRows(token, sheetId, _txTitle, [fromLeg, toLeg]);

        // 2. Self Transfer Sheet: Logs legs formatted in 8 columns as per user request & Image 1
        final List<List<dynamic>> selfTransferSheetRows = [];
        if (tx.breakdowns.isNotEmpty) {
          for (final fb in tx.breakdowns) {
            selfTransferSheetRows.add(formatSelfTransferSheetRow(
              tx: tx,
              isWithdrawal: true,
              account: fb.effectiveAccount.isNotEmpty ? fb.effectiveAccount : fromAcc,
              paymentType: fb.paymentType ?? fromPaymentType,
              amount: fb.amount != 0.0 ? fb.amount : tx.totalAmount,
            ));
          }
        } else {
          selfTransferSheetRows.add(formatSelfTransferSheetRow(
            tx: tx,
            isWithdrawal: true,
            account: fromAcc,
            paymentType: fromPaymentType,
            amount: tx.totalAmount,
          ));
        }

        if (tx.toBreakdowns != null && tx.toBreakdowns!.isNotEmpty) {
          for (final tb in tx.toBreakdowns!) {
            selfTransferSheetRows.add(formatSelfTransferSheetRow(
              tx: tx,
              isWithdrawal: false,
              account: tb.effectiveAccount.isNotEmpty ? tb.effectiveAccount : toAcc,
              paymentType: tb.paymentType ?? toPaymentType,
              amount: tb.amount != 0.0 ? tb.amount : tx.totalAmount,
            ));
          }
        } else {
          selfTransferSheetRows.add(formatSelfTransferSheetRow(
            tx: tx,
            isWithdrawal: false,
            account: toAcc,
            paymentType: toPaymentType,
            amount: tx.totalAmount,
          ));
        }

        await _appendRows(token, sheetId, _selfTransferTitle, selfTransferSheetRows);

        // NOTE: Strictly bypasses "Monthly Transaction" sheet so internal transfers don't inflate P&L!

        // Sub-flow: Cash Matrix for Self-Transfer
        for (final b in tx.breakdowns) {
          if (_isCashWithDenominations(b)) {
            final cashRow = formatCashEntryRow(
              tx: tx,
              breakdown: b,
              isOutflow: true,
              customNarration: '${tx.narration} (From)',
            );
            await _appendRows(token, sheetId, _cashTitle, [cashRow]);
          }
        }
        if (tx.toBreakdowns != null) {
          for (final b in tx.toBreakdowns!) {
            if (_isCashWithDenominations(b)) {
              final cashRow = formatCashEntryRow(
                tx: tx,
                breakdown: b,
                isOutflow: false,
                customNarration: '${tx.narration} (To)',
              );
              await _appendRows(token, sheetId, _cashTitle, [cashRow]);
            }
          }
        }

        // Sub-flow: Credit sheet for Self-Transfer
        bool creditLogged = false;
        for (final b in tx.breakdowns) {
          if (_isCreditAccount(b, tx)) {
            final creditRow = formatCreditRow(
              tx: tx,
              breakdown: b,
              isWithdrawal: true,
              customNarration: '${tx.narration} (From)',
            );
            debugPrint('Logging to Credit sheet ($_creditTitle): $creditRow');
            await _appendRows(token, sheetId, _creditTitle, [creditRow]);
            creditLogged = true;
          }
        }
        if (tx.toBreakdowns != null) {
          for (final b in tx.toBreakdowns!) {
            if (_isCreditAccount(b, tx)) {
              final creditRow = formatCreditRow(
                tx: tx,
                breakdown: b,
                isWithdrawal: false,
                customNarration: '${tx.narration} (To)',
              );
              debugPrint('Logging to Credit sheet ($_creditTitle): $creditRow');
              await _appendRows(token, sheetId, _creditTitle, [creditRow]);
              creditLogged = true;
            }
          }
        }
        if (!creditLogged && _isCreditSummary(tx)) {
          final fromLower = tx.fromSummary.toLowerCase().trim();
          final toLower = tx.toSummary.toLowerCase().trim();
          final isFromCard = fromLower.contains('card') || fromLower.contains('credit') || fromLower.contains('cc');
          final isToCard = toLower.contains('card') || toLower.contains('credit') || toLower.contains('cc');
          if (isFromCard) {
            final fb = PaymentBreakdown(paymentType: 'Credit Card', account: tx.fromSummary, amount: tx.totalAmount);
            final creditRow = formatCreditRow(tx: tx, breakdown: fb, isWithdrawal: true, customNarration: '${tx.narration} (From)');
            await _appendRows(token, sheetId, _creditTitle, [creditRow]);
          }
          if (isToCard) {
            final fb = PaymentBreakdown(paymentType: 'Credit Card', account: tx.toSummary, amount: tx.totalAmount);
            final creditRow = formatCreditRow(tx: tx, breakdown: fb, isWithdrawal: false, customNarration: '${tx.narration} (To)');
            await _appendRows(token, sheetId, _creditTitle, [creditRow]);
          }
        }

        // Sub-flow: Automated Billing Updates
        if (tx.narration.toLowerCase().contains('cleared card bill')) {
          await _updateBillingSheet(token, sheetId, tx);
        }
      }

      // =======================================================================
      // FLOW C: SPLIT BILL / LOAN
      // =======================================================================
      else if (isSplit) {
        final List<List<dynamic>> rowsToAppend = [];
        if (tx.breakdowns.length > 1) {
          for (final b in tx.breakdowns) {
            rowsToAppend.add(formatTransactionBreakdownRow(tx, b));
          }
        } else {
          rowsToAppend.add(formatTransactionRow(tx));
        }

        // 1. Full Statement: Logs full payment details
        await _appendRows(token, sheetId, _txTitle, rowsToAppend);

        // 2. Monthly Transaction: Logs ONLY personal share amount
        final personalShare = _findPersonalShare(tx.splitRecipients);
        if (personalShare != null && personalShare.amount > 0) {
          final monthlyRow = formatMonthlyTransactionRow(tx, personalShare);
          await _appendRows(token, sheetId, _monthlyTitle, [monthlyRow]);
        }

        // 3. Loan Sheet: Loops through recipients and logs a row for each borrower
        final borrowers = tx.splitRecipients!
            .where((r) => !r.isPersonal && r.name.trim().toLowerCase() != 'personal share' && r.amount > 0)
            .toList();

        if (borrowers.isNotEmpty) {
          final loanRows = <List<dynamic>>[];
          for (int i = 0; i < borrowers.length; i++) {
            loanRows.add(formatLoanRow(tx, borrowers[i], i + 1));
          }
          await _appendRows(token, sheetId, _loanTitle, loanRows);
        }

        // Sub-flow: Cash Matrix for Split Bill
        for (final b in tx.breakdowns) {
          if (_isCashWithDenominations(b)) {
            final isOutflow = !tx.flow.toLowerCase().contains('deposit');
            final cashRow = formatCashEntryRow(tx: tx, breakdown: b, isOutflow: isOutflow);
            await _appendRows(token, sheetId, _cashTitle, [cashRow]);
          }
        }

        // Sub-flow: Credit sheet for Split Bill
        bool creditLogged = false;
        for (final b in tx.breakdowns) {
          if (_isCreditAccount(b, tx)) {
            final isWithdrawal = !tx.flow.toLowerCase().contains('deposit');
            final creditRow = formatCreditRow(tx: tx, breakdown: b, isWithdrawal: isWithdrawal);
            debugPrint('Logging to Credit sheet ($_creditTitle): $creditRow');
            await _appendRows(token, sheetId, _creditTitle, [creditRow]);
            creditLogged = true;
          }
        }
        if (!creditLogged && _isCreditSummary(tx)) {
          final isWithdrawal = !tx.flow.toLowerCase().contains('deposit');
          final fallbackBreakdown = PaymentBreakdown(
            paymentType: 'Credit Card',
            account: tx.fromSummary,
            amount: tx.totalAmount,
          );
          final creditRow = formatCreditRow(tx: tx, breakdown: fallbackBreakdown, isWithdrawal: isWithdrawal);
          debugPrint('Logging to Credit sheet via summary fallback ($_creditTitle): $creditRow');
          await _appendRows(token, sheetId, _creditTitle, [creditRow]);
        }
      }

      // =======================================================================
      // FLOW A: STANDARD EXPENSE OR INCOME
      // =======================================================================
      else {
        final List<List<dynamic>> rowsToAppend = [];
        if (tx.breakdowns.length > 1) {
          for (final b in tx.breakdowns) {
            rowsToAppend.add(formatTransactionBreakdownRow(tx, b));
          }
        } else {
          rowsToAppend.add(formatTransactionRow(tx));
        }

        // 1. Full Statement: Logs complete transaction details
        await _appendRows(token, sheetId, _txTitle, rowsToAppend);

        // 2. Monthly Transaction: Logs complete transaction details (personal P&L)
        await _appendRows(token, sheetId, _monthlyTitle, rowsToAppend);

        // Sub-flow: Cash Matrix for Standard Transaction
        for (final b in tx.breakdowns) {
          if (_isCashWithDenominations(b)) {
            final isOutflow = !tx.flow.toLowerCase().contains('deposit');
            final cashRow = formatCashEntryRow(tx: tx, breakdown: b, isOutflow: isOutflow);
            await _appendRows(token, sheetId, _cashTitle, [cashRow]);
          }
        }

        // Sub-flow: Credit sheet for Standard Transaction
        bool creditLogged = false;
        for (final b in tx.breakdowns) {
          if (_isCreditAccount(b, tx)) {
            final isWithdrawal = !tx.flow.toLowerCase().contains('deposit');
            final creditRow = formatCreditRow(tx: tx, breakdown: b, isWithdrawal: isWithdrawal);
            debugPrint('Logging to Credit sheet ($_creditTitle): $creditRow');
            await _appendRows(token, sheetId, _creditTitle, [creditRow]);
            creditLogged = true;
          }
        }
        if (!creditLogged && _isCreditSummary(tx)) {
          final isWithdrawal = !tx.flow.toLowerCase().contains('deposit');
          final fallbackBreakdown = PaymentBreakdown(
            paymentType: 'Credit Card',
            account: tx.fromSummary,
            amount: tx.totalAmount,
          );
          final creditRow = formatCreditRow(tx: tx, breakdown: fallbackBreakdown, isWithdrawal: isWithdrawal);
          debugPrint('Logging to Credit sheet via summary fallback ($_creditTitle): $creditRow');
          await _appendRows(token, sheetId, _creditTitle, [creditRow]);
        }

        // Sub-flow: Automated Billing Updates
        if (tx.narration.toLowerCase().contains('cleared card bill')) {
          await _updateBillingSheet(token, sheetId, tx);
        }
      }

      syncStatusNotifier.value = 'Saved directly to Google Sheets';
      return true;
    } catch (e) {
      debugPrint('Save transaction to Google Sheets error: $e');
      syncStatusNotifier.value = 'Error saving to Google Sheet: $e';
    } finally {
      isSyncingNotifier.value = false;
    }
    return false;
  }

  // =========================================================================
  // 3. DELETE TRANSACTION DIRECTLY FROM GOOGLE SHEETS
  // =========================================================================
  Future<bool> deleteTransaction(String idOrReference, {String? referenceId}) async {
    isSyncingNotifier.value = true;
    syncStatusNotifier.value = 'Deleting transaction from Google Sheet...';

    final targets = <String>{};
    if (idOrReference.trim().isNotEmpty) targets.add(idOrReference.trim());
    if (referenceId != null && referenceId.trim().isNotEmpty) targets.add(referenceId.trim());

    // Remove from in-memory session cache immediately
    cachedTransactions?.removeWhere((t) =>
      targets.contains(t.id) || targets.contains(t.referenceId)
    );

    try {
      // 1. Post to Web App if configured
      final webAppUrl = await getWebAppUrl();
      if (webAppUrl != null && webAppUrl.trim().isNotEmpty) {
        for (final ref in targets) {
          await _postDeleteToWebApp(webAppUrl.trim(), ref);
        }
      }

      final token = await GoogleAuthService.instance.getAccessToken();
      if (token == null) {
        isSyncingNotifier.value = false;
        return true;
      }

      var sheetId = await getSpreadsheetId();
      if (sheetId == null || sheetId.isEmpty) {
        sheetId = await findOrCreateLedger(token);
        if (sheetId == null || sheetId.isEmpty) {
          isSyncingNotifier.value = false;
          return false;
        }
      }

      await _ensureAllSheetsAndHeaders(token, sheetId);

      // Clean rows across all 6 data log sheets
      await _deleteMatchingRows(token: token, spreadsheetId: sheetId, sheetTitle: _txTitle, gid: _txGid, colLetter: 'J', targetsToMatch: targets);
      await _deleteMatchingRows(token: token, spreadsheetId: sheetId, sheetTitle: _monthlyTitle, gid: _monthlyGid, colLetter: 'J', targetsToMatch: targets);
      await _deleteMatchingRows(token: token, spreadsheetId: sheetId, sheetTitle: _selfTransferTitle, gid: _selfTransferGid, colLetter: 'H', targetsToMatch: targets);
      await _deleteMatchingRows(token: token, spreadsheetId: sheetId, sheetTitle: _loanTitle, gid: _loanGid, colLetter: 'I', targetsToMatch: targets);
      await _deleteMatchingRows(token: token, spreadsheetId: sheetId, sheetTitle: _cashTitle, gid: _cashGid, colLetter: 'K', targetsToMatch: targets);
      await _deleteMatchingRows(token: token, spreadsheetId: sheetId, sheetTitle: _creditTitle, gid: _creditGid, colLetter: 'F', targetsToMatch: targets);

      syncStatusNotifier.value = 'Deleted from Google Sheet';
      return true;
    } catch (e) {
      debugPrint('Delete transaction exception: $e');
      syncStatusNotifier.value = 'Error deleting from Google Sheet: $e';
    } finally {
      isSyncingNotifier.value = false;
    }
    return false;
  }

  Future<bool> _postDeleteToWebApp(String webAppUrl, String reference) async {
    try {
      final res = await http.post(
        Uri.parse(webAppUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'delete',
          'reference': reference,
        }),
      );
      return res.statusCode == 200 || res.statusCode == 302;
    } catch (_) {
      return false;
    }
  }

  // =========================================================================
  // SUB-FLOW HELPERS
  // =========================================================================

  bool _isCashWithDenominations(PaymentBreakdown b) {
    final isCash = (b.paymentType?.toUpperCase() == 'CASH') ||
        b.effectiveAccount.toLowerCase().contains('cash');
    final hasDenoms = b.denominations.values.any((count) => count != 0);
    return isCash && hasDenoms;
  }

  bool _isCreditAccount(PaymentBreakdown b, [FinanceTransaction? tx]) {
    final typeUpper = (b.paymentType ?? '').toUpperCase().trim();
    final accLower = b.effectiveAccount.toLowerCase().trim();
    if (typeUpper.contains('CREDIT') || typeUpper == 'CC' || (typeUpper.contains('CARD') && !typeUpper.contains('DEBIT'))) {
      return true;
    }
    if (accLower.contains('card') || accLower.contains('credit') || accLower.contains('cc')) {
      return true;
    }
    final defaultCards = StorageService.defaultCategoryAccounts['Credit Cards'] ?? [];
    for (final card in defaultCards) {
      if (card.trim().isNotEmpty && accLower.contains(card.trim().toLowerCase())) return true;
    }
    if (tx != null && tx.isSelfTransfer) {
      final toSummaryLower = tx.toSummary.toLowerCase().trim();
      if (toSummaryLower.contains('card') || toSummaryLower.contains('credit') || toSummaryLower.contains('cc')) return true;
      for (final card in defaultCards) {
        if (card.trim().isNotEmpty && toSummaryLower.contains(card.trim().toLowerCase())) return true;
      }
    }
    return false;
  }

  bool _isCreditSummary(FinanceTransaction tx) {
    final fromLower = tx.fromSummary.toLowerCase().trim();
    final toLower = tx.toSummary.toLowerCase().trim();
    final purposeLower = tx.purpose.toLowerCase().trim();
    final narrationLower = tx.narration.toLowerCase().trim();
    if (fromLower.contains('card') || fromLower.contains('credit') || fromLower.contains('cc')) return true;
    if (toLower.contains('card') || toLower.contains('credit') || toLower.contains('cc')) return true;
    if (purposeLower.contains('card') || purposeLower.contains('credit')) return true;
    if (narrationLower.contains('credit card') || narrationLower.contains('card bill')) return true;
    final defaultCards = StorageService.defaultCategoryAccounts['Credit Cards'] ?? [];
    for (final card in defaultCards) {
      final cLower = card.trim().toLowerCase();
      if (cLower.isNotEmpty && (fromLower.contains(cLower) || toLower.contains(cLower))) return true;
    }
    return false;
  }

  /// Automated Billing Updates:
  /// Matches Account name and Amount in Billing sheet, marks status as Paid,
  /// logs payment date, and advances Bill Date & Due Date forward by 1 month.
  Future<void> _updateBillingSheet(String token, String sheetId, FinanceTransaction tx) async {
    try {
      final billingUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/\'$_billingTitle\'!A2:G',
      );
      final res = await http.get(billingUrl, headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body);
      final rows = (data['values'] as List<dynamic>?) ?? [];
      if (rows.isEmpty) return;

      final targetAccount = tx.toSummary.isNotEmpty && tx.toSummary != 'None'
          ? tx.toSummary.toLowerCase()
          : tx.fromSummary.toLowerCase();
      final targetAmount = tx.totalAmount;

      for (int i = 0; i < rows.length; i++) {
        final r = rows[i];
        if (r is! List || r.isEmpty) continue;

        final acc = r[0]?.toString().toLowerCase() ?? '';
        final billDateStr = r.length > 1 ? r[1]?.toString() ?? '' : '';
        final dueDateStr = r.length > 2 ? r[2]?.toString() ?? '' : '';
        final amtStr = r.length > 3 ? r[3]?.toString() ?? '' : '';
        final amt = parseDoubleSafe(amtStr);

        final matchesAcc = acc.isNotEmpty && (acc.contains(targetAccount) || targetAccount.contains(acc));
        final matchesAmt = (amt - targetAmount).abs() < 1.0;

        if (matchesAcc && matchesAmt) {
          final rowNumber = i + 2; // 1-based, header is row 1
          final paidDateFormatted = DateFormat('dd/MMM/yyyy').format(tx.date);

          // Advance Bill Date & Due Date by 1 month
          final newBillDate = _advanceDateOneMonth(billDateStr);
          final newDueDate = _advanceDateOneMonth(dueDateStr);

          final updatedRow = [
            r[0],
            newBillDate,
            newDueDate,
            r.length > 3 ? r[3] : targetAmount,
            'Paid',
            paidDateFormatted,
            tx.referenceId,
          ];

          final putUrl = Uri.parse(
            'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/\'$_billingTitle\'!A$rowNumber:G$rowNumber?valueInputOption=USER_ENTERED',
          );
          await http.put(
            putUrl,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'values': [updatedRow]}),
          );
          debugPrint('Billing sheet row $rowNumber updated to Paid & advanced 1 month.');
          break;
        }
      }
    } catch (e) {
      debugPrint('Error updating Billing sheet: $e');
    }
  }

  String _advanceDateOneMonth(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final dt = parseDateSafe(dateStr);
      int year = dt.year;
      int month = dt.month + 1;
      if (month > 12) {
        month = 1;
        year += 1;
      }
      int maxDay = DateTime(year, month + 1, 0).day;
      int day = dt.day > maxDay ? maxDay : dt.day;
      return DateFormat('dd/MMM/yyyy').format(DateTime(year, month, day));
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _appendRows(String token, String sheetId, String title, List<List<dynamic>> rows) async {
    final encodedRange = Uri.encodeComponent("'$title'!A:A");
    final appendUrl = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$encodedRange:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS',
    );
    final res = await http.post(
      appendUrl,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'values': rows}),
    );
    if (res.statusCode != 200) {
      debugPrint('Append to $title failed (${res.statusCode}): ${res.body}');
    } else {
      debugPrint('Successfully appended ${rows.length} row(s) to $title');
    }
  }

  Future<void> _deleteMatchingRows({
    required String token,
    required String spreadsheetId,
    required String sheetTitle,
    required int gid,
    required String colLetter,
    required Set<String> targetsToMatch,
  }) async {
    try {
      final validTargets = targetsToMatch.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
      if (validTargets.isEmpty) return;

      final encodedCol = Uri.encodeComponent("'$sheetTitle'!$colLetter:$colLetter");
      final rangeUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/$encodedCol',
      );
      final res = await http.get(rangeUrl, headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body);
      final rows = (data['values'] as List<dynamic>?) ?? [];
      final matchingIndices = <int>[];

      for (int i = 0; i < rows.length; i++) {
        final r = rows[i];
        if (r is List && r.isNotEmpty) {
          final val = r[0].toString().trim();
          bool matches = false;
          for (final target in validTargets) {
            if (val == target || val.startsWith('$target-') || val.startsWith('$target/')) {
              matches = true;
              break;
            }
          }
          if (matches) {
            matchingIndices.add(i); // 0-based row index
          }
        }
      }

      if (matchingIndices.isEmpty) return;

      // Delete in descending order so earlier indices remain valid
      matchingIndices.sort((a, b) => b.compareTo(a));

      final requests = matchingIndices.map((idx) => {
        'deleteDimension': {
          'range': {
            'sheetId': gid,
            'dimension': 'ROWS',
            'startIndex': idx,
            'endIndex': idx + 1,
          }
        }
      }).toList();

      final deleteUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId:batchUpdate',
      );
      await http.post(
        deleteUrl,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'requests': requests}),
      );
    } catch (e) {
      debugPrint('Error deleting matching rows from $sheetTitle: $e');
    }
  }

  SplitRecipient? _findPersonalShare(List<SplitRecipient>? recipients) {
    if (recipients == null) return null;
    for (final r in recipients) {
      if (r.isPersonal || r.name.trim().toLowerCase() == 'personal share') {
        return r;
      }
    }
    return null;
  }

  bool _sheetsEnsured = false;

  /// Ensures that all 7 sheets exist and have correct headers.
  Future<void> _ensureAllSheetsAndHeaders(String token, String sheetId, {bool force = false}) async {
    if (_sheetsEnsured && !force) return;
    try {
      final metaUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId?fields=sheets.properties',
      );
      final metaRes = await http.get(metaUrl, headers: {'Authorization': 'Bearer $token'});

      bool hasTx = false;
      bool hasMonthly = false;
      bool hasSelfTransfer = false;
      bool hasLoan = false;
      bool hasCash = false;
      bool hasCredit = false;
      bool hasBilling = false;
      bool hasBalances = false;
      bool hasConfig = false;
      bool hasEmi = false;

      if (metaRes.statusCode == 200) {
        final metaData = jsonDecode(metaRes.body);
        final sheets = (metaData['sheets'] as List<dynamic>?) ?? [];

        // 1. Search specifically for "Full Statement" first for main transaction logs
        for (final s in sheets) {
          final props = s['properties'];
          if (props == null) continue;
          final title = props['title']?.toString() ?? '';
          final gid = props['sheetId'] as int? ?? 0;

          if (RegExp(r'^full\s*statement$', caseSensitive: false).hasMatch(title)) {
            hasTx = true;
            _txTitle = title;
            _txGid = gid;
            await setSheetGid(gid);
            break;
          }
        }

        // 2. Scan remaining sheets (and fallback to "Transactions" only if "Full Statement" absent)
        for (final s in sheets) {
          final props = s['properties'];
          if (props == null) continue;
          final title = props['title']?.toString() ?? '';
          final gid = props['sheetId'] as int? ?? 0;

          if (!hasTx && RegExp(r'^transactions?$', caseSensitive: false).hasMatch(title)) {
            hasTx = true;
            _txTitle = title;
            _txGid = gid;
            await setSheetGid(gid);
          } else if (RegExp(r'^monthly\s*transactions?$', caseSensitive: false).hasMatch(title)) {
            hasMonthly = true;
            _monthlyTitle = title;
            _monthlyGid = gid;
          } else if (RegExp(r'^self\s*transfers?$', caseSensitive: false).hasMatch(title)) {
            hasSelfTransfer = true;
            _selfTransferTitle = title;
            _selfTransferGid = gid;
          } else if (RegExp(r'^loans?$', caseSensitive: false).hasMatch(title)) {
            hasLoan = true;
            _loanTitle = title;
            _loanGid = gid;
          } else if (RegExp(r'^cash\s*(entries|matrix)?$', caseSensitive: false).hasMatch(title)) {
            hasCash = true;
            _cashTitle = title;
            _cashGid = gid;
          } else if (RegExp(r'^credit$', caseSensitive: false).hasMatch(title.trim())) {
            hasCredit = true;
            _creditTitle = title;
            _creditGid = gid;
          } else if (RegExp(r'^billings?$', caseSensitive: false).hasMatch(title)) {
            hasBilling = true;
            _billingTitle = title;
            _billingGid = gid;
          } else if (RegExp(r'^account\s*balances?$|^balances?$', caseSensitive: false).hasMatch(title)) {
            hasBalances = true;
            _balancesTitle = title;
            _balancesGid = gid;
          } else if (RegExp(r'^app\s*config|^masters?\s*(&|and)?\s*templates?', caseSensitive: false).hasMatch(title)) {
            hasConfig = true;
            _configTitle = title;
            _configGid = gid;
          } else if (RegExp(r'^active\s*emis?$|^emis?$', caseSensitive: false).hasMatch(title)) {
            hasEmi = true;
            _emiTitle = title;
            _emiGid = gid;
          }
        }
      }

      // Add missing sheets via batchUpdate
      final addRequests = <Map<String, dynamic>>[];
      if (!hasTx) {
        _txTitle = 'Full Statement';
        _txGid = 0;
        addRequests.add({'addSheet': {'properties': {'title': _txTitle, 'sheetId': _txGid}}});
      }
      if (!hasMonthly) {
        _monthlyTitle = 'Monthly Transaction';
        _monthlyGid = 1;
        addRequests.add({'addSheet': {'properties': {'title': _monthlyTitle, 'sheetId': _monthlyGid}}});
      }
      if (!hasSelfTransfer) {
        _selfTransferTitle = 'Self Transfer';
        _selfTransferGid = 2;
        addRequests.add({'addSheet': {'properties': {'title': _selfTransferTitle, 'sheetId': _selfTransferGid}}});
      }
      if (!hasLoan) {
        _loanTitle = 'Loan';
        _loanGid = 3;
        addRequests.add({'addSheet': {'properties': {'title': _loanTitle, 'sheetId': _loanGid}}});
      }
      if (!hasCash) {
        _cashTitle = 'Cash Entries';
        _cashGid = 4;
        addRequests.add({'addSheet': {'properties': {'title': _cashTitle, 'sheetId': _cashGid}}});
      }
      if (!hasCredit) {
        _creditTitle = 'Credit';
        _creditGid = 5;
        addRequests.add({'addSheet': {'properties': {'title': _creditTitle, 'sheetId': _creditGid}}});
      }
      if (!hasBilling) {
        _billingTitle = 'Billing';
        _billingGid = 6;
        addRequests.add({'addSheet': {'properties': {'title': _billingTitle, 'sheetId': _billingGid}}});
      }
      if (!hasBalances) {
        _balancesTitle = 'Account Balances';
        _balancesGid = 7;
        addRequests.add({'addSheet': {'properties': {'title': _balancesTitle, 'sheetId': _balancesGid}}});
      }
      if (!hasConfig) {
        _configTitle = 'App Config & Masters';
        _configGid = 8;
        addRequests.add({'addSheet': {'properties': {'title': _configTitle, 'sheetId': _configGid}}});
      }
      if (!hasEmi) {
        _emiTitle = 'Active_EMIs';
        _emiGid = 9;
        addRequests.add({'addSheet': {'properties': {'title': _emiTitle, 'sheetId': _emiGid}}});
      }

      if (addRequests.isNotEmpty) {
        final batchUrl = Uri.parse(
          'https://sheets.googleapis.com/v4/spreadsheets/$sheetId:batchUpdate',
        );
        final batchRes = await http.post(
          batchUrl,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'requests': addRequests}),
        );
        if (batchRes.statusCode == 200) {
          final batchData = jsonDecode(batchRes.body);
          final replies = (batchData['replies'] as List<dynamic>?) ?? [];
          for (final rep in replies) {
            final addedProps = rep['addSheet']?['properties'];
            if (addedProps != null) {
              final addedTitle = addedProps['title']?.toString() ?? '';
              final addedGid = addedProps['sheetId'] as int? ?? 0;
              if (addedTitle == _txTitle) _txGid = addedGid;
              if (addedTitle == _monthlyTitle) _monthlyGid = addedGid;
              if (addedTitle == _selfTransferTitle) _selfTransferGid = addedGid;
              if (addedTitle == _loanTitle) _loanGid = addedGid;
              if (addedTitle == _cashTitle) _cashGid = addedGid;
              if (addedTitle == _creditTitle) _creditGid = addedGid;
              if (addedTitle == _billingTitle) _billingGid = addedGid;
              if (addedTitle == _balancesTitle) _balancesGid = addedGid;
              if (addedTitle == _configTitle) _configGid = addedGid;
              if (addedTitle == _emiTitle) _emiGid = addedGid;
            }
          }
        }
      }

      // Update headers for all sheets
      await _writeHeaderIfEmpty(token, sheetId, _txTitle, 'A1:J1', requiredHeaders);
      await _writeHeaderIfEmpty(token, sheetId, _monthlyTitle, 'A1:J1', requiredMonthlyHeaders);
      await _writeHeaderIfEmpty(token, sheetId, _selfTransferTitle, 'A1:H1', requiredSelfTransferHeaders);
      await _writeHeaderIfEmpty(token, sheetId, _loanTitle, 'A1:I1', requiredLoanHeaders);
      await _writeHeaderIfEmpty(token, sheetId, _cashTitle, 'A1:K1', requiredCashHeaders);
      await _writeHeaderIfEmpty(token, sheetId, _creditTitle, 'A1:F1', requiredCreditHeaders);
      await _writeHeaderIfEmpty(token, sheetId, _billingTitle, 'A1:G1', requiredBillingHeaders);
      await _writeHeaderIfEmpty(token, sheetId, _balancesTitle, 'A1:J1', requiredBalancesHeaders);
      await _writeHeaderIfEmpty(token, sheetId, _configTitle, 'A1:E1', requiredConfigHeaders);
      await _writeHeaderIfEmpty(token, sheetId, _emiTitle, 'A1:N1', requiredEmiHeaders);
      _sheetsEnsured = true;
    } catch (e) {
      debugPrint('Error ensuring all sheets and headers: $e');
    }
  }

  Future<void> _writeHeaderIfEmpty(
    String token,
    String sheetId,
    String title,
    String range,
    List<String> headers,
  ) async {
    try {
      final encodedRange = Uri.encodeComponent("'$title'!$range");
      // Check if header row is already present
      final getUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$encodedRange',
      );
      final checkRes = await http.get(getUrl, headers: {'Authorization': 'Bearer $token'});
      if (checkRes.statusCode == 200) {
        final data = jsonDecode(checkRes.body);
        final values = data['values'] as List<dynamic>?;
        if (values != null && values.isNotEmpty && values[0] is List && (values[0] as List).isNotEmpty) {
          // Headers already present, do not overwrite!
          return;
        }
      }

      final headerUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$encodedRange?valueInputOption=USER_ENTERED',
      );
      await http.put(
        headerUrl,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'values': [headers],
        }),
      );
    } catch (e) {
      debugPrint('Error updating header for $title: $e');
    }
  }

  /// Verifies whether the specified spreadsheet exists, is accessible with the token, and is named "account ledger".
  Future<bool> _verifySpreadsheetAccess(String token, String sheetId) async {
    try {
      final verifyUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId?fields=properties.title',
      );
      final res = await http.get(verifyUrl, headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final title = data['properties']?['title']?.toString() ?? '';
        return title.trim().toLowerCase() == 'account ledger';
      }
    } catch (_) {}
    return false;
  }

  /// Searches the user's Google Drive for an existing spreadsheet named "account ledger".
  Future<String?> findExistingLedger(String token) async {
    try {
      final query = Uri.encodeComponent(
        "(name = 'account ledger' or name = 'Account Ledger') and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false",
      );
      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?q=$query&spaces=drive&fields=files(id,name,webViewLink,modifiedTime)&orderBy=modifiedTime desc&pageSize=10',
      );
      final res = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final files = data['files'] as List<dynamic>?;
        if (files != null && files.isNotEmpty) {
          // Prefer exact 'account ledger' / 'Account Ledger'
          final match = files.firstWhere(
            (f) => (f['name']?.toString().toLowerCase() == 'account ledger'),
            orElse: () => files.first,
          );
          final id = match['id']?.toString();
          final webUrl = match['webViewLink']?.toString();
          if (id != null && id.isNotEmpty) {
            debugPrint('Found existing account ledger on Google Drive: name=${match['name']}, id=$id, url=$webUrl');
            await setSpreadsheetId(id);
            if (webUrl != null) await setSpreadsheetUrl(webUrl);
            await setSheetGid(0);
            return id;
          }
        }
      } else {
        debugPrint('Drive API search returned ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('Error searching Google Drive for existing ledger: $e');
    }
    return null;
  }

  /// Discovers an existing "account ledger" in the user's Google account or creates one if not found.
  Future<String?> findOrCreateLedger(String token) async {
    // 1. Check if the locally saved spreadsheet ID for this account is still accessible and is named "account ledger"
    var sheetId = await getSpreadsheetId();
    if (sheetId != null && sheetId.isNotEmpty) {
      final isValid = await _verifySpreadsheetAccess(token, sheetId);
      if (isValid) {
        debugPrint('Using verified locally saved spreadsheet ID for account ledger: $sheetId');
        await _ensureAllSheetsAndHeaders(token, sheetId);
        return sheetId;
      } else {
        debugPrint('Locally saved sheetId $sheetId is not "account ledger" or inaccessible. Clearing cache and switching...');
        cachedTransactions = null;
        await StorageService.instance.clearCachedTransactions();
      }
    }

    // 2. Search Google Drive for any spreadsheet named "account ledger"
    syncStatusNotifier.value = 'Searching for existing "account ledger"...';
    sheetId = await findExistingLedger(token);
    if (sheetId != null && sheetId.isNotEmpty) {
      debugPrint('Connected to existing account ledger on Google Drive: $sheetId');
      cachedTransactions = null;
      await StorageService.instance.clearCachedTransactions();
      await _ensureAllSheetsAndHeaders(token, sheetId);
      syncStatusNotifier.value = 'Connected to existing account ledger';
      return sheetId;
    }

    // 3. If none exists, create a new one
    syncStatusNotifier.value = 'Creating account ledger...';
    debugPrint('No existing account ledger found; creating new one');
    sheetId = await _createSpreadsheet(token);
    cachedTransactions = null;
    await StorageService.instance.clearCachedTransactions();
    return sheetId;
  }

  /// Creates a new "account ledger" Google Sheet with all 7 sheets pre-configured.
  Future<String?> _createSpreadsheet(String token) async {
    try {
      final createUrl = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets');
      final res = await http.post(
        createUrl,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'properties': {'title': 'account ledger'},
          'sheets': [
            {'properties': {'title': 'Full Statement', 'sheetId': 0}},
            {'properties': {'title': 'Monthly Transaction', 'sheetId': 1}},
            {'properties': {'title': 'Self Transfer', 'sheetId': 2}},
            {'properties': {'title': 'Loan', 'sheetId': 3}},
            {'properties': {'title': 'Cash Entries', 'sheetId': 4}},
            {'properties': {'title': 'Credit', 'sheetId': 5}},
            {'properties': {'title': 'Billing', 'sheetId': 6}},
            {'properties': {'title': 'Account Balances', 'sheetId': 7}},
            {'properties': {'title': 'App Config & Masters', 'sheetId': 8}},
          ]
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final id = data['spreadsheetId']?.toString();
        final url = data['spreadsheetUrl']?.toString();
        if (id != null) {
          await setSpreadsheetId(id);
          if (url != null) await setSpreadsheetUrl(url);
          await setSheetGid(0);

          _txTitle = 'Full Statement';
          _txGid = 0;
          _monthlyTitle = 'Monthly Transaction';
          _monthlyGid = 1;
          _selfTransferTitle = 'Self Transfer';
          _selfTransferGid = 2;
          _loanTitle = 'Loan';
          _loanGid = 3;
          _cashTitle = 'Cash Entries';
          _cashGid = 4;
          _creditTitle = 'Credit';
          _creditGid = 5;
          _billingTitle = 'Billing';
          _billingGid = 6;
          _balancesTitle = 'Account Balances';
          _balancesGid = 7;
          _configTitle = 'App Config & Masters';
          _configGid = 8;
          _emiTitle = 'Active_EMIs';
          _emiGid = 9;

          // Write exact headers for each sheet
          await _writeHeaderIfEmpty(token, id, _txTitle, 'A1:J1', requiredHeaders);
          await _writeHeaderIfEmpty(token, id, _monthlyTitle, 'A1:J1', requiredMonthlyHeaders);
          await _writeHeaderIfEmpty(token, id, _selfTransferTitle, 'A1:H1', requiredSelfTransferHeaders);
          await _writeHeaderIfEmpty(token, id, _loanTitle, 'A1:I1', requiredLoanHeaders);
          await _writeHeaderIfEmpty(token, id, _cashTitle, 'A1:K1', requiredCashHeaders);
          await _writeHeaderIfEmpty(token, id, _creditTitle, 'A1:F1', requiredCreditHeaders);
          await _writeHeaderIfEmpty(token, id, _billingTitle, 'A1:G1', requiredBillingHeaders);
          await _writeHeaderIfEmpty(token, id, _balancesTitle, 'A1:J1', requiredBalancesHeaders);
          await _writeHeaderIfEmpty(token, id, _configTitle, 'A1:E1', requiredConfigHeaders);
          await _writeHeaderIfEmpty(token, id, _emiTitle, 'A1:N1', requiredEmiHeaders);
          return id;
        }
      } else {
        debugPrint('Create spreadsheet failed ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('Create spreadsheet error: $e');
    }
    return null;
  }

  /// Sends a transaction to an optional Google Apps Script Web App.
  Future<bool> _postToWebApp(String webAppUrl, FinanceTransaction tx) async {
    try {
      final isSelfTransfer = tx.isSelfTransfer ||
          tx.flow == 'Transfer' ||
          tx.purpose.toLowerCase().contains('self transfer');
      final isSplit = !isSelfTransfer && (tx.isSplitMode || (tx.splitRecipients != null && tx.splitRecipients!.isNotEmpty));

      final personalShare = _findPersonalShare(tx.splitRecipients);

      final payload = {
        'scenario': isSelfTransfer ? 'B_SELF_TRANSFER' : (isSplit ? 'C_SPLIT' : 'A_STANDARD'),
        'reference': tx.referenceId,
        'date': DateFormat('dd/MMM/yyyy').format(tx.date),
        'narration': tx.narration,
        'invoiceNo': tx.invoice,
        'purpose': tx.purpose,
        'spentFor': tx.spentFor,
        'flow': tx.flow,
        'amount': tx.totalAmount,
        'self_transfer': isSelfTransfer,
        'split_enabled': isSplit ? '1' : '0',
        'personal_share': personalShare?.amount ?? 0.0,
        'payments': tx.breakdowns.map((b) => b.toJson()).toList(),
        'to_payments': tx.toBreakdowns?.map((b) => b.toJson()).toList(),
        'recipients': tx.splitRecipients?.map((s) => s.toJson()).toList(),
        'cleared_card_bill': tx.narration.toLowerCase().contains('cleared card bill'),
      };

      final res = await http.post(
        Uri.parse(webAppUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      return res.statusCode == 200 || res.statusCode == 302;
    } catch (_) {
      return false;
    }
  }

  /// Syncs real-time account balances, credit limits, and cash in hand to Google Sheets.
  Future<bool> syncAccountBalances({
    required LiveAccountBalanceSummary summary,
    required AccountBalanceConfig config,
  }) async {
    final token = await GoogleAuthService.instance.getAccessToken();
    if (token == null) return false;
    final sheetId = await findOrCreateLedger(token);
    if (sheetId == null || sheetId.isEmpty) return false;

    try {
      await _ensureAllSheetsAndHeaders(token, sheetId);

      // Build rows for Account Balances:
      // Columns: ['Account / Card', 'Type', 'Total Limit', 'Used Limit', 'Available Balance', 'Shared Group', 'Bill Day', 'Due Day', 'Statement Billed', 'Last Updated']
      final nowStr = DateFormat('dd/MMM/yyyy HH:mm').format(DateTime.now());
      final List<List<dynamic>> rows = [];

      // 1. Bank Accounts
      for (final entry in summary.bankBalances.entries) {
        rows.add([
          entry.key,
          'Bank Account',
          '',
          '',
          entry.value.toStringAsFixed(2),
          '',
          '',
          '',
          '',
          nowStr,
        ]);
      }

      // 2. Credit Cards
      for (final entry in summary.creditCardSummaries.entries) {
        final cc = entry.value;
        final cardLimit = config.creditCardLimits[entry.key];
        rows.add([
          entry.key,
          'Credit Card',
          cc.totalLimit.toStringAsFixed(2),
          cc.usedLimit.toStringAsFixed(2),
          cc.availableLimit.toStringAsFixed(2),
          cardLimit?.sharedGroupName ?? '',
          cardLimit?.billDay?.toString() ?? '',
          cardLimit?.dueDay?.toString() ?? '',
          cardLimit?.statementBilledAmount?.toStringAsFixed(2) ?? '',
          nowStr,
        ]);
      }

      // 3. Cash In Hand
      rows.add([
        'Cash In Hand',
        'Cash',
        '',
        '',
        summary.totalCashInHand.toStringAsFixed(2),
        '',
        '',
        '',
        '',
        nowStr,
      ]);

      // 4. Cash Denominations breakdown
      final denomsStr = summary.cashDenominations.entries
          .where((e) => e.value > 0)
          .map((e) => '₹${e.key} x ${e.value}')
          .join(', ');
      if (denomsStr.isNotEmpty) {
        rows.add([
          'Cash Notes',
          'Cash Denominations',
          '',
          '',
          denomsStr,
          '',
          '',
          '',
          '',
          nowStr,
        ]);
      }

      // 5. Wallets
      for (final entry in summary.walletBalances.entries) {
        rows.add([
          entry.key,
          'Wallet',
          '',
          '',
          entry.value.toStringAsFixed(2),
          '',
          '',
          '',
          '',
          nowStr,
        ]);
      }

      // 6. Rewards
      for (final entry in summary.rewardBalances.entries) {
        rows.add([
          entry.key,
          'Reward Points',
          '',
          '',
          entry.value.toStringAsFixed(2),
          '',
          '',
          '',
          '',
          nowStr,
        ]);
      }

      // Clear previous values in Account Balances sheet starting from row 2
      final clearUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$_balancesTitle!A2:J:clear',
      );
      await http.post(
        clearUrl,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      // Write updated values
      if (rows.isNotEmpty) {
        final updateUrl = Uri.parse(
          'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$_balancesTitle!A2:J${rows.length + 1}?valueInputOption=USER_ENTERED',
        );
        final updateRes = await http.put(
          updateUrl,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'values': rows}),
        );
        return updateRes.statusCode == 200;
      }
      return true;
    } catch (e) {
      debugPrint('Error syncing account balances to sheet: $e');
      return false;
    }
  }

  /// Backs up all Masters (purposes, spent-for, categories), Templates, Recurring Transactions,
  /// and Account Balance Configuration to the 'App Config & Masters' sheet.
  Future<bool> backupAllConfigAndMasters() async {
    try {
      final token = await GoogleAuthService.instance.getAccessToken();
      if (token == null) return false;
      final sheetId = await findOrCreateLedger(token);
      if (sheetId == null || sheetId.isEmpty) return false;

      await _ensureAllSheetsAndHeaders(token, sheetId);

      final storage = StorageService.instance;
      final purposes = await storage.getPurposes();
      final spentFors = await storage.getSpentFors();
      final categories = await storage.getCategoryAccounts();
      final templates = await storage.getTemplates();
      final recurring = await storage.getRecurringTransactions();
      final balanceConfig = await storage.getAccountBalanceConfig();

      final nowStr = DateFormat('dd/MMM/yyyy HH:mm:ss').format(DateTime.now());
      final List<List<dynamic>> rows = [];

      // 1. Purposes
      for (final p in purposes) {
        rows.add(['Purpose', p, '', jsonEncode(p), nowStr]);
      }

      // 2. Spent For
      for (final sf in spentFors) {
        rows.add(['Spent For', sf, '', jsonEncode(sf), nowStr]);
      }

      // 3. Categories & Accounts (Bank Accounts, Credit Cards, Wallets, Rewards, Borrowers)
      for (final entry in categories.entries) {
        rows.add([
          'Category Account',
          entry.key,
          entry.value.join(', '),
          jsonEncode(entry.value),
          nowStr,
        ]);
      }

      // 4. Templates
      for (final t in templates) {
        rows.add([
          'Template',
          t.name,
          '${t.flow} | ${t.purpose} | ₹${t.totalAmount}',
          jsonEncode(t.toJson()),
          nowStr,
        ]);
      }

      // 5. Recurring Transactions
      for (final r in recurring) {
        rows.add([
          'Recurring',
          r.narration,
          '${r.frequency} | Due: ${DateFormat('dd/MMM/yyyy').format(r.nextDueDate)} | ₹${r.totalAmount}',
          jsonEncode(r.toJson()),
          nowStr,
        ]);
      }

      // 6. Balance Config Snapshot
      rows.add([
        'Balance Config',
        'Account Balance Config',
        'Configured: ${balanceConfig.isConfigured}',
        jsonEncode(balanceConfig.toJson()),
        nowStr,
      ]);

      // Clear previous rows starting from row 2
      final clearUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/\'$_configTitle\'!A2:E:clear',
      );
      await http.post(
        clearUrl,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      // Write updated rows
      if (rows.isNotEmpty) {
        final updateUrl = Uri.parse(
          'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/\'$_configTitle\'!A2:E${rows.length + 1}?valueInputOption=USER_ENTERED',
        );
        final res = await http.put(
          updateUrl,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'values': rows}),
        );
        if (res.statusCode != 200) {
          debugPrint('Failed to backup config & masters: ${res.statusCode} ${res.body}');
        }
      }

      // Also ensure Account Balances tab is synchronized
      final live = await storage.getLiveAccountBalances();
      await syncAccountBalances(summary: live, config: balanceConfig);

      return true;
    } catch (e) {
      debugPrint('Error backing up config and masters: $e');
      return false;
    }
  }

  /// Fetches AccountBalanceConfig from 'Account Balances' and 'Billing' sheets on Google Sheets.
  Future<AccountBalanceConfig?> fetchAccountBalanceConfigFromSheet({String? token, String? sheetId}) async {
    token ??= await GoogleAuthService.instance.getAccessToken();
    if (token == null) return null;
    sheetId ??= await getSpreadsheetId();
    if (sheetId == null || sheetId.isEmpty) return null;

    try {
      // 1. Read Account Balances sheet
      final balUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/\'$_balancesTitle\'!A2:J',
      );
      final balRes = await http.get(balUrl, headers: {'Authorization': 'Bearer $token'});

      final Map<String, double> banks = {};
      final Map<String, CreditCardLimit> cards = {};
      final Map<int, int> cashDenoms = {};
      final Map<String, double> wallets = {};
      final Map<String, double> rewards = {};
      bool hasData = false;

      if (balRes.statusCode == 200) {
        final balData = jsonDecode(balRes.body);
        final rows = (balData['values'] as List<dynamic>?) ?? [];
        for (final r in rows) {
          if (r is! List || r.isEmpty) continue;
          final name = r[0]?.toString().trim() ?? '';
          final type = r.length > 1 ? r[1]?.toString().trim().toLowerCase() ?? '' : '';
          if (name.isEmpty) continue;

          if (type.contains('bank')) {
            final bal = r.length > 4 ? parseDoubleSafe(r[4]?.toString()) : 0.0;
            banks[name] = bal;
            hasData = true;
          } else if (type.contains('wallet')) {
            final bal = r.length > 4 ? parseDoubleSafe(r[4]?.toString()) : 0.0;
            wallets[name] = bal;
            hasData = true;
          } else if (type.contains('reward')) {
            final bal = r.length > 4 ? parseDoubleSafe(r[4]?.toString()) : 0.0;
            rewards[name] = bal;
            hasData = true;
          } else if (type.contains('credit')) {
            final total = r.length > 2 ? parseDoubleSafe(r[2]?.toString()) : 0.0;
            final used = r.length > 3 ? parseDoubleSafe(r[3]?.toString()) : 0.0;
            final group = r.length > 5 ? r[5]?.toString().trim() : null;
            final billDay = r.length > 6 ? int.tryParse(r[6]?.toString().trim() ?? '') : null;
            final dueDay = r.length > 7 ? int.tryParse(r[7]?.toString().trim() ?? '') : null;
            final billedAmt = r.length > 8 ? double.tryParse(r[8]?.toString().trim() ?? '') : null;

            cards[name] = CreditCardLimit(
              totalLimit: total,
              initialUsedAmount: used,
              sharedGroupName: (group != null && group.isNotEmpty) ? group : null,
              groupTotalLimit: (group != null && group.isNotEmpty) ? total : null,
              billDay: billDay,
              dueDay: dueDay,
              statementBilledAmount: billedAmt,
            );
            hasData = true;
          } else if (type.contains('denomination') || name.toLowerCase().contains('notes')) {
            final text = r.length > 4 ? r[4]?.toString() ?? '' : '';
            final parts = text.split(',');
            for (final p in parts) {
              final match = RegExp(r'₹?(\d+)\s*[xX*]\s*(\d+)').firstMatch(p.trim());
              if (match != null) {
                final denom = int.tryParse(match.group(1)!);
                final count = int.tryParse(match.group(2)!);
                if (denom != null && count != null) {
                  cashDenoms[denom] = count;
                }
              }
            }
            hasData = true;
          }
        }
      }

      // 2. Cross-reference Billing sheet for any missing billing cycle dates or billed amounts
      final billingUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/\'$_billingTitle\'!A2:G',
      );
      final billingRes = await http.get(billingUrl, headers: {'Authorization': 'Bearer $token'});
      if (billingRes.statusCode == 200) {
        final billingData = jsonDecode(billingRes.body);
        final bRows = (billingData['values'] as List<dynamic>?) ?? [];
        for (final r in bRows) {
          if (r is! List || r.isEmpty) continue;
          final cardName = r[0]?.toString().trim() ?? '';
          final billDateStr = r.length > 1 ? r[1]?.toString().trim() ?? '' : '';
          final dueDateStr = r.length > 2 ? r[2]?.toString().trim() ?? '' : '';
          final amt = r.length > 3 ? parseDoubleSafe(r[3]?.toString()) : 0.0;

          if (cardName.isNotEmpty) {
            int? bDay;
            int? dDay;
            if (billDateStr.isNotEmpty) {
              final dt = parseDateSafe(billDateStr);
              bDay = dt.day;
            }
            if (dueDateStr.isNotEmpty) {
              final dt = parseDateSafe(dueDateStr);
              dDay = dt.day;
            }

            if (cards.containsKey(cardName)) {
              final existing = cards[cardName]!;
              cards[cardName] = existing.copyWith(
                billDay: existing.billDay ?? bDay,
                dueDay: existing.dueDay ?? dDay,
                statementBilledAmount: existing.statementBilledAmount ?? (amt > 0 ? amt : null),
              );
            } else {
              cards[cardName] = CreditCardLimit(
                totalLimit: 0.0,
                initialUsedAmount: 0.0,
                billDay: bDay,
                dueDay: dDay,
                statementBilledAmount: amt > 0 ? amt : null,
              );
              hasData = true;
            }
          }
        }
      }

      if (!hasData) return null;

      final config = AccountBalanceConfig(
        bankOpeningBalances: banks,
        creditCardLimits: cards,
        cashOpeningDenominations: cashDenoms,
        walletOpeningBalances: wallets,
        rewardOpeningBalances: rewards,
        isConfigured: true,
      );

      // Save to local storage
      await StorageService.instance.saveAccountBalanceConfig(config);

      // Add discovered accounts to categories
      final categories = await StorageService.instance.getCategoryAccounts();
      final bankList = categories['Bank Accounts'] ?? [];
      for (final b in banks.keys) {
        if (!bankList.contains(b)) bankList.add(b);
      }
      categories['Bank Accounts'] = bankList;

      final ccList = categories['Credit Cards'] ?? [];
      for (final c in cards.keys) {
        if (!ccList.contains(c)) ccList.add(c);
      }
      categories['Credit Cards'] = ccList;

      final walletList = categories['Wallets'] ?? [];
      for (final w in wallets.keys) {
        if (!walletList.contains(w)) walletList.add(w);
      }
      categories['Wallets'] = walletList;

      final rewardList = categories['Rewards'] ?? [];
      for (final r in rewards.keys) {
        if (!rewardList.contains(r)) rewardList.add(r);
      }
      categories['Rewards'] = rewardList;

      await StorageService.instance.saveCategoryAccounts(categories);

      return config;
    } catch (e) {
      debugPrint('Error fetching account balance config from sheet: $e');
      return null;
    }
  }

  /// Restores all masters, templates, recurring transactions, balances, and card limits from Google Sheets.
  Future<bool> restoreAllFromSheet(String token, String sheetId) async {
    try {
      await _ensureAllSheetsAndHeaders(token, sheetId);

      // 1. Fetch values from App Config & Masters sheet
      final configUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/\'$_configTitle\'!A2:E',
      );
      final res = await http.get(configUrl, headers: {'Authorization': 'Bearer $token'});

      bool restoredConfigSheet = false;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rows = (data['values'] as List<dynamic>?) ?? [];
        if (rows.isNotEmpty) {
          final List<String> purposes = [];
          final List<String> spentFors = [];
          final Map<String, List<String>> categories = {};
          final List<TransactionTemplate> templates = [];
          final List<RecurringTransaction> recurring = [];
          AccountBalanceConfig? balanceConfig;

          for (final r in rows) {
            if (r is! List || r.isEmpty) continue;
            final type = r[0]?.toString().trim() ?? '';
            final key = r.length > 1 ? r[1]?.toString().trim() ?? '' : '';
            final summary = r.length > 2 ? r[2]?.toString().trim() ?? '' : '';
            final jsonPayload = r.length > 3 ? r[3]?.toString().trim() ?? '' : '';

            if (type == 'Purpose') {
              if (key.isNotEmpty && !purposes.contains(key)) purposes.add(key);
            } else if (type == 'Spent For') {
              if (key.isNotEmpty && !spentFors.contains(key)) spentFors.add(key);
            } else if (type == 'Category Account') {
              if (key.isNotEmpty) {
                List<String> accounts = [];
                if (jsonPayload.isNotEmpty) {
                  try {
                    final decoded = jsonDecode(jsonPayload);
                    if (decoded is List) accounts = decoded.map((e) => e.toString()).toList();
                  } catch (_) {}
                }
                if (accounts.isEmpty && summary.isNotEmpty) {
                  accounts = summary.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                }
                if (accounts.isNotEmpty) {
                  categories[key] = accounts;
                }
              }
            } else if (type == 'Template') {
              if (jsonPayload.isNotEmpty) {
                try {
                  final decoded = jsonDecode(jsonPayload);
                  if (decoded is Map<String, dynamic>) {
                    templates.add(TransactionTemplate.fromJson(decoded));
                  }
                } catch (_) {}
              }
            } else if (type == 'Recurring') {
              if (jsonPayload.isNotEmpty) {
                try {
                  final decoded = jsonDecode(jsonPayload);
                  if (decoded is Map<String, dynamic>) {
                    recurring.add(RecurringTransaction.fromJson(decoded));
                  }
                } catch (_) {}
              }
            } else if (type == 'Balance Config') {
              if (jsonPayload.isNotEmpty) {
                try {
                  final decoded = jsonDecode(jsonPayload);
                  if (decoded is Map<String, dynamic>) {
                    balanceConfig = AccountBalanceConfig.fromJson(decoded);
                  }
                } catch (_) {}
              }
            }
          }

          final storage = StorageService.instance;
          if (purposes.isNotEmpty) await storage.savePurposes(purposes);
          if (spentFors.isNotEmpty) await storage.saveSpentFors(spentFors);
          if (categories.isNotEmpty) await storage.saveCategoryAccounts(categories);
          if (templates.isNotEmpty) await storage.saveAllTemplates(templates);
          if (recurring.isNotEmpty) await storage.saveAllRecurringTransactions(recurring);
          if (balanceConfig != null && balanceConfig.isConfigured) {
            await storage.saveAccountBalanceConfig(balanceConfig);
          }
          restoredConfigSheet = true;
        }
      }

      // 2. Cross-restore from Account Balances and Billing sheets
      await fetchAccountBalanceConfigFromSheet(token: token, sheetId: sheetId);

      return restoredConfigSheet;
    } catch (e) {
      debugPrint('Error restoring config and masters from sheet: $e');
      return false;
    }
  }

  // =========================================================================
  // GROCERY_DB & INVOICE MANAGER INTEGRATION
  // =========================================================================
  static const String _groceryDbName = 'Grocery_DB';
  static const String _groceryInvoiceTitle = 'Invoice';
  static const String _groceryPricesTitle = 'Dealer_Prices';

  static const List<String> groceryInvoiceHeaders = [
    'Bill Date',
    'Shop Name',
    'Bill No',
    'Item Name',
    'Quantity',
    'Price',
    'Total',
  ];

  static const List<String> groceryPricesHeaders = [
    'Item',
    'Dealer',
    'Price',
    'LastUpdated',
  ];

  Future<String?> getGroceryDbSpreadsheetId() async {
    final cachedId = await StorageService.instance.getGroceryDbId();
    if (cachedId != null && cachedId.isNotEmpty) return cachedId;

    final token = await GoogleAuthService.instance.getAccessToken();
    if (token == null) return null;

    final foundId = await findExistingGroceryDb(token);
    if (foundId != null && foundId.isNotEmpty) {
      await StorageService.instance.saveGroceryDbId(foundId);
      return foundId;
    }
    return null;
  }

  Future<String?> findExistingGroceryDb(String token) async {
    try {
      final query = Uri.encodeComponent(
        "(name = '$_groceryDbName' or name = 'grocery_db') and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false",
      );
      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?q=$query&spaces=drive&fields=files(id,name,webViewLink,modifiedTime)&orderBy=modifiedTime desc&pageSize=10',
      );
      final res = await http.get(url, headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final files = data['files'] as List<dynamic>?;
        if (files != null && files.isNotEmpty) {
          final id = files.first['id'] as String;
          await StorageService.instance.saveGroceryDbId(id);
          await _ensureGrocerySheetsExist(token, id);
          return id;
        }
      }
      // If not found, create new Grocery_DB
      return await _createGroceryDb(token);
    } catch (e) {
      debugPrint('Error finding Grocery_DB: $e');
      return null;
    }
  }

  Future<String?> _createGroceryDb(String token) async {
    try {
      final url = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets');
      final body = jsonEncode({
        'properties': {'title': _groceryDbName},
        'sheets': [
          {
            'properties': {'title': _groceryInvoiceTitle, 'sheetId': 0},
          },
          {
            'properties': {'title': _groceryPricesTitle, 'sheetId': 1},
          },
        ],
      });
      final res = await http.post(
        url,
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: body,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final id = data['spreadsheetId'] as String;
        await StorageService.instance.saveGroceryDbId(id);

        // Write headers
        await _writeSheetHeader(token, id, '$_groceryInvoiceTitle!A1:G1', groceryInvoiceHeaders);
        await _writeSheetHeader(token, id, '$_groceryPricesTitle!A1:D1', groceryPricesHeaders);

        return id;
      }
    } catch (e) {
      debugPrint('Error creating Grocery_DB: $e');
    }
    return null;
  }

  Future<void> _writeSheetHeader(String token, String sheetId, String range, List<String> headers) async {
    try {
      final url = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/${Uri.encodeComponent(range)}?valueInputOption=USER_ENTERED',
      );
      await http.put(
        url,
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'values': [headers]}),
      );
    } catch (e) {
      debugPrint('Error writing sheet header $range: $e');
    }
  }

  Future<void> _ensureGrocerySheetsExist(String token, String sheetId) async {
    try {
      final metaUrl = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$sheetId?fields=sheets.properties');
      final metaRes = await http.get(metaUrl, headers: {'Authorization': 'Bearer $token'});
      if (metaRes.statusCode != 200) return;

      final data = jsonDecode(metaRes.body);
      final sheets = (data['sheets'] as List<dynamic>?) ?? [];
      final titles = sheets.map((s) => s['properties']['title']?.toString()).toSet();

      final requests = <Map<String, dynamic>>[];
      if (!titles.contains(_groceryInvoiceTitle)) {
        requests.add({
          'addSheet': {
            'properties': {'title': _groceryInvoiceTitle},
          },
        });
      }
      if (!titles.contains(_groceryPricesTitle)) {
        requests.add({
          'addSheet': {
            'properties': {'title': _groceryPricesTitle},
          },
        });
      }

      if (requests.isNotEmpty) {
        final batchUrl = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$sheetId:batchUpdate');
        await http.post(
          batchUrl,
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({'requests': requests}),
        );
      }

      // Ensure headers exist
      final checkInvoice = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/${Uri.encodeComponent("$_groceryInvoiceTitle!A1:G1")}',
      );
      final invRes = await http.get(checkInvoice, headers: {'Authorization': 'Bearer $token'});
      if (invRes.statusCode == 200) {
        final invData = jsonDecode(invRes.body);
        final values = invData['values'] as List<dynamic>?;
        if (values == null || values.isEmpty) {
          await _writeSheetHeader(token, sheetId, '$_groceryInvoiceTitle!A1:G1', groceryInvoiceHeaders);
        }
      }

      final checkPrices = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/${Uri.encodeComponent("$_groceryPricesTitle!A1:D1")}',
      );
      final priceRes = await http.get(checkPrices, headers: {'Authorization': 'Bearer $token'});
      if (priceRes.statusCode == 200) {
        final priceData = jsonDecode(priceRes.body);
        final values = priceData['values'] as List<dynamic>?;
        if (values == null || values.isEmpty) {
          await _writeSheetHeader(token, sheetId, '$_groceryPricesTitle!A1:D1', groceryPricesHeaders);
        }
      }
    } catch (e) {
      debugPrint('Error ensuring grocery sheets exist: $e');
    }
  }

  Future<List<InvoiceItemRecord>> fetchInvoiceItems({bool forceRefresh = false, DateTime? filterDate}) async {
    // 1. Local-first hit if not forcing refresh
    final localItems = await StorageService.instance.getCachedInvoices();
    if (!forceRefresh && localItems.isNotEmpty) {
      if (filterDate != null) {
        return localItems.where((it) =>
          it.billDate.year == filterDate.year &&
          it.billDate.month == filterDate.month &&
          it.billDate.day == filterDate.day
        ).toList();
      }
      return localItems;
    }

    final token = await GoogleAuthService.instance.getAccessToken();
    if (token == null) {
      if (filterDate != null) {
        return localItems.where((it) =>
          it.billDate.year == filterDate.year &&
          it.billDate.month == filterDate.month &&
          it.billDate.day == filterDate.day
        ).toList();
      }
      return localItems;
    }

    final sheetId = await getGroceryDbSpreadsheetId();
    if (sheetId == null) {
      if (filterDate != null) {
        return localItems.where((it) =>
          it.billDate.year == filterDate.year &&
          it.billDate.month == filterDate.month &&
          it.billDate.day == filterDate.day
        ).toList();
      }
      return localItems;
    }

    try {
      final range = Uri.encodeComponent("$_groceryInvoiceTitle!A2:H");
      final url = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$range');
      final res = await http.get(url, headers: {'Authorization': 'Bearer $token'});

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final values = data['values'] as List<dynamic>?;
        if (values != null && values.isNotEmpty) {
          final items = <InvoiceItemRecord>[];
          for (int i = 0; i < values.length; i++) {
            final row = values[i] as List<dynamic>;
            if (row.isEmpty || row.every((c) => c.toString().trim().isEmpty)) continue;
            items.add(InvoiceItemRecord.fromSheetRow(row, rowIndex: i + 2));
          }
          await StorageService.instance.saveCachedInvoices(items);
          if (filterDate != null) {
            return items.where((it) =>
              it.billDate.year == filterDate.year &&
              it.billDate.month == filterDate.month &&
              it.billDate.day == filterDate.day
            ).toList();
          }
          return items;
        }
      }
    } catch (e) {
      debugPrint('Error fetching invoices from Grocery_DB: $e');
    }

    if (filterDate != null) {
      return localItems.where((it) =>
        it.billDate.year == filterDate.year &&
        it.billDate.month == filterDate.month &&
        it.billDate.day == filterDate.day
      ).toList();
    }
    return localItems;
  }

  Future<List<DealerPriceItem>> fetchDealerPrices({bool forceRefresh = false}) async {
    final localPrices = await StorageService.instance.getCachedDealerPrices();
    if (!forceRefresh && localPrices.isNotEmpty) return localPrices;

    final token = await GoogleAuthService.instance.getAccessToken();
    if (token == null) return localPrices;

    final sheetId = await getGroceryDbSpreadsheetId();
    if (sheetId == null) return localPrices;

    try {
      final range = Uri.encodeComponent("$_groceryPricesTitle!A2:D");
      final url = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$range');
      final res = await http.get(url, headers: {'Authorization': 'Bearer $token'});

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final values = data['values'] as List<dynamic>?;
        if (values != null && values.isNotEmpty) {
          final prices = <DealerPriceItem>[];
          for (var row in values) {
            if (row is List<dynamic> && row.isNotEmpty) {
              if (row.every((c) => c.toString().trim().isEmpty)) continue;
              prices.add(DealerPriceItem.fromSheetRow(row));
            }
          }
          await StorageService.instance.saveCachedDealerPrices(prices);
          return prices;
        }
      }
    } catch (e) {
      debugPrint('Error fetching dealer prices from Grocery_DB: $e');
    }

    return localPrices;
  }

  Future<bool> upsertDealerPrices(List<DealerPriceItem> newPrices) async {
    if (newPrices.isEmpty) return true;

    // 1. Get current prices
    final current = await fetchDealerPrices();
    final updatedList = List<DealerPriceItem>.from(current);

    bool hasChanges = false;
    final now = DateTime.now();

    for (var np in newPrices) {
      if (np.item.trim().isEmpty || np.dealer.trim().isEmpty || np.price <= 0) continue;

      final existingIdx = updatedList.indexWhere((p) =>
        p.item.trim().toLowerCase() == np.item.trim().toLowerCase() &&
        p.dealer.trim().toLowerCase() == np.dealer.trim().toLowerCase()
      );

      if (existingIdx != -1) {
        final existing = updatedList[existingIdx];
        if (existing.price != np.price) {
          updatedList[existingIdx] = DealerPriceItem(
            item: existing.item,
            dealer: existing.dealer,
            price: np.price,
            lastUpdated: now,
          );
          hasChanges = true;
        }
      } else {
        updatedList.add(DealerPriceItem(
          item: np.item.trim(),
          dealer: np.dealer.trim(),
          price: np.price,
          lastUpdated: now,
        ));
        hasChanges = true;
      }
    }

    if (!hasChanges) return true;

    // 2. Save local cache
    await StorageService.instance.saveCachedDealerPrices(updatedList);

    // 3. Write to Google Sheets
    final token = await GoogleAuthService.instance.getAccessToken();
    if (token == null) return true;

    final sheetId = await getGroceryDbSpreadsheetId();
    if (sheetId == null) return true;

    try {
      final clearUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/${Uri.encodeComponent("$_groceryPricesTitle!A2:D")}:clear',
      );
      await http.post(clearUrl, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});

      if (updatedList.isNotEmpty) {
        final rows = updatedList.map((p) => p.toSheetRow()).toList();
        final putUrl = Uri.parse(
          'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/${Uri.encodeComponent("$_groceryPricesTitle!A2:D${updatedList.length + 1}")}?valueInputOption=USER_ENTERED',
        );
        await http.put(
          putUrl,
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({'values': rows}),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Error updating Dealer_Prices in Grocery_DB: $e');
      return false;
    }
  }

  Future<bool> appendInvoiceItems(List<InvoiceItemRecord> newItems) async {
    if (newItems.isEmpty) return true;

    // 1. Instantly update local cache
    final current = await StorageService.instance.getCachedInvoices();
    current.addAll(newItems);
    await StorageService.instance.saveCachedInvoices(current);

    // 2. Sync to remote Google Sheet
    final token = await GoogleAuthService.instance.getAccessToken();
    if (token == null) return true;

    final sheetId = await getGroceryDbSpreadsheetId();
    if (sheetId == null) return true;

    try {
      final range = Uri.encodeComponent("$_groceryInvoiceTitle!A1:G1");
      final url = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$range:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS',
      );
      final rows = newItems.map((it) => it.toSheetRow()).toList();
      final body = jsonEncode({'values': rows});

      final res = await http.post(
        url,
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: body,
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error appending invoice items to Grocery_DB: $e');
      return false;
    }
  }

  Future<bool> deleteInvoice(String billNo) async {
    if (billNo.trim().isEmpty) return false;

    // 1. Update local cache
    final current = await StorageService.instance.getCachedInvoices();
    final remaining = current.where((it) => it.billNo.trim() != billNo.trim()).toList();
    await StorageService.instance.saveCachedInvoices(remaining);

    // 2. Sync to Google Sheets
    final token = await GoogleAuthService.instance.getAccessToken();
    if (token == null) return true;

    final sheetId = await getGroceryDbSpreadsheetId();
    if (sheetId == null) return true;

    try {
      // Clear existing values and write back remaining rows
      final clearUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/${Uri.encodeComponent("$_groceryInvoiceTitle!A2:H")}:clear',
      );
      await http.post(clearUrl, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});

      if (remaining.isNotEmpty) {
        final putUrl = Uri.parse(
          'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/${Uri.encodeComponent("$_groceryInvoiceTitle!A2:H${remaining.length + 1}")}?valueInputOption=USER_ENTERED',
        );
        final rows = remaining.map((it) => it.toSheetRow()).toList();
        await http.put(
          putUrl,
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({'values': rows}),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Error deleting invoice from Grocery_DB: $e');
      return false;
    }
  }

  void clearSessionCache() {
    cachedTransactions = null;
    cachedLoanEntries = null;
  }

  // =========================================================================
  // CREDIT CARD EMIs (Active_EMIs)
  // =========================================================================

  Future<List<EmiPlan>> fetchEmiPlans({bool forceRefresh = false}) async {
    // 1. Local-first
    final cached = await StorageService.instance.getCachedEmiPlans();
    if (!forceRefresh && cached.isNotEmpty) {
      return cached;
    }

    final token = await GoogleAuthService.instance.getAccessToken();
    if (token == null) return cached;

    final sheetId = await getSpreadsheetId();
    if (sheetId == null) return cached;

    try {
      await _ensureAllSheetsAndHeaders(token, sheetId);
      final range = Uri.encodeComponent("'$_emiTitle'!A2:N");
      final url = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$range');
      final res = await http.get(url, headers: {'Authorization': 'Bearer $token'});

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final values = data['values'] as List<dynamic>?;
        if (values != null && values.isNotEmpty) {
          final plans = <EmiPlan>[];
          for (final row in values) {
            if (row is List<dynamic> && row.isNotEmpty && row[0]?.toString().trim().isNotEmpty == true) {
              try {
                plans.add(EmiPlan.fromSheetRow(row));
              } catch (e) {
                debugPrint('Error parsing EMI row: $e');
              }
            }
          }
          await StorageService.instance.saveCachedEmiPlans(plans);
          return plans;
        }
      }
    } catch (e) {
      debugPrint('Error fetching EMI plans from sheet: $e');
    }

    return cached;
  }

  Future<bool> saveEmiPlan(EmiPlan plan) async {
    // 1. Local-first update
    await StorageService.instance.saveEmiPlanLocal(plan);

    // 2. Google Sheets sync
    final token = await GoogleAuthService.instance.getAccessToken();
    if (token == null) return true;

    final sheetId = await getSpreadsheetId();
    if (sheetId == null) return true;

    try {
      await _ensureAllSheetsAndHeaders(token, sheetId);
      final allPlans = await StorageService.instance.getCachedEmiPlans();
      final rows = allPlans.map((p) => p.toSheetRow()).toList();

      final clearUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/${Uri.encodeComponent("'$_emiTitle'!A2:N")}:clear',
      );
      await http.post(clearUrl, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});

      if (rows.isNotEmpty) {
        final putUrl = Uri.parse(
          'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/${Uri.encodeComponent("'$_emiTitle'!A2:N${rows.length + 1}")}?valueInputOption=USER_ENTERED',
        );
        await http.put(
          putUrl,
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({'values': rows}),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Error syncing EMI plan to sheet: $e');
      return false;
    }
  }

  Future<bool> updateEmiInstallmentPaid(
    String planId,
    int installmentNumber,
    bool isPaid, {
    DateTime? paidDate,
  }) async {
    // 1. Local update
    await StorageService.instance.updateEmiInstallmentLocal(
      planId,
      installmentNumber,
      isPaid,
      paidDate: paidDate,
    );

    // 2. Sync full EMI table to sheet
    final token = await GoogleAuthService.instance.getAccessToken();
    if (token == null) return true;

    final sheetId = await getSpreadsheetId();
    if (sheetId == null) return true;

    try {
      await _ensureAllSheetsAndHeaders(token, sheetId);
      final allPlans = await StorageService.instance.getCachedEmiPlans();
      final rows = allPlans.map((p) => p.toSheetRow()).toList();

      final clearUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/${Uri.encodeComponent("'$_emiTitle'!A2:N")}:clear',
      );
      await http.post(clearUrl, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});

      if (rows.isNotEmpty) {
        final putUrl = Uri.parse(
          'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/${Uri.encodeComponent("'$_emiTitle'!A2:N${rows.length + 1}")}?valueInputOption=USER_ENTERED',
        );
        await http.put(
          putUrl,
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({'values': rows}),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Error updating EMI installment in sheet: $e');
      return false;
    }
  }

  Future<bool> deleteEmiPlan(String planId) async {
    // 1. Local delete
    await StorageService.instance.deleteEmiPlanLocal(planId);

    // 2. Google Sheets sync
    final token = await GoogleAuthService.instance.getAccessToken();
    if (token == null) return true;

    final sheetId = await getSpreadsheetId();
    if (sheetId == null) return true;

    try {
      await _ensureAllSheetsAndHeaders(token, sheetId);
      final allPlans = await StorageService.instance.getCachedEmiPlans();
      final rows = allPlans.map((p) => p.toSheetRow()).toList();

      final clearUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/${Uri.encodeComponent("'$_emiTitle'!A2:N")}:clear',
      );
      await http.post(clearUrl, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});

      if (rows.isNotEmpty) {
        final putUrl = Uri.parse(
          'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/${Uri.encodeComponent("'$_emiTitle'!A2:N${rows.length + 1}")}?valueInputOption=USER_ENTERED',
        );
        await http.put(
          putUrl,
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({'values': rows}),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Error deleting EMI plan from sheet: $e');
      return false;
    }
  }
}

class _ParsedCashEntry {
  final String rawRef;
  final String baseRef;
  final String narration;
  final String invoice;
  final String account;
  final double amount;
  final bool isOutflow;
  final bool isFrom;
  final bool isTo;
  final Map<int, int> denominations;
  final DateTime date;

  _ParsedCashEntry({
    required this.rawRef,
    required this.baseRef,
    required this.narration,
    required this.invoice,
    required this.account,
    required this.amount,
    required this.isOutflow,
    required this.isFrom,
    required this.isTo,
    required this.denominations,
    required this.date,
  });
}

class _ParsedCreditEntry {
  final String rawRef;
  final String baseRef;
  final String narration;
  final String invoice;
  final String purpose;
  final String spentFor;
  final String account;
  final double amount;
  final bool isWithdrawal;
  final bool isFrom;
  final bool isTo;
  final DateTime date;

  _ParsedCreditEntry({
    required this.rawRef,
    required this.baseRef,
    required this.narration,
    required this.invoice,
    required this.purpose,
    required this.spentFor,
    required this.account,
    required this.amount,
    required this.isWithdrawal,
    required this.isFrom,
    required this.isTo,
    required this.date,
  });
}

class _ParsedTransferLeg {
  final String rawRef;
  final String baseRef;
  final String narration;
  final String invoice;
  final String account;
  final String paymentType;
  final double amount;
  final bool isWithdrawal;
  final DateTime date;

  _ParsedTransferLeg({
    required this.rawRef,
    required this.baseRef,
    required this.narration,
    required this.invoice,
    required this.account,
    required this.paymentType,
    required this.amount,
    required this.isWithdrawal,
    required this.date,
  });
}
