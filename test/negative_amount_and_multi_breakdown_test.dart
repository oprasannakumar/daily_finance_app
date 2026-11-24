import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/services/google_sheets_service.dart';
import 'package:daily_finance_app/models/transaction_model.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Negative Amount Parsing & Preservation', () {
    test('parseDoubleSafe correctly preserves negative signs and formats', () {
      expect(GoogleSheetsService.parseDoubleSafe('-9.47'), -9.47);
      expect(GoogleSheetsService.parseDoubleSafe('- 9.47'), -9.47);
      expect(GoogleSheetsService.parseDoubleSafe('(9.47)'), -9.47);
      expect(GoogleSheetsService.parseDoubleSafe('-₹9.47'), -9.47);
      expect(GoogleSheetsService.parseDoubleSafe('₹-9.47'), -9.47);
      expect(GoogleSheetsService.parseDoubleSafe(-9.47), -9.47);
      expect(GoogleSheetsService.parseDoubleSafe(388.47), 388.47);
      expect(GoogleSheetsService.parseDoubleSafe('388.47'), 388.47);
      expect(GoogleSheetsService.parseDoubleSafe('₹ 388.47'), 388.47);
      expect(GoogleSheetsService.parseDoubleSafe(''), 0.0);
      expect(GoogleSheetsService.parseDoubleSafe(null), 0.0);
      expect(GoogleSheetsService.parseDoubleSafe('0'), 0.0);
    });

    test('parseRowToTransaction preserves negative amount', () {
      final sheets = GoogleSheetsService.instance;
      final row = [
        '2-Oct-26', // 0: Date
        'Paid to Airtel Prepaid', // 1: Narration
        '', // 2: Invoice
        'Mobile Recharge', // 3: Purpose
        'Self', // 4: Spent For
        'REWARDS', // 5: Transaction Type
        'HDFC PhonePe', // 6: From/To
        '-9.47', // 7: Withdrawn
        '', // 8: Deposit
        'REF-20261002-5KRW', // 9: Reference
      ];

      final tx = sheets.parseRowToTransaction(row);
      expect(tx, isNotNull);
      expect(tx!.totalAmount, -9.47);
      expect(tx.flow, 'Withdraw');
      expect(tx.breakdowns.length, 1);
      expect(tx.breakdowns[0].amount, -9.47);
      expect(tx.breakdowns[0].paymentType, 'REWARDS');
      expect(tx.breakdowns[0].effectiveAccount, 'HDFC PhonePe');
    });

    test('Multi-row breakdown with negative reward discount retains both legs and correct net total', () {
      const ref = 'REF-20261002-5KRW';

      final row1 = [
        '2-Oct-26',
        'Paid to Airtel Prepaid',
        '',
        'Mobile Recharge',
        'Self',
        'CREDIT',
        'HDFC PhonePe',
        '388.47',
        '',
        ref,
      ];

      final row2 = [
        '2-Oct-26',
        'Paid to Airtel Prepaid',
        '',
        'Mobile Recharge',
        'Self',
        'REWARDS',
        'HDFC PhonePe',
        '-9.47',
        '',
        ref,
      ];

      final txRowsForRef = [row1, row2];

      // Simulate grouping in fetchTransactions
      final firstRow = txRowsForRef.first;
      final date = GoogleSheetsService.parseDateSafe(firstRow[0].toString());
      final narration = firstRow[1].toString();
      final purpose = firstRow[3].toString();
      final spentFor = firstRow[4].toString();

      double sumW = 0.0;
      double sumD = 0.0;
      for (final r in txRowsForRef) {
        sumW += GoogleSheetsService.parseDoubleSafe(r.length > 7 ? r[7] : null);
        sumD += GoogleSheetsService.parseDoubleSafe(r.length > 8 ? r[8] : null);
      }

      final flow = (sumD > 0 && sumW <= 0) ? 'Deposit' : 'Withdraw';
      final totalAmount = flow == 'Deposit' ? sumD : sumW;

      final breakdowns = <PaymentBreakdown>[];
      for (final r in txRowsForRef) {
        final rTxType = r.length > 5 ? r[5].toString().trim() : '';
        final rFromTo = r.length > 6 ? r[6].toString().trim() : '';
        final rW = GoogleSheetsService.parseDoubleSafe(r.length > 7 ? r[7] : null);
        final rD = GoogleSheetsService.parseDoubleSafe(r.length > 8 ? r[8] : null);
        final rAmt = (rW != 0.0) ? rW : rD;

        breakdowns.add(PaymentBreakdown(
          paymentType: rTxType.isNotEmpty ? rTxType : (flow == 'Withdraw' ? 'UPI' : 'Account'),
          account: rFromTo,
          amount: rAmt,
        ));
      }

      final tx = FinanceTransaction(
        id: ref,
        date: date,
        referenceId: ref,
        narration: narration,
        invoice: '',
        flow: flow,
        purpose: purpose,
        spentFor: spentFor,
        breakdowns: breakdowns,
        totalAmount: totalAmount,
        isSplitMode: false,
      );

      // Verify net total is preserved accurately without stripping minus sign
      expect(tx.totalAmount, 379.00);
      expect(tx.isSplitMode, false);
      expect(tx.spentFor, 'Self');
      expect(tx.breakdowns.length, 2);
      expect(tx.breakdowns[0].paymentType, 'CREDIT');
      expect(tx.breakdowns[0].amount, 388.47);
      expect(tx.breakdowns[1].paymentType, 'REWARDS');
      expect(tx.breakdowns[1].amount, -9.47);
    });

    test('formatTransactionBreakdownRow preserves negative amounts in written row', () {
      final sheets = GoogleSheetsService.instance;
      final tx = FinanceTransaction(
        date: DateTime(2026, 10, 2),
        referenceId: 'REF-20261002-5KRW',
        narration: 'Paid to Airtel Prepaid',
        invoice: '',
        flow: 'Withdraw',
        purpose: 'Mobile Recharge',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(paymentType: 'CREDIT', account: 'HDFC PhonePe', amount: 388.47),
          PaymentBreakdown(paymentType: 'REWARDS', account: 'HDFC PhonePe', amount: -9.47),
        ],
        totalAmount: 379.00,
      );

      final row1 = sheets.formatTransactionBreakdownRow(tx, tx.breakdowns[0]);
      final row2 = sheets.formatTransactionBreakdownRow(tx, tx.breakdowns[1]);

      expect(row1[5], 'CREDIT');
      expect(row1[6], 'HDFC PhonePe');
      expect(row1[7], 388.47);

      expect(row2[5], 'REWARDS');
      expect(row2[6], 'HDFC PhonePe');
      expect(row2[7], -9.47); // Preserved negative!
    });

    test('Cash denominations sign rule: outflow (withdraw) -> negative, inflow (deposit) -> positive', () {
      final sheets = GoogleSheetsService.instance;
      final txWithdraw = FinanceTransaction(
        date: DateTime(2026, 11, 23),
        referenceId: 'REF-20261123-WTHD',
        narration: 'Cash Outflow',
        flow: 'Withdraw',
        invoice: '',
        purpose: 'Expense',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(
            paymentType: 'Cash',
            account: 'Cash Pool',
            amount: 700.0,
            denominations: {500: 1, 200: 1},
          ),
        ],
        totalAmount: 700.0,
      );

      final rowWithdraw = sheets.formatCashEntryRow(
        tx: txWithdraw,
        breakdown: txWithdraw.breakdowns.first,
        isOutflow: true,
      );

      // Outflow: note counts multiplied with negative sign
      expect(rowWithdraw[1], -1); // 500
      expect(rowWithdraw[2], -1); // 200
      expect(rowWithdraw[3], 0);  // 100
      expect(rowWithdraw[10], 'REF-20261123-WTHD'); // strictly pure reference ID

      final txDeposit = FinanceTransaction(
        date: DateTime(2026, 11, 23),
        referenceId: 'REF-20261123-DPST',
        narration: 'Cash Inflow',
        flow: 'Deposit',
        invoice: '',
        purpose: 'Income',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(
            paymentType: 'Cash',
            account: 'Cash Pool',
            amount: 700.0,
            denominations: {500: 1, 200: 1},
          ),
        ],
        totalAmount: 700.0,
      );

      final rowDeposit = sheets.formatCashEntryRow(
        tx: txDeposit,
        breakdown: txDeposit.breakdowns.first,
        isOutflow: false,
      );

      // Inflow: positive sign
      expect(rowDeposit[1], 1); // 500
      expect(rowDeposit[2], 1); // 200
      expect(rowDeposit[3], 0); // 100
      expect(rowDeposit[10], 'REF-20261123-DPST'); // strictly pure reference ID
    });

    test('Negative cash denomination input by user is preserved and handled properly', () {
      final b = PaymentBreakdown(
        paymentType: 'Cash',
        account: 'Cash Pool',
        amount: 0.0,
        denominations: {500: 2, 200: -1}, // 2 * 500 - 1 * 200 = 800
      );

      expect(b.calculatedCashAmount, 800.0);
      b.recalculateCashAmount();
      expect(b.amount, 800.0);
    });

    test('Withdrawal with mixed positive and negative cash denominations multiplies signs with -', () {
      final sheets = GoogleSheetsService.instance;
      final txWithdraw = FinanceTransaction(
        date: DateTime(2026, 11, 23),
        referenceId: 'REF-23112026-75CZ',
        narration: 'Morning coffee & breakfast snacks',
        flow: 'Withdraw',
        invoice: '',
        purpose: 'Food & Groceries',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(
            paymentType: 'Cash',
            account: 'Cash Pool',
            amount: 400.0,
            denominations: {500: 1, 100: -1}, // 500*1 + 100*(-1) = 400
          ),
        ],
        totalAmount: 400.0,
      );

      final row = sheets.formatCashEntryRow(
        tx: txWithdraw,
        breakdown: txWithdraw.breakdowns.first,
        isOutflow: true,
      );

      // On withdraw, counts are multiplied by -1:
      // 500 note: 1 * -1 = -1
      // 100 note: -1 * -1 = 1
      expect(row[1], -1); // 500
      expect(row[2], 0);  // 200
      expect(row[3], 1);  // 100
      expect(row[10], 'REF-23112026-75CZ'); // pure ref ID
    });
  });
}
