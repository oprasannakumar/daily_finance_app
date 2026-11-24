import 'package:flutter_test/flutter_test.dart';
import 'package:daily_finance_app/models/transaction_model.dart';
import 'package:daily_finance_app/services/google_sheets_service.dart';

void main() {
  group('Full Multi-Sheet Architecture Specifications', () {
    test('Headers for all 7 sheets match architecture specifications', () {
      // 1. Transactions / Full Statement
      expect(GoogleSheetsService.requiredHeaders.length, 10);
      expect(GoogleSheetsService.requiredHeaders.first, 'Date');
      expect(GoogleSheetsService.requiredHeaders.last, 'Reference');

      // 2. Monthly Transaction
      expect(GoogleSheetsService.requiredMonthlyHeaders.length, 10);

      // 3. Self Transfer (8 columns as specified by user)
      expect(GoogleSheetsService.requiredSelfTransferHeaders, [
        'Date',
        'Narration',
        'From Type',
        'From Acccount',
        'To Type',
        'To Account',
        'Amount',
        'Reference ID',
      ]);

      // 4. Loan
      expect(GoogleSheetsService.requiredLoanHeaders, [
        'Date',
        'Borrower',
        'Narration',
        'Invoice No.',
        'Transaction Type',
        'Account',
        'Given Amount',
        'Received Amount',
        'Reference',
      ]);

      // 5. Cash Entries (Cash Matrix: 11 columns)
      expect(GoogleSheetsService.requiredCashHeaders, [
        'Date',
        '500',
        '200',
        '100',
        '50',
        '20',
        '10',
        '5',
        '2',
        '1',
        'Reference ID',
      ]);

      // 6. Credit (6 columns)
      expect(GoogleSheetsService.requiredCreditHeaders, [
        'Date',
        'Narration',
        'Account',
        'Deposited Amount',
        'Withdrawn Amount',
        'Reference ID',
      ]);

      // 7. Billing
      expect(GoogleSheetsService.requiredBillingHeaders, [
        'Account',
        'Bill Date',
        'Due Date',
        'Amount',
        'Status',
        'Paid Date',
        'Reference',
      ]);
    });

    test('Flow A (Standard Expense): routes full details to Full Statement and Monthly', () {
      final txDate = DateTime(2026, 11, 18);
      final tx = FinanceTransaction(
        date: txDate,
        referenceId: 'REF-18112026-STND',
        narration: 'Grocery Store',
        flow: 'Withdraw',
        invoice: 'BILL-100',
        purpose: 'Grocery',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(paymentType: 'UPI', account: 'HDFC Bank', amount: 850.0),
        ],
        totalAmount: 850.0,
      );

      final sheets = GoogleSheetsService.instance;
      final row = sheets.formatTransactionRow(tx);

      expect(row[0], '18/Nov/2026');
      expect(row[1], 'Grocery Store');
      expect(row[6], 'HDFC Bank');
      expect(row[7], 850.0);
      expect(row[9], 'REF-18112026-STND');
    });

    test('Flow B (Self-Transfer): formats withdrawal leg and deposit leg with -FROM and -TO references', () {
      final txDate = DateTime(2026, 11, 18);
      final tx = FinanceTransaction(
        date: txDate,
        referenceId: 'REF-18112026-XFER',
        narration: 'ATM Cash Withdrawal',
        flow: 'Transfer',
        invoice: '',
        purpose: 'Self Transfer',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(paymentType: 'Debit', account: 'HDFC Bank', amount: 2000.0),
        ],
        toBreakdowns: [
          PaymentBreakdown(paymentType: 'Cash', account: 'Wallet', amount: 2000.0),
        ],
        totalAmount: 2000.0,
        isSelfTransfer: true,
      );

      final sheets = GoogleSheetsService.instance;
      final fromLeg = sheets.formatTransferLegRow(
        tx: tx,
        isWithdrawal: true,
        account: 'HDFC Bank',
        paymentType: 'Debit',
      );
      final toLeg = sheets.formatTransferLegRow(
        tx: tx,
        isWithdrawal: false,
        account: 'Wallet',
        paymentType: 'Cash',
      );

      // Withdrawal leg
      expect(fromLeg[1], 'ATM Cash Withdrawal (From)');
      expect(fromLeg[6], 'HDFC Bank');
      expect(fromLeg[7], 2000.0); // Withdrawn
      expect(fromLeg[8], '');
      expect(fromLeg[9], 'REF-18112026-XFER');

      // Deposit leg
      expect(toLeg[1], 'ATM Cash Withdrawal (To)');
      expect(toLeg[6], 'Wallet');
      expect(toLeg[7], '');
      expect(toLeg[8], 2000.0); // Deposit
      expect(toLeg[9], 'REF-18112026-XFER');
    });

    test('Flow C (Split Bill): routes personal share to Monthly and borrower rows to loan', () {
      final txDate = DateTime(2026, 11, 18);
      final tx = FinanceTransaction(
        date: txDate,
        referenceId: 'REF-18112026-SPLT',
        narration: 'Team Dinner',
        flow: 'Withdraw',
        invoice: 'DIN-99',
        purpose: 'Food',
        spentFor: 'Split',
        breakdowns: [
          PaymentBreakdown(paymentType: 'Credit', account: 'HDFC Regalia', amount: 1500.0),
        ],
        totalAmount: 1500.0,
        isSplitMode: true,
        splitRecipients: [
          SplitRecipient(name: 'Personal Share', isPersonal: true, amount: 500.0, percentage: 33.3),
          SplitRecipient(name: 'Ravi', isPersonal: false, amount: 500.0, percentage: 33.3),
          SplitRecipient(name: 'Suresh', isPersonal: false, amount: 500.0, percentage: 33.3),
        ],
      );

      final sheets = GoogleSheetsService.instance;

      // Personal share -> Monthly
      final personalShare = tx.splitRecipients!.firstWhere((r) => r.isPersonal);
      final monthlyRow = sheets.formatMonthlyTransactionRow(tx, personalShare);
      expect(monthlyRow[7], 500.0); // Only 500 hits Monthly Transaction
      expect(monthlyRow[9], 'REF-18112026-SPLT');

      // Borrowers -> Loan
      final borrowers = tx.splitRecipients!.where((r) => !r.isPersonal).toList();
      final raviRow = sheets.formatLoanRow(tx, borrowers[0], 1);
      final sureshRow = sheets.formatLoanRow(tx, borrowers[1], 2);

      expect(raviRow[1], 'Ravi');
      expect(raviRow[6], 500.0);
      expect(raviRow[8], 'REF-18112026-SPLT');

      expect(sureshRow[1], 'Suresh');
      expect(sureshRow[6], 500.0);
      expect(sureshRow[8], 'REF-18112026-SPLT');
    });

    test('Sub-Flow: Cash Matrix logs 11 columns with note counts and reference ID', () {
      final txDate = DateTime(2026, 11, 18);
      final tx = FinanceTransaction(
        date: txDate,
        referenceId: 'REF-18112026-CASH',
        narration: 'Market Cash Purchase',
        flow: 'Withdraw',
        invoice: '',
        purpose: 'Grocery',
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

      final sheets = GoogleSheetsService.instance;

      final cashRow = sheets.formatCashEntryRow(
        tx: tx,
        breakdown: tx.breakdowns.first,
        isOutflow: true,
      );
      // Date | 500 | 200 | 100 | 50 | 20 | 10 | 5 | 2 | 1 | Reference ID
      // For outflow (withdraw), note counts are multiplied with negative sign
      expect(cashRow.length, 11);
      expect(cashRow[0], '18-Nov-26');
      expect(cashRow[1], -1); // 500 note count = -1 (outflow)
      expect(cashRow[2], -1); // 200 note count = -1 (outflow)
      expect(cashRow[3], 0);  // 100 note count = 0
      expect(cashRow[10], 'REF-18112026-CASH'); // strictly pure reference ID without suffix

      // Inflow (deposit) check
      final depositCashRow = sheets.formatCashEntryRow(
        tx: tx,
        breakdown: tx.breakdowns.first,
        isOutflow: false,
      );
      expect(depositCashRow[1], 1); // 500 note count = 1 (inflow)
      expect(depositCashRow[2], 1); // 200 note count = 1 (inflow)
      expect(depositCashRow[10], 'REF-18112026-CASH');
    });

    test('Sub-Flow: Credit sheet tracks credit card liabilities in 6 columns', () {
      final txDate = DateTime(2026, 11, 18);
      final tx = FinanceTransaction(
        date: txDate,
        referenceId: 'REF-18112026-CRDT',
        narration: 'Electronics Purchase',
        flow: 'Withdraw',
        invoice: 'INV-ELEC',
        purpose: 'Shopping',
        spentFor: 'Self',
        breakdowns: [
          PaymentBreakdown(paymentType: 'Credit', account: 'ICICI Amazon Pay Card', amount: 3200.0),
        ],
        totalAmount: 3200.0,
      );

      final sheets = GoogleSheetsService.instance;
      final creditRow = sheets.formatCreditRow(
        tx: tx,
        breakdown: tx.breakdowns.first,
        isWithdrawal: true,
      );

      // Date | Narration | Account | Deposited Amount | Withdrawn Amount | Reference ID
      expect(creditRow.length, 6);
      expect(creditRow[0], '18-Nov-26');
      expect(creditRow[1], 'Electronics Purchase');
      expect(creditRow[2], 'ICICI Amazon Pay Card');
      expect(creditRow[3], '');
      expect(creditRow[4], 3200.0);
      expect(creditRow[5], 'REF-18112026-CRDT');
    });

    test('URI encoding for append with spaces in title and A:A range', () {
      final title = 'Monthly Transaction';
      final sheetId = 'test_sheet_123';
      final encodedRange = Uri.encodeComponent("'$title'!A:A");
      final url = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$encodedRange:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS',
      );
      expect(url.queryParameters['valueInputOption'], 'USER_ENTERED');
      expect(url.queryParameters['insertDataOption'], 'INSERT_ROWS');
      expect(url.path.contains(':append'), isTrue);
    });
  });
}
