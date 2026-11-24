import 'package:flutter_test/flutter_test.dart';
import 'package:daily_finance_app/services/google_sheets_service.dart';
import 'package:daily_finance_app/models/transaction_model.dart';
import 'package:daily_finance_app/widgets/borrower_faceted_filter_sheet.dart';
import 'package:daily_finance_app/widgets/faceted_filter_sheet.dart';

void main() {
  group('Date Parsing & Range Filter Robustness Tests', () {
    test('parseDateSafe correctly resolves 2-digit, 4-digit, and 0026 years to 2026', () {
      final inputs = [
        '22/Nov/2026',
        '22/Nov/26',
        '22/Nov/0026',
        '22-Nov-26',
        '22-Nov-2026',
        '22/11/26',
        '22/11/2026',
        '22-11-26',
        '22-11-2026',
        '2026-11-22',
        '2026/11/22',
        '22.11.26',
        '22.11.2026',
        '22 Nov 2026',
        '22 Nov 26',
      ];

      for (final s in inputs) {
        final dt = GoogleSheetsService.parseDateSafe(s);
        expect(dt.year, 2026, reason: 'Failed for input: $s');
        expect(dt.month, 11, reason: 'Failed month for input: $s');
        expect(dt.day, 22, reason: 'Failed day for input: $s');
      }
    });

    test('parseDateSafe resolves Google Sheets serial date numbers', () {
      // 46348 is 2026-11-22
      final dt = GoogleSheetsService.parseDateSafe('46348');
      expect(dt.year, 2026);
      expect(dt.month, 11);
      expect(dt.day, 22);
    });

    test('FinanceTransaction and LoanEntry constructors sanitize 2-digit and 0026 years', () {
      final tx = FinanceTransaction(
        date: DateTime(26, 11, 22),
        referenceId: 'REF-1',
        narration: 'Test',
        flow: 'Withdraw',
        invoice: '',
        purpose: 'General',
        spentFor: 'Self',
        breakdowns: [],
        totalAmount: 100,
      );
      expect(tx.date.year, 2026);

      final loan = LoanEntry(
        date: DateTime(26, 11, 22),
        borrower: 'Ramesh',
        narration: 'Test loan',
        referenceId: 'REF-LOAN-1',
        givenAmount: 500,
      );
      expect(loan.date.year, 2026);
    });

    test('FinanceTransaction.fromJson and LoanEntry.fromJson sanitize 0026 stored dates', () {
      final txJson = {
        'id': 'tx_1',
        'date': '0026-11-22T00:00:00.000',
        'referenceId': 'REF-1',
        'narration': 'Test',
        'flow': 'Withdraw',
        'invoice': '',
        'purpose': 'General',
        'spentFor': 'Self',
        'breakdowns': [],
        'totalAmount': 100.0,
      };
      final tx = FinanceTransaction.fromJson(txJson);
      expect(tx.date.year, 2026);

      final loanJson = {
        'id': 'loan_1',
        'date': '0026-11-22T00:00:00.000',
        'borrower': 'Ramesh',
        'narration': 'Test',
        'givenAmount': 500.0,
        'receivedAmount': 0.0,
        'referenceId': 'REF-LOAN-1',
      };
      final loan = LoanEntry.fromJson(loanJson);
      expect(loan.date.year, 2026);
    });

    test('BorrowerFilterCriteria matches date range correctly', () {
      final criteria = BorrowerFilterCriteria();
      criteria.startDate = DateTime(2026, 11, 1);
      criteria.endDate = DateTime(2026, 11, 30);

      final matchingLoan = LoanEntry(
        date: DateTime(2026, 11, 22),
        borrower: 'Suresh',
        narration: 'Cash',
        referenceId: 'REF-1',
        givenAmount: 1000,
      );
      expect(criteria.matches(matchingLoan), isTrue);

      final outsideLoan = LoanEntry(
        date: DateTime(2026, 10, 15),
        borrower: 'Suresh',
        narration: 'Cash',
        referenceId: 'REF-2',
        givenAmount: 1000,
      );
      expect(criteria.matches(outsideLoan), isFalse);
    });

    test('TransactionFilterCriteria matches date range correctly for transactions', () {
      final criteria = TransactionFilterCriteria();
      criteria.startDate = DateTime(2026, 11, 1);
      criteria.endDate = DateTime(2026, 11, 30);

      final matchingTx = FinanceTransaction(
        date: DateTime(2026, 11, 22),
        referenceId: 'REF-1',
        narration: 'Grocery',
        flow: 'Withdraw',
        invoice: '',
        purpose: 'Food',
        spentFor: 'Self',
        breakdowns: [],
        totalAmount: 250,
      );
      expect(criteria.matches(matchingTx), isTrue);

      final outsideTx = FinanceTransaction(
        date: DateTime(2026, 10, 15),
        referenceId: 'REF-2',
        narration: 'Old Grocery',
        flow: 'Withdraw',
        invoice: '',
        purpose: 'Food',
        spentFor: 'Self',
        breakdowns: [],
        totalAmount: 250,
      );
      expect(criteria.matches(outsideTx), isFalse);
    });
  });
}
