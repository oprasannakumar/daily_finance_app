import 'emi_plan_model.dart';
import 'transaction_model.dart';

class CreditCardLimit {
  final double totalLimit;
  final double initialUsedAmount;
  final String? sharedGroupName; // e.g. 'Axis Bank Cards', null/empty if standalone
  final double? groupTotalLimit; // Limit of the shared group
  final int? billDay; // 1 to 31: day of month when bill is generated
  final int? dueDay; // 1 to 31: day of month when bill is due
  final double? statementBilledAmount; // Active statement billed amount
  final String? manualPaidCycle; // e.g. '2026-11' when manually marked as paid

  const CreditCardLimit({
    required this.totalLimit,
    this.initialUsedAmount = 0.0,
    this.sharedGroupName,
    this.groupTotalLimit,
    this.billDay,
    this.dueDay,
    this.statementBilledAmount,
    this.manualPaidCycle,
  });

  bool get isShared => sharedGroupName != null && sharedGroupName!.trim().isNotEmpty;

  double get effectiveTotalLimit => isShared ? (groupTotalLimit ?? totalLimit) : totalLimit;

  double get initialAvailableLimit => (effectiveTotalLimit - initialUsedAmount).clamp(0.0, double.infinity);

  Map<String, dynamic> toJson() => {
        'totalLimit': totalLimit,
        'initialUsedAmount': initialUsedAmount,
        'sharedGroupName': sharedGroupName,
        'groupTotalLimit': groupTotalLimit,
        'billDay': billDay,
        'dueDay': dueDay,
        'statementBilledAmount': statementBilledAmount,
        'manualPaidCycle': manualPaidCycle,
      };

  factory CreditCardLimit.fromJson(Map<String, dynamic> json) => CreditCardLimit(
        totalLimit: (json['totalLimit'] as num?)?.toDouble() ?? 0.0,
        initialUsedAmount: (json['initialUsedAmount'] as num?)?.toDouble() ?? 0.0,
        sharedGroupName: json['sharedGroupName'] as String?,
        groupTotalLimit: (json['groupTotalLimit'] as num?)?.toDouble(),
        billDay: (json['billDay'] as num?)?.toInt(),
        dueDay: (json['dueDay'] as num?)?.toInt(),
        statementBilledAmount: (json['statementBilledAmount'] as num?)?.toDouble(),
        manualPaidCycle: json['manualPaidCycle'] as String?,
      );

  CreditCardLimit copyWith({
    double? totalLimit,
    double? initialUsedAmount,
    String? sharedGroupName,
    double? groupTotalLimit,
    int? billDay,
    int? dueDay,
    double? statementBilledAmount,
    String? manualPaidCycle,
  }) {
    return CreditCardLimit(
      totalLimit: totalLimit ?? this.totalLimit,
      initialUsedAmount: initialUsedAmount ?? this.initialUsedAmount,
      sharedGroupName: sharedGroupName ?? this.sharedGroupName,
      groupTotalLimit: groupTotalLimit ?? this.groupTotalLimit,
      billDay: billDay ?? this.billDay,
      dueDay: dueDay ?? this.dueDay,
      statementBilledAmount: statementBilledAmount ?? this.statementBilledAmount,
      manualPaidCycle: manualPaidCycle ?? this.manualPaidCycle,
    );
  }
}

class CreditCardDueBill {
  final String cardName;
  final String? sharedGroupName;
  final DateTime billDate;
  final DateTime dueDate;
  final double billedAmount;
  final double paidAmount;
  final double remainingDue;
  final String cycleKey; // e.g. '2026-11'
  final bool isOverdue;
  final bool isDueToday;
  final int daysUntilDue;

  CreditCardDueBill({
    required this.cardName,
    this.sharedGroupName,
    required this.billDate,
    required this.dueDate,
    required this.billedAmount,
    required this.paidAmount,
    required this.remainingDue,
    required this.cycleKey,
    required this.isOverdue,
    required this.isDueToday,
    required this.daysUntilDue,
  });
}

class AccountBalanceConfig {
  final Map<String, double> bankOpeningBalances;
  final Map<String, CreditCardLimit> creditCardLimits;
  final Map<int, int> cashOpeningDenominations; // 500, 200, 100, 50, 20, 10, 5, 2, 1
  final Map<String, double> walletOpeningBalances;
  final Map<String, double> rewardOpeningBalances;
  final DateTime setupDate;
  final bool isConfigured;

