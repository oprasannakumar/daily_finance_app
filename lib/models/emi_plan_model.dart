import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';

class EmiInstallment {
  final int installmentNumber;
  DateTime billingDate;
  double emiAmount;
  double principal;
  double interest;
  double balancePrincipal;
  double applicableTaxes; // 18% GST on interest in India
  bool isPaid;
  DateTime? paidDate;
  String? paymentReference;

  EmiInstallment({
    required this.installmentNumber,
    required this.billingDate,
    required this.emiAmount,
    required this.principal,
    required this.interest,
    required this.balancePrincipal,
    this.applicableTaxes = 0.0,
    this.isPaid = false,
    this.paidDate,
    this.paymentReference,
  });

  double get totalDueWithTax => emiAmount + applicableTaxes;

  EmiInstallment copyWith({
    int? installmentNumber,
    DateTime? billingDate,
    double? emiAmount,
    double? principal,
    double? interest,
    double? balancePrincipal,
    double? applicableTaxes,
    bool? isPaid,
    DateTime? paidDate,
    String? paymentReference,
  }) {
    return EmiInstallment(
      installmentNumber: installmentNumber ?? this.installmentNumber,
      billingDate: billingDate ?? this.billingDate,
      emiAmount: emiAmount ?? this.emiAmount,
      principal: principal ?? this.principal,
      interest: interest ?? this.interest,
      balancePrincipal: balancePrincipal ?? this.balancePrincipal,
      applicableTaxes: applicableTaxes ?? this.applicableTaxes,
      isPaid: isPaid ?? this.isPaid,
      paidDate: paidDate ?? this.paidDate,
      paymentReference: paymentReference ?? this.paymentReference,
    );
  }

  Map<String, dynamic> toJson() => {
        'installmentNumber': installmentNumber,
        'billingDate': DateFormat('yyyy-MM-dd').format(billingDate),
        'emiAmount': emiAmount,
        'principal': principal,
        'interest': interest,
        'balancePrincipal': balancePrincipal,
        'applicableTaxes': applicableTaxes,
        'isPaid': isPaid,
        'paidDate': paidDate != null ? DateFormat('yyyy-MM-dd').format(paidDate!) : null,
        'paymentReference': paymentReference,
      };

  factory EmiInstallment.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      try {
        return DateTime.parse(val.toString());
      } catch (_) {
        return DateTime.now();
      }
    }

    return EmiInstallment(
      installmentNumber: (json['installmentNumber'] as num?)?.toInt() ?? 1,
      billingDate: parseDate(json['billingDate']),
      emiAmount: (json['emiAmount'] as num?)?.toDouble() ?? 0.0,
      principal: (json['principal'] as num?)?.toDouble() ?? 0.0,
      interest: (json['interest'] as num?)?.toDouble() ?? 0.0,
      balancePrincipal: (json['balancePrincipal'] as num?)?.toDouble() ?? 0.0,
      applicableTaxes: (json['applicableTaxes'] as num?)?.toDouble() ?? 0.0,
      isPaid: json['isPaid'] == true,
      paidDate: json['paidDate'] != null ? DateTime.tryParse(json['paidDate'].toString()) : null,
      paymentReference: json['paymentReference'] as String?,
    );
  }
}

class EmiPlan {
  final String id;
  final String title;
  final String account;
  final DateTime transactionDate;
  final double totalTransactionAmount;
  final double bookingPrincipal;
  final double annualInterestRate;
  final int tenureMonths;
  final double processingFee;
  final double processingFeeGst;
  final DateTime firstEmiDate;
  final List<EmiInstallment> installments;
  final String status; // 'ACTIVE', 'COMPLETED', 'PRECLOSED'
  final String? notes;

  EmiPlan({
    required this.id,
    required this.title,
    required this.account,
    required this.transactionDate,
    required this.totalTransactionAmount,
    required this.bookingPrincipal,
    required this.annualInterestRate,
    required this.tenureMonths,
    this.processingFee = 0.0,
    this.processingFeeGst = 0.0,
    required this.firstEmiDate,
    required this.installments,
    this.status = 'ACTIVE',
    this.notes,
  });

  /// The non-converted swipe amount that remains on the regular credit card statement.
  double get nonEmiBalance => max(0.0, totalTransactionAmount - bookingPrincipal);

  bool get isPartialConversion => nonEmiBalance > 0.01;

  double get totalPrincipalPaid =>
      installments.where((it) => it.isPaid).fold(0.0, (sum, it) => sum + it.principal);

  double get remainingPrincipal => max(0.0, bookingPrincipal - totalPrincipalPaid);

  double get totalInterest =>
      installments.fold(0.0, (sum, it) => sum + it.interest);

