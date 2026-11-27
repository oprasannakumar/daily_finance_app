import 'package:daily_finance_app/screens/invoice_manager_screen.dart';
import 'package:daily_finance_app/services/invoice_extractor_service.dart';
import 'package:daily_finance_app/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InvoiceExtractorService tests', () {
    test('parseInvoiceJson extracts billing date, invoice number, dealer, and comma prices', () {
      const raw = '''
<think>Analyzing OCR rows...</think>
```json
{
  "dealer_name": "BAJAJ ELECTRONICS",
  "invoice_number": "2106/26/S-9185",
  "billing_date": "26/11/2026",
  "currency": "₹",
  "items": [
    {"name": "HAIER AC HSO19-5NB-I, OU", "quantity": 1, "unit_price": "0.01"},
    {"name": "HAIER AC HSA19KHD-GAI5NB-I, IU", "quantity": "1.0", "unit_price": "₹36,355.93"},
    {"description": "AC WALL MOUNT STAND", "qty": 2, "total": "₹1,000.00"}
  ]
}
```
''';

      final parsed = InvoiceExtractorService.instance.parseInvoiceJson(
        raw,
        'Groq (llama-3.3-70b-versatile)',
        ocrText: 'OCR SAMPLE',
      );
      expect(parsed.dealerName, 'BAJAJ ELECTRONICS');
      expect(parsed.invoiceNumber, '2106/26/S-9185');
      expect(parsed.billingDate, DateTime(2026, 11, 26));
      expect(parsed.ocrText, 'OCR SAMPLE');
      expect(parsed.items.length, 3);
      expect(parsed.items[0].name, 'HAIER AC HSO19-5NB-I, OU');
      expect(parsed.items[1].unitPrice, closeTo(36355.93, 0.01));
      expect(parsed.items[2].name, 'AC WALL MOUNT STAND');
      expect(parsed.items[2].quantity, 2.0);
      expect(parsed.items[2].unitPrice, closeTo(500.0, 0.01));
    });

    test('parseOpenAiModelsResponse filters audio/guard models and keeps LLMs', () {
      const jsonBody = '''
{
  "data": [
    {"id": "whisper-large-v3"},
    {"id": "playai-tts"},
    {"id": "meta-llama/llama-guard-4-12b"},
    {"id": "llama-3.3-70b-versatile"},
    {"id": "qwen/qwen3.8-27b"},
    {"id": "openai/gpt-oss-120b"}
  ]
}
''';
      final models = InvoiceExtractorService.instance.parseOpenAiModelsResponse(jsonBody);
      expect(models, containsAll(['llama-3.3-70b-versatile', 'qwen/qwen3.8-27b', 'openai/gpt-oss-120b']));
      expect(models, isNot(contains('whisper-large-v3')));
      expect(models, isNot(contains('playai-tts')));
      expect(models, isNot(contains('meta-llama/llama-guard-4-12b')));
    });

    test('parseGeminiModelsResponse filters generateContent models and strips prefix', () {
      const jsonBody = '''
{
  "models": [
    {"name": "models/embedding-001", "supportedGenerationMethods": ["embedContent"]},
    {"name": "models/gemini-2.5-flash", "supportedGenerationMethods": ["generateContent", "countTokens"]},
    {"name": "models/gemini-3.6-flash", "supportedGenerationMethods": ["generateContent"]},
    {"name": "models/imagen-3.0-generate-002", "supportedGenerationMethods": ["predict"]}
  ]
}
''';
      final models = InvoiceExtractorService.instance.parseGeminiModelsResponse(jsonBody);
      expect(models, containsAll(['gemini-2.5-flash', 'gemini-3.6-flash']));
      expect(models, isNot(contains('embedding-001')));
      expect(models, isNot(contains('imagen-3.0-generate-002')));
    });

    test('StorageService persists selected Grok and Gemini models', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.instance.setSelectedGrokModel('openai/gpt-oss-120b');
      await StorageService.instance.setSelectedGeminiModel('gemini-2.5-flash-lite');

      expect(await StorageService.instance.getSelectedGrokModel(), 'openai/gpt-oss-120b');
      expect(await StorageService.instance.getSelectedGeminiModel(), 'gemini-2.5-flash-lite');
    });

    test('extractFromOcrText rejects empty OCR or missing API keys cleanly', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.instance.setGrokApiKey('');
      await StorageService.instance.setGeminiApiKey('');

      await expectLater(
        () => InvoiceExtractorService.instance.extractFromOcrText('   '),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        () => InvoiceExtractorService.instance.extractFromOcrText('BAJAJ ELECTRONICS INV-1 100.00'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('InvoiceManagerScreen Scan FAB & mapping dialog tests', () {
    testWidgets('Hides inline extractor card and expands Scan FAB into PDF/Image and Camera FABs', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const MaterialApp(home: InvoiceManagerScreen()));
      await tester.pumpAndSettle();

      // Inline extractor & model dropdowns must not be inside Invoice Manager form
      expect(find.text('AI Invoice Extractor (OCR → AI)'), findsNothing);
      expect(find.text('Grok Model'), findsNothing);
      expect(find.text('Gemini Model'), findsNothing);

      // Scan FAB visible on Create Invoice tab
      expect(find.widgetWithText(FloatingActionButton, 'Scan'), findsOneWidget);
      expect(find.widgetWithText(FloatingActionButton, 'PDF / Image'), findsNothing);
      expect(find.widgetWithText(FloatingActionButton, 'Camera'), findsNothing);

      // Tap Scan FAB -> reveals PDF / Image and Camera FABs
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FloatingActionButton, 'PDF / Image'), findsOneWidget);
      expect(find.widgetWithText(FloatingActionButton, 'Camera'), findsOneWidget);
      expect(find.widgetWithText(FloatingActionButton, 'Close'), findsOneWidget);

      // Tap Close FAB -> hides PDF / Image and Camera FABs
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Close'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FloatingActionButton, 'PDF / Image'), findsNothing);
      expect(find.widgetWithText(FloatingActionButton, 'Camera'), findsNothing);
      expect(find.widgetWithText(FloatingActionButton, 'Scan'), findsOneWidget);
    });

    testWidgets('MapExtractedInvoiceDialog maps billing date, invoice no, and Self/Others assignment', (tester) async {
      final extracted = ExtractedInvoiceData(
        dealerName: 'BAJAJ ELECTRONICS',
        invoiceNumber: '2106/26/S-9185',
        billingDate: DateTime(2026, 11, 26),
        currency: '₹',
        items: [
          ExtractedInvoiceItem(name: 'HAIER AC', quantity: 1, unitPrice: 36355.93),
          ExtractedInvoiceItem(name: 'WALL STAND', quantity: 1, unitPrice: 500.0),
        ],
        usedProvider: 'Groq (llama-3.3-70b-versatile)',
      );

      MappedInvoiceResult? mappedResult;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              isDense: true,
              constraints: BoxConstraints(minHeight: 46),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  mappedResult = await showDialog<MappedInvoiceResult>(
                    context: ctx,
                    builder: (_) => MapExtractedInvoiceDialog(
                      extracted: extracted,
                      initialDealer: extracted.dealerName,
                      initialBillNo: extracted.invoiceNumber,
                      initialBillingDate: extracted.billingDate!,
                      knownDealers: const ['BAJAJ ELECTRONICS'],
                      recipientOptions: const ['Self', 'Family', 'Friends'],
                    ),
                  );
                },
                child: const Text('Open Map'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Map'));
      await tester.pumpAndSettle();

      expect(find.text('2106/26/S-9185'), findsOneWidget);
      expect(find.text('26-Nov-26'), findsOneWidget);
      expect(find.text('HAIER AC'), findsOneWidget);
      expect(find.text('WALL STAND'), findsOneWidget);

      // Reassign second item from Self to Family
      await tester.tap(find.text('Self').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Family').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply to Invoice'));
      await tester.pumpAndSettle();

      expect(mappedResult, isNotNull);
      expect(mappedResult!.billNo, '2106/26/S-9185');
      expect(mappedResult!.billingDate, DateTime(2026, 11, 26));
      expect(mappedResult!.assignments, ['Self', 'Family']);
    });

    testWidgets('RemapItemSplitDialog supports partial remapping (1 -> 0.5 Self + 0.5 Other)', (tester) async {
      List<ItemAllocationSplit>? splitResult;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              isDense: true,
              constraints: BoxConstraints(minHeight: 46),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  splitResult = await showDialog<List<ItemAllocationSplit>>(
                    context: ctx,
                    builder: (_) => RemapItemSplitDialog(
                      itemName: 'Rasgulla',
                      billedQty: 1.0,
                      unitPrice: 120.0,
                      initialAllocations: [
                        ItemAllocationSplit(recipient: 'Self', quantity: 1.0),
                      ],
                      recipientOptions: const ['Self', 'Family', 'Friends'],
                    ),
                  );
                },
                child: const Text('Remap'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Remap'));
      await tester.pumpAndSettle();

      // Verify dropdown and Qty input align horizontally at identical 46px height
      final recipRect = tester.getRect(find.byKey(const ValueKey('split_alloc_recip_0_Self')));
      final qtyRect = tester.getRect(find.byKey(const ValueKey('split_alloc_qty_0')));
      final qtyLabelRect = tester.getRect(find.text('Qty').first);
      final qtyInputRect = tester.getRect(find.byType(EditableText).first);
      expect(recipRect.top, closeTo(qtyRect.top, 0.1));
      expect(recipRect.bottom, closeTo(qtyRect.bottom, 0.1));
      expect(recipRect.height, closeTo(46.0, 0.1));
      expect(qtyInputRect.center.dy, closeTo(qtyRect.center.dy, 2.0));
      expect(qtyLabelRect.center.dy, closeTo(qtyRect.center.dy, 2.0));

      // User changes 1 -> 0.5
      final qtyField = find.byType(TextField).first;
      await tester.enterText(qtyField, '0.5');
      await tester.pumpAndSettle();

      // Tap "+ Map Left (0.5)" button
      expect(find.text('+ Map Left (0.5)'), findsOneWidget);
      await tester.tap(find.text('+ Map Left (0.5)'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Allocated cleanly'), findsOneWidget);
      await tester.tap(find.text('Apply Remap'));
      await tester.pumpAndSettle();

      expect(splitResult, isNotNull);
      expect(splitResult!.length, 2);
      expect(splitResult![0].recipient, 'Self');
      expect(splitResult![0].quantity, closeTo(0.5, 0.001));
      expect(splitResult![1].recipient, 'Family');
      expect(splitResult![1].quantity, closeTo(0.5, 0.001));
    });

    testWidgets('MapExtractedInvoiceDialog splits extracted item partially across Self and Other', (tester) async {
      final extracted = ExtractedInvoiceData(
        dealerName: 'SWEET HOUSE',
        invoiceNumber: 'INV-99',
        billingDate: DateTime(2026, 11, 27),
        currency: '₹',
        items: [
          ExtractedInvoiceItem(name: 'Rasgulla', quantity: 1.0, unitPrice: 120.0),
        ],
        usedProvider: 'Groq (llama-3.3-70b-versatile)',
      );

      MappedInvoiceResult? mappedResult;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              isDense: true,
              constraints: BoxConstraints(minHeight: 46),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  mappedResult = await showDialog<MappedInvoiceResult>(
                    context: ctx,
                    builder: (_) => MapExtractedInvoiceDialog(
                      extracted: extracted,
                      initialDealer: extracted.dealerName,
                      initialBillNo: extracted.invoiceNumber,
                      initialBillingDate: extracted.billingDate!,
                      knownDealers: const ['SWEET HOUSE'],
                      recipientOptions: const ['Self', 'Family'],
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Split / Partial Remap'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Split Equally'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Remap'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Self: 0.5'), findsOneWidget);
      expect(find.textContaining('Family: 0.5'), findsOneWidget);

      await tester.tap(find.text('Apply to Invoice'));
      await tester.pumpAndSettle();

      expect(mappedResult, isNotNull);
      expect(mappedResult!.allocationsPerItem.length, 1);
      expect(mappedResult!.allocationsPerItem[0].length, 2);
      expect(mappedResult!.allocationsPerItem[0][0].recipient, 'Self');
      expect(mappedResult!.allocationsPerItem[0][0].quantity, closeTo(0.5, 0.001));
      expect(mappedResult!.allocationsPerItem[0][1].recipient, 'Family');
      expect(mappedResult!.allocationsPerItem[0][1].quantity, closeTo(0.5, 0.001));
    });
  });
}
