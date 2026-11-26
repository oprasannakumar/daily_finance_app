import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';

class ExtractedInvoiceItem {
  String name;
  double quantity;
  double unitPrice;

  ExtractedInvoiceItem({
    required this.name,
    this.quantity = 1.0,
    this.unitPrice = 0.0,
  });

  factory ExtractedInvoiceItem.fromJson(Map<String, dynamic> json) {
    return ExtractedInvoiceItem(
      name: (json['name'] ?? '').toString().trim(),
      quantity: (json['quantity'] is num)
          ? (json['quantity'] as num).toDouble()
          : (double.tryParse(json['quantity']?.toString() ?? '') ?? 1.0),
      unitPrice: (json['unit_price'] is num)
          ? (json['unit_price'] as num).toDouble()
          : (double.tryParse(json['unit_price']?.toString() ?? '') ?? 0.0),
    );
  }
}

class ExtractedInvoiceData {
  final String dealerName;
  final String billNumber;
  final DateTime? invoiceDate;
  final String currency;
  final List<ExtractedInvoiceItem> items;
  final String usedProvider;

  ExtractedInvoiceData({
    required this.dealerName,
    this.billNumber = '',
    this.invoiceDate,
    required this.currency,
    required this.items,
    required this.usedProvider,
  });
}

class InvoiceExtractorService {
  InvoiceExtractorService._();
  static final InvoiceExtractorService instance = InvoiceExtractorService._();

  static const String _grokEndpoint = 'https://openrouter.ai/api/v1/chat/completions';
  static const String _grokModel = 'qwen/qwen3.8-27b';
  static const String _geminiModel = 'gemini-3.6-flash';

  static const String _extractionPrompt = '''
You are an expert invoice data extraction assistant.
Analyze the provided OCR text extracted from an invoice/bill and extract the following fields strictly as valid JSON:
{
  "dealer_name": "Name of the dealer, vendor, store, or seller issuing the invoice",
  "bill_number": "Invoice number, bill number, or receipt number if visible, otherwise empty string",
  "invoice_date": "Invoice date in YYYY-MM-DD format if visible, otherwise empty string",
  "currency": "Currency symbol or 3-letter ISO code if visible (e.g., ₹, INR, \$, USD), otherwise empty string",
  "items": [
    {
      "name": "Description or name of the individual item",
      "quantity": 1.0,
      "unit_price": 0.0
    }
  ]
}

Rules:
- Extract every line item shown on the invoice.
- "unit_price" must be the price of ONE individual unit of that item (not the line total, unless quantity is 1 or only line total is shown, in which case compute unit_price = line_total / quantity).
- "quantity" and "unit_price" must be numbers (not strings).
- Do not include tax, shipping, subtotal, or grand total rows as items.
- Return ONLY the JSON object, with no extra commentary or markdown.
''';