  double get totalGst =>
      installments.fold(0.0, (sum, it) => sum + it.applicableTaxes) + processingFeeGst;

  double get totalRepayableWithTax =>
      installments.fold(0.0, (sum, it) => sum + it.totalDueWithTax) + processingFee + processingFeeGst;

  int get paidInstallmentsCount =>
      installments.where((it) => it.isPaid).length;

  double get progressFraction =>
      tenureMonths > 0 ? (paidInstallmentsCount / tenureMonths).clamp(0.0, 1.0) : 0.0;

  EmiInstallment? get nextDueInstallment {
    for (final it in installments) {
      if (!it.isPaid) return it;
    }
    return null;
  }

  /// Calculates a standard reducing-balance amortization schedule.
  static List<EmiInstallment> calculateSchedule({
    required double principal,
    required double annualInterestRate,
    required int tenureMonths,
    required DateTime firstEmiDate,
    double defaultGstRate = 0.18, // 18% GST on interest
  }) {
    if (tenureMonths <= 0 || principal <= 0) return [];

    final r = (annualInterestRate / 100.0) / 12.0;
    double emi;
    if (r == 0) {
      emi = principal / tenureMonths;
    } else {
      emi = (principal * r * pow(1 + r, tenureMonths)) / (pow(1 + r, tenureMonths) - 1);
    }

    final schedule = <EmiInstallment>[];
    double balance = principal;

    for (int i = 1; i <= tenureMonths; i++) {
      final billingDate = addMonthsClamped(firstEmiDate, i - 1);
      final interest = balance * r;
      double installmentPrincipal = emi - interest;

      if (i == tenureMonths) {
        // Final installment adjustments for exact paise closure
        installmentPrincipal = balance;
        balance = 0.0;
      } else {
        balance = max(0.0, balance - installmentPrincipal);
      }

      final applicableTax = interest * defaultGstRate;

      schedule.add(EmiInstallment(
        installmentNumber: i,
        billingDate: billingDate,
        emiAmount: double.parse(emi.toStringAsFixed(2)),
        principal: double.parse(installmentPrincipal.toStringAsFixed(2)),
        interest: double.parse(interest.toStringAsFixed(2)),
        balancePrincipal: double.parse(balance.toStringAsFixed(2)),
        applicableTaxes: double.parse(applicableTax.toStringAsFixed(2)),
        isPaid: false,
      ));
    }

    return schedule;
  }

  /// Safely advances months without skipping past month-ends (e.g. Jan 31 -> Feb 28).
  static DateTime addMonthsClamped(DateTime start, int monthsToAdd) {
    int year = start.year;
    int month = start.month + monthsToAdd;
    while (month > 12) {
      year += 1;
      month -= 12;
    }
    while (month < 1) {
      year -= 1;
      month += 12;
    }
    // Days in target month
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final day = min(start.day, daysInMonth);
    return DateTime(year, month, day);
  }

  EmiPlan copyWith({
    String? id,
    String? title,
    String? account,
    DateTime? transactionDate,
    double? totalTransactionAmount,
    double? bookingPrincipal,
    double? annualInterestRate,
    int? tenureMonths,
    double? processingFee,
    double? processingFeeGst,
    DateTime? firstEmiDate,
    List<EmiInstallment>? installments,
    String? status,
    String? notes,
  }) {
    return EmiPlan(
      id: id ?? this.id,
      title: title ?? this.title,
      account: account ?? this.account,
      transactionDate: transactionDate ?? this.transactionDate,
      totalTransactionAmount: totalTransactionAmount ?? this.totalTransactionAmount,
      bookingPrincipal: bookingPrincipal ?? this.bookingPrincipal,
      annualInterestRate: annualInterestRate ?? this.annualInterestRate,
      tenureMonths: tenureMonths ?? this.tenureMonths,
      processingFee: processingFee ?? this.processingFee,
      processingFeeGst: processingFeeGst ?? this.processingFeeGst,
      firstEmiDate: firstEmiDate ?? this.firstEmiDate,
      installments: installments ?? this.installments.map((it) => it.copyWith()).toList(),
      status: status ?? this.status,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'account': account,
        'transactionDate': DateFormat('yyyy-MM-dd').format(transactionDate),
        'totalTransactionAmount': totalTransactionAmount,
        'bookingPrincipal': bookingPrincipal,
        'annualInterestRate': annualInterestRate,
        'tenureMonths': tenureMonths,
        'processingFee': processingFee,
        'processingFeeGst': processingFeeGst,
        'firstEmiDate': DateFormat('yyyy-MM-dd').format(firstEmiDate),
        'status': status,
        'notes': notes,
        'installments': installments.map((it) => it.toJson()).toList(),
      };

  factory EmiPlan.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      try {
        return DateTime.parse(val.toString());
      } catch (_) {
        return DateTime.now();
      }
    }

