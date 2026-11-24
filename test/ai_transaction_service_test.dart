import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/services/ai_transaction_service.dart';
import 'package:daily_finance_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AiTransactionService Tests', () {
    test('Correctly parses "paid 600 rupees electricity bill via hdfc New account"', () async {
      final service = AiTransactionService.instance;
      final parsed = await service.parse(
        text: 'paid 600 rupees electricity bill via hdfc New account',
        availablePurposes: StorageService.defaultPurposes,
        availableSpentFors: StorageService.defaultSpentFors,
        categoryAccounts: StorageService.defaultCategoryAccounts,
      );

      expect(parsed.flow, 'Withdraw');
      expect(parsed.amount, 600.0);
      expect(parsed.purpose, 'Rent & Utilities');
      expect(parsed.account?.toLowerCase(), contains('hdfc new'));
      expect(parsed.narration.toLowerCase(), contains('electricity bill'));
    });

    test('Correctly parses salary income received', () async {
      final service = AiTransactionService.instance;
      final parsed = await service.parse(
        text: 'received 45000 salary to SBI Savings A/c',
        availablePurposes: StorageService.defaultPurposes,
        availableSpentFors: StorageService.defaultSpentFors,
        categoryAccounts: StorageService.defaultCategoryAccounts,
      );

      expect(parsed.flow, 'Deposit');
      expect(parsed.amount, 45000.0);
      expect(parsed.purpose, 'Salary & Income');
      expect(parsed.account, 'SBI Savings A/c');
    });

    test('Correctly parses transfer between accounts', () async {
      final service = AiTransactionService.instance;
      final parsed = await service.parse(
        text: 'transferred 5000 via Paytm Wallet',
        availablePurposes: StorageService.defaultPurposes,
        availableSpentFors: StorageService.defaultSpentFors,
        categoryAccounts: StorageService.defaultCategoryAccounts,
      );

      expect(parsed.flow, 'Transfer');
      expect(parsed.amount, 5000.0);
      expect(parsed.account, 'Paytm Wallet');
    });

    test('Pattern 1: paid 658 at dmart using HDFC PhonePe credit card', () async {
      final service = AiTransactionService.instance;
      final parsed = await service.parse(
        text: 'paid 658 at dmart using HDFC PhonePe credit card',
        availablePurposes: StorageService.defaultPurposes,
        availableSpentFors: StorageService.defaultSpentFors,
        categoryAccounts: StorageService.defaultCategoryAccounts,
      );

      expect(parsed.isSelfTransfer, false);
      expect(parsed.flow, 'Withdraw');
      expect(parsed.narration, 'Paid at dmart');
      expect(parsed.purpose, 'Food & Groceries');
      expect(parsed.spentFor, isNull); // Blank
      expect(parsed.paymentType, 'Credit');
      expect(parsed.account, 'HDFC PhonePe');
      expect(parsed.amount, 658.0);
    });

    test('Pattern 2: paid 658 at dmart using HDFC PhonePe credit card for mother', () async {
      final service = AiTransactionService.instance;
      final parsed = await service.parse(
        text: 'paid 658 at dmart using HDFC PhonePe credit card for mother',
        availablePurposes: StorageService.defaultPurposes,
        availableSpentFors: StorageService.defaultSpentFors,
        categoryAccounts: StorageService.defaultCategoryAccounts,
      );

      expect(parsed.isSelfTransfer, false);
      expect(parsed.flow, 'Withdraw');
      expect(parsed.narration, 'Paid at dmart');
      expect(parsed.purpose, 'Food & Groceries');
      expect(parsed.spentFor, 'Mother');
      expect(parsed.paymentType, 'Credit');
      expect(parsed.account, 'HDFC PhonePe');
      expect(parsed.amount, 658.0);
    });

    test('Pattern 3: paid 5660 HDFC PhonePe credit card bill using SBI account', () async {
      final service = AiTransactionService.instance;
      final parsed = await service.parse(
        text: 'paid 5660 HDFC PhonePe credit card bill using SBI account',
        availablePurposes: StorageService.defaultPurposes,
        availableSpentFors: StorageService.defaultSpentFors,
        categoryAccounts: StorageService.defaultCategoryAccounts,
      );

      expect(parsed.isSelfTransfer, true);
      expect(parsed.flow, 'Transfer');
      expect(parsed.fromPaymentType, 'UPI');
      expect(parsed.fromAccount, 'SBI');
      expect(parsed.fromAmount, 5660.0);
      expect(parsed.toPaymentType, 'Credit');
      expect(parsed.toAccount, 'HDFC PhonePe');
      expect(parsed.toAmount, 5660.0);
      expect(parsed.amount, 5660.0);
    });

    test('Pattern 4: 10000 cash withdrawn from kotak with default 500*20 notes', () async {
      final service = AiTransactionService.instance;
      final parsed = await service.parse(
        text: '10000 cash withdrawn from kotak',
        availablePurposes: StorageService.defaultPurposes,
        availableSpentFors: StorageService.defaultSpentFors,
        categoryAccounts: StorageService.defaultCategoryAccounts,
      );

      expect(parsed.isSelfTransfer, true);
      expect(parsed.flow, 'Transfer');
      expect(parsed.fromPaymentType, 'Debit');
      expect(parsed.fromAccount, 'Kotak');
      expect(parsed.fromAmount, 10000.0);
      expect(parsed.toPaymentType, 'Cash');
      expect(parsed.toAccount, isNull);
      expect(parsed.toAmount, 10000.0);
      expect(parsed.denominations?[500], 20);
      expect(parsed.amount, 10000.0);
    });

    test('Pattern 4b: 10000 cash withdrawn from kotak with custom denominations 200*50', () async {
      final service = AiTransactionService.instance;
      final parsed = await service.parse(
        text: '10000 cash withdrawn from kotak 200*50',
        availablePurposes: StorageService.defaultPurposes,
        availableSpentFors: StorageService.defaultSpentFors,
        categoryAccounts: StorageService.defaultCategoryAccounts,
      );

      expect(parsed.isSelfTransfer, true);
      expect(parsed.flow, 'Transfer');
      expect(parsed.fromPaymentType, 'Debit');
      expect(parsed.fromAccount, 'Kotak');
      expect(parsed.toPaymentType, 'Cash');
      expect(parsed.toAccount, isNull);
      expect(parsed.denominations?[200], 50);
      expect(parsed.denominations?[500], isNull);
    });

    test('Pattern 5: 5000 cash deposited into kotak with default 500*10 notes', () async {
      final service = AiTransactionService.instance;
      final parsed = await service.parse(
        text: '5000 cash deposited into kotak',
        availablePurposes: StorageService.defaultPurposes,
        availableSpentFors: StorageService.defaultSpentFors,
        categoryAccounts: StorageService.defaultCategoryAccounts,
      );

      expect(parsed.isSelfTransfer, true);
      expect(parsed.flow, 'Transfer');
      expect(parsed.fromPaymentType, 'Cash');
      expect(parsed.fromAccount, isNull);
      expect(parsed.fromAmount, 5000.0);
      expect(parsed.toPaymentType, 'Debit');
      expect(parsed.toAccount, 'Kotak');
      expect(parsed.toAmount, 5000.0);
      expect(parsed.denominations?[500], 10);
      expect(parsed.amount, 5000.0);
    });
  });
}
