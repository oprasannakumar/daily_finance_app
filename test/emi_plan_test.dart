import 'package:flutter_test/flutter_test.dart';
import 'package:daily_finance_app/models/emi_plan_model.dart';

void main() {
  group('Credit Card EMI Model & Calculation Tests', () {
    test('Standard reducing-balance schedule calculation with HP Victus numbers', () {
      final schedule = EmiPlan.calculateSchedule(
        principal: 10236.49,
        annualInterestRate: 17.0,
        tenureMonths: 6,
        firstEmiDate: DateTime(2026, 10, 24),
      );

      expect(schedule.length, equals(6));
      expect(schedule[0].billingDate, equals(DateTime(2026, 10, 24)));
      expect(schedule[1].billingDate, equals(DateTime(2026, 11, 24)));
      expect(schedule[2].billingDate, equals(DateTime(2026, 12, 24)));
      expect(schedule[3].billingDate, equals(DateTime(2027, 1, 24)));
      expect(schedule[4].billingDate, equals(DateTime(2027, 2, 24)));
      expect(schedule[5].billingDate, equals(DateTime(2027, 3, 24)));

      // Calculated mathematical EMI is ~1791.66
      expect(schedule[0].emiAmount, closeTo(1791.66, 1.0));

      // Sum of principals must equal booking principal
      final sumPrincipal = schedule.fold(0.0, (sum, it) => sum + it.principal);
      expect(sumPrincipal, closeTo(10236.49, 0.05));

      // Final balance must be 0
      expect(schedule.last.balancePrincipal, equals(0.0));
    });

    test('Partial conversion calculations (HP Victus ₹72,272.47 swipe with ₹10,236.49 EMI)', () {
      final schedule = EmiPlan.calculateSchedule(
        principal: 10236.49,
        annualInterestRate: 17.0,
        tenureMonths: 6,
        firstEmiDate: DateTime(2026, 10, 24),
      );

      final plan = EmiPlan(
        id: 'EMI-HP-VICTUS-001',
        title: 'HP Victus Laptop EMI',
        account: 'HDFC Credit Card',
        transactionDate: DateTime(2026, 10, 11),
        totalTransactionAmount: 72272.47,
        bookingPrincipal: 10236.49,
        annualInterestRate: 17.0,
        tenureMonths: 6,
        processingFee: 45.0,
        processingFeeGst: 8.10,
        firstEmiDate: DateTime(2026, 10, 24),
        installments: schedule,
      );

      expect(plan.isPartialConversion, isTrue);
      expect(plan.nonEmiBalance, closeTo(62035.98, 0.01));
      expect(plan.remainingPrincipal, closeTo(10236.49, 0.01));
      expect(plan.paidInstallmentsCount, equals(0));
      expect(plan.progressFraction, equals(0.0));
      expect(plan.nextDueInstallment?.installmentNumber, equals(1));
    });

    test('Custom bank manual overrides (e.g. Month 1 broken-period interest MRA = 1,796.49)', () {
      final schedule = EmiPlan.calculateSchedule(
        principal: 10236.49,
        annualInterestRate: 17.0,
        tenureMonths: 6,
        firstEmiDate: DateTime(2026, 10, 24),
      );

      // Bank specific schedule override matching user's image exactly
      final bankSchedule = List<EmiInstallment>.from(schedule);
      bankSchedule[0] = bankSchedule[0].copyWith(
        emiAmount: 1796.49,
        interest: 149.84,
        principal: 1646.65,
        balancePrincipal: 8589.84,
        applicableTaxes: 26.97,
      );

      final plan = EmiPlan(
        id: 'EMI-HP-VICTUS-OVERRIDE',
        title: 'HP Victus Bank Matched',
        account: 'HDFC Credit Card',
        transactionDate: DateTime(2026, 10, 11),
        totalTransactionAmount: 72272.47,
        bookingPrincipal: 10236.49,
        annualInterestRate: 17.0,
        tenureMonths: 6,
        processingFee: 45.0,
        processingFeeGst: 8.10,
        firstEmiDate: DateTime(2026, 10, 24),
        installments: bankSchedule,
      );

      expect(plan.installments[0].emiAmount, equals(1796.49));
      expect(plan.installments[0].interest, equals(149.84));
      expect(plan.installments[0].principal, equals(1646.65));
      expect(plan.installments[0].applicableTaxes, equals(26.97));
      expect(plan.installments[0].totalDueWithTax, closeTo(1823.46, 0.01));

      // Serialize to sheet row and back
      final sheetRow = plan.toSheetRow();
      expect(sheetRow.length, equals(16));
      expect(sheetRow[0], equals('EMI-HP-VICTUS-OVERRIDE'));
      expect(sheetRow[5], equals(10236.49));

      final restored = EmiPlan.fromSheetRow(sheetRow);
      expect(restored.id, equals('EMI-HP-VICTUS-OVERRIDE'));
      expect(restored.bookingPrincipal, equals(10236.49));
      expect(restored.installments[0].emiAmount, equals(1796.49));
      expect(restored.installments[0].interest, equals(149.84));
      expect(restored.installments[0].applicableTaxes, equals(26.97));
      expect(restored.installments[1].emiAmount, closeTo(1791.66, 0.1));
    });

    test('Transaction linkage serialization (linkedTransactionId & linkedTransactionRef)', () {
      final schedule = EmiPlan.calculateSchedule(
        principal: 5000.0,
        annualInterestRate: 15.0,
        tenureMonths: 3,
        firstEmiDate: DateTime(2026, 11, 25),
      );

      final plan = EmiPlan(
        id: 'EMI-LINKED-001',
        title: 'Flipkart Big Billion Days',
        account: 'SBI SimplyClick Credit Card',
        transactionDate: DateTime(2026, 11, 10),
        totalTransactionAmount: 25000.0,
        bookingPrincipal: 5000.0,
        annualInterestRate: 15.0,
        tenureMonths: 3,
        firstEmiDate: DateTime(2026, 11, 25),
        installments: schedule,
        linkedTransactionId: 'tx_12345678',
        linkedTransactionRef: 'REF-10112026-ABCD',
      );

      expect(plan.linkedTransactionId, equals('tx_12345678'));
      expect(plan.linkedTransactionRef, equals('REF-10112026-ABCD'));
      expect(plan.isPartialConversion, isTrue);
      expect(plan.nonEmiBalance, equals(20000.0));

      // JSON round-trip
      final json = plan.toJson();
      expect(json['linkedTransactionId'], equals('tx_12345678'));
      expect(json['linkedTransactionRef'], equals('REF-10112026-ABCD'));
      final fromJson = EmiPlan.fromJson(json);
      expect(fromJson.linkedTransactionId, equals('tx_12345678'));
      expect(fromJson.linkedTransactionRef, equals('REF-10112026-ABCD'));

      // Sheet row round-trip
      final row = plan.toSheetRow();
      expect(row.length, equals(16));
      expect(row[14], equals('tx_12345678'));
      expect(row[15], equals('REF-10112026-ABCD'));

      final fromSheet = EmiPlan.fromSheetRow(row);
      expect(fromSheet.linkedTransactionId, equals('tx_12345678'));
      expect(fromSheet.linkedTransactionRef, equals('REF-10112026-ABCD'));
    });

    test('Progress tracking & installment payment status updates', () {
      final schedule = EmiPlan.calculateSchedule(
        principal: 10236.49,
        annualInterestRate: 17.0,
        tenureMonths: 6,
        firstEmiDate: DateTime(2026, 10, 24),
      );

      final plan = EmiPlan(
        id: 'EMI-TEST-002',
        title: 'Laptop EMI',
        account: 'HDFC',
        transactionDate: DateTime(2026, 10, 11),
        totalTransactionAmount: 72272.47,
        bookingPrincipal: 10236.49,
        annualInterestRate: 17.0,
        tenureMonths: 6,
        firstEmiDate: DateTime(2026, 10, 24),
        installments: schedule,
      );

      expect(plan.paidInstallmentsCount, equals(0));
      expect(plan.status, equals('ACTIVE'));

      // Pay first 2 installments
      schedule[0].isPaid = true;
      schedule[0].paidDate = DateTime(2026, 10, 24);
      schedule[1].isPaid = true;
      schedule[1].paidDate = DateTime(2026, 11, 24);

      expect(plan.paidInstallmentsCount, equals(2));
      expect(plan.progressFraction, closeTo(2 / 6, 0.001));
      expect(plan.nextDueInstallment?.installmentNumber, equals(3));
      expect(plan.totalPrincipalPaid, greaterThan(3000));
      expect(plan.remainingPrincipal, lessThan(7500));
    });

    test('Clamped month addition for month-end dates (e.g. Jan 31 -> Feb 28)', () {
      final jan31 = DateTime(2027, 1, 31);
      final feb = EmiPlan.addMonthsClamped(jan31, 1);
      expect(feb.year, equals(2027));
      expect(feb.month, equals(2));
      expect(feb.day, equals(28));

      final mar = EmiPlan.addMonthsClamped(jan31, 2);
      expect(mar.year, equals(2027));
      expect(mar.month, equals(3));
      expect(mar.day, equals(31));
    });
  });
}