    final rawInst = json['installments'] as List<dynamic>? ?? [];
    final installments = rawInst
        .map((it) => EmiInstallment.fromJson(it as Map<String, dynamic>))
        .toList();

    return EmiPlan(
      id: json['id'] as String? ?? 'EMI-${DateTime.now().millisecondsSinceEpoch}',
      title: json['title'] as String? ?? 'Credit Card EMI',
      account: json['account'] as String? ?? 'Credit Card',
      transactionDate: parseDate(json['transactionDate']),
      totalTransactionAmount: (json['totalTransactionAmount'] as num?)?.toDouble() ?? 0.0,
      bookingPrincipal: (json['bookingPrincipal'] as num?)?.toDouble() ?? 0.0,
      annualInterestRate: (json['annualInterestRate'] as num?)?.toDouble() ?? 0.0,
      tenureMonths: (json['tenureMonths'] as num?)?.toInt() ?? 6,
      processingFee: (json['processingFee'] as num?)?.toDouble() ?? 0.0,
      processingFeeGst: (json['processingFeeGst'] as num?)?.toDouble() ?? 0.0,
      firstEmiDate: parseDate(json['firstEmiDate']),
      installments: installments,
      status: json['status'] as String? ?? 'ACTIVE',
      notes: json['notes'] as String?,
    );
  }

  List<dynamic> toSheetRow() {
    return [
      id,
      title,
      account,
      DateFormat('yyyy-MM-dd').format(transactionDate),
      totalTransactionAmount,
      bookingPrincipal,
      tenureMonths,
      annualInterestRate,
      processingFee,
      processingFeeGst,
      DateFormat('yyyy-MM-dd').format(firstEmiDate),
      status,
      notes ?? '',
      jsonEncode(installments.map((it) => it.toJson()).toList()),
    ];
  }

  factory EmiPlan.fromSheetRow(List<dynamic> row) {
    if (row.isEmpty) {
      throw FormatException('Empty EMI row');
    }

    String getString(int index) => index < row.length ? row[index]?.toString().trim() ?? '' : '';
    double getDouble(int index) {
      if (index >= row.length) return 0.0;
      final val = row[index];
      if (val is num) return val.toDouble();
      return double.tryParse(val?.toString().replaceAll(',', '').trim() ?? '') ?? 0.0;
    }
    int getInt(int index) {
      if (index >= row.length) return 0;
      final val = row[index];
      if (val is num) return val.toInt();
      return int.tryParse(val?.toString().trim() ?? '') ?? 0;
    }
    DateTime parseDate(int index) {
      final str = getString(index);
      if (str.isEmpty) return DateTime.now();
      try {
        if (str.contains('-')) {
          return DateTime.parse(str);
        }
        if (str.contains('/')) {
          final parts = str.split('/');
          if (parts.length == 3) {
            // DD/MM/YYYY
            final d = int.parse(parts[0]);
            final m = int.parse(parts[1]);
            final y = int.parse(parts[2]);
            return DateTime(y, m, d);
          }
        }
      } catch (_) {}
      return DateTime.now();
    }

    final id = getString(0);
    final title = getString(1);
    final account = getString(2);
    final txDate = parseDate(3);
    final totalAmount = getDouble(4);
    final principal = getDouble(5);
    final tenure = getInt(6);
    final roi = getDouble(7);
    final procFee = getDouble(8);
    final procFeeGst = getDouble(9);
    final firstDate = parseDate(10);
    final status = getString(11).isNotEmpty ? getString(11) : 'ACTIVE';
    final notes = getString(12);

    List<EmiInstallment> installments = [];
    if (row.length > 13) {
      final jsonStr = getString(13);
      if (jsonStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(jsonStr) as List<dynamic>;
          installments = decoded
              .map((it) => EmiInstallment.fromJson(it as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }
    }

    if (installments.isEmpty) {
      installments = calculateSchedule(
        principal: principal > 0 ? principal : totalAmount,
        annualInterestRate: roi,
        tenureMonths: tenure > 0 ? tenure : 6,
        firstEmiDate: firstDate,
      );
    }

    return EmiPlan(
      id: id,
      title: title,
      account: account,
      transactionDate: txDate,
      totalTransactionAmount: totalAmount,
      bookingPrincipal: principal > 0 ? principal : totalAmount,
      annualInterestRate: roi,
      tenureMonths: tenure > 0 ? tenure : 6,
      processingFee: procFee,
      processingFeeGst: procFeeGst,
      firstEmiDate: firstDate,
      installments: installments,
      status: status,
      notes: notes.isNotEmpty ? notes : null,
    );
  }
}
