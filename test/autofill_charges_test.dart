import 'package:flutter_test/flutter_test.dart';
import 'package:daily_finance_app/services/clipboard_transaction_parser.dart';
import 'package:daily_finance_app/models/transaction_model.dart';

void main() {
  group('Auto-Fill with Charges & Rewards Breakdown Tests', () {
    const rawInput = '''
📅 Date: 06-09-2026
📱 App: PhonePe
👤 Name: Life Insurance Corporation (LIC)
🆔 ID: 284046757903
📝 Msg: Insurance Success
💰 Amount: 2575
💸 Charges: 28.06
📊 Direction: 🔴 OUT
⇄ Type: Credit
🏢 Account: HDFC PhonePe
🏷️ Category: Transfer to Others
🔗 Ref: REF-20260906-SYQE
''';

    test('ClipboardTransactionParser parses exact input correctly with charges', () {
      final drafts = ClipboardTransactionParser.parse(rawInput);
      expect(drafts.length, 1);

      final d = drafts.first;
      expect(d.date.year, 2026);
      expect(d.date.month, 9);
      expect(d.date.day, 6);
      expect(d.narration, 'Paid to Life Insurance Corporation (LIC) - Insurance Success');
      expect(d.amount, 2575.0);
      expect(d.charges, 28.06);
      expect(d.flow, 'Withdraw');
      expect(d.paymentType, 'Credit Card');
      expect(d.account, 'HDFC PhonePe');
      expect(d.purpose, 'Transfer to Others');
      expect(d.referenceId, 'REF-20260906-SYQE');
    });

    test('Generates two payment modes for charges: Gross Credit + Negative Rewards', () {
      final drafts = ClipboardTransactionParser.parse(rawInput);
      final draft = drafts.first;

      expect(draft.charges > 0, isTrue);

      final grossAmt = double.parse((draft.amount + draft.charges.abs()).toStringAsFixed(2));
      final rewardAmt = -double.parse(draft.charges.abs().toStringAsFixed(2));

      expect(grossAmt, 2603.06);
      expect(rewardAmt, -28.06);

      final b1 = PaymentBreakdown(
        paymentType: draft.paymentType,
        account: draft.account,
        amount: grossAmt,
      );

      final b2 = PaymentBreakdown(
        paymentType: 'Rewards',
        account: draft.account,
        amount: rewardAmt,
      );

      final tx = FinanceTransaction(
        date: draft.date,
        referenceId: draft.referenceId,
        narration: draft.narration,
        flow: draft.flow,
        purpose: draft.purpose,
        spentFor: 'Self',
        breakdowns: [b1, b2],
        totalAmount: b1.amount + b2.amount,
        invoice: '',
      );

      expect(tx.breakdowns.length, 2);
      expect(tx.breakdowns[0].paymentType, 'Credit Card');
      expect(tx.breakdowns[0].account, 'HDFC PhonePe');
      expect(tx.breakdowns[0].amount, 2603.06);

      expect(tx.breakdowns[1].paymentType, 'Rewards');
      expect(tx.breakdowns[1].account, 'HDFC PhonePe');
      expect(tx.breakdowns[1].amount, -28.06);

      // Verify net final amount
      expect(tx.totalAmount, 2575.0);
    });
  });
}
