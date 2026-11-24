import 'package:flutter_test/flutter_test.dart';
import 'package:daily_finance_app/services/clipboard_transaction_parser.dart';

void main() {
  group('ClipboardTransactionParser Tests', () {
    test('Parses multi-transaction sample from user prompt', () {
      const sample = '''
--- Transaction 1 ---
📅 Date: 17-11-2026
📱 App: PhonePe
👤 Name: PRABHAKAR TRADERS
🆔 ID: T2611171356515793883629
📝 Msg: 
💰 Amount: 313
💸 Charges: 0
📊 Direction: 🔴 OUT
⇄ Type: Credit
🏢 Account: HDFC PhonePe
🏷️ Category: Others
🔗 Ref: REF-20261117-TG5Z

--- Transaction 2 ---
📅 Date: 17-11-2026
📱 App: PhonePe
👤 Name: OM SRI DURGA FANCY AND GE
🆔 ID: T2611171403508694419836
📝 Msg: StaticQR
💰 Amount: 132
💸 Charges: 0
📊 Direction: 🔴 OUT
⇄ Type: Credit
🏢 Account: HDFC PhonePe
🏷️ Category: Others
🔗 Ref: REF-20261117-J83E

--- Transaction 3 ---
📅 Date: 17-11-2026
📱 App: PhonePe
👤 Name: Sai Karthik
🆔 ID: T2611171432374840735987
📝 Msg: 
💰 Amount: 1900
💸 Charges: 0
📊 Direction: 🟢 IN
⇄ Type: UPI
🏢 Account: SBI
🏷️ Category: Transfer to Others
🔗 Ref: REF-20261117-98NF

--- Transaction 4 ---
📅 Date: 17-11-2026
📱 App: PhonePe
👤 Name: Mr Chef Fast Foods
🆔 ID: T2611171718301937514930
📝 Msg: Noodles
💰 Amount: 60
💸 Charges: 0
📊 Direction: 🔴 OUT
⇄ Type: Credit
🏢 Account: HDFC PhonePe
🏷️ Category: Dining Out
🔗 Ref: REF-20261117-LGW7

--- Transaction 5 ---
📅 Date: 17-11-2026
📱 App: PhonePe
👤 Name: NAGARANI KONDURU
🆔 ID: T2611171749065675796080
📝 Msg: 
💰 Amount: 500
💸 Charges: 0
📊 Direction: 🔴 OUT
⇄ Type: UPI
🏢 Account: HDFC Old
🏷️ Category: Transfer to Others
🔗 Ref: REF-20261117-YPZS
''';

      final drafts = ClipboardTransactionParser.parse(sample);
      expect(drafts.length, 5);

      // Draft 1
      expect(drafts[0].amount, 313.0);
      expect(drafts[0].flow, 'Withdraw');
      expect(drafts[0].paymentType, 'Credit Card');
      expect(drafts[0].account, 'HDFC PhonePe');
      expect(drafts[0].referenceId, 'REF-20261117-TG5Z');
      expect(drafts[0].narration, 'Paid to PRABHAKAR TRADERS');
      expect(drafts[0].purpose, 'Others');

      // Draft 2
      expect(drafts[1].amount, 132.0);
      expect(drafts[1].flow, 'Withdraw');
      expect(drafts[1].paymentType, 'Credit Card');
      expect(drafts[1].account, 'HDFC PhonePe');
      expect(drafts[1].referenceId, 'REF-20261117-J83E');

      // Draft 3 (Deposit)
      expect(drafts[2].amount, 1900.0);
      expect(drafts[2].flow, 'Deposit');
      expect(drafts[2].paymentType, 'UPI');
      expect(drafts[2].account, 'SBI');
      expect(drafts[2].narration, 'Received from Sai Karthik');

      // Draft 4
      expect(drafts[3].amount, 60.0);
      expect(drafts[3].flow, 'Withdraw');
      expect(drafts[3].purpose, 'Dining Out');
      expect(drafts[3].narration.contains('Mr Chef Fast Foods'), isTrue);

      // Draft 5
      expect(drafts[4].amount, 500.0);
      expect(drafts[4].flow, 'Withdraw');
      expect(drafts[4].paymentType, 'UPI');
      expect(drafts[4].account, 'HDFC Old');
    });

    test('Parses single block without header', () {
      const single = '''
📅 Date: 16-11-2026
👤 Name: Amazon Retail
💰 Amount: 849.50
📊 Direction: 🔴 OUT
⇄ Type: Debit
🏢 Account: SBI Savings A/c
🏷️ Category: Shopping
🔗 Ref: REF-20261116-AMZ1
''';
      final drafts = ClipboardTransactionParser.parse(single);
      expect(drafts.length, 1);
      expect(drafts[0].amount, 849.50);
      expect(drafts[0].flow, 'Withdraw');
      expect(drafts[0].paymentType, 'Debit Card');
      expect(drafts[0].narration, 'Paid to Amazon Retail');
      expect(drafts[0].purpose, 'Shopping');
    });
  });
}
