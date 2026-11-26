import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
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
  final String currency;
  final List<ExtractedInvoiceItem> items;
  final String usedProvider;

  ExtractedInvoiceData({
    required this.dealerName,
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
Analyze the provided invoice page image(s) and extract the following fields strictly as valid JSON:
{
  "dealer_name": "Name of the dealer, vendor, store, or seller issuing the invoice",
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

  Future<ExtractedInvoiceData> extractFromImages(List<Uint8List> imageBytesList) async {
    if (imageBytesList.isEmpty) {
      throw Exception('No invoice image provided.');
    }

    final grokKey = ((await StorageService.instance.getGrokApiKey()) ?? '').trim();
    final geminiKey = ((await StorageService.instance.getGeminiApiKey()) ?? '').trim();

    if (grokKey.isEmpty && geminiKey.isEmpty) {
      throw Exception('Please configure at least one API key (Grok or Gemini) in API Keys settings.');
    }

    final base64Pages = imageBytesList.map((b) => base64Encode(b)).toList();
    String? primaryError;

    if (grokKey.isNotEmpty) {
      try {
        return await _extractWithGrok(grokKey, base64Pages);
      } catch (e) {
        primaryError = e.toString();
      }
    } else {
      primaryError = 'Grok API key not set.';
    }

    if (geminiKey.isNotEmpty) {
      try {
        return await _extractWithGemini(geminiKey, base64Pages);
      } catch (e) {
        throw Exception('Both models failed.\n• Grok: $primaryError\n• Gemini: $e');
      }
    }

    throw Exception('Grok extraction failed: $primaryError');
  }

  Future<ExtractedInvoiceData> _extractWithGrok(String apiKey, List<String> base64Pages) async {
    final contentParts = <Map<String, dynamic>>[
      {'type': 'text', 'text': _extractionPrompt.trim()},
      for (final b64 in base64Pages)
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/jpeg;base64,$b64'},
        },
    ];

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
              {'role': 'user', 'content': contentParts},
            ],
          }),
        )
        .timeout(const Duration(seconds: 90));

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

  Future<ExtractedInvoiceData> _extractWithGemini(String apiKey, List<String> base64Pages) async {
    final parts = <Map<String, dynamic>>[
      {'text': _extractionPrompt.trim()},
      for (final b64 in base64Pages)
        {
          'inline_data': {
            'mime_type': 'image/jpeg',
            'data': b64,
          },
        },
    ];

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$apiKey',
    );
    final res = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {'parts': parts},
            ],
            'generationConfig': {
              'temperature': 0.0,
              'responseMimeType': 'application/json',
            },
          }),
        )
        .timeout(const Duration(seconds: 90));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final root = jsonDecode(res.body) as Map<String, dynamic>;
    final candidates = root['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini response missing candidates.');
    }
    final text = (candidates.first as Map<String, dynamic>)['content']?['parts']?[0]?['text']?.toString() ?? '';
    return _parseInvoiceJson(text, 'Gemini ($_geminiModel)');
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
      currency: (map['currency'] ?? '').toString().trim(),
      items: items,
      usedProvider: provider,
    );
  }
}
