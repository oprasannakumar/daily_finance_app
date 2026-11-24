import 'package:flutter_test/flutter_test.dart';
import 'package:daily_finance_app/models/transaction_model.dart';

void main() {
  group('Self Transfer & Split Mode Tests', () {
    test('FinanceTransaction correctly handles self transfer properties', () {
      final fromBreakdown = PaymentBreakdown(
        paymentType: 'Bank',
        account: 'HDFC Bank',
        amount: 5000.0,
      );
      final toBreakdown = PaymentBreakdown(
        paymentType: 'Credit Card',
        account: 'SBI SimplyCLICK',
        amount: 5000.0,
      );

      final tx = FinanceTransaction(
        date: DateTime(2026, 11, 16),
        referenceId: 'TXN-20261116-0001',
        narration: 'Credit card bill payment',
        flow: 'Transfer',
        invoice: '',
        purpose: 'Self Transfer',
        spentFor: 'Self',
        breakdowns: [fromBreakdown],
        toBreakdowns: [toBreakdown],
        isSelfTransfer: true,
        totalAmount: 5000.0,
      );

      expect(tx.isSelfTransfer, isTrue);
      expect(tx.fromSummary, 'HDFC Bank');
      expect(tx.toSummary, 'SBI SimplyCLICK');

      // Test JSON serialization & deserialization
      final json = tx.toJson();
      final fromJson = FinanceTransaction.fromJson(json);

      expect(fromJson.isSelfTransfer, isTrue);
      expect(fromJson.flow, 'Transfer');
      expect(fromJson.toBreakdowns, isNotNull);
      expect(fromJson.toBreakdowns!.length, 1);
      expect(fromJson.toBreakdowns![0].effectiveAccount, 'SBI SimplyCLICK');
      expect(fromJson.totalAmount, 5000.0);
    });

    test('TransactionTemplate matchesDataExceptNarration detects duplicates in self transfer', () {
      final t1 = TransactionTemplate(
        name: 'HDFC to SBI CC',
        narration: 'CC bill Nov',
        flow: 'Transfer',
        purpose: 'Self Transfer',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(paymentType: 'Bank', account: 'HDFC Bank', amount: 3000.0),
        ],
        toBreakdowns: [
          PaymentBreakdown(paymentType: 'Credit Card', account: 'SBI CC', amount: 3000.0),
        ],
        isSelfTransfer: true,
      );

      final t2 = TransactionTemplate(
        name: 'Different Name',
        narration: 'CC bill Dec', // Different narration
        flow: 'Transfer',
        purpose: 'Self Transfer',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(paymentType: 'Bank', account: 'HDFC Bank', amount: 3000.0),
        ],
        toBreakdowns: [
          PaymentBreakdown(paymentType: 'Credit Card', account: 'SBI CC', amount: 3000.0),
        ],
        isSelfTransfer: true,
      );

      expect(t1.matchesDataExceptNarration(t2), isTrue);

      final t3 = TransactionTemplate(
        name: 'Different Target',
        narration: 'CC bill Dec',
        flow: 'Transfer',
        purpose: 'Self Transfer',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(paymentType: 'Bank', account: 'HDFC Bank', amount: 3000.0),
        ],
        toBreakdowns: [
          PaymentBreakdown(paymentType: 'Bank', account: 'ICICI Bank', amount: 3000.0),
        ],
        isSelfTransfer: true,
      );

      expect(t1.matchesDataExceptNarration(t3), isFalse);
    });
  });
}
