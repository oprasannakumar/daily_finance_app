import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:daily_finance_app/models/invoice_model.dart';
import 'package:daily_finance_app/services/ai_transaction_service.dart';
import 'package:daily_finance_app/services/receipt_scanner_service.dart';

void main() {
  group('AI Model Configuration Tests', () {
    test('ReceiptScannerService uses gemini-3.6-flash', () {
      expect(ReceiptScannerService.geminiModel, 'gemini-3.6-flash');
    });

    test('AiTransactionService uses qwen/qwen3.8-27b for Groq and gemini-3.6-flash for Gemini', () {
      expect(AiTransactionService.grokModelName, 'qwen/qwen3.8-27b');
      expect(AiTransactionService.geminiModelName, 'gemini-3.6-flash');
    });
  });

  group('ReceiptScannerService Result & Parser Tests', () {
    test('ScannedReceiptResult error state holds correct error message', () {
      final res = ScannedReceiptResult.error('API key missing');
      expect(res.isSuccess, isFalse);
      expect(res.errorMessage, 'API key missing');
      expect(res.items.isEmpty, isTrue);
    });

    test('parses receipt JSON structure into InvoiceItemRecord list accurately', () {
      const rawJson = '''
      {
        "shopName": "Babu oil mill",
        "billNo": "INV-1795506205151",
        "billDate": "2026-11-24",
        "items": [
          {
            "itemName": "Gingelly oil gade 2 | Sesame Oil",
            "quantity": 0.5,
            "price": 165.0,
            "total": 82.5,
            "recipient": "Self"
          },
          {
            "itemName": "Coconut oil | Coconut Oil",
            "quantity": 0.25,
            "price": 350.0,
            "total": 87.5,
            "recipient": "Grand Father"
          },
          {
            "itemName": "Groundnut oil | Peanut Oil",
            "quantity": 4.0,
            "price": 202.0,
            "total": 808.0,
            "recipient": "Grand Father"
          }
        ]
      }
      ''';

      final parsed = jsonDecode(rawJson) as Map<String, dynamic>;
      final shopName = parsed['shopName'] as String;
      final billNo = parsed['billNo'] as String;
      final billDate = InvoiceItemRecord.parseDateSafe(parsed['billDate'] as String);
      final rawItems = parsed['items'] as List<dynamic>;

      final items = <InvoiceItemRecord>[];
      for (int i = 0; i < rawItems.length; i++) {
        final itemMap = rawItems[i] as Map<String, dynamic>;
        items.add(InvoiceItemRecord(
          id: '${billNo}_$i',
          billDate: billDate,
          shopName: shopName,
          billNo: billNo,
          itemName: itemMap['itemName'] as String,
          quantity: (itemMap['quantity'] as num).toDouble(),
          price: (itemMap['price'] as num).toDouble(),
          total: (itemMap['total'] as num).toDouble(),
          recipient: itemMap['recipient'] as String,
        ));
      }

      final summary = InvoiceSummary(
        billNo: billNo,
        shopName: shopName,
        billDate: billDate,
        items: items,
      );

      expect(summary.billNo, 'INV-1795506205151');
      expect(summary.shopName, 'Babu oil mill');
      expect(summary.totalAmount, 978.0);
      expect(summary.hasBorrowers, isTrue);
      expect(summary.selfShare, 82.5);
      expect(summary.borrowerShares['Grand Father'], 895.5);
    });
  });
}
