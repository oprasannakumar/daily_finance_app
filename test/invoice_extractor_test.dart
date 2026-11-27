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

  group('InvoiceManagerScreen AI model dropdown widget tests', () {
    testWidgets('Shows Grok and Gemini model dropdowns and extractor controls', (tester) async {
      SharedPreferences.setMockInitialValues({
        'cached_grok_models': ['llama-3.3-70b-versatile', 'qwen/qwen3.8-27b'],
        'cached_gemini_models': ['gemini-2.5-flash', 'gemini-3.6-flash'],
        'selected_grok_model': 'qwen/qwen3.8-27b',
        'selected_gemini_model': 'gemini-3.6-flash',
      });

      await tester.pumpWidget(const MaterialApp(home: InvoiceManagerScreen()));
      await tester.pumpAndSettle();

      expect(find.text('AI Invoice Extractor (OCR → AI)'), findsOneWidget);
      expect(find.text('Grok Model'), findsOneWidget);
      expect(find.text('Gemini Model'), findsOneWidget);
      expect(find.text('PDF / Image'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('qwen/qwen3.8-27b'), findsOneWidget);
      expect(find.text('gemini-3.6-flash'), findsOneWidget);
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
  });
}
