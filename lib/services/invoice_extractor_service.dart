import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
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
    final rawName = json['name'] ??
        json['item_name'] ??
        json['itemName'] ??
        json['description'] ??
        json['item'] ??
        json['product'] ??
        json['title'] ??
        '';
    final qty = _parseFlexibleNumber(json['quantity'] ?? json['qty'], fallback: 1.0);
    var unitPrice = _parseFlexibleNumber(
      json['unit_price'] ?? json['unitPrice'] ?? json['price'] ?? json['rate'],
      fallback: 0.0,
    );
    if (unitPrice <= 0) {
      final lineTotal = _parseFlexibleNumber(
        json['total'] ?? json['line_total'] ?? json['lineTotal'] ?? json['amount'] ?? json['net_amount'],
        fallback: 0.0,
      );
      if (lineTotal > 0) {
        unitPrice = qty > 0 ? (lineTotal / qty) : lineTotal;
      }
    }
    return ExtractedInvoiceItem(
      name: rawName.toString().trim(),
      quantity: qty > 0 ? qty : 1.0,
      unitPrice: unitPrice,
    );
  }

  static double _parseFlexibleNumber(dynamic raw, {required double fallback}) {
    if (raw == null) return fallback;
    if (raw is num) return raw.toDouble();
    final cleaned = raw.toString().replaceAll(RegExp(r'[₹$€£,\s]|INR|Rs\.?|/-', caseSensitive: false), '');
    return double.tryParse(cleaned) ?? fallback;
  }
}

class ExtractedInvoiceData {
  final String dealerName;
  final String invoiceNumber;
  final DateTime? billingDate;
  final String currency;
  final List<ExtractedInvoiceItem> items;
  final String usedProvider;
  final String ocrText;

  ExtractedInvoiceData({
    required this.dealerName,
    this.invoiceNumber = '',
    this.billingDate,
    required this.currency,
    required this.items,
    required this.usedProvider,
    this.ocrText = '',
  });
}

class InvoiceExtractorService {
  InvoiceExtractorService._();
  static final InvoiceExtractorService instance = InvoiceExtractorService._();

  static const String groqChatEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const String openRouterChatEndpoint = 'https://openrouter.ai/api/v1/chat/completions';
  static const String xaiChatEndpoint = 'https://api.x.ai/v1/chat/completions';

  static const String groqModelsEndpoint = 'https://api.groq.com/openai/v1/models';
  static const String openRouterModelsEndpoint = 'https://openrouter.ai/api/v1/models';
  static const String xaiModelsEndpoint = 'https://api.x.ai/v1/models';

  static const List<String> defaultGroqModels = [
    'llama-3.3-70b-versatile',
    'qwen/qwen3.8-27b',
    'openai/gpt-oss-120b',
    'llama-3.1-8b-instant',
  ];

  static const List<String> defaultOpenRouterModels = [
    'qwen/qwen3.8-27b',
    'meta-llama/llama-3.3-70b-instruct',
    'google/gemini-2.5-flash',
  ];

  static const List<String> defaultXaiModels = [
    'grok-3-mini-fast',
    'grok-3-mini',
    'grok-3',
    'grok-2-latest',
  ];

  static const List<String> defaultGeminiModels = [
    'gemini-2.5-flash',
    'gemini-3.6-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.0-flash',
  ];

  static const String _extractionPrompt = '''
You are an expert invoice and receipt data extraction AI agent.
Analyze the OCR-extracted text from an invoice/bill and return strictly valid JSON matching this schema:
{
  "dealer_name": "Store, dealer, vendor, or seller name",
  "invoice_number": "Invoice number, bill number, or receipt number if visible, otherwise empty string",
  "billing_date": "Billing/invoice date in YYYY-MM-DD format if visible, otherwise empty string",
  "currency": "Currency symbol or ISO code (e.g., ₹, INR, \$, USD)",
  "items": [
    {
      "name": "Purchased product or service name/description",
      "quantity": 1.0,
      "unit_price": 0.0
    }
  ]
}

Rules:
- Extract every purchased product or service line item present in the OCR text.
- Note that OCR text from multi-column invoices may place names, quantities, HSN codes, rates, and totals across columns on each row — match each item carefully to its quantity and price.
- "quantity" and "unit_price" MUST be JSON numbers (no commas or currency symbols).
- "unit_price" must be the price per 1 unit (if only a line total is printed and quantity > 1, compute line_total / quantity; if quantity is 1 or missing, use the item's amount).
- Exclude subtotal, grand total, CGST/SGST/IGST/tax summary, round-off, and payment summary lines from "items".
- Return ONLY the raw JSON object with no markdown fences or commentary.
''';

