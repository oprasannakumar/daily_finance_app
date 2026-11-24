import 'dart:math';
import 'package:intl/intl.dart';

DateTime sanitizeDateYear(DateTime d) {
  if (d.year < 100) {
    final fullYear = d.year < 70 ? d.year + 2000 : d.year + 1900;
    return DateTime(fullYear, d.month, d.day, d.hour, d.minute, d.second, d.millisecond, d.microsecond);
  }
  return d;
}

class PaymentBreakdown {
  static int _idCounter = 0;
  final String id;
  String? paymentType; // Cash, Credit, Debit, Net, Rewards, UPI, Wallets
  String? account; // Selected account or custom account when Other is picked
  String? otherAccountText; // If 'Other' was selected, holds the manual input
  double amount;
  Map<int, int> denominations; // 500, 200, 100, 50, 20, 10, 5, 2, 1

  PaymentBreakdown({
    String? id,
    this.paymentType,
    this.account,
    this.otherAccountText,
    this.amount = 0.0,
    Map<int, int>? denominations,
  })  : id = id ?? '${DateTime.now().microsecondsSinceEpoch}_${++_idCounter}',
        denominations = denominations ??
            {
              500: 0,
              200: 0,
              100: 0,
              50: 0,
              20: 0,
              10: 0,
              5: 0,
              2: 0,
              1: 0,
            };

  static const List<int> supportedDenominations = [500, 200, 100, 50, 20, 10, 5, 2, 1];

  String get effectiveAccount {
    if (account == 'Other' && (otherAccountText != null && otherAccountText!.isNotEmpty)) {
      return otherAccountText!;
    }
    return account ?? '';
  }

  double get calculatedCashAmount {
    double total = 0.0;
    denominations.forEach((denom, count) {
      total += denom * count;
    });
    return total;
  }

  void recalculateCashAmount() {
    if (paymentType == 'Cash') {
      amount = calculatedCashAmount;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'paymentType': paymentType,
      'account': effectiveAccount,
      'otherAccountText': otherAccountText,
      'amount': amount,
      'denominations': denominations.map((k, v) => MapEntry(k.toString(), v)),
    };
  }

  factory PaymentBreakdown.fromJson(Map<String, dynamic> json) {
    final rawDenom = json['denominations'] as Map<String, dynamic>?;
    final Map<int, int> denoms = {
      500: 0,
      200: 0,
      100: 0,
      50: 0,
      20: 0,
      10: 0,
      5: 0,
      2: 0,
      1: 0,
    };
    if (rawDenom != null) {
      rawDenom.forEach((key, val) {
        final parsedKey = int.tryParse(key);
        if (parsedKey != null) {
          denoms[parsedKey] = (val as num).toInt();
        }
      });
    }

    return PaymentBreakdown(
      id: json['id'] as String?,
      paymentType: json['paymentType'] as String? ?? 'Cash',
      account: json['account'] as String?,
      otherAccountText: json['otherAccountText'] as String?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      denominations: denoms,
    );
  }

  PaymentBreakdown copy() {
    return PaymentBreakdown(
      id: id,
      paymentType: paymentType,
      account: account,
      otherAccountText: otherAccountText,
      amount: amount,
      denominations: Map<int, int>.from(denominations),
    );
  }
}

class SplitRecipient {
  final String id;
  String name; // 'Personal Share' or selected Spent For category/contact
  double amount;
  double percentage;
  bool isPersonal;

    SplitRecipient({
    String? id,
    required this.name,
    this.amount = 0.0,
    this.percentage = 0.0,
    this.isPersonal = false,
  }) : id = id ?? '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'percentage': percentage,
      'isPersonal': isPersonal,
    };
  }

  factory SplitRecipient.fromJson(Map<String, dynamic> json) {
    return SplitRecipient(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'Personal Share',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
      isPersonal: json['isPersonal'] as bool? ?? false,
    );
  }

  SplitRecipient copy() {
    return SplitRecipient(
      id: id,
      name: name,
      amount: amount,
      percentage: percentage,
      isPersonal: isPersonal,
    );
  }
}

class TransactionTemplate {
  final String id;
  String name;
  String narration;
  String flow;
  String purpose;
  String spentFor;
  List<PaymentBreakdown> breakdowns;
  List<SplitRecipient>? splitRecipients;
  bool isSplitMode;
  bool isSelfTransfer;
  List<PaymentBreakdown>? toBreakdowns;

