import 'package:daily_finance_app/services/invoice_extractor_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InvoiceExtractorService parsing tests', () {
    test('parseInvoiceJson strips <think> tags and parses formatted prices', () {
      const raw = '''
<think>
Let me inspect { "draft": 1 } carefully.
</think>
```json
{
  "dealer_name": "BAJAJ ELECTRONICS",
  "bill_number": "2106/26/S-9185",
  "invoice_date": "2026-11-26",
  "currency": "₹",
  "items": [
    {"name": "HAIER AC HSO19-5NB-I, OU", "quantity": 1, "unit_price": "0.01"},
    {"name": "HAIER AC HSA19KHD-GAI5NB-I, IU", "quantity": "1.0", "unit_price": "₹36,355.93"},
    {"description": "AC WALL MOUNT STAND", "qty": 2, "total": "₹1,000.00"}
  ]
}
```
''';

      final parsed = InvoiceExtractorService.instance.parseInvoiceJson(raw, 'Groq (qwen/qwen3.8-27b)');
      expect(parsed.dealerName, 'BAJAJ ELECTRONICS');
      expect(parsed.billNumber, '2106/26/S-9185');
      expect(parsed.invoiceDate, DateTime(2026, 11, 26));
      expect(parsed.items.length, 3);
      expect(parsed.items[1].unitPrice, closeTo(36355.93, 0.01));
      expect(parsed.items[2].name, 'AC WALL MOUNT STAND');
      expect(parsed.items[2].quantity, 2.0);
      expect(parsed.items[2].unitPrice, closeTo(500.0, 0.01));
    });

    test('parseOcrTextOffline parses row-aligned GST invoice and supermarket lines', () {
      const ocr = '''
BAJAJ ELECTRONICS
Tax Invoice
Invoice No: 2106/26/S-9185   Date: 26/11/2026
1   HAIER AC HSO19-5NB-I, OU   84151010   1.00   NOS   0.01   0.01
2   HAIER AC HSA19KHD-GAI5NB-I, IU   84151010   1.00   NOS   36,355.93   36,355.93
3   AC WALL MOUNT ANGULAR STAND   84159000   1.00   NOS   0.01   0.01
CGST @ 9%   3,272.04
SGST @ 9%   3,272.04
Grand Total   42,900.00
''';

      final res = InvoiceExtractorService.instance.parseOcrTextOffline(ocr);
      expect(res.dealerName, 'BAJAJ ELECTRONICS');
      expect(res.billNumber, '2106/26/S-9185');
      expect(res.invoiceDate, DateTime(2026, 11, 26));
      expect(res.items.length, 3);
      expect(res.items[0].name, contains('HAIER AC HSO19-5NB-I, OU'));
      expect(res.items[0].unitPrice, closeTo(0.01, 0.001));
      expect(res.items[1].name, contains('HAIER AC HSA19KHD-GAI5NB-I, IU'));
      expect(res.items[1].unitPrice, closeTo(36355.93, 0.01));
      expect(res.items[2].name, contains('AC WALL MOUNT ANGULAR STAND'));
    });

    test('parseOcrTextOffline handles qty x rate and multi-column grocery bills', () {
      const ocr = '''
D-MART SUPERMARKET
Bill No: DM-889   Date: 26-Nov-26
Ashirvaad Atta 5kg   1   285.00   285.00
Sunflower Oil 1L   2 x 145.00 = 290.00
Sub Total   575.00
''';
      final res = InvoiceExtractorService.instance.parseOcrTextOffline(ocr);
      expect(res.billNumber, 'DM-889');
      expect(res.invoiceDate, DateTime(2026, 11, 26));
      expect(res.items.length, 2);
      expect(res.items[0].name, 'Ashirvaad Atta 5kg');
      expect(res.items[0].unitPrice, 285.0);
      expect(res.items[1].name, 'Sunflower Oil 1L');
      expect(res.items[1].quantity, 2.0);
      expect(res.items[1].unitPrice, 145.0);
    });

    test('extractFromOcrText throws clear guidance when no keys and 0 offline items', () async {
      SharedPreferences.setMockInitialValues({});
      await expectLater(
        () => InvoiceExtractorService.instance.extractFromOcrText('Some unparseable note without prices'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