  static String providerLabelForKey(String apiKey) {
    final k = apiKey.trim();
    if (k.startsWith('gsk_')) return 'Groq';
    if (k.startsWith('sk-or-')) return 'OpenRouter';
    if (k.startsWith('xai-')) return 'Grok xAI';
    return 'Groq / Grok';
  }

  static List<String> defaultGrokModelsForKey(String apiKey) {
    final k = apiKey.trim();
    if (k.startsWith('sk-or-')) return defaultOpenRouterModels;
    if (k.startsWith('xai-')) return defaultXaiModels;
    return defaultGroqModels;
  }

  static String _modelsEndpointForKey(String apiKey) {
    final k = apiKey.trim();
    if (k.startsWith('sk-or-')) return openRouterModelsEndpoint;
    if (k.startsWith('xai-')) return xaiModelsEndpoint;
    return groqModelsEndpoint;
  }

  static String _chatEndpointForKey(String apiKey) {
    final k = apiKey.trim();
    if (k.startsWith('sk-or-')) return openRouterChatEndpoint;
    if (k.startsWith('xai-')) return xaiChatEndpoint;
    return groqChatEndpoint;
  }

  /// Fetches live available chat/reasoning models for the given Grok/Groq/OpenRouter/xAI API key.
  Future<List<String>> fetchAvailableGrokModels(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      final cached = await StorageService.instance.getCachedGrokModels();
      return cached.isNotEmpty ? cached : defaultGroqModels;
    }

    final endpoints = key.startsWith('gsk_') || key.startsWith('sk-or-') || key.startsWith('xai-')
        ? [_modelsEndpointForKey(key)]
        : [groqModelsEndpoint, openRouterModelsEndpoint, xaiModelsEndpoint];

    for (final endpoint in endpoints) {
      try {
        final res = await http.get(
          Uri.parse(endpoint),
          headers: {'Authorization': 'Bearer $key'},
        ).timeout(const Duration(seconds: 20));

        if (res.statusCode >= 200 && res.statusCode < 300) {
          final models = parseOpenAiModelsResponse(res.body);
          if (models.isNotEmpty) {
            await StorageService.instance.setCachedGrokModels(models);
            return models;
          }
        }
      } catch (_) {}
    }

