import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/services/google_sheets_service.dart';
import 'package:daily_finance_app/models/transaction_model.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Reference ID Normalization & Extraction', () {
    test('normalizeReferenceId strips all sub-sheet suffixes accurately', () {
      const base = 'REF-19112026-WXYZ';

      expect(GoogleSheetsService.normalizeReferenceId('$base-CASH'), equals(base));
      expect(GoogleSheetsService.normalizeReferenceId('$base-CASH-FROM'), equals(base));
      expect(GoogleSheetsService.normalizeReferenceId('$base-CASH-TO'), equals(base));
      expect(GoogleSheetsService.normalizeReferenceId('$base-BORROWER-1'), equals(base));
      expect(GoogleSheetsService.normalizeReferenceId('$base-BORROWER-12'), equals(base));
      expect(GoogleSheetsService.normalizeReferenceId('$base-BORROWER'), equals(base));
      expect(GoogleSheetsService.normalizeReferenceId('$base-SELF'), equals(base));
      expect(GoogleSheetsService.normalizeReferenceId('$base-CREDIT'), equals(base));
      expect(GoogleSheetsService.normalizeReferenceId('$base-CREDIT-FROM'), equals(base));
      expect(GoogleSheetsService.normalizeReferenceId('$base-CREDIT-TO'), equals(base));
      expect(GoogleSheetsService.normalizeReferenceId('$base-FROM'), equals(base));
      expect(GoogleSheetsService.normalizeReferenceId('$base-TO'), equals(base));
      expect(GoogleSheetsService.normalizeReferenceId(base), equals(base));
    });

    test('extractReference resolves index and scans row fallback', () {
      final txRow = [
        '19/Nov/2026',
        'Dinner with friends',
        'INV-101',
        'Food & Dining',
        'Split',
        'UPI',
        'HDFC Bank A/c',
        '1500.00',
        '',
        'REF-19112026-DINN',
      ];
      expect(GoogleSheetsService.extractReference(txRow, defaultIdx: 9), equals('REF-19112026-DINN'));

      // Missing at defaultIdx but present in row
      final shiftedRow = [
        '19/Nov/2026',
        'Dinner',
        'REF-19112026-SHIFT',
      ];
      expect(GoogleSheetsService.extractReference(shiftedRow, defaultIdx: 9), equals('REF-19112026-SHIFT'));
    });
  });

  group('Multi-Sheet Row Merging Logic', () {
    test('Cash denominations are correctly parsed and assigned to PaymentBreakdown', () {
      final cashRow = [
        '19/Nov/2026', // 0: Date
        'Grocery shopping', // 1: Narration
        '', // 2: Invoice
        'CASH', // 3: Tx Type
        'Main Cash Box', // 4: Account
        '-2', // 5: 500 (count = 2)
        '-1', // 6: 200 (count = 1)
        '-3', // 7: 100 (count = 3)
        '0', // 8: 50
        '0', // 9: 20
        '0', // 10: 10
        '0', // 11: 5
        '0', // 12: 2
        '0', // 13: 1
        '-1500', // 14: Total Cash
        'REF-19112026-GROC-CASH', // 15: Ref
      ];

      final rawRef = GoogleSheetsService.extractReference(cashRow, defaultIdx: 15);
      final baseRef = GoogleSheetsService.normalizeReferenceId(rawRef);
      expect(baseRef, equals('REF-19112026-GROC'));

      final denomList = [500, 200, 100, 50, 20, 10, 5, 2, 1];
      final Map<int, int> denoms = {};
      for (int i = 0; i < denomList.length; i++) {
        final colIdx = 5 + i;
        final valStr = cashRow[colIdx];
        final count = (double.tryParse(valStr.replaceAll(RegExp(r'[^\d.-]'), '')) ?? 0).abs().toInt();
        denoms[denomList[i]] = count;
      }

      expect(denoms[500], equals(2));
      expect(denoms[200], equals(1));
      expect(denoms[100], equals(3));
      expect(denoms[50], equals(0));

      final pb = PaymentBreakdown(
        paymentType: 'Cash',
        account: cashRow[4],
        amount: 1500.0,
        denominations: denoms,
      );

      expect(pb.calculatedCashAmount, equals(1500.0));
      expect(pb.effectiveAccount, equals('Main Cash Box'));
    });

    test('Split transaction correctly merges borrower rows and personal share', () {
      const ref = 'REF-19112026-SPLT';
      final loanRows = [
        ['19/Nov/2026', 'Alice', 'Team Lunch', '', 'UPI', 'HDFC', '300.00', '', '$ref-BORROWER-1'],
        ['19/Nov/2026', 'Bob', 'Team Lunch', '', 'UPI', 'HDFC', '300.00', '', '$ref-BORROWER-2'],
      ];
      final monthlyRow = [
        '19/Nov/2026', 'Team Lunch', '', 'Food', 'Self', 'UPI', 'HDFC', '400.00', '', '$ref-SELF'
      ];

      // Parse loan rows
      final borrowers = <SplitRecipient>[];
      for (final r in loanRows) {
        borrowers.add(SplitRecipient(
          name: r[1],
          amount: double.parse(r[6]),
          isPersonal: false,
        ));
      }

      final personalAmt = double.parse(monthlyRow[7]);
      const totalAmount = 1000.0;

      final allRecipients = <SplitRecipient>[
        SplitRecipient(name: 'Personal Share', amount: personalAmt, isPersonal: true),
        ...borrowers,
      ];

      for (final r in allRecipients) {
        r.percentage = double.parse(((r.amount / totalAmount) * 100).toStringAsFixed(2));
      }

      expect(allRecipients.length, equals(3));
      expect(allRecipients[0].name, equals('Personal Share'));
      expect(allRecipients[0].amount, equals(400.0));
      expect(allRecipients[0].percentage, equals(40.0));
      expect(allRecipients[0].isPersonal, isTrue);

      expect(allRecipients[1].name, equals('Alice'));
      expect(allRecipients[1].amount, equals(300.0));
      expect(allRecipients[1].percentage, equals(30.0));
      expect(allRecipients[1].isPersonal, isFalse);

      expect(allRecipients[2].name, equals('Bob'));
      expect(allRecipients[2].amount, equals(300.0));
      expect(allRecipients[2].percentage, equals(30.0));
    });
  });
}
