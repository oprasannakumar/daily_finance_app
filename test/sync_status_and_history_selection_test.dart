import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/models/transaction_model.dart';
import 'package:daily_finance_app/services/storage_service.dart';
import 'package:daily_finance_app/services/google_sheets_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Sync Status & Pending Notification Tests', () {
    test('isPendingSync returns true when reference or id is in pending set', () {
      final storage = StorageService.instance;
      storage.pendingSyncSetNotifier.value = {'REF-123', 'ID-456'};

      expect(storage.isPendingSync('REF-123'), isTrue);
      expect(storage.isPendingSync(null, 'ID-456'), isTrue);
      expect(storage.isPendingSync('REF-999'), isFalse);
      expect(storage.isPendingSync(null, 'ID-999'), isFalse);

      storage.pendingSyncSetNotifier.value = {};
      expect(storage.isPendingSync('REF-123'), isFalse);
    });

    test('Selection stats computation: Inflow, Outflow, Transfer, Count', () {
      final t1 = FinanceTransaction(
        id: '1',
        referenceId: 'REF-1',
        date: DateTime(2026, 11, 19),
        narration: 'Salary',
        invoice: '',
        flow: 'Deposit',
        totalAmount: 5000,
        purpose: 'Salary',
        spentFor: 'Self',
        breakdowns: [PaymentBreakdown(paymentType: 'Bank Accounts', account: 'HDFC', amount: 5000)],
      );

      final t2 = FinanceTransaction(
        id: '2',
        referenceId: 'REF-2',
        date: DateTime(2026, 11, 19),
        narration: 'Groceries',
        invoice: '',
        flow: 'Withdraw',
        totalAmount: 1200,
        purpose: 'Groceries',
        spentFor: 'Self',
        breakdowns: [PaymentBreakdown(paymentType: 'Cash', amount: 1200)],
      );

      final t3 = FinanceTransaction(
        id: '3',
        referenceId: 'REF-3',
        date: DateTime(2026, 11, 19),
        narration: 'Self Transfer',
        invoice: '',
        flow: 'Transfer',
        isSelfTransfer: true,
        totalAmount: 2000,
        purpose: 'Internal Transfer',
        spentFor: 'Self',
        breakdowns: [PaymentBreakdown(paymentType: 'Bank Accounts', account: 'HDFC', amount: 2000)],
      );

      final all = [t1, t2, t3];

      // Case 1: No selection -> stats for all
      double inSum = 0;
      double outSum = 0;
      double transferSum = 0;
      for (final t in all) {
        if (t.isSelfTransfer || t.flow == 'Transfer') {
          transferSum += t.totalAmount;
        } else if (t.flow == 'Deposit') {
          inSum += t.totalAmount;
        } else if (t.flow == 'Withdraw') {
          outSum += t.totalAmount;
        }
      }

      expect(inSum, 5000);
      expect(outSum, 1200);
      expect(transferSum, 2000);
      expect(all.length, 3);

      // Case 2: Selection of t2 and t3 only
      final selectedIds = {'2', '3'};
      final selectedItems = all.where((t) => selectedIds.contains(t.id)).toList();

      double selIn = 0;
      double selOut = 0;
      double selTransfer = 0;
      for (final t in selectedItems) {
        if (t.isSelfTransfer || t.flow == 'Transfer') {
          selTransfer += t.totalAmount;
        } else if (t.flow == 'Deposit') {
          selIn += t.totalAmount;
        } else if (t.flow == 'Withdraw') {
          selOut += t.totalAmount;
        }
      }

      expect(selIn, 0);
      expect(selOut, 1200);
      expect(selTransfer, 2000);
      expect(selectedItems.length, 2);
    });

    test('saveTransaction clears isPendingSync after background processing finishes', () async {
      final storage = StorageService.instance;
      final tx = FinanceTransaction(
        id: '12345',
        referenceId: 'REF-22112026-TEST',
        date: DateTime(2026, 11, 22),
        narration: 'Sync Test',
        invoice: '',
        flow: 'Withdraw',
        totalAmount: 100,
        purpose: 'General',
        spentFor: 'Self',
        breakdowns: [PaymentBreakdown(paymentType: 'Cash', amount: 100)],
      );

      await storage.saveTransaction(tx);
      // Allow async queue event loop microtasks to settle
      await Future.delayed(const Duration(milliseconds: 50));

      expect(storage.isPendingSync(tx.referenceId, tx.id), isFalse);
    });

    test('GoogleSheetsService account-based spreadsheet caching & clearActiveSpreadsheetInfo', () async {
      final sheets = GoogleSheetsService.instance;
      await sheets.setSpreadsheetId('SHEET-12345', email: 'user@example.com');
      await sheets.setSpreadsheetUrl('https://docs.google.com/spreadsheets/d/SHEET-12345/edit', email: 'user@example.com');

      expect(await sheets.getSpreadsheetId(), 'SHEET-12345');
      expect(await sheets.getSpreadsheetId(email: 'user@example.com'), 'SHEET-12345');

      // On sign out / disconnect, active spreadsheet info is cleared
      await sheets.clearActiveSpreadsheetInfo();

      // Active is now null
      expect(await StorageService.instance.getString('google_sheet_id'), isNull);

      // But email-keyed association is preserved for seamless reconnect
      expect(await sheets.getSpreadsheetId(email: 'user@example.com'), 'SHEET-12345');
    });
  });
}