  AccountBalanceConfig({
    Map<String, double>? bankOpeningBalances,
    Map<String, CreditCardLimit>? creditCardLimits,
    Map<int, int>? cashOpeningDenominations,
    Map<String, double>? walletOpeningBalances,
    Map<String, double>? rewardOpeningBalances,
    DateTime? setupDate,
    this.isConfigured = false,
  })  : bankOpeningBalances = bankOpeningBalances ?? {},
        creditCardLimits = creditCardLimits ?? {},
        walletOpeningBalances = walletOpeningBalances ?? {},
        rewardOpeningBalances = rewardOpeningBalances ?? {},
        cashOpeningDenominations = cashOpeningDenominations ??
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
            },
        setupDate = setupDate ?? DateTime.now();

  double get totalCashInHand {
    double sum = 0.0;
    cashOpeningDenominations.forEach((denom, count) {
      sum += denom * count;
    });
    return sum;
  }

  double get totalWalletOpeningBalance => walletOpeningBalances.values.fold(0.0, (sum, b) => sum + b);
  double get totalRewardOpeningBalance => rewardOpeningBalances.values.fold(0.0, (sum, b) => sum + b);

  Map<String, dynamic> toJson() => {
        'bankOpeningBalances': bankOpeningBalances,
        'creditCardLimits': creditCardLimits.map((k, v) => MapEntry(k, v.toJson())),
        'cashOpeningDenominations': cashOpeningDenominations.map((k, v) => MapEntry(k.toString(), v)),
        'walletOpeningBalances': walletOpeningBalances,
        'rewardOpeningBalances': rewardOpeningBalances,
        'setupDate': setupDate.toIso8601String(),
        'isConfigured': isConfigured,
      };

  factory AccountBalanceConfig.fromJson(Map<String, dynamic> json) {
    final rawBank = json['bankOpeningBalances'] as Map<String, dynamic>? ?? {};
    final Map<String, double> banks = {};
    rawBank.forEach((k, v) {
      banks[k] = (v as num).toDouble();
    });

    final rawCC = json['creditCardLimits'] as Map<String, dynamic>? ?? {};
    final Map<String, CreditCardLimit> ccs = {};
    rawCC.forEach((k, v) {
      if (v is Map<String, dynamic>) {
        ccs[k] = CreditCardLimit.fromJson(v);
      }
    });

    final rawCash = json['cashOpeningDenominations'] as Map<String, dynamic>? ?? {};
    final Map<int, int> cash = {
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
    rawCash.forEach((k, v) {
      final parsedKey = int.tryParse(k);
      if (parsedKey != null) {
        cash[parsedKey] = (v as num).toInt();
      }
    });

    final rawWallet = json['walletOpeningBalances'] as Map<String, dynamic>? ?? {};
    final Map<String, double> wallets = {};
    rawWallet.forEach((k, v) {
      wallets[k] = (v as num).toDouble();
    });

    final rawReward = json['rewardOpeningBalances'] as Map<String, dynamic>? ?? {};
    final Map<String, double> rewards = {};
    rawReward.forEach((k, v) {
      rewards[k] = (v as num).toDouble();
    });

    return AccountBalanceConfig(
      bankOpeningBalances: banks,
      creditCardLimits: ccs,
      cashOpeningDenominations: cash,
      walletOpeningBalances: wallets,
      rewardOpeningBalances: rewards,
      setupDate: json['setupDate'] != null ? DateTime.tryParse(json['setupDate'] as String) ?? DateTime.now() : DateTime.now(),
      isConfigured: json['isConfigured'] as bool? ?? false,
    );
  }

  AccountBalanceConfig copyWith({
    Map<String, double>? bankOpeningBalances,
    Map<String, CreditCardLimit>? creditCardLimits,
    Map<int, int>? cashOpeningDenominations,
    Map<String, double>? walletOpeningBalances,
    Map<String, double>? rewardOpeningBalances,
    DateTime? setupDate,
    bool? isConfigured,
  }) {
    return AccountBalanceConfig(
      bankOpeningBalances: bankOpeningBalances ?? Map<String, double>.from(this.bankOpeningBalances),
      creditCardLimits: creditCardLimits ?? Map<String, CreditCardLimit>.from(this.creditCardLimits),
      cashOpeningDenominations: cashOpeningDenominations ?? Map<int, int>.from(this.cashOpeningDenominations),
      walletOpeningBalances: walletOpeningBalances ?? Map<String, double>.from(this.walletOpeningBalances),
      rewardOpeningBalances: rewardOpeningBalances ?? Map<String, double>.from(this.rewardOpeningBalances),
      setupDate: setupDate ?? this.setupDate,
      isConfigured: isConfigured ?? this.isConfigured,
    );
  }
}

