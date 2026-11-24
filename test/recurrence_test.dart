import 'package:flutter_test/flutter_test.dart';
import 'package:daily_finance_app/models/transaction_model.dart';

void main() {
  group('RecurringTransaction Tests', () {
    test('computeNextDate advances monthly accurately', () {
      final baseDate = DateTime(2026, 1, 15);
      final tx = RecurringTransaction(
        narration: 'Office Rent',
        nextDueDate: baseDate,
        frequency: 'Month',
        totalAmount: 15000,
        breakdowns: [PaymentBreakdown(amount: 15000)],
      );

      final next = tx.computeNextDate(baseDate);
      expect(next.year, 2026);
      expect(next.month, 2);
      expect(next.day, 15);
    });

    test('computeNextDate advances quarterly (+3 months)', () {
      final baseDate = DateTime(2026, 3, 10);
      final tx = RecurringTransaction(
        narration: 'Quarterly Maintenance',
        nextDueDate: baseDate,
        frequency: 'Quarterly',
        totalAmount: 4500,
        breakdowns: [PaymentBreakdown(amount: 4500)],
      );

      final next = tx.computeNextDate(baseDate);
      expect(next.year, 2026);
      expect(next.month, 6);
      expect(next.day, 10);
    });

    test('computeNextDate advances half-yearly (+6 months)', () {
      final baseDate = DateTime(2026, 2, 20);
      final tx = RecurringTransaction(
        narration: 'Insurance Premium',
        nextDueDate: baseDate,
        frequency: 'Half-Yearly',
        totalAmount: 12000,
        breakdowns: [PaymentBreakdown(amount: 12000)],
      );

      final next = tx.computeNextDate(baseDate);
      expect(next.year, 2026);
      expect(next.month, 8);
      expect(next.day, 20);
    });

    test('computeNextDate advances yearly (+1 year)', () {
      final baseDate = DateTime(2026, 5, 1);
      final tx = RecurringTransaction(
        narration: 'Domain Renewal',
        nextDueDate: baseDate,
        frequency: 'Yearly',
        totalAmount: 1200,
        breakdowns: [PaymentBreakdown(amount: 1200)],
      );

      final next = tx.computeNextDate(baseDate);
      expect(next.year, 2027);
      expect(next.month, 5);
      expect(next.day, 1);
    });

    test('computeNextDate advances custom months and days', () {
      final baseDate = DateTime(2026, 1, 10);
      final tx = RecurringTransaction(
        narration: 'Custom Subscription',
        nextDueDate: baseDate,
        frequency: 'Custom',
        customMonths: 2,
        customDays: 5,
        totalAmount: 999,
        breakdowns: [PaymentBreakdown(amount: 999)],
      );

      final next = tx.computeNextDate(baseDate);
      // 2026-01-10 + 2 months = 2026-03-10 + 5 days = 2026-03-15
      expect(next.year, 2026);
      expect(next.month, 3);
      expect(next.day, 15);
    });

    test('JSON serialization & deserialization preserves all recurrence properties', () {
      final tx = RecurringTransaction(
        id: 'rec_123',
        narration: 'Gym Membership',
        nextDueDate: DateTime(2026, 11, 25),
        frequency: 'Month',
        customMonths: null,
        customDays: null,
        totalAmount: 2500,
        flow: 'Withdraw',
        purpose: 'Medical & Health',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(paymentType: 'UPI', account: 'HDFC Bank A/c', amount: 2500),
        ],
      );

      final json = tx.toJson();
      final fromJson = RecurringTransaction.fromJson(json);

      expect(fromJson.id, 'rec_123');
      expect(fromJson.narration, 'Gym Membership');
      expect(fromJson.frequency, 'Month');
      expect(fromJson.totalAmount, 2500);
      expect(fromJson.breakdowns.first.paymentType, 'UPI');
      expect(fromJson.breakdowns.first.effectiveAccount, 'HDFC Bank A/c');
    });
  });
}
