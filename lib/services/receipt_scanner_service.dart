import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/invoice_model.dart';
import 'storage_service.dart';

class ScannedReceiptResult {
  final bool isSuccess;
  final String shopName;
  final String billNo;
  final DateTime billDate;
  final List<InvoiceItemRecord> items;
  final double totalAmount;
  final String? errorMessage;
  final String rawResponse;

  ScannedReceiptResult({
    required this.isSuccess,
    this.shopName = '',
    this.billNo = '',
    DateTime? billDate,
    this.items = const [],
    this.totalAmount = 0.0,
    this.errorMessage,
    this.rawResponse = '',
  }) : billDate = billDate ?? DateTime.now();

  factory ScannedReceiptResult.error(String msg) {
    return ScannedReceiptResult(
      isSuccess: false,
      errorMessage: msg,
    );
  }
}

class ReceiptScannerService {
  static final ReceiptScannerService instance = ReceiptScannerService._internal();
  ReceiptScannerService._internal();

  static const String geminiModel = 'gemini-2.5-flash';

  /// Scans receipt image bytes using Gemini Vision and extracts structured invoice data.
  Future<ScannedReceiptResult> scanReceipt({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
    List<String> knownDealers = const [],
    List<String> knownRecipients = const [],
  }) async {
    final apiKey = await StorageService.instance.getGeminiApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      return ScannedReceiptResult.error(
        'Gemini API Key is not configured. Please add your key in Settings or AI config to enable receipt scanning.',
      );
    }

    try {
      final base64Image = base64Encode(imageBytes);

      final prompt = '''
You are an expert OCR receipt and supermarket bill parser for a personal finance system.
Extract all details accurately from this bill/receipt image.

Respond ONLY with pure, valid JSON (no markdown formatting, no backticks, no code fence).
The JSON must follow this exact schema:
{
  "shopName": "Store or Dealer name (e.g. Babu oil mill, D-Mart, Prabhakar Traders)",
  "billNo": "Invoice or Bill number if visible, otherwise create one like INV-YYYYMMDD-XXX",
  "billDate": "YYYY-MM-DD or DD/MMM/YYYY",
  "items": [
    {
      "itemName": "Exact item or product name",
      "quantity": 1.0,
      "price": 100.0,
      "total": 100.0,
      "recipient": "Self"
    }
  ]
}

Guidelines:
1. Ensure quantity is numeric (e.g. 0.5, 1, 2.5).
2. Ensure price is the unit price, and total is quantity * price.
3. If the shop matches any known dealer, normalize it: ${knownDealers.join(", ")}.
4. Default recipient to "Self". If an item name mentions a person or borrower (${knownRecipients.join(", ")}), set recipient accordingly.
5. Extract EVERY visible item on the bill.
''';

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent?key=${apiKey.trim()}',
      );

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {
                'inlineData': {
                  'mimeType': mimeType,
                  'data': base64Image,
                }
              },
              {
                'text': prompt,
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.1,
          'responseMimeType': 'application/json',
        }
      });

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        debugPrint('Gemini OCR returned error ${response.statusCode}: ${response.body}');
        return ScannedReceiptResult.error(
          'Receipt scan failed (HTTP ${response.statusCode}). Please check your connection or API key.',
        );
      }

      final resData = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = resData['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        return ScannedReceiptResult.error('No receipt details recognized from the image.');
      }

      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) {
        return ScannedReceiptResult.error('Empty response from AI receipt scanner.');
      }

      var rawJson = parts.first['text'] as String? ?? '';
      rawJson = rawJson.trim();
      if (rawJson.startsWith('```json')) {
        rawJson = rawJson.substring(7);
      }
      if (rawJson.startsWith('```')) {
        rawJson = rawJson.substring(3);
      }
      if (rawJson.endsWith('```')) {
        rawJson = rawJson.substring(0, rawJson.length - 3);
      }
      rawJson = rawJson.trim();

      final parsed = jsonDecode(rawJson) as Map<String, dynamic>;

      final shopName = (parsed['shopName'] as String? ?? '').trim();
      final billNo = (parsed['billNo'] as String? ?? 'INV-${DateFormat("yyyyMMdd-HHmm").format(DateTime.now())}').trim();
      final rawDate = parsed['billDate'] as String?;
      final billDate = InvoiceItemRecord.parseDateSafe(rawDate);

      final rawItems = parsed['items'] as List<dynamic>? ?? [];
      final items = <InvoiceItemRecord>[];

      for (int i = 0; i < rawItems.length; i++) {
        final itemMap = rawItems[i] as Map<String, dynamic>;
        final itemName = (itemMap['itemName'] as String? ?? '').trim();
        if (itemName.isEmpty) continue;

        final qty = (itemMap['quantity'] as num?)?.toDouble() ?? 1.0;
        final price = (itemMap['price'] as num?)?.toDouble() ?? 0.0;
        final total = (itemMap['total'] as num?)?.toDouble() ?? (qty * price);
        final recip = (itemMap['recipient'] as String? ?? 'Self').trim();

        items.add(InvoiceItemRecord(
          id: '${billNo}_${i}_${itemName.hashCode}',
          billDate: billDate,
          shopName: shopName,
          billNo: billNo,
          itemName: itemName,
          quantity: qty,
          price: price,
          total: total,
          recipient: recip.isEmpty ? 'Self' : recip,
        ));
      }

      final calcTotal = items.fold(0.0, (sum, it) => sum + it.total);

      return ScannedReceiptResult(
        isSuccess: true,
        shopName: shopName,
        billNo: billNo,
        billDate: billDate,
        items: items,
        totalAmount: calcTotal,
        rawResponse: rawJson,
      );
    } catch (e) {
      debugPrint('ReceiptScannerService error: $e');
      return ScannedReceiptResult.error('Scan error: $e');
    }
  }
}