class LiveCreditCardSummary {
  final String cardName;
  final double totalLimit;
  final double usedLimit;
  final double availableLimit;
  final bool isShared;
  final String? sharedGroupName;
  final double? groupTotalLimit;
  final double? groupTotalUsed;
  final int? billDay;
  final int? dueDay;
  final DateTime? nextBillDate;
  final DateTime? nextDueDate;
  final CreditCardDueBill? dueBill;
  final double unbilledEmiPrincipal;
  final int activeEmiPlansCount;
  final DateTime? nextEmiDueDate;
  final double? nextEmiAmount;

  LiveCreditCardSummary({
    this.cardName = '',
    required this.totalLimit,
    required this.usedLimit,
    required this.availableLimit,
    this.isShared = false,
    this.sharedGroupName,
    this.groupTotalLimit,
    this.groupTotalUsed,
    this.billDay,
    this.dueDay,
    this.nextBillDate,
    this.nextDueDate,
    this.dueBill,
    this.unbilledEmiPrincipal = 0.0,
    this.activeEmiPlansCount = 0,
    this.nextEmiDueDate,
    this.nextEmiAmount,
  });

  double get billedDueAmount => dueBill?.remainingDue ?? 0.0;
  double get blockedEmiPrincipal => unbilledEmiPrincipal;
  double get unbilledSpendAmount =>
      (usedLimit - billedDueAmount - blockedEmiPrincipal).clamp(0.0, double.infinity);

  /// Estimated interest-free credit days for a purchase made today.
  int? get interestFreeDays {
    if (nextBillDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final bill = DateTime(nextBillDate!.year, nextBillDate!.month, nextBillDate!.day);

    DateTime dueForNextBill;
    if (dueDay != null && billDay != null) {
      final targetMonth = dueDay! > billDay! ? bill.month : bill.month + 1;
      final daysInTargetMonth = DateTime(bill.year, targetMonth + 1, 0).day;
      dueForNextBill = DateTime(bill.year, targetMonth, dueDay!.clamp(1, daysInTargetMonth));
    } else {
      dueForNextBill = bill.add(const Duration(days: 20));
    }

    return dueForNextBill.difference(today).inDays.clamp(0, 62);
  }
}

class LiveAccountBalanceSummary {
  final Map<String, double> bankBalances;
  final Map<String, LiveCreditCardSummary> creditCardSummaries;
  final Map<int, int> cashDenominations;
  final double totalCashInHand;
  final Map<String, double> walletBalances;
  final Map<String, double> rewardBalances;
  /// Maps each transaction ID to a map of {AccountName: RunningBalance} after that transaction
  final Map<String, Map<String, double>> txRunningBalances;
  final List<CreditCardDueBill> dueBills;

  LiveAccountBalanceSummary({
    required this.bankBalances,
    required this.creditCardSummaries,
    required this.cashDenominations,
    required this.totalCashInHand,
    required this.txRunningBalances,
    this.walletBalances = const {},
    this.rewardBalances = const {},
    this.dueBills = const [],
  });

  int get totalDueBillsCount => dueBills.length;
  double get totalBankBalance => bankBalances.values.fold(0.0, (sum, b) => sum + b);
  double get totalCashBalance => totalCashInHand;
  double get totalWalletBalance => walletBalances.values.fold(0.0, (sum, b) => sum + b);
  double get totalRewardBalance => rewardBalances.values.fold(0.0, (sum, b) => sum + b);
  double get totalCreditCardUsed => creditCardSummaries.values.fold(0.0, (sum, c) => sum + c.usedLimit);
  double get totalCreditCardLimit => creditCardSummaries.values.fold(0.0, (sum, c) => sum + c.totalLimit);
  double get totalDueBills => dueBills.fold(0.0, (sum, b) => sum + b.remainingDue);
  double get totalUnbilledEmiPrincipal =>
      creditCardSummaries.values.fold(0.0, (sum, c) => sum + c.unbilledEmiPrincipal);