  TransactionTemplate({
    String? id,
    required this.name,
    required this.narration,
    required this.flow,
    required this.purpose,
    required this.spentFor,
    required this.breakdowns,
    this.splitRecipients,
    this.isSplitMode = false,
    this.isSelfTransfer = false,
    this.toBreakdowns,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'narration': narration,
      'flow': flow,
      'purpose': purpose,
      'spentFor': spentFor,
      'breakdowns': breakdowns.map((b) => b.toJson()).toList(),
      'splitRecipients': splitRecipients?.map((s) => s.toJson()).toList(),
      'isSplitMode': isSplitMode,
      'isSelfTransfer': isSelfTransfer,
      'toBreakdowns': toBreakdowns?.map((b) => b.toJson()).toList(),
    };
  }

  factory TransactionTemplate.fromJson(Map<String, dynamic> json) {
    final rawBreakdowns = (json['breakdowns'] as List<dynamic>?) ?? [];
    final rawSplits = (json['splitRecipients'] as List<dynamic>?) ?? [];
    final rawToBreakdowns = (json['toBreakdowns'] as List<dynamic>?) ?? [];
    return TransactionTemplate(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      narration: json['narration'] as String? ?? '',
      flow: json['flow'] as String? ?? 'Withdraw',
      purpose: json['purpose'] as String? ?? '',
      spentFor: json['spentFor'] as String? ?? '',
      breakdowns: rawBreakdowns
          .map((b) => PaymentBreakdown.fromJson(b as Map<String, dynamic>))
          .toList(),
      splitRecipients: rawSplits
          .map((s) => SplitRecipient.fromJson(s as Map<String, dynamic>))
          .toList(),
      isSplitMode: json['isSplitMode'] as bool? ?? (rawSplits.isNotEmpty),
      isSelfTransfer: json['isSelfTransfer'] as bool? ?? (json['flow'] == 'Transfer'),
      toBreakdowns: rawToBreakdowns
          .map((b) => PaymentBreakdown.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }

  double get totalAmount => breakdowns.fold<double>(0.0, (sum, b) => sum + b.amount);

  TransactionTemplate copy() {
    return TransactionTemplate(
      id: id,
      name: name,
      narration: narration,
      flow: flow,
      purpose: purpose,
      spentFor: spentFor,
      breakdowns: breakdowns.map((b) => b.copy()).toList(),
      splitRecipients: splitRecipients?.map((s) => s.copy()).toList(),
      isSplitMode: isSplitMode,
      isSelfTransfer: isSelfTransfer,
      toBreakdowns: toBreakdowns?.map((b) => b.copy()).toList(),
    );
  }

  /// Checks whether another template matches this template across all fields EXCEPT narration.
  bool matchesDataExceptNarration(TransactionTemplate other) {
    if (isSelfTransfer != other.isSelfTransfer) return false;
    if (isSelfTransfer) {
      if (breakdowns.length != other.breakdowns.length) return false;
      for (int i = 0; i < breakdowns.length; i++) {
        final b1 = breakdowns[i];
        final b2 = other.breakdowns[i];
        if (b1.paymentType != b2.paymentType) return false;
        if (b1.effectiveAccount.trim().toLowerCase() != b2.effectiveAccount.trim().toLowerCase()) return false;
        if ((b1.amount - b2.amount).abs() > 0.01) return false;
      }
      final to1 = toBreakdowns ?? [];
      final to2 = other.toBreakdowns ?? [];
      if (to1.length != to2.length) return false;
      for (int i = 0; i < to1.length; i++) {
        final b1 = to1[i];
        final b2 = to2[i];
        if (b1.paymentType != b2.paymentType) return false;
        if (b1.effectiveAccount.trim().toLowerCase() != b2.effectiveAccount.trim().toLowerCase()) return false;
        if ((b1.amount - b2.amount).abs() > 0.01) return false;
      }
      return true;
    }

    if (flow != other.flow) return false;
    if (purpose.trim().toLowerCase() != other.purpose.trim().toLowerCase()) return false;
    if (spentFor.trim().toLowerCase() != other.spentFor.trim().toLowerCase()) return false;
    if (isSplitMode != other.isSplitMode) return false;

    // Compare breakdowns
    if (breakdowns.length != other.breakdowns.length) return false;
    for (int i = 0; i < breakdowns.length; i++) {
      final b1 = breakdowns[i];
      final b2 = other.breakdowns[i];
      if (b1.paymentType != b2.paymentType) return false;
      if (b1.effectiveAccount.trim().toLowerCase() != b2.effectiveAccount.trim().toLowerCase()) return false;
      if ((b1.amount - b2.amount).abs() > 0.01) return false;
    }

    // Compare splitRecipients if split mode
    final splits1 = splitRecipients ?? [];
    final splits2 = other.splitRecipients ?? [];
    if (splits1.length != splits2.length) return false;
    for (int i = 0; i < splits1.length; i++) {
      final s1 = splits1[i];
      final s2 = splits2[i];
      if (s1.name.trim().toLowerCase() != s2.name.trim().toLowerCase()) return false;
      if (s1.isPersonal != s2.isPersonal) return false;
      if ((s1.amount - s2.amount).abs() > 0.01) return false;
    }

    return true;
  }
}

class FinanceTransaction {
  final String id;
  final DateTime date;
  final String referenceId;
  final String narration;
  final String flow;
  final String invoice;
  final String purpose;
  final String spentFor;
  final List<PaymentBreakdown> breakdowns; // In Self Transfer, represents "From"
  final double totalAmount;
  final List<SplitRecipient>? splitRecipients;
  final bool isSplitMode;
  final bool isSelfTransfer;
  final List<PaymentBreakdown>? toBreakdowns; // In Self Transfer, represents "To"

  FinanceTransaction({
    String? id,
    required DateTime date,
    required this.referenceId,
    required this.narration,
    required this.flow,
    required this.invoice,
    required this.purpose,
    required this.spentFor,
    required this.breakdowns,
    required this.totalAmount,
    this.splitRecipients,
    this.isSplitMode = false,
    this.isSelfTransfer = false,
    this.toBreakdowns,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        date = sanitizeDateYear(date);

  static String generateReferenceId(DateTime date) {
    final dayStr = date.day.toString().padLeft(2, '0');
    final monthStr = date.month.toString().padLeft(2, '0');
    final yearStr = date.year.toString();
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final random = Random();
    final randomAlphaNum = List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
    return 'REF-$dayStr$monthStr$yearStr-$randomAlphaNum';
  }

  static String formatDate(DateTime date) {
    return DateFormat('dd/MMM/yyyy').format(date);
  }

  String get fromSummary {
    if (breakdowns.isEmpty) return 'None';
    return breakdowns.map((b) => b.effectiveAccount.isNotEmpty ? b.effectiveAccount : (b.paymentType ?? 'Account')).join(', ');
  }

  String get toSummary {
    if (toBreakdowns == null || toBreakdowns!.isEmpty) return 'None';
    return toBreakdowns!.map((b) => b.effectiveAccount.isNotEmpty ? b.effectiveAccount : (b.paymentType ?? 'Account')).join(', ');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'referenceId': referenceId,
      'narration': narration,
      'flow': flow,
      'invoice': invoice,
      'purpose': purpose,
      'spentFor': spentFor,
      'breakdowns': breakdowns.map((b) => b.toJson()).toList(),
      'totalAmount': totalAmount,
      'splitRecipients': splitRecipients?.map((s) => s.toJson()).toList(),
      'isSplitMode': isSplitMode,
      'isSelfTransfer': isSelfTransfer,
      'toBreakdowns': toBreakdowns?.map((b) => b.toJson()).toList(),
    };
  }

  factory FinanceTransaction.fromJson(Map<String, dynamic> json) {
    final rawBreakdowns = (json['breakdowns'] as List<dynamic>?) ?? [];
    final rawSplits = (json['splitRecipients'] as List<dynamic>?) ?? [];
    final rawToBreakdowns = (json['toBreakdowns'] as List<dynamic>?) ?? [];
    return FinanceTransaction(
      id: json['id'] as String?,
      date: sanitizeDateYear(DateTime.parse(json['date'] as String)),
      referenceId: json['referenceId'] as String? ?? '',
      narration: json['narration'] as String? ?? '',
      flow: json['flow'] as String? ?? 'Withdraw',
      invoice: json['invoice'] as String? ?? '',
      purpose: json['purpose'] as String? ?? '',
      spentFor: json['spentFor'] as String? ?? '',
      breakdowns: rawBreakdowns
          .map((b) => PaymentBreakdown.fromJson(b as Map<String, dynamic>))
          .toList(),
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      splitRecipients: rawSplits
          .map((s) => SplitRecipient.fromJson(s as Map<String, dynamic>))
          .toList(),
      isSplitMode: json['isSplitMode'] as bool? ?? (rawSplits.isNotEmpty),
      isSelfTransfer: json['isSelfTransfer'] as bool? ?? (json['flow'] == 'Transfer'),
      toBreakdowns: rawToBreakdowns
          .map((b) => PaymentBreakdown.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }
}

class RecurringTransaction {
  final String id;
  final String narration;
  final DateTime nextDueDate;
  final String frequency; // 'Month', 'Quarterly', 'Half-Yearly', 'Yearly', 'Custom'
  final int? customMonths;
  final int? customDays;
  final double totalAmount;
  final String flow;
  final String purpose;
  final String spentFor;
  final String invoice;
  final List<PaymentBreakdown> breakdowns;
  final List<PaymentBreakdown>? toBreakdowns;
  final List<SplitRecipient>? splitRecipients;
  final bool isSplitMode;
  final bool isSelfTransfer;
  final bool isPaused;

  RecurringTransaction({
    String? id,
    required this.narration,
    required this.nextDueDate,
    required this.frequency,
    this.customMonths,
    this.customDays,
    required this.totalAmount,
    this.flow = 'Withdraw',
    this.purpose = '',
    this.spentFor = '',
    this.invoice = '',
    required this.breakdowns,
    this.toBreakdowns,
    this.splitRecipients,
    this.isSplitMode = false,
    this.isSelfTransfer = false,
    this.isPaused = false,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  DateTime computeNextDate(DateTime fromDate) {
    switch (frequency) {
      case 'Month':
      case 'Monthly':
        return _addMonths(fromDate, 1);
      case 'Quarterly':
        return _addMonths(fromDate, 3);
      case 'Half-Yearly':
      case 'Halfyearly':
      case 'Half-yearly':
        return _addMonths(fromDate, 6);
      case 'Yearly':
        return _addMonths(fromDate, 12);
      case 'Custom':
        final months = customMonths ?? 0;
        final days = customDays ?? 0;
        final base = months > 0 ? _addMonths(fromDate, months) : fromDate;
        return base.add(Duration(days: days));
      default:
        return _addMonths(fromDate, 1);
    }
  }

  static DateTime _addMonths(DateTime date, int months) {
    int newYear = date.year;
    int newMonth = date.month + months;
    while (newMonth > 12) {
      newYear++;
      newMonth -= 12;
    }
    while (newMonth < 1) {
      newYear--;
      newMonth += 12;
    }
    int daysInMonth = DateTime(newYear, newMonth + 1, 0).day;
    int newDay = date.day > daysInMonth ? daysInMonth : date.day;
    return DateTime(newYear, newMonth, newDay, date.hour, date.minute, date.second);
  }

  RecurringTransaction copyWith({
    String? id,
    String? narration,
    DateTime? nextDueDate,
    String? frequency,
    int? customMonths,
    int? customDays,
    double? totalAmount,
    String? flow,
    String? purpose,
    String? spentFor,
    String? invoice,
    List<PaymentBreakdown>? breakdowns,
    List<PaymentBreakdown>? toBreakdowns,
    List<SplitRecipient>? splitRecipients,
    bool? isSplitMode,
    bool? isSelfTransfer,
    bool? isPaused,
  }) {
    return RecurringTransaction(
      id: id ?? this.id,
      narration: narration ?? this.narration,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      frequency: frequency ?? this.frequency,
      customMonths: customMonths ?? this.customMonths,
      customDays: customDays ?? this.customDays,
      totalAmount: totalAmount ?? this.totalAmount,
      flow: flow ?? this.flow,
      purpose: purpose ?? this.purpose,
      spentFor: spentFor ?? this.spentFor,
      invoice: invoice ?? this.invoice,
      breakdowns: breakdowns ?? this.breakdowns.map((b) => b.copy()).toList(),
      toBreakdowns: toBreakdowns ?? this.toBreakdowns?.map((b) => b.copy()).toList(),
      splitRecipients: splitRecipients ?? this.splitRecipients?.map((s) => s.copy()).toList(),
      isSplitMode: isSplitMode ?? this.isSplitMode,
      isSelfTransfer: isSelfTransfer ?? this.isSelfTransfer,
      isPaused: isPaused ?? this.isPaused,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'narration': narration,
      'nextDueDate': nextDueDate.toIso8601String(),
      'frequency': frequency,
      'customMonths': customMonths,
      'customDays': customDays,
      'totalAmount': totalAmount,
      'flow': flow,
      'purpose': purpose,
      'spentFor': spentFor,
      'invoice': invoice,
      'breakdowns': breakdowns.map((b) => b.toJson()).toList(),
      'toBreakdowns': toBreakdowns?.map((b) => b.toJson()).toList(),
      'splitRecipients': splitRecipients?.map((s) => s.toJson()).toList(),
      'isSplitMode': isSplitMode,
      'isSelfTransfer': isSelfTransfer,
      'isPaused': isPaused,
    };
  }

  factory RecurringTransaction.fromJson(Map<String, dynamic> json) {
    final rawBreakdowns = (json['breakdowns'] as List<dynamic>?) ?? [];
    final rawSplits = (json['splitRecipients'] as List<dynamic>?) ?? [];
    final rawToBreakdowns = (json['toBreakdowns'] as List<dynamic>?) ?? [];
    return RecurringTransaction(
      id: json['id'] as String?,
      narration: json['narration'] as String? ?? '',
      nextDueDate: DateTime.parse(json['nextDueDate'] as String),
      frequency: json['frequency'] as String? ?? 'Month',
      customMonths: json['customMonths'] as int?,
      customDays: json['customDays'] as int?,
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      flow: json['flow'] as String? ?? 'Withdraw',
      purpose: json['purpose'] as String? ?? '',
      spentFor: json['spentFor'] as String? ?? '',
      invoice: json['invoice'] as String? ?? '',
      breakdowns: rawBreakdowns
          .map((b) => PaymentBreakdown.fromJson(b as Map<String, dynamic>))
          .toList(),
      toBreakdowns: rawToBreakdowns
          .map((b) => PaymentBreakdown.fromJson(b as Map<String, dynamic>))
          .toList(),
      splitRecipients: rawSplits
          .map((s) => SplitRecipient.fromJson(s as Map<String, dynamic>))
          .toList(),
      isSplitMode: json['isSplitMode'] as bool? ?? false,
      isSelfTransfer: json['isSelfTransfer'] as bool? ?? false,
      isPaused: json['isPaused'] as bool? ?? false,
    );
  }
}

class LoanEntry {
  final String id;
  final DateTime date;
  final String borrower;
  final String narration;
  final String invoice;
  final String transactionType;
  final String account;
  final double givenAmount;
  final double receivedAmount;
  final String referenceId;
  final FinanceTransaction? parentTransaction;

  LoanEntry({
    String? id,
    required DateTime date,
    required this.borrower,
    required this.narration,
    this.invoice = '',
    this.transactionType = '',
    this.account = '',
    this.givenAmount = 0.0,
    this.receivedAmount = 0.0,
    required this.referenceId,
    this.parentTransaction,
  })  : id = id ?? '${referenceId}_${borrower}_${givenAmount}_$receivedAmount',
        date = sanitizeDateYear(date);

  double get amount => givenAmount > 0 ? givenAmount : receivedAmount;
  bool get isGiven => givenAmount > 0;
  double get netAmount => givenAmount - receivedAmount;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'borrower': borrower,
      'narration': narration,
      'invoice': invoice,
      'transactionType': transactionType,
      'account': account,
      'givenAmount': givenAmount,
      'receivedAmount': receivedAmount,
      'referenceId': referenceId,
    };
  }

  factory LoanEntry.fromJson(Map<String, dynamic> json) {
    return LoanEntry(
      id: json['id'] as String?,
      date: sanitizeDateYear(DateTime.parse(json['date'] as String)),
      borrower: json['borrower'] as String? ?? '',
      narration: json['narration'] as String? ?? '',
      invoice: json['invoice'] as String? ?? '',
      transactionType: json['transactionType'] as String? ?? '',
      account: json['account'] as String? ?? '',
      givenAmount: (json['givenAmount'] as num?)?.toDouble() ?? 0.0,
      receivedAmount: (json['receivedAmount'] as num?)?.toDouble() ?? 0.0,
      referenceId: json['referenceId'] as String? ?? '',
    );
  }
}