    final cached = await StorageService.instance.getCachedGrokModels();
    return cached.isNotEmpty ? cached : defaultGrokModelsForKey(key);
  }

  /// Fetches live available Gemini models that support `generateContent` for the given Gemini API key.
  Future<List<String>> fetchAvailableGeminiModels(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      final cached = await StorageService.instance.getCachedGeminiModels();
      return cached.isNotEmpty ? cached : defaultGeminiModels;
    }

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models?key=$key&pageSize=100',
      );
      final res = await http.get(
        url,
        headers: {'x-goog-api-key': key},
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final models = parseGeminiModelsResponse(res.body);
        if (models.isNotEmpty) {
          await StorageService.instance.setCachedGeminiModels(models);
          return models;
        }
      }
    } catch (_) {}

    final cached = await StorageService.instance.getCachedGeminiModels();
    return cached.isNotEmpty ? cached : defaultGeminiModels;
  }

  @visibleForTesting
  List<String> parseOpenAiModelsResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const [];
    final data = decoded['data'] as List<dynamic>? ?? const [];
    final excluded = RegExp(
      r'whisper|tts|playai|guard|safeguard|embed|rerank|imagen|flux|dall-e|sora|audio|moderation',
      caseSensitive: false,
    );
    final ids = <String>[];
    for (final entry in data) {
      if (entry is Map<String, dynamic>) {
        final id = (entry['id'] ?? '').toString().trim();
        if (id.isNotEmpty && !excluded.hasMatch(id) && !ids.contains(id)) {
          ids.add(id);
        }
      }
    }
    ids.sort();
    // Keep most useful general models near the top if present while preserving full alphabetical list
    const preferred = ['llama-3.3-70b-versatile', 'qwen/qwen3.8-27b', 'openai/gpt-oss-120b', 'grok-3-mini-fast'];
    for (final p in preferred.reversed) {
      if (ids.remove(p)) ids.insert(0, p);
    }
    return ids.length > 80 ? ids.sublist(0, 80) : ids;
  }

  @visibleForTesting
  List<String> parseGeminiModelsResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const [];
    final models = decoded['models'] as List<dynamic>? ?? const [];
    final excluded = RegExp(
      r'embedding|aqa|imagen|veo|tts|robotics|native-audio|live',
      caseSensitive: false,
    );
    final result = <String>[];
    for (final entry in models) {
      if (entry is! Map<String, dynamic>) continue;
      final methods = (entry['supportedGenerationMethods'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();
      if (!methods.contains('generateContent')) continue;
      var name = (entry['name'] ?? '').toString().trim();
      if (name.startsWith('models/')) {
        name = name.substring('models/'.length);
      }
      if (name.isEmpty || excluded.hasMatch(name)) continue;
      if (!result.contains(name)) result.add(name);
    }
    result.sort();
    const preferred = ['gemini-2.5-flash', 'gemini-3.6-flash', 'gemini-2.5-flash-lite', 'gemini-2.0-flash'];
    for (final p in preferred.reversed) {
      if (result.remove(p)) result.insert(0, p);
    }
    return result;
  }

  /// Composites a rasterized PDF PNG onto an opaque white background so dark text is
  /// never rendered against transparent pixels during ML Kit OCR.
  Future<Uint8List> compositeOnWhiteBackground(Uint8List pngBytes) async {
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..color = Colors.white;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        paint,
      );
      canvas.drawImage(image, Offset.zero, Paint());
      final picture = recorder.endRecording();
      final flattened = await picture.toImage(image.width, image.height);
      try {
        final byteData = await flattened.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List() ?? pngBytes;
      } finally {
        flattened.dispose();
        picture.dispose();
      }
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  /// Step 1: Runs on-device ML Kit OCR on image/PDF page bytes and returns row-aligned text.
  Future<String> extractOcrText(List<Uint8List> imageBytesList) async {
    if (imageBytesList.isEmpty) return '';
    final tempDir = await getTemporaryDirectory();
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final buffer = StringBuffer();

    try {
      for (int i = 0; i < imageBytesList.length; i++) {
        final bytes = imageBytesList[i];
        final ext = _detectImageExtension(bytes);
        final file = File('${tempDir.path}/ocr_page_${DateTime.now().millisecondsSinceEpoch}_$i.$ext');
        await file.writeAsBytes(bytes, flush: true);
        try {
          final inputImage = InputImage.fromFilePath(file.path);
          final recognized = await recognizer.processImage(inputImage);
          final pageText = _formatRowAlignedText(recognized);
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

  String _detectImageExtension(Uint8List bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45) {
      return 'webp';
    }
    return 'png';
  }

  /// Groups ML Kit text lines by vertical row center so multi-column invoice rows remain aligned.
  String _formatRowAlignedText(RecognizedText recognized) {
    final lines = <TextLine>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        if (line.text.trim().isNotEmpty) {
          lines.add(line);
        }
      }
    }
    if (lines.isEmpty) return recognized.text.trim();

    lines.sort((a, b) {
      final yCmp = a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy);
      if (yCmp != 0) return yCmp;
      return a.boundingBox.left.compareTo(b.boundingBox.left);
    });

    final rows = <List<TextLine>>[];
    for (final line in lines) {
      final box = line.boundingBox;
      final lineHeight = math.max(1.0, box.height);
      if (rows.isNotEmpty) {
        final lastRow = rows.last;
        final anchorBox = lastRow.first.boundingBox;
        final anchorHeight = math.max(1.0, anchorBox.height);
        final tolerance = math.max(lineHeight, anchorHeight) * 0.6;
        if ((box.center.dy - anchorBox.center.dy).abs() <= tolerance) {
          lastRow.add(line);
          continue;
        }
      }
      rows.add([line]);
    }

    return rows
        .map((row) {
          row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
          return row.map((l) => l.text.trim()).join('   ');
        })
        .join('\n')
        .trim();
  }

  /// Steps 2 & 3: Feeds OCR text into the selected Grok/Gemini AI agents and extracts
  /// billing date, invoice number, dealer name, and line items (name, qty, price).
  Future<ExtractedInvoiceData> extractFromOcrText(
    String ocrText, {
    String? selectedGrokModel,
    String? selectedGeminiModel,
    void Function(String status)? onStatus,
  }) async {
    if (ocrText.trim().isEmpty) {
      throw Exception('OCR did not detect any readable text in the selected file.');
    }

    final grokKey = ((await StorageService.instance.getGrokApiKey()) ?? '').trim();
    final geminiKey = ((await StorageService.instance.getGeminiApiKey()) ?? '').trim();

    if (grokKey.isEmpty && geminiKey.isEmpty) {
      throw Exception('Please configure at least one API key (Grok or Gemini) before extracting.');
    }

    final grokModel = (selectedGrokModel != null && selectedGrokModel.trim().isNotEmpty)
        ? selectedGrokModel.trim()
        : ((await StorageService.instance.getSelectedGrokModel()) ?? defaultGrokModelsForKey(grokKey).first);

    final geminiModel = (selectedGeminiModel != null && selectedGeminiModel.trim().isNotEmpty)
        ? selectedGeminiModel.trim()
        : ((await StorageService.instance.getSelectedGeminiModel()) ?? defaultGeminiModels.first);

    final errors = <String>[];

    // 1. Try primary Grok / Groq / OpenRouter / xAI selected model
    if (grokKey.isNotEmpty) {
      final label = providerLabelForKey(grokKey);
      onStatus?.call('Analyzing OCR text with $label ($grokModel)...');
      try {
        final primary = await _callOpenAiCompatible(
          endpoint: _chatEndpointForKey(grokKey),
          providerLabel: label,
          model: grokModel,
          apiKey: grokKey,
          ocrText: ocrText,
        );
        if (primary.items.isNotEmpty) {
          return primary;
        }
        errors.add('$label ($grokModel): returned 0 items');
      } catch (e) {
        errors.add('$label ($grokModel): ${_cleanError(e)}');
      }
    }

    // 2. Fallback to selected Gemini model
    if (geminiKey.isNotEmpty) {
      onStatus?.call('Analyzing OCR text with Gemini ($geminiModel)...');
      try {
        final fallback = await _callGemini(
          apiKey: geminiKey,
          ocrText: ocrText,
          model: geminiModel,
        );
        if (fallback.items.isNotEmpty) {
          return fallback;
        }
        errors.add('Gemini ($geminiModel): returned 0 items');
      } catch (e) {
        errors.add('Gemini ($geminiModel): ${_cleanError(e)}');
      }
    }

    throw Exception(errors.join('\n'));
  }

  Future<ExtractedInvoiceData> _callOpenAiCompatible({
    required String endpoint,
    required String providerLabel,
    required String model,
    required String apiKey,
    required String ocrText,
    bool useJsonResponseFormat = true,
  }) async {
    final payload = <String, dynamic>{
      'model': model,
      'temperature': 0.0,
      if (useJsonResponseFormat) 'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'user',
          'content': '${_extractionPrompt.trim()}\n\nOCR TEXT:\n$ocrText',
        },
      ],
    };

    final res = await http
        .post(
          Uri.parse(endpoint),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 60));

    if (res.statusCode == 400 && useJsonResponseFormat) {
      return _callOpenAiCompatible(
        endpoint: endpoint,
        providerLabel: providerLabel,
        model: model,
        apiKey: apiKey,
        ocrText: ocrText,
        useJsonResponseFormat: false,
      );
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${_extractApiErrorMessage(res.body)}');
    }

    final root = jsonDecode(res.body) as Map<String, dynamic>;
    final choices = root['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('Response missing choices.');
    }
    final msg = (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
    var content = msg?['content']?.toString().trim() ?? '';
    if (content.isEmpty) {
      content = (msg?['reasoning_content'] ?? msg?['reasoning'] ?? '').toString().trim();
    }
    return parseInvoiceJson(content, '$providerLabel ($model)', ocrText: ocrText);
  }

  Future<ExtractedInvoiceData> _callGemini({
    required String apiKey,
    required String ocrText,
    required String model,
  }) async {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );
    final res = await http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
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
      throw Exception('HTTP ${res.statusCode}: ${_extractApiErrorMessage(res.body)}');
    }

    final root = jsonDecode(res.body) as Map<String, dynamic>;
    final candidates = root['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini response missing candidates.');
    }
    final text = (candidates.first as Map<String, dynamic>)['content']?['parts']?[0]?['text']?.toString() ?? '';
    return parseInvoiceJson(text, 'Gemini ($model)', ocrText: ocrText);
  }

  String _extractApiErrorMessage(String body) {
    try {
      final root = jsonDecode(body);
      if (root is Map<String, dynamic>) {
        final err = root['error'];
        if (err is Map<String, dynamic> && err['message'] != null) {
          final msg = err['message'].toString().replaceAll('\n', ' ').trim();
          return msg.length > 140 ? '${msg.substring(0, 140)}...' : msg;
        }
      }
    } catch (_) {}
    final singleLine = body.replaceAll('\n', ' ').trim();
    return singleLine.length > 140 ? '${singleLine.substring(0, 140)}...' : singleLine;
  }

  String _cleanError(Object e) {
    return e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').split('\n').first.trim();
  }

  DateTime? _parseInvoiceDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
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
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final mTxt = RegExp(r'^(\d{1,2})[\s\-]([A-Za-z]{3,9})[\s\-](\d{2,4})$').firstMatch(s);
    if (mTxt != null) {
      final d = int.parse(mTxt.group(1)!);
      final mo = months[mTxt.group(2)!.substring(0, 3).toLowerCase()];
      var y = int.parse(mTxt.group(3)!);
      if (y < 100) y += 2000;
      if (mo != null && d >= 1 && d <= 31) {
        return DateTime(y, mo, d);
      }
    }
    return null;
  }

  @visibleForTesting
  ExtractedInvoiceData parseInvoiceJson(
    String raw,
    String provider, {
    String ocrText = '',
  }) {
    var cleaned = raw.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '').trim();
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
    final decoded = jsonDecode(cleaned.substring(start, end + 1));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Model response is not a JSON object.');
    }

    final nested = decoded['invoice'] is Map<String, dynamic>
        ? decoded['invoice'] as Map<String, dynamic>
        : (decoded['data'] is Map<String, dynamic> ? decoded['data'] as Map<String, dynamic> : decoded);

    final rawItems = (nested['items'] ??
            nested['line_items'] ??
            nested['lineItems'] ??
            nested['products'] ??
            decoded['items'] ??
            const []) as List<dynamic>;

    final items = rawItems
        .whereType<Map<String, dynamic>>()
        .map(ExtractedInvoiceItem.fromJson)
        .where((it) => it.name.isNotEmpty)
        .toList();

    final dateRaw =
        (nested['billing_date'] ?? nested['billingDate'] ?? nested['invoice_date'] ?? nested['invoiceDate'] ?? nested['date'] ?? '')
            .toString();
    final invNoRaw =
        (nested['invoice_number'] ?? nested['invoiceNumber'] ?? nested['bill_number'] ?? nested['billNumber'] ?? nested['bill_no'] ?? '')
            .toString()
            .trim();
    final dealerRaw =
        (nested['dealer_name'] ?? nested['dealerName'] ?? nested['vendor'] ?? nested['shop_name'] ?? '')
            .toString()
            .trim();

    return ExtractedInvoiceData(
      dealerName: dealerRaw,
      invoiceNumber: invNoRaw,
      billingDate: _parseInvoiceDate(dateRaw),
      currency: (nested['currency'] ?? '').toString().trim(),
      items: items,
      usedProvider: provider,
      ocrText: ocrText,
    );
  }
}
