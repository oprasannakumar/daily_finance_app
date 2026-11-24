import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/services/google_sheets_service.dart';
import 'package:daily_finance_app/models/transaction_model.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Self Transfer Sheet Headers & 8-Column Format Tests', () {
    test('requiredSelfTransferHeaders matches exact user specified headers', () {
      expect(
        GoogleSheetsService.requiredSelfTransferHeaders,
        [
          'Date',
          'Narration',
          'From Type',
          'From Acccount',
          'To Type',
          'To Account',
          'Amount',
          'Reference ID',
        ],
      );
    });

    test('formatSelfTransferSheetRow outputs exact 8 columns matching Image 1 for data in Image 2', () {
      final tx = FinanceTransaction(
        date: DateTime(2026, 11, 23),
        referenceId: 'REF-20261123-KACH',
        narration: 'Cleared card bill',
        flow: 'Transfer',
        invoice: '',
        purpose: 'Self Transfer',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(paymentType: 'UPI', account: 'HDFC Old', amount: 9356.0),
        ],
        toBreakdowns: [
          PaymentBreakdown(paymentType: 'Credit', account: 'HDFC Millennia', amount: 9356.0),
        ],
        totalAmount: 9356.0,
        isSelfTransfer: true,
      );

      final fromRow = GoogleSheetsService.instance.formatSelfTransferSheetRow(
        tx: tx,
        isWithdrawal: true,
        account: 'HDFC Old',
        paymentType: 'UPI',
        amount: 9356.0,
      );

      final toRow = GoogleSheetsService.instance.formatSelfTransferSheetRow(
        tx: tx,
        isWithdrawal: false,
        account: 'HDFC Millennia',
        paymentType: 'Credit',
        amount: 9356.0,
      );

      // Verify Row 1: Cleared card bill (From) -> Col C/D are From Type/Account
      expect(fromRow.length, 8);
      expect(fromRow[0], '23-Nov-26');
      expect(fromRow[1], 'Cleared card bill (From)');
      expect(fromRow[2], 'UPI'); // From Type
      expect(fromRow[3], 'HDFC Old'); // From Acccount
      expect(fromRow[4], ''); // To Type
      expect(fromRow[5], ''); // To Account
      expect(fromRow[6], 9356.0);
      expect(fromRow[7], 'REF-20261123-KACH');

      // Verify Row 2: Cleared card bill (To) -> Col E/F are To Type/Account
      expect(toRow.length, 8);
      expect(toRow[0], '23-Nov-26');
      expect(toRow[1], 'Cleared card bill (To)');
      expect(toRow[2], ''); // From Type
      expect(toRow[3], ''); // From Account
      expect(toRow[4], 'Credit'); // To Type
      expect(toRow[5], 'HDFC Millennia'); // To Account
      expect(toRow[6], 9356.0);
      expect(toRow[7], 'REF-20261123-KACH');
    });
  });
}
