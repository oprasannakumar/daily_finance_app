import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/models/transaction_model.dart';
import 'package:daily_finance_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.initTheme();
  });

  group('Local-First Instant Storage & Background Sync Tests', () {
    test('saveTransaction immediately saves to mobile storage without blocking', () async {
      final storage = StorageService.instance;
      final tx = FinanceTransaction(
        date: DateTime(2026, 11, 19),
        referenceId: 'REF-19112026-INST',
        narration: 'Quick Coffee',
        flow: 'Withdraw',
        invoice: '',
        purpose: 'Food & Groceries',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(paymentType: 'UPI', account: 'HDFC Bank', amount: 80.0),
        ],
        totalAmount: 80.0,
      );

      final stopwatch = Stopwatch()..start();
      await storage.saveTransaction(tx);
      stopwatch.stop();

      // Immediate response (< 100ms)
      expect(stopwatch.elapsedMilliseconds, lessThan(100));

      // Immediately available from in-memory / local storage
      final list = await storage.getTransactions();
      expect(list.any((t) => t.referenceId == 'REF-19112026-INST'), isTrue);
      expect(list.first.narration, 'Quick Coffee');
      expect(list.first.totalAmount, 80.0);
    });

    test('edit/update transaction immediately reflects in mobile storage', () async {
      final storage = StorageService.instance;
      final initialTx = FinanceTransaction(
        date: DateTime(2026, 11, 19),
        referenceId: 'REF-19112026-EDIT',
        narration: 'Initial Description',
        flow: 'Withdraw',
        invoice: '',
        purpose: 'Shopping',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(paymentType: 'Cash', account: 'Cash', amount: 500.0),
        ],
        totalAmount: 500.0,
      );
      await storage.saveTransaction(initialTx);

      // Edit transaction
      final updatedTx = FinanceTransaction(
        id: initialTx.id,
        date: initialTx.date,
        referenceId: initialTx.referenceId,
        narration: 'Updated Description',
        flow: initialTx.flow,
        invoice: initialTx.invoice,
        purpose: initialTx.purpose,
        spentFor: initialTx.spentFor,
        breakdowns: [
          PaymentBreakdown(paymentType: 'Cash', account: 'Cash', amount: 650.0),
        ],
        totalAmount: 650.0,
      );

      await storage.saveTransaction(updatedTx);

      final list = await storage.getTransactions();
      expect(list.length, 1);
      expect(list.first.narration, 'Updated Description');
      expect(list.first.totalAmount, 650.0);
    });

    test('deleteTransaction immediately removes from mobile storage', () async {
      final storage = StorageService.instance;
      final tx = FinanceTransaction(
        date: DateTime(2026, 11, 19),
        referenceId: 'REF-19112026-DEL1',
        narration: 'Temporary Entry',
        flow: 'Withdraw',
        invoice: '',
        purpose: 'Other',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(paymentType: 'UPI', account: 'SBI', amount: 120.0),
        ],
        totalAmount: 120.0,
      );
      await storage.saveTransaction(tx);

      var list = await storage.getTransactions();
      expect(list.any((t) => t.referenceId == 'REF-19112026-DEL1'), isTrue);

      // Delete immediately
      final stopwatch = Stopwatch()..start();
      await storage.deleteTransaction(tx.id);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100));

      list = await storage.getTransactions();
      expect(list.any((t) => t.referenceId == 'REF-19112026-DEL1'), isFalse);
    });
  });
}