  static LiveAccountBalanceSummary calculate({
    required AccountBalanceConfig config,
    required List<FinanceTransaction> transactions,
    required Map<String, List<String>> categories,
    List<EmiPlan>? emiPlans,
    DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final ccList = categories['Credit Cards'] ?? [];
    final walletList = categories['Wallets'] ?? [];
    final rewardList = categories['Rewards'] ?? [];

    bool isCreditCard(String accountName, [String? paymentType]) {
      final accLower = accountName.trim().toLowerCase();
      if (config.creditCardLimits.containsKey(accountName)) return true;
      if (ccList.any((c) => c.trim().toLowerCase() == accLower)) return true;
      if (paymentType != null && paymentType.toLowerCase().contains('credit')) return true;
      return false;
    }

    bool isCash(String? paymentType) {
      if (paymentType == null) return false;
      return paymentType.trim().toLowerCase() == 'cash';
    }

    bool isWallet(String accountName, [String? paymentType]) {
      final accLower = accountName.trim().toLowerCase();
      if (config.walletOpeningBalances.containsKey(accountName)) return true;
      if (walletList.any((w) => w.trim().toLowerCase() == accLower)) return true;
      if (paymentType != null && paymentType.toLowerCase().contains('wallet')) return true;
      return false;
    }

    bool isReward(String accountName, [String? paymentType]) {
      final accLower = accountName.trim().toLowerCase();
      if (config.rewardOpeningBalances.containsKey(accountName)) return true;
      if (rewardList.any((r) => r.trim().toLowerCase() == accLower)) return true;
      if (paymentType != null && paymentType.toLowerCase().contains('reward')) return true;
      return false;
    }

    // Initialize running balances with opening configuration
    final Map<String, double> currentBankBalances = Map<String, double>.from(config.bankOpeningBalances);
    final Map<String, double> currentWalletBalances = Map<String, double>.from(config.walletOpeningBalances);
    final Map<String, double> currentRewardBalances = Map<String, double>.from(config.rewardOpeningBalances);
    final Map<String, double> currentCCUsed = {};
    for (final entry in config.creditCardLimits.entries) {
      currentCCUsed[entry.key] = entry.value.initialUsedAmount;
    }

    final Map<int, int> currentCashDenoms = Map<int, int>.from(config.cashOpeningDenominations);
    double currentCashTotal = config.totalCashInHand;

    final Map<String, Map<String, double>> runningMap = {};

    // Sort transactions chronologically: oldest first
    final chronologicalTx = List<FinanceTransaction>.from(transactions)
      ..sort((a, b) {
        final cmp = a.date.compareTo(b.date);
        if (cmp != 0) return cmp;
        return a.referenceId.compareTo(b.referenceId);
      });

    final setupStartOfDay = DateTime(config.setupDate.year, config.setupDate.month, config.setupDate.day);

    for (final tx in chronologicalTx) {
      final txDay = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (txDay.isBefore(setupStartOfDay)) continue;

      final Map<String, double> accountsTouched = {};

      if (tx.isSelfTransfer || tx.flow == 'Transfer') {
        // Outflow from breakdowns
        for (final b in tx.breakdowns) {
          final acc = b.effectiveAccount;
          final pt = b.paymentType ?? '';
          final amt = b.amount;

          if (isCash(pt)) {
            currentCashTotal -= amt;
            b.denominations.forEach((denom, count) {
              final prev = currentCashDenoms[denom] ?? 0;
              currentCashDenoms[denom] = prev - (count as num).toInt();
            });
          } else if (isCreditCard(acc, pt)) {
            currentCCUsed[acc] = (currentCCUsed[acc] ?? 0.0) + amt;
          } else if (isWallet(acc, pt)) {
            currentWalletBalances[acc] = (currentWalletBalances[acc] ?? 0.0) - amt;
            accountsTouched[acc] = currentWalletBalances[acc]!;
          } else if (isReward(acc, pt)) {
            currentRewardBalances[acc] = (currentRewardBalances[acc] ?? 0.0) - amt;
            accountsTouched[acc] = currentRewardBalances[acc]!;
          } else {
            currentBankBalances[acc] = (currentBankBalances[acc] ?? 0.0) - amt;
            accountsTouched[acc] = currentBankBalances[acc]!;
          }
        }

        // Inflow to toBreakdowns
        for (final to in (tx.toBreakdowns ?? [])) {
          final acc = to.effectiveAccount;
          final pt = to.paymentType ?? '';
          final amt = to.amount;

          if (isCash(pt)) {
            currentCashTotal += amt;
            to.denominations.forEach((denom, count) {
              final prev = currentCashDenoms[denom] ?? 0;
              currentCashDenoms[denom] = prev + (count as num).toInt();
            });
          } else if (isCreditCard(acc, pt)) {
            currentCCUsed[acc] = (currentCCUsed[acc] ?? 0.0) - amt;
          } else if (isWallet(acc, pt)) {
            currentWalletBalances[acc] = (currentWalletBalances[acc] ?? 0.0) + amt;
            accountsTouched[acc] = currentWalletBalances[acc]!;
          } else if (isReward(acc, pt)) {
            currentRewardBalances[acc] = (currentRewardBalances[acc] ?? 0.0) + amt;
            accountsTouched[acc] = currentRewardBalances[acc]!;
          } else {
            currentBankBalances[acc] = (currentBankBalances[acc] ?? 0.0) + amt;
            accountsTouched[acc] = currentBankBalances[acc]!;
          }
        }
      } else if (tx.flow == 'Withdraw') {
        for (final b in tx.breakdowns) {
          final acc = b.effectiveAccount;
          final pt = b.paymentType ?? '';
          final amt = b.amount;

          if (isCash(pt)) {
            currentCashTotal -= amt;
            b.denominations.forEach((denom, count) {
              final prev = currentCashDenoms[denom] ?? 0;
              currentCashDenoms[denom] = prev - (count as num).toInt();
            });
          } else if (isCreditCard(acc, pt)) {
            currentCCUsed[acc] = (currentCCUsed[acc] ?? 0.0) + amt;
          } else if (isWallet(acc, pt)) {
            currentWalletBalances[acc] = (currentWalletBalances[acc] ?? 0.0) - amt;
            accountsTouched[acc] = currentWalletBalances[acc]!;
          } else if (isReward(acc, pt)) {
            currentRewardBalances[acc] = (currentRewardBalances[acc] ?? 0.0) - amt;
            accountsTouched[acc] = currentRewardBalances[acc]!;
          } else {
            currentBankBalances[acc] = (currentBankBalances[acc] ?? 0.0) - amt;
            accountsTouched[acc] = currentBankBalances[acc]!;
          }
        }
      } else if (tx.flow == 'Deposit') {
        for (final b in tx.breakdowns) {
          final acc = b.effectiveAccount;
          final pt = b.paymentType ?? '';
          final amt = b.amount;

          if (isCash(pt)) {
            currentCashTotal += amt;
            b.denominations.forEach((denom, count) {
              final prev = currentCashDenoms[denom] ?? 0;
              currentCashDenoms[denom] = prev + (count as num).toInt();
            });
          } else if (isCreditCard(acc, pt)) {
            currentCCUsed[acc] = (currentCCUsed[acc] ?? 0.0) - amt;
          } else if (isWallet(acc, pt)) {
            currentWalletBalances[acc] = (currentWalletBalances[acc] ?? 0.0) + amt;
            accountsTouched[acc] = currentWalletBalances[acc]!;
          } else if (isReward(acc, pt)) {
            currentRewardBalances[acc] = (currentRewardBalances[acc] ?? 0.0) + amt;
            accountsTouched[acc] = currentRewardBalances[acc]!;
          } else {
            currentBankBalances[acc] = (currentBankBalances[acc] ?? 0.0) + amt;
            accountsTouched[acc] = currentBankBalances[acc]!;
          }
        }
      }

      if (accountsTouched.isNotEmpty) {
        runningMap[tx.id] = Map<String, double>.from(accountsTouched);
      }
    }

    // ==========================================
    // SHARED LIMIT GROUP CALCULATIONS
    // ==========================================
    final Map<String, double> groupTotalLimits = {};
    final Map<String, double> groupTotalUsed = {};

    for (final entry in config.creditCardLimits.entries) {
      final card = entry.value;
      if (card.isShared) {
        final gName = card.sharedGroupName!.trim();
        final gLimit = card.groupTotalLimit ?? card.totalLimit;
        groupTotalLimits[gName] = gLimit;
        final used = currentCCUsed[entry.key] ?? card.initialUsedAmount;
        groupTotalUsed[gName] = (groupTotalUsed[gName] ?? 0.0) + used;
      }
    }

    // ==========================================
    // BILLING DATES & DUE BILLS CALCULATION
    // ==========================================
    final List<CreditCardDueBill> dueBills = [];
    final Map<String, LiveCreditCardSummary> ccSummaries = {};

    for (final entry in config.creditCardLimits.entries) {
      final cardName = entry.key;
      final card = entry.value;
      final cardUsed = currentCCUsed[cardName] ?? card.initialUsedAmount;

      double cardTotal;
      double cardAvailable;

      if (card.isShared) {
        final gName = card.sharedGroupName!.trim();
        cardTotal = groupTotalLimits[gName] ?? card.totalLimit;
        final totalUsedInGroup = groupTotalUsed[gName] ?? cardUsed;
        cardAvailable = (cardTotal - totalUsedInGroup).clamp(0.0, double.infinity);
      } else {
        cardTotal = card.totalLimit;
        cardAvailable = (cardTotal - cardUsed).clamp(0.0, double.infinity);
      }

      // Compute cycle dates if billDay and dueDay exist
      DateTime? nextBillDate;
      DateTime? nextDueDate;
      CreditCardDueBill? cardDueBill;

      if (card.billDay != null && card.dueDay != null) {
        final bDay = card.billDay!.clamp(1, 31);
        final dDay = card.dueDay!.clamp(1, 31);

        DateTime activeBillDate;
        DateTime activeDueDate;
        String cycleKey;

        if (bDay <= dDay) {
          // Bill and Due in the same calendar month (e.g. Bill 5th, Due 25th)
          if (today.day >= bDay) {
            activeBillDate = DateTime(today.year, today.month, bDay);
            activeDueDate = DateTime(today.year, today.month, dDay);
            cycleKey = '${today.year}-${today.month.toString().padLeft(2, '0')}';
            nextBillDate = DateTime(today.month == 12 ? today.year + 1 : today.year, today.month == 12 ? 1 : today.month + 1, bDay);
            nextDueDate = DateTime(today.month == 12 ? today.year + 1 : today.year, today.month == 12 ? 1 : today.month + 1, dDay);
          } else {
            final prevMonth = today.month == 1 ? 12 : today.month - 1;
            final prevYear = today.month == 1 ? today.year - 1 : today.year;
            activeBillDate = DateTime(prevYear, prevMonth, bDay);
            activeDueDate = DateTime(prevYear, prevMonth, dDay);
            cycleKey = '$prevYear-${prevMonth.toString().padLeft(2, '0')}';
            nextBillDate = DateTime(today.year, today.month, bDay);
            nextDueDate = DateTime(today.year, today.month, dDay);
          }
        } else {
          // Bill in one month, Due in next month (e.g. Bill 15th, Due 2nd next month)
          if (today.day >= bDay) {
            activeBillDate = DateTime(today.year, today.month, bDay);
            final nextMonth = today.month == 12 ? 1 : today.month + 1;
            final nextYear = today.month == 12 ? today.year + 1 : today.year;
            activeDueDate = DateTime(nextYear, nextMonth, dDay);
            cycleKey = '${today.year}-${today.month.toString().padLeft(2, '0')}';
            nextBillDate = DateTime(nextMonth, today.month == 12 ? today.year + 1 : today.year, bDay);
            final afterNextMonth = nextMonth == 12 ? 1 : nextMonth + 1;
            final afterNextYear = nextMonth == 12 ? nextYear + 1 : nextYear;
            nextDueDate = DateTime(afterNextYear, afterNextMonth, dDay);
          } else {
            final prevMonth = today.month == 1 ? 12 : today.month - 1;
            final prevYear = today.month == 1 ? today.year - 1 : today.year;
            activeBillDate = DateTime(prevYear, prevMonth, bDay);
            activeDueDate = DateTime(today.year, today.month, dDay);
            cycleKey = '$prevYear-${prevMonth.toString().padLeft(2, '0')}';
            nextBillDate = DateTime(today.year, today.month, bDay);
            final nextMonth = today.month == 12 ? 1 : today.month + 1;
            final nextYear = today.month == 12 ? today.year + 1 : today.year;
            nextDueDate = DateTime(nextYear, nextMonth, dDay);
          }
        }

        // Determine Billed Amount
        final billedAmt = card.statementBilledAmount != null && card.statementBilledAmount! > 0
            ? card.statementBilledAmount!
            : cardUsed;

        // Sum payments to this card within this active cycle (since activeBillDate)
        double paidInCycle = 0.0;
        for (final tx in transactions) {
          if ((tx.isSelfTransfer || tx.flow == 'Transfer') && !tx.date.isBefore(activeBillDate)) {
            final toList = tx.toBreakdowns ?? [];
            for (final to in toList) {
              if (to.effectiveAccount.trim().toLowerCase() == cardName.trim().toLowerCase()) {
                paidInCycle += to.amount;
              }
            }
          }
        }

        final remaining = (billedAmt - paidInCycle).clamp(0.0, double.infinity);
        final isManuallyPaid = card.manualPaidCycle == cycleKey;

        // If remaining > 0, bill is active and not manually marked paid
        if (billedAmt > 0 && remaining > 0.01 && !isManuallyPaid) {
          final daysDiff = activeDueDate.difference(today).inDays;
          final isOverdue = today.isAfter(activeDueDate);
          final isDueToday = today.year == activeDueDate.year &&
              today.month == activeDueDate.month &&
              today.day == activeDueDate.day;

          cardDueBill = CreditCardDueBill(
            cardName: cardName,
            sharedGroupName: card.sharedGroupName,
            billDate: activeBillDate,
            dueDate: activeDueDate,
            billedAmount: billedAmt,
            paidAmount: paidInCycle,
            remainingDue: remaining,
            cycleKey: cycleKey,
            isOverdue: isOverdue,
            isDueToday: isDueToday,
            daysUntilDue: daysDiff,
          );
          dueBills.add(cardDueBill);
        }
      }

      // Active EMI calculation for this card
      final cardActiveEmis = (emiPlans ?? []).where((p) {
        if (p.status.toUpperCase() != 'ACTIVE') return false;
        final planAcc = p.account.trim().toLowerCase();
        final cName = cardName.trim().toLowerCase();
        return planAcc == cName || planAcc.contains(cName) || cName.contains(planAcc);
      }).toList();

      final unbilledEmiPrincipal = cardActiveEmis.fold(0.0, (sum, p) => sum + p.remainingPrincipal);
      final activeEmiPlansCount = cardActiveEmis.length;

      DateTime? nextEmiDueDate;
      double? nextEmiAmount;
      for (final plan in cardActiveEmis) {
        final nextInst = plan.nextDueInstallment;
        if (nextInst != null) {
          if (nextEmiDueDate == null || nextInst.billingDate.isBefore(nextEmiDueDate)) {
            nextEmiDueDate = nextInst.billingDate;
            nextEmiAmount = nextInst.totalDueWithTax;
          }
        }
      }

      ccSummaries[cardName] = LiveCreditCardSummary(
        cardName: cardName,
        totalLimit: cardTotal,
        usedLimit: cardUsed,
        availableLimit: cardAvailable,
        isShared: card.isShared,
        sharedGroupName: card.sharedGroupName,
        groupTotalLimit: card.isShared ? (groupTotalLimits[card.sharedGroupName!.trim()]) : null,
        groupTotalUsed: card.isShared ? (groupTotalUsed[card.sharedGroupName!.trim()]) : null,
        billDay: card.billDay,
        dueDay: card.dueDay,
        nextBillDate: nextBillDate,
        nextDueDate: nextDueDate,
        dueBill: cardDueBill,
        unbilledEmiPrincipal: unbilledEmiPrincipal,
        activeEmiPlansCount: activeEmiPlansCount,
        nextEmiDueDate: nextEmiDueDate,
        nextEmiAmount: nextEmiAmount,
      );
    }

    return LiveAccountBalanceSummary(
      bankBalances: currentBankBalances,
      creditCardSummaries: ccSummaries,
      cashDenominations: currentCashDenoms,
      totalCashInHand: currentCashTotal,
      walletBalances: currentWalletBalances,
      rewardBalances: currentRewardBalances,
      txRunningBalances: runningMap,
      dueBills: dueBills,
    );
  }
}
