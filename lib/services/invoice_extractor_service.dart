import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
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
    final rawName =
        json['name'] ?? json['item_name'] ?? json['description'] ?? json['item'] ?? json['title'] ?? '';
    final qty = _parseFlexibleNumber(json['quantity'] ?? json['qty'], fallback: 1.0);
    var unitPrice = _parseFlexibleNumber(
      json['unit_price'] ?? json['unitPrice'] ?? json['price'] ?? json['rate'],
      fallback: 0.0,
    );
    if (unitPrice <= 0) {
      final lineTotal = _parseFlexibleNumber(
        json['total'] ?? json['line_total'] ?? json['amount'] ?? json['net_amount'],
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

  static const String _groqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _openRouterEndpoint = 'https://openrouter.ai/api/v1/chat/completions';
  static const String _xaiEndpoint = 'https://api.x.ai/v1/chat/completions';

  static const List<String> _groqModels = [
    'qwen/qwen3.8-27b',
    'qwen/qwen3-32b',
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant',
  ];
  static const List<String> _openRouterModels = [
    'qwen/qwen3.8-27b',
    'qwen/qwen3-32b',
  ];
  static const List<String> _xaiModels = [
    'grok-3-mini-fast',
    'grok-3-mini',
    'grok-2-latest',
  ];
  static const List<String> _geminiModels = [
    'gemini-3.6-flash',
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.0-flash',
  ];

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
- Handle minor OCR typos or spacing variations sensibly.
- Return ONLY the JSON object, with no extra commentary or markdown.
''';

  /// Runs on-device ML Kit OCR on the given image/PDF page bytes and returns row-aligned text.
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

  /// Groups ML Kit text lines by vertical row center so tabular invoice columns stay together.
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

    return rows.map((row) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      return row.map((l) => l.text.trim()).join('   ');
    }).join('\n').trim();
  }

  Future<ExtractedInvoiceData> extractFromOcrText(String ocrText) async {
    if (ocrText.trim().isEmpty) {
      throw Exception('No readable text found in the selected document.');
    }

    final grokKey = ((await StorageService.instance.getGrokApiKey()) ?? '').trim();
    final geminiKey = ((await StorageService.instance.getGeminiApiKey()) ?? '').trim();
    final errors = <String>[];

    if (grokKey.isNotEmpty) {
      final grokRes = await _extractTextWithGrok(grokKey, ocrText, errors);
      if (grokRes != null && grokRes.items.isNotEmpty) {
        return grokRes;
      }
    }

    if (geminiKey.isNotEmpty) {
      for (final model in _geminiModels) {
        try {
          final gemRes = await _extractTextWithGemini(geminiKey, ocrText, model);
          if (gemRes.items.isNotEmpty) {
            return gemRes;
          }
          errors.add('Gemini ($model): 0 items extracted');
        } catch (e) {
          errors.add('Gemini ($model): ${_cleanError(e)}');
        }
      }
    }

    // Fallback to offline OCR parser if AI keys are missing, quota-limited, or failed
    final offline = parseOcrTextOffline(ocrText);
    if (offline.items.isNotEmpty) {
      return offline;
    }

    if (errors.isNotEmpty) {
      throw Exception(errors.join('\n'));
    }
    if (grokKey.isEmpty && geminiKey.isEmpty) {
      throw Exception('No items matched offline and no AI API keys are set. Tap the Key icon to add a Groq, OpenRouter, xAI, or Gemini key.');
    }
    return offline;
  }

  List<(String endpoint, String providerLabel, List<String> models)> _resolveOpenAiTargets(String apiKey) {
    if (apiKey.startsWith('gsk_')) {
      return [
        (_groqEndpoint, 'Groq', _groqModels),
      ];
    }
    if (apiKey.startsWith('xai-')) {
      return [
        (_xaiEndpoint, 'Grok xAI', _xaiModels),
      ];
    }
    if (apiKey.startsWith('sk-or-')) {
      return [
        (_openRouterEndpoint, 'OpenRouter', _openRouterModels),
      ];
    }
    return [
      (_groqEndpoint, 'Groq', _groqModels),
      (_openRouterEndpoint, 'OpenRouter', _openRouterModels),
      (_xaiEndpoint, 'Grok xAI', _xaiModels),
    ];
  }

  Future<ExtractedInvoiceData?> _extractTextWithGrok(
    String apiKey,
    String ocrText,
    List<String> errors,
  ) async {
    final targets = _resolveOpenAiTargets(apiKey);
    for (final (endpoint, providerLabel, models) in targets) {
      for (final model in models) {
        try {
          final parsed = await _callOpenAiCompatible(
            endpoint: endpoint,
            providerLabel: providerLabel,
            model: model,
            apiKey: apiKey,
            ocrText: ocrText,
          );
          if (parsed.items.isNotEmpty) {
            return parsed;
          }
          errors.add('$providerLabel ($model): 0 items extracted');
        } catch (e) {
          final msg = _cleanError(e);
          errors.add('$providerLabel ($model): $msg');
          // Invalid/unauthorized key on this provider won't succeed on its other models
          if (msg.contains('HTTP 401') || msg.contains('HTTP 403')) {
            break;
          }
        }
      }
    }
    return null;
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
      // Some reasoning / instruct models reject response_format=json_object
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
    final content = (choices.first as Map<String, dynamic>)['message']?['content']?.toString() ?? '';
    return parseInvoiceJson(content, '$providerLabel ($model)');
  }

  Future<ExtractedInvoiceData> _extractTextWithGemini(String apiKey, String ocrText, String model) async {
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
    return parseInvoiceJson(text, 'Gemini ($model)');
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

  /// Heuristic offline parser supporting row-aligned GST bills, commas in amounts,
  /// multiple trailing numeric columns (qty / rate / total), and two-line item blocks.
  @visibleForTesting
  ExtractedInvoiceData parseOcrTextOffline(String ocrText) {
    final lines = ocrText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    String dealer = '';
    String billNo = '';
    DateTime? date;
    final items = <ExtractedInvoiceItem>[];

    final skipDealerRx = RegExp(
      r'^(tax\s*invoice|invoice|bill\s*of\s*supply|cash\s*memo|receipt|original|duplicate|page\s*\d+|gstin|www\.|http)',
      caseSensitive: false,
    );
    final billRx = RegExp(
      r'\b(?:inv(?:oice)?|bill|receipt)\s*(?:(?:no|num|number)\.?\s*[:\s#\.\-]*|[:#])\s*([A-Z0-9][A-Z0-9/\-]{2,})',
      caseSensitive: false,
    );
    final dateRx = RegExp(
      r'(\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}|\d{4}[/\-]\d{1,2}[/\-]\d{1,2}|\d{1,2}[\s\-][A-Za-z]{3}[\s\-]\d{2,4})',
    );
    final ignoreRowRx = RegExp(
      r'(sub\s*total|grand\s*total|net\s*total|invoice\s*total|bill\s*total|round(?:ed)?\s*off|total\s*(?:qty|tax|amount|gst|rs)|cgst|sgst|igst|utgst|cess|vat\b|gst\b|discount|saving|balance|change\b|amount\s*paid|tender|card\s*payment|upi\s*ref|gstin|pan\s*no|phone|mobile|tel\s*:|fax|email|hsn\s*/?\s*sac|sr\.?\s*no|sl\.?\s*no|particulars|description)',
      caseSensitive: false,
    );
    final exprQtyPriceRx = RegExp(
      r'^(.{3,}?)\s+(\d+(?:\.\d+)?)\s*[x×*]\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)(?:\s*=?\s*(?:₹|rs\.?|inr)?\s*[\d,]+(?:\.\d{1,2})?)?$',
      caseSensitive: false,
    );
    final trailingNumberTokenRx = RegExp(
      r'^(?:₹|rs\.?|inr)?([\d,]+(?:\.\d{1,2})?)/?-?$',
      caseSensitive: false,
    );
    final unitWordRx = RegExp(r'^(nos?|pcs?|ea|each|qty|kgs?|g|gms?|l|ltr|ml|box|pkt|pack|set|pair|unit)s?$', caseSensitive: false);

    for (final line in lines) {
      if (dealer.isEmpty && !skipDealerRx.hasMatch(line) && RegExp(r'[A-Za-z]{3,}').hasMatch(line) && !dateRx.hasMatch(line)) {
        dealer = line.split(RegExp(r'\s{3,}')).first.trim();
      }
      if (billNo.isEmpty) {
        final bm = billRx.firstMatch(line);
        if (bm != null) billNo = bm.group(1) ?? '';
      }
      if (date == null) {
        final dm = dateRx.firstMatch(line);
        if (dm != null) date = _parseInvoiceDate(dm.group(1)!);
      }

      final lower = line.toLowerCase();
      if (ignoreRowRx.hasMatch(lower) || RegExp(r'\btotal\b').hasMatch(lower)) {
        continue;
      }

      // 1. Check explicit "Name   qty x rate [= total]" format
      final em = exprQtyPriceRx.firstMatch(line);
      if (em != null) {
        final name = _cleanItemName(em.group(1)!);
        final qty = double.tryParse(em.group(2) ?? '1') ?? 1.0;
        final price = _parseNumStr(em.group(3)) ?? 0.0;
        if (name.length >= 2 && price > 0) {
          items.add(ExtractedInvoiceItem(name: name, quantity: qty > 0 ? qty : 1.0, unitPrice: price));
          continue;
        }
      }

      // 2. Columnar row parsing from right to left (Rate/Total/Qty columns)
      final tokens = line.split(RegExp(r'\s+'));
      if (tokens.length < 2) continue;

      final trailingNums = <double>[];
      var splitIdx = tokens.length;
      for (int idx = tokens.length - 1; idx >= 1; idx--) {
        final tok = tokens[idx];
        if (unitWordRx.hasMatch(tok)) {
          splitIdx = idx;
          continue;
        }
        // Skip trailing percentage tokens like "18%" or "9.0%"
        if (RegExp(r'^\d+(?:\.\d+)?%$').hasMatch(tok)) {
          splitIdx = idx;
          continue;
        }
        final m = trailingNumberTokenRx.firstMatch(tok);
        if (m != null) {
          final parsed = _parseNumStr(m.group(1));
          if (parsed != null) {
            // Stop before leading/mid 6-8 digit HSN/SAC codes (no decimal and >= 100000) if we already have price
            if (trailingNums.isNotEmpty && !tok.contains('.') && parsed >= 100000) {
              break;
            }
            trailingNums.insert(0, parsed);
            splitIdx = idx;
            if (trailingNums.length >= 4) break;
            continue;
          }
        }
        break;
      }

      if (trailingNums.isEmpty) continue;
      final nameRaw = tokens.sublist(0, splitIdx).join(' ');
      final name = _cleanItemName(nameRaw);
      if (name.length < 3 || !RegExp(r'[A-Za-z]{2,}').hasMatch(name)) continue;

      // Determine qty & unitPrice from trailing numeric columns
      double qty = 1.0;
      double unitPrice = trailingNums.last;

      if (trailingNums.length >= 3) {
        // Common patterns: [qty, rate, total] or [rate, tax, total]
        final n0 = trailingNums[0];
        final n1 = trailingNums[1];
        final nLast = trailingNums.last;
        if (n0 > 0 && n0 <= 999 && (n0 * n1 - nLast).abs() <= math.max(1.0, nLast * 0.25)) {
          qty = n0;
          unitPrice = n1;
        } else {
          unitPrice = nLast;
        }
      } else if (trailingNums.length == 2) {
        final first = trailingNums[0];
        final second = trailingNums[1];
        if (first > 0 && first <= 100 && first == first.roundToDouble() && second >= first) {
          qty = first;
          // If second looks like rate vs line total, prefer dividing only if second != first*rate?
          // Wait: `[Name] [Qty] [Rate]` vs `[Name] [Qty] [Total]` -> when 2 numbers remain on invoices without Rate column, second is usually line total unless qty==1.
          unitPrice = qty > 1 ? (second / qty) : second;
        } else if ((first - second).abs() < 0.02) {
          unitPrice = first;
        } else {
          unitPrice = second > 0 ? second : first;
        }
      }

      if (unitPrice > 0) {
        items.add(ExtractedInvoiceItem(name: name, quantity: qty, unitPrice: unitPrice));
      }
    }

    return ExtractedInvoiceData(
      dealerName: dealer,
      billNumber: billNo,
      invoiceDate: date,
      currency: '₹',
      items: items,
      usedProvider: 'Offline OCR Parser',
    );
  }

  String _cleanItemName(String raw) {
    var s = raw.trim();
    // Strip leading serial number like "1 ", "01.", "1)"
    s = s.replaceFirst(RegExp(r'^\d{1,3}[\.\)\-\s]+\s*'), '');
    // Strip trailing 6-8 digit HSN/SAC code left over
    s = s.replaceFirst(RegExp(r'\s+\d{6,8}$'), '');
    return s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  double? _parseNumStr(String? s) {
    if (s == null) return null;
    final clean = s.replaceAll(',', '').trim();
    return double.tryParse(clean);
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
    final mTxt = RegExp(r'^(\d{1,2})[\s\-]([A-Za-z]{3})[\s\-](\d{2,4})$').firstMatch(s);
    if (mTxt != null) {
      final d = int.parse(mTxt.group(1)!);
      final mo = months[mTxt.group(2)!.toLowerCase()];
      var y = int.parse(mTxt.group(3)!);
      if (y < 100) y += 2000;
      if (mo != null && d >= 1 && d <= 31) {
        return DateTime(y, mo, d);
      }
    }
    return null;
  }

  @visibleForTesting
  ExtractedInvoiceData parseInvoiceJson(String raw, String provider) {
    // Remove Qwen/reasoning <think>...</think> blocks before locating JSON braces
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