  /// Runs on-device ML Kit OCR on the given image/PDF page bytes and returns combined text.
  Future<String> extractOcrText(List<Uint8List> imageBytesList) async {
    if (imageBytesList.isEmpty) return '';
    final tempDir = await getTemporaryDirectory();
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final buffer = StringBuffer();

    try {
      for (int i = 0; i < imageBytesList.length; i++) {
        final file = File('${tempDir.path}/ocr_page_${DateTime.now().millisecondsSinceEpoch}_$i.png');
        await file.writeAsBytes(imageBytesList[i], flush: true);
        try {
          final inputImage = InputImage.fromFilePath(file.path);
          final recognized = await recognizer.processImage(inputImage);
          final pageText = recognized.text.trim();
          if (pageText.isNotEmpty) {
            if (buffer.isNotEmpty) buffer.writeln('\n--- PAGE ${i + 1} ---\n');
            buffer.writeln(pageText);
          }
        } finally {
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
    } finally {
      await recognizer.close();
    }
    return buffer.toString().trim();
  }

  Future<ExtractedInvoiceData> extractFromOcrText(String ocrText) async {
    if (ocrText.trim().isEmpty) {
      throw Exception('No readable text found in the selected document.');
    }

    final grokKey = ((await StorageService.instance.getGrokApiKey()) ?? '').trim();
    final geminiKey = ((await StorageService.instance.getGeminiApiKey()) ?? '').trim();

    if (grokKey.isEmpty && geminiKey.isEmpty) {
      throw Exception('Please configure at least one API key (Grok or Gemini) in API Keys settings.');
    }

    String? primaryError;

    if (grokKey.isNotEmpty) {
      try {
        return await _extractTextWithGrok(grokKey, ocrText);
      } catch (e) {
        primaryError = e.toString();
      }
    } else {
      primaryError = 'Grok API key not set.';
    }

    if (geminiKey.isNotEmpty) {
      try {
        return await _extractTextWithGemini(geminiKey, ocrText);
      } catch (e) {
        throw Exception('Both models failed.\n• Grok: $primaryError\n• Gemini: $e');
      }
    }

    throw Exception('Grok extraction failed: $primaryError');
  }

  Future<ExtractedInvoiceData> _extractTextWithGrok(String apiKey, String ocrText) async {
    final res = await http
        .post(
          Uri.parse(_grokEndpoint),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': _grokModel,
            'temperature': 0.0,
            'response_format': {'type': 'json_object'},
            'messages': [
              {
                'role': 'user',
                'content': '${_extractionPrompt.trim()}\n\nOCR TEXT:\n$ocrText',
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final root = jsonDecode(res.body) as Map<String, dynamic>;
    final choices = root['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('Grok response missing choices.');
    }
    final content = (choices.first as Map<String, dynamic>)['message']?['content']?.toString() ?? '';
    return _parseInvoiceJson(content, 'Grok ($_grokModel)');
  }

  Future<ExtractedInvoiceData> _extractTextWithGemini(String apiKey, String ocrText) async {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$apiKey',
    );
    final res = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': '${_extractionPrompt.trim()}\n\nOCR TEXT:\n$ocrText'},
                ],
              },
            ],
            'generationConfig': {
              'temperature': 0.0,
              'responseMimeType': 'application/json',
            },
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final root = jsonDecode(res.body) as Map<String, dynamic>;
    final candidates = root['candidates']?.jsonArrayOrNull ?? root['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini response missing candidates.');
    }
    final text = (candidates.first as Map<String, dynamic>)['content']?['parts']?[0]?['text']?.toString() ?? '';
    return _parseInvoiceJson(text, 'Gemini ($_geminiModel)');
  }

  DateTime? _parseInvoiceDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    // Try DD/MM/YYYY or DD-MM-YYYY
    final m = RegExp(r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})$').firstMatch(s);
    if (m != null) {
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
        return DateTime(y, mo, d);
      }
    }
    return null;
  }

  ExtractedInvoiceData _parseInvoiceJson(String raw, String provider) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('```')) {
      final firstNl = cleaned.indexOf('\n');
      final lastFence = cleaned.lastIndexOf('```');
      if (firstNl != -1 && lastFence > firstNl) {
        cleaned = cleaned.substring(firstNl + 1, lastFence).trim();
      }
    }
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end <= start) {
      throw Exception('Model did not return valid JSON.');
    }
    final map = jsonDecode(cleaned.substring(start, end + 1)) as Map<String, dynamic>;
    final rawItems = map['items'] as List<dynamic>? ?? [];
    final items = rawItems
        .whereType<Map<String, dynamic>>()
        .map(ExtractedInvoiceItem.fromJson)
        .where((it) => it.name.isNotEmpty)
        .toList();

    return ExtractedInvoiceData(
      dealerName: (map['dealer_name'] ?? '').toString().trim(),
      billNumber: (map['bill_number'] ?? '').toString().trim(),
      invoiceDate: _parseInvoiceDate((map['invoice_date'] ?? '').toString()),
      currency: (map['currency'] ?? '').toString().trim(),
      items: items,
      usedProvider: provider,
    );
  }
}

extension on Object? {
  List<dynamic>? get jsonArrayOrNull => this is List<dynamic> ? this as List<dynamic> : null;
}
