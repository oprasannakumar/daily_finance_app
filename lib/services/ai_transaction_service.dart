import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class AiParsedTransaction {
  final String action; // 'reset_form', 'load_template', 'set_mode', 'self_transfer', 'log_transaction'
  final String? templateName;
  final String? modeTarget; // 'biketaxi', 'batch', 'recurring', 'split', 'selfTransfer'
  final bool isSelfTransfer;
  final String flow; // 'Withdraw', 'Deposit', 'Transfer'
  final double amount;
  final String narration;
  final String? purpose;
  final String? spentFor; // Nullable (Blank)
  final String? account;
  final String? paymentType;
  final DateTime? date;

  // Self Transfer specific fields
  final String? fromPaymentType;
  final String? fromAccount;
  final double? fromAmount;
  final String? toPaymentType;
  final String? toAccount;
  final double? toAmount;
  final Map<int, int>? denominations; // For Cash

  // Split specific fields
  final List<String> splitRecipientNames;
  final bool isSplitEqually;
  final bool includesSelfInSplit;
  final bool isLoanOrSplit;

  final String source; // 'grok', 'gemini', 'local_rules'

  AiParsedTransaction({
    this.action = 'log_transaction',
    this.templateName,
    this.modeTarget,
    this.isSelfTransfer = false,
    required this.flow,
    required this.amount,
    required this.narration,
    this.purpose,
    this.spentFor,
    this.account,
    this.paymentType,
    this.date,
    this.fromPaymentType,
    this.fromAccount,
    this.fromAmount,
    this.toPaymentType,
    this.toAccount,
    this.toAmount,
    this.denominations,
    this.splitRecipientNames = const [],
    this.isSplitEqually = false,
    this.includesSelfInSplit = false,
    this.isLoanOrSplit = false,
    this.source = 'local_rules',
  });

  @override
  String toString() {
    return 'AiParsedTransaction(action: $action, isSelfTransfer: $isSelfTransfer, flow: $flow, amount: $amount, narration: $narration, purpose: $purpose, spentFor: $spentFor, account: $account, source: $source)';
  }
}

class AiTransactionService {
  static final AiTransactionService instance = AiTransactionService._internal();
  AiTransactionService._internal();

  /// Synchronous local rule parsing for instant (0ms) UI updates while typing or speaking.
  AiParsedTransaction parseLocalRulesOnly({
    required String userInput,
    required List<String> purposes,
    required List<String> spentFors,
    required Map<String, List<String>> categoryAccounts,
  }) {
    return _parseWithLocalRules(
      userInput: userInput,
      purposes: purposes,
      spentFors: spentFors,
      categoryAccounts: categoryAccounts,
    );
  }

  /// Parse natural language into structured finance fields.
  /// When API keys are configured, Cloud AI runs FIRST (Grok -> Gemini fallback).
  /// Falls back to Local Rule Engine when keys are missing or network/API fails.
  Future<AiParsedTransaction> parse({
    required String text,
    required List<String> availablePurposes,
    required List<String> availableSpentFors,
    required Map<String, List<String>> categoryAccounts,
    bool forceAi = false,
  }) async {
    final cleanInput = text.trim();
    if (cleanInput.isEmpty) {
      return AiParsedTransaction(
        flow: 'Withdraw',
        amount: 0.0,
        narration: '',
        source: 'local_rules',
      );
    }

    final grokKey = await StorageService.instance.getGrokApiKey();
    final geminiKey = await StorageService.instance.getGeminiApiKey();

    final hasGrok = grokKey != null && grokKey.trim().isNotEmpty;
    final hasGemini = geminiKey != null && geminiKey.trim().isNotEmpty;

    // 1. Try Grok FIRST (qwen/qwen3.8-27b) if key provided
    if (hasGrok) {
      try {
        final result = await _callGrok(
          apiKey: grokKey.trim(),
          userInput: cleanInput,
          purposes: availablePurposes,
          spentFors: availableSpentFors,
          categoryAccounts: categoryAccounts,
        );
        if (result != null) return result;
      } catch (e) {
        debugPrint('Grok error: $e');
      }
    }

    // 2. Try Gemini FALLBACK (gemini-2.0-flash / gemini-1.5-flash) if key provided
    if (hasGemini) {
      try {
        final result = await _callGemini(
          apiKey: geminiKey.trim(),
          userInput: cleanInput,
          purposes: availablePurposes,
          spentFors: availableSpentFors,
          categoryAccounts: categoryAccounts,
        );
        if (result != null) return result;
      } catch (e) {
        debugPrint('Gemini error: $e');
      }
    }

    // 3. Fallback to Local Deterministic Rule Engine
    return _parseWithLocalRules(
      userInput: cleanInput,
      purposes: availablePurposes,
      spentFors: availableSpentFors,
      categoryAccounts: categoryAccounts,
    );
  }

  String _buildSystemPrompt({
    required String userInput,
    required List<String> purposes,
    required List<String> spentFors,
    required Map<String, List<String>> categoryAccounts,
  }) {
    final allKnownAccounts = <String>[];
    categoryAccounts.forEach((cat, list) {
      allKnownAccounts.addAll(list);
    });

    return '''
You are the brain of a voice-controlled financial app. Parse this command: "$userInput"

Determine the user's INTENT and return EXACTLY this JSON structure. Do NOT wrap it in markdown.
{
  "action": "reset_form" | "load_template" | "set_mode" | "self_transfer" | "log_transaction",
    * "reset_form": ONLY to clear the whole form.
    * "self_transfer": Moving money between own accounts, cash deposited/withdrawn, OR paying/clearing a credit card bill.
    * "log_transaction": Standard expenses, incomes, split bills, and ALL bank/card/UPI purchase or credit SMS alerts (e.g. "Spent Rs.324 On HDFC Bank Card 4179 At AVENUE SUPERMARTS..."). IMPORTANT: A card purchase SMS is ALWAYS "log_transaction" (flow "withdraw"), NEVER "self_transfer"! Ignore SMS fraud/block disclaimers like "Not You? To Block+Reissue Call .../SMS BLOCK CC 4179 to ...".
  "template_name": "name of template if loading, else empty",
  "mode_target": "biketaxi|batch|recurring|split|selfTransfer if setting mode, else empty",
  "source_account": "ONLY if action is 'self_transfer': account money is leaving from. Otherwise leave EMPTY ''.",
  "destination_account": "ONLY if action is 'self_transfer': account receiving money. Otherwise leave EMPTY ''.",
  "narration": "Short clean description of the transaction (e.g. 'Spent at AVENUE SUPERMARTS LIMI'). Never include card block instructions or phone numbers. If paying a credit card bill, strictly use 'Cleared card bill'.",
  "date": "YYYY-MM-DD if an explicit date is in the text/SMS, else empty ''",
  "flow": "withdraw" or "deposit",
  "account": "Best match from lists: [${allKnownAccounts.join(', ')}] or 'Cash' (match bank/card name or last-4 digits like 4179 if present)",
  "payment_type": "STRICT RULE: If the account is a digital wallet (like Paytm, PhonePe Wallet, Amazon Pay, Mobikwik, Freecharge) OR if the word 'wallet' is used, payment_type MUST BE 'WALLET'. If 'Card', 'Credit Card', or 'CC' is used (without 'Debit'), payment_type MUST BE 'CREDIT'. Otherwise use 'DEBIT', 'UPI', 'CASH', or 'NET'.",
  "denominations": {"500": 2, "100": 1} (Extract count of notes if mentioned, e.g., '2 notes of 500', '500x2', '500*2'. Keys MUST be valid INR note values: 500, 200, 100, 50, 20, 10. Omit if no notes mentioned.),
  "amount": 0.00, (Must be a number, NOT card digits or helpline numbers. If denominations are provided but no total is mentioned, mathematically calculate it: 500*2 + 100*1 = 1100),
  "purpose": "Best match from: [${purposes.join(', ')}] (e.g. 'AVENUE SUPERMARTS' / 'DMART' -> Groceries)",
  "spent_for": "If multiple people are involved or it's a split equally, output 'Split'. If just one specific person for a loan/split, output their name. Otherwise best match from [${spentFors.join(', ')}].",
  "split_recipient_names": ["Name 1", "Name 2"] (Array of strings. Extract ALL other people involved. Do NOT include the user ('Self'). If none, empty array []),
  "is_split_equally": boolean (true if text contains 'split equally', 'divided equally', or implies dividing the total evenly),
  "includes_self_in_split": boolean (true if the user is ALSO paying a share, e.g., "Lunch split with John". false if the user is paying ENTIRELY for others, e.g., "Paid for Chinnama and Grandfather split equally"),
  "is_loan_or_split": boolean (true if text contains 'split', 'loan', 'due', 'given to [Name]', etc.)
}''';
  }

  static const String grokModelName = 'qwen/qwen3.8-27b';
  static const String geminiModelName = 'gemini-3.6-flash';

  List<String> _grokEndpointsForKey(String key) {
    final trimmed = key.trim();
    if (trimmed.startsWith('gsk_')) {
      return const ['https://api.groq.com/openai/v1/chat/completions'];
    }
    if (trimmed.startsWith('sk-or-')) {
      return const ['https://openrouter.ai/api/v1/chat/completions'];
    }
    if (trimmed.startsWith('xai-')) {
      return const ['https://api.x.ai/v1/chat/completions'];
    }
    return const [
      'https://api.groq.com/openai/v1/chat/completions',
      'https://openrouter.ai/api/v1/chat/completions',
      'https://api.x.ai/v1/chat/completions',
    ];
  }

  // --- 1. Grok API Caller ---
  Future<AiParsedTransaction?> _callGrok({
    required String apiKey,
    required String userInput,
    required List<String> purposes,
    required List<String> spentFors,
    required Map<String, List<String>> categoryAccounts,
  }) async {
    final model = (await StorageService.instance.getSelectedGrokModel()) ?? grokModelName;
    final promptText = _buildSystemPrompt(
      userInput: userInput,
      purposes: purposes,
      spentFors: spentFors,
      categoryAccounts: categoryAccounts,
    );

    final endpoints = _grokEndpointsForKey(apiKey);

    for (final endpoint in endpoints) {
      try {
        final res = await http.post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {
                'role': 'system',
                'content': 'You are a JSON parser. You must return pure JSON following the exact structure requested, with no markdown formatting.'
              },
              {'role': 'user', 'content': promptText}
            ],
            'response_format': {'type': 'json_object'},
            'temperature': 0.1,
          }),
        ).timeout(const Duration(seconds: 15));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final content = data['choices']?[0]?['message']?['content']?.toString() ?? '';
          final parsed = _extractJsonAndMap(content, 'grok ($model)');
          if (parsed != null) return parsed;
        } else {
          debugPrint('Grok $endpoint with $model returned ${res.statusCode}: ${res.body}');
        }
      } catch (e) {
        debugPrint('Grok $endpoint with $model failed: $e');
      }
    }
    return null;
  }

  // --- 2. Gemini API Caller ---
  Future<AiParsedTransaction?> _callGemini({
    required String apiKey,
    required String userInput,
    required List<String> purposes,
    required List<String> spentFors,
    required Map<String, List<String>> categoryAccounts,
  }) async {
    final model = (await StorageService.instance.getSelectedGeminiModel()) ?? geminiModelName;
    final promptText = _buildSystemPrompt(
      userInput: userInput,
      purposes: purposes,
      spentFors: spentFors,
      categoryAccounts: categoryAccounts,
    );

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );

    final payload = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': promptText}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'response_mime_type': 'application/json',
      }
    });

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: payload,
        ).timeout(const Duration(seconds: 20));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final text = candidates[0]?['content']?['parts']?[0]?['text']?.toString() ?? '';
            final parsed = _extractJsonAndMap(text, 'gemini ($model)');
            if (parsed != null) return parsed;
          }
        } else if (res.statusCode == 503) {
          debugPrint('Gemini 503 temporary high demand. Retrying in 1s...');
          await Future.delayed(const Duration(seconds: 1));
          continue;
        } else {
          debugPrint('Gemini returned ${res.statusCode}: ${res.body}');
        }
      } catch (e) {
        debugPrint('Gemini exception: $e');
      }
    }
    return null;
  }

  Future<Map<String, String>> testConnection({
    String? grokKey,
    String? geminiKey,
    String? grokModel,
    String? geminiModel,
  }) async {
    final results = <String, String>{};
    final chosenGrokModel = (grokModel != null && grokModel.trim().isNotEmpty)
        ? grokModel.trim()
        : ((await StorageService.instance.getSelectedGrokModel()) ?? grokModelName);
    final chosenGeminiModel = (geminiModel != null && geminiModel.trim().isNotEmpty)
        ? geminiModel.trim()
        : ((await StorageService.instance.getSelectedGeminiModel()) ?? geminiModelName);

    if (grokKey != null && grokKey.trim().isNotEmpty) {
      final key = grokKey.trim();
      final endpoints = _grokEndpointsForKey(key);

      String? lastError;
      bool succeeded = false;

      for (final endpoint in endpoints) {
        try {
          final res = await http.post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $key',
            },
            body: jsonEncode({
              'model': chosenGrokModel,
              'messages': [
                {'role': 'user', 'content': 'hi'}
              ],
              'max_tokens': 5,
            }),
          ).timeout(const Duration(seconds: 15));

          if (res.statusCode == 200) {
            results['grok'] = 'Connected successfully ($chosenGrokModel)';
            succeeded = true;
            break;
          } else {
            lastError = 'Error ${res.statusCode}: ${res.body.length > 80 ? res.body.substring(0, 80) : res.body}';
          }
        } catch (e) {
          lastError = 'Connection failed: $e';
        }
      }

      if (!succeeded && lastError != null) {
        results['grok'] = lastError;
      }
    }

    if (geminiKey != null && geminiKey.trim().isNotEmpty) {
      final key = geminiKey.trim();
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$chosenGeminiModel:generateContent?key=$key',
      );

      final payload = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': 'Respond with pure JSON: {"status": "ok"}'}
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.1,
          'response_mime_type': 'application/json',
        }
      });

      try {
        final res = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': key,
          },
          body: payload,
        ).timeout(const Duration(seconds: 20));

        if (res.statusCode == 200) {
          results['gemini'] = 'Connected successfully ($chosenGeminiModel)';
        } else if (res.statusCode == 503) {
          results['gemini'] = 'Temporary high demand on Google servers (503). Retries automatically during usage.';
        } else {
          results['gemini'] = 'Error ${res.statusCode}: ${res.body.length > 80 ? res.body.substring(0, 80) : res.body}';
        }
      } catch (e) {
        results['gemini'] = 'Connection failed: $e';
      }
    }

    return results;
  }

  // --- JSON Extractor Helper ---
  AiParsedTransaction? _extractJsonAndMap(String rawText, String source) {
    try {
      var text = rawText.trim();
      if (text.startsWith('```json')) {
        text = text.substring(7);
      } else if (text.startsWith('```')) {
        text = text.substring(3);
      }
      if (text.endsWith('```')) {
        text = text.substring(0, text.length - 3);
      }
      text = text.trim();

      final firstBrace = text.indexOf('{');
      final lastBrace = text.lastIndexOf('}');
      if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
        text = text.substring(firstBrace, lastBrace + 1);
      }

      final json = jsonDecode(text) as Map<String, dynamic>;

      final action = (json['action']?.toString() ?? 'log_transaction').toLowerCase();
      final templateName = json['template_name']?.toString().trim();
      final modeTarget = json['mode_target']?.toString().trim();

      final hasNonEmptyTransferAccounts =
          (json['source_account']?.toString().trim().isNotEmpty ?? false) &&
          (json['destination_account']?.toString().trim().isNotEmpty ?? false);
      final hasNonEmptyTransferTypes =
          (json['fromPaymentType']?.toString().trim().isNotEmpty ?? false) &&
          (json['toPaymentType']?.toString().trim().isNotEmpty ?? false);

      bool isSelfTransfer = action == 'self_transfer' ||
          json['isSelfTransfer'] == true ||
          json['isSelfTransfer']?.toString().toLowerCase() == 'true' ||
          json['is_self_transfer'] == true ||
          json['is_self_transfer']?.toString().toLowerCase() == 'true' ||
          json['selfTransfer'] == true ||
          json['self_transfer'] == true ||
          (action != 'log_transaction' &&
              (hasNonEmptyTransferAccounts || hasNonEmptyTransferTypes)) ||
          (json['flow']?.toString().toLowerCase() == 'transfer');

      final lowerRaw = '$rawText ${json['narration']?.toString() ?? ''}'.toLowerCase();
      if (!isSelfTransfer && action != 'log_transaction') {
        if (lowerRaw.contains('credit card bill') ||
            lowerRaw.contains('card bill') ||
            lowerRaw.contains('cash withdrawn') ||
            lowerRaw.contains('cash withdrawal') ||
            lowerRaw.contains('cash deposited') ||
            lowerRaw.contains('cash deposit') ||
            (lowerRaw.contains('cash') && (lowerRaw.contains('withdraw') || lowerRaw.contains('withdrawn') || lowerRaw.contains('deposit') || lowerRaw.contains('deposited')))) {
          isSelfTransfer = true;
        }
      }

      final flowRaw = json['flow']?.toString().toLowerCase() ?? 'withdraw';
      final flow = isSelfTransfer
          ? 'Transfer'
          : flowRaw.contains('deposit')
              ? 'Deposit'
              : flowRaw.contains('transfer')
                  ? 'Transfer'
                  : 'Withdraw';

      final amountNum = json['amount'];
      double amount = (amountNum is num)
          ? amountNum.toDouble()
          : double.tryParse(amountNum?.toString() ?? '') ?? 0.0;

      final narration = json['narration']?.toString().trim() ?? '';
      final purpose = json['purpose']?.toString().trim();
      final spentFor = (json['spent_for'] ?? json['spentFor']) != null &&
              (json['spent_for'] ?? json['spentFor']).toString().trim().isNotEmpty
          ? (json['spent_for'] ?? json['spentFor']).toString().trim()
          : null;
      final account = json['account']?.toString().trim();
      final paymentTypeRaw = (json['payment_type'] ?? json['paymentType'])?.toString().trim();
      String? paymentType;
      if (paymentTypeRaw != null && paymentTypeRaw.isNotEmpty) {
        final up = paymentTypeRaw.toUpperCase();
        if (up == 'WALLET' || up == 'WALLETS') {
          paymentType = 'Wallets';
        } else if (up == 'CREDIT') {
          paymentType = 'Credit';
        } else if (up == 'DEBIT') {
          paymentType = 'Debit';
        } else if (up == 'UPI') {
          paymentType = 'UPI';
        } else if (up == 'NET') {
          paymentType = 'Net';
        } else if (up == 'CASH') {
          paymentType = 'Cash';
        } else {
          paymentType = paymentTypeRaw;
        }
      }

      // Self transfer fields
      final fromPaymentType = json['fromPaymentType']?.toString().trim() ?? 'UPI';
      final fromAccount = json['source_account']?.toString().trim() ?? json['fromAccount']?.toString().trim();
      final fromAmount = (json['fromAmount'] is num) ? (json['fromAmount'] as num).toDouble() : amount;
      final toPaymentType = json['toPaymentType']?.toString().trim() ?? 'Credit';
      final toAccount = json['destination_account']?.toString().trim() ?? json['toAccount']?.toString().trim();
      final toAmount = (json['toAmount'] is num) ? (json['toAmount'] as num).toDouble() : amount;

      Map<int, int>? denominations;
      if (json['denominations'] is Map) {
        denominations = {};
        (json['denominations'] as Map).forEach((k, v) {
          final intKey = int.tryParse(k.toString());
          final intVal = int.tryParse(v.toString());
          if (intKey != null && intVal != null) {
            denominations![intKey] = intVal;
          }
        });
      }

      // If denominations provided but amount == 0, calculate total from denominations
      if (amount == 0.0 && denominations != null && denominations.isNotEmpty) {
        int denomTotal = 0;
        denominations.forEach((val, count) => denomTotal += (val * count));
        if (denomTotal > 0) amount = denomTotal.toDouble();
      }

      // Split recipients
      List<String> splitRecipientNames = [];
      if (json['split_recipient_names'] is List) {
        splitRecipientNames = (json['split_recipient_names'] as List)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty && e.toLowerCase() != 'self')
            .toList();
      }

      final isSplitEqually = json['is_split_equally'] == true ||
          json['is_split_equally']?.toString().toLowerCase() == 'true';
      final includesSelfInSplit = json['includes_self_in_split'] == true ||
          json['includes_self_in_split']?.toString().toLowerCase() == 'true';
      final isLoanOrSplit = json['is_loan_or_split'] == true ||
          json['is_loan_or_split']?.toString().toLowerCase() == 'true';

      DateTime? parsedDate;
      final dateRaw = json['date']?.toString().trim();
      if (dateRaw != null && dateRaw.isNotEmpty) {
        parsedDate = DateTime.tryParse(dateRaw);
      }

      return AiParsedTransaction(
        action: action,
        templateName: templateName,
        modeTarget: modeTarget,
        isSelfTransfer: isSelfTransfer,
        flow: flow,
        amount: amount,
        narration: narration,
        purpose: purpose,
        spentFor: spentFor,
        account: account,
        paymentType: paymentType,
        date: parsedDate,
        fromPaymentType: fromPaymentType,
        fromAccount: fromAccount,
        fromAmount: fromAmount,
        toPaymentType: toPaymentType,
        toAccount: toAccount,
        toAmount: toAmount,
        denominations: denominations,
        splitRecipientNames: splitRecipientNames,
        isSplitEqually: isSplitEqually,
        includesSelfInSplit: includesSelfInSplit,
        isLoanOrSplit: isLoanOrSplit,
        source: source,
      );
    } catch (e) {
      debugPrint('JSON parse error: $e for text: $rawText');
      return null;
    }
  }

  // --- 3. Deterministic Local Rule Parser ---
  AiParsedTransaction _parseWithLocalRules({
    required String userInput,
    required List<String> purposes,
    required List<String> spentFors,
    required Map<String, List<String>> categoryAccounts,
  }) {
    final lower = userInput.toLowerCase();

    // 1. Amount detection
    double amount = 0.0;
    final amountRegex = RegExp(
      r'(?:rs\.?|inr|rupees|₹)?\s*([0-9]+(?:\.[0-9]{1,2})?)\s*(?:rs\.?|inr|rupees|₹|bucks)?',
      caseSensitive: false,
    );
    final amountMatches = amountRegex.allMatches(userInput);
    for (final match in amountMatches) {
      final valStr = match.group(1);
      if (valStr != null) {
        final parsed = double.tryParse(valStr);
        if (parsed != null && parsed > 0) {
          amount = parsed;
          break;
        }
      }
    }

    // 2. Denomination parser (e.g. 500*20 or 500x20 or default 500 notes)
    final denominations = <int, int>{};
    final denomRegex = RegExp(r'([0-9]+)\s*[*xX]\s*([0-9]+)');
    final denomMatches = denomRegex.allMatches(userInput);
    for (final m in denomMatches) {
      final d = int.tryParse(m.group(1) ?? '');
      final c = int.tryParse(m.group(2) ?? '');
      if (d != null && c != null) {
        denominations[d] = c;
      }
    }
    if (denominations.isEmpty && amount > 0) {
      // Default denomination: 500 rupee notes
      final count500 = amount ~/ 500;
      final rem = (amount % 500).toInt();
      if (count500 > 0) {
        denominations[500] = count500;
      }
      if (rem > 0) {
        denominations[100] = rem ~/ 100;
      }
    }

    // ==========================================
    // CASE A: Credit Card Bill Payment (Self Transfer)
    // e.g. "paid 5660 HDFC PhonePe credit card bill using SBI account"
    // ==========================================
    // Credit card bill payment MUST contain "bill" or "due" (e.g. "credit card bill", "card bill", "cc bill")
    // Note: Do NOT match "using credit card" or "via credit card" without "bill", as those are regular purchases!
    final hasCardBill = lower.contains('credit card bill') ||
        lower.contains('card bill') ||
        lower.contains('cc bill') ||
        (lower.contains('credit card') && (lower.contains('bill') || lower.contains('due'))) ||
        (lower.contains('bill') && (lower.contains('credit card') || lower.contains('card')));

    if (hasCardBill) {
      // Extract from account: words following "using" or "from"
      String fromAccount = 'SBI';
      final fromMatch = RegExp(
        r'(?:using|from|via)\s+([a-zA-Z0-9\s]+?)(?:\s+(?:bank|account|a/c|acc)|(?:\s*[.,])|$)',
        caseSensitive: false,
      ).firstMatch(userInput);
      if (fromMatch != null) {
        fromAccount = _cleanAccountName(fromMatch.group(1) ?? 'SBI');
      }

      // Extract to credit card: words before "credit card bill" or between amount and "credit card"
      String toAccount = 'HDFC PhonePe';
      final toMatch = RegExp(
        r'(?:paid\s+)?[0-9.]*\s*([a-zA-Z0-9\s]+?)(?:\s+credit\s+card\s+bill|\s+card\s+bill)',
        caseSensitive: false,
      ).firstMatch(userInput);
      if (toMatch != null) {
        toAccount = _cleanAccountName(toMatch.group(1) ?? 'HDFC PhonePe');
      }

      final narration = 'Paid ${_cleanAccountName(toAccount)} credit card bill';

      return AiParsedTransaction(
        isSelfTransfer: true,
        flow: 'Transfer',
        amount: amount,
        narration: narration,
        purpose: 'Rent & Utilities',
        spentFor: null,
        fromPaymentType: 'UPI',
        fromAccount: fromAccount,
        fromAmount: amount,
        toPaymentType: 'Credit',
        toAccount: toAccount,
        toAmount: amount,
        source: 'local_rules',
      );
    }

    // ==========================================
    // CASE B: Cash Withdrawal (Self Transfer)
    // e.g. "10000 cash withdrawn from kotak" or "withdrew 10000 cash from kotak"
    // ==========================================
    if (lower.contains('cash withdrawn') ||
        lower.contains('cash withdrawal') ||
        lower.contains('cash withdraw') ||
        lower.contains('withdrew cash') ||
        lower.contains('atm withdraw') ||
        lower.contains('atm cash') ||
        (lower.contains('cash') && (lower.contains('withdraw') || lower.contains('withdrawn') || lower.contains('withdrew'))) ||
        ((lower.contains('withdrawn') || lower.contains('withdraw') || lower.contains('withdrew')) && (lower.contains('atm') || lower.contains('bank') || lower.contains('kotak') || lower.contains('sbi') || lower.contains('hdfc')))) {
      String fromAccount = 'Kotak';
      final bankMatch = RegExp(
        r'(?:from|in|at)\s+([a-zA-Z0-9\s]+?)(?:\s+(?:bank|account|a/c|acc|\d+\s*[*xX])|(?:\s*[.,])|$)',
        caseSensitive: false,
      ).firstMatch(userInput);
      if (bankMatch != null) {
        fromAccount = _cleanAccountName(bankMatch.group(1) ?? 'Kotak');
      } else {
        fromAccount = _findMentionedBank(userInput) ?? 'Kotak';
      }

      final narration = 'Cash withdrawn from ${_cleanAccountName(fromAccount)}';

      return AiParsedTransaction(
        isSelfTransfer: true,
        flow: 'Transfer',
        amount: amount,
        narration: narration,
        purpose: 'Others',
        spentFor: null,
        fromPaymentType: 'Debit',
        fromAccount: fromAccount,
        fromAmount: amount,
        toPaymentType: 'Cash',
        toAccount: null,
        toAmount: amount,
        denominations: denominations,
        source: 'local_rules',
      );
    }

    // ==========================================
    // CASE C: Cash Deposit (Self Transfer)
    // e.g. "10000 cash deposited into kotak" or "deposit 5000 cash in sbi"
    // ==========================================
    if (lower.contains('cash deposited') ||
        lower.contains('cash deposit') ||
        (lower.contains('cash') && (lower.contains('deposit') || lower.contains('deposited'))) ||
        ((lower.contains('deposit') || lower.contains('deposited')) && (lower.contains('into') || lower.contains('in ') || lower.contains('to ')) && (lower.contains('kotak') || lower.contains('sbi') || lower.contains('hdfc') || lower.contains('bank') || lower.contains('account')))) {
      String toAccount = 'Kotak';
      final bankMatch = RegExp(
        r'(?:into|to|in|at)\s+([a-zA-Z0-9\s]+?)(?:\s+(?:bank|account|a/c|acc|\d+\s*[*xX])|(?:\s*[.,])|$)',
        caseSensitive: false,
      ).firstMatch(userInput);
      if (bankMatch != null) {
        toAccount = _cleanAccountName(bankMatch.group(1) ?? 'Kotak');
      } else {
        toAccount = _findMentionedBank(userInput) ?? 'Kotak';
      }

      final narration = 'Cash deposited into ${_cleanAccountName(toAccount)}';

      return AiParsedTransaction(
        isSelfTransfer: true,
        flow: 'Transfer',
        amount: amount,
        narration: narration,
        purpose: 'Others',
        spentFor: null,
        fromPaymentType: 'Cash',
        fromAccount: null,
        fromAmount: amount,
        toPaymentType: 'Debit',
        toAccount: toAccount,
        toAmount: amount,
        denominations: denominations,
        source: 'local_rules',
      );
    }

    // ==========================================
    // CASE D: General Transfer Between Accounts
    // e.g. "transfer 5000 from sbi to hdfc"
    // ==========================================
    if (((lower.contains('transfer') || lower.contains('transferred') || lower.contains('send') || lower.contains('sent')) && lower.contains('to ') && lower.contains('from ')) ||
        lower.contains('self transfer')) {
      final fromMatch = RegExp(r'from\s+([a-zA-Z0-9\s]+?)(?:\s+to|\s+$)', caseSensitive: false).firstMatch(userInput);
      final toMatch = RegExp(r'to\s+([a-zA-Z0-9\s]+?)(?:\s+from|\s+$)', caseSensitive: false).firstMatch(userInput);

      final fromAccount = _cleanAccountName(fromMatch?.group(1) ?? 'SBI');
      final toAccount = _cleanAccountName(toMatch?.group(1) ?? 'HDFC');

      return AiParsedTransaction(
        isSelfTransfer: true,
        flow: 'Transfer',
        amount: amount,
        narration: 'Transfer to $toAccount',
        purpose: 'Self Transfer',
        spentFor: null,
        fromPaymentType: 'UPI',
        fromAccount: fromAccount,
        fromAmount: amount,
        toPaymentType: 'UPI',
        toAccount: toAccount,
        toAmount: amount,
        source: 'local_rules',
      );
    }

    // ==========================================
    // CASE E: Regular Transaction (Withdraw or Deposit)
    // e.g. "paid 658 at dmart using HDFC PhonePe credit card for mother"
    // ==========================================
    String flow = 'Withdraw';
    if (lower.contains('receive') ||
        lower.contains('received') ||
        lower.contains('got') ||
        lower.contains('credited') ||
        (lower.contains('credit') && !lower.contains('credit card') && !lower.contains('credit mode')) ||
        lower.contains('salary') ||
        lower.contains('deposit') ||
        lower.contains('income') ||
        lower.contains('refund') ||
        lower.contains('cashback')) {
      flow = 'Deposit';
    } else if (lower.contains('transfer') || lower.contains('transferred')) {
      flow = 'Transfer';
    }
    if (lower.startsWith('paid') || lower.contains('paid ') || lower.contains('spent')) {
      flow = 'Withdraw';
    }

    final coreText = userInput
        .replaceAll(
          RegExp(
            r'(?:\.\s*)?(?:not\s+you\??|if\s+not\s+done\s+by\s+you|to\s+block\b|sms\s+block\b|call\s+1800\d+).*$',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        )
        .trim();
    final coreLower = coreText.toLowerCase();

    DateTime? smsDate;
    final isoDateMatch = RegExp(r'\b(20\d{2})-(\d{2})-(\d{2})\b').firstMatch(coreText);
    if (isoDateMatch != null) {
      final y = int.tryParse(isoDateMatch.group(1)!);
      final m = int.tryParse(isoDateMatch.group(2)!);
      final d = int.tryParse(isoDateMatch.group(3)!);
      if (y != null && m != null && d != null) {
        smsDate = DateTime(y, m, d);
      }
    }

    // Spent For detection (Blank if not specified)
    String? spentFor;
    final forMatch = RegExp(r'\bfor\s+([a-zA-Z]+)\b', caseSensitive: false).firstMatch(coreText);
    if (forMatch != null) {
      final rawSf = forMatch.group(1)?.trim();
      if (rawSf != null && rawSf.isNotEmpty && !['a', 'an', 'the', 'my'].contains(rawSf.toLowerCase())) {
        spentFor = rawSf[0].toUpperCase() + rawSf.substring(1).toLowerCase();
      }
    }

    // Payment Mode & Account detection
    String paymentType = 'UPI';
    if (!coreLower.contains('debit') &&
        (coreLower.contains('credit card') ||
            coreLower.contains('credit') ||
            RegExp(r'\b(?:bank\s+card|cc|card)\b').hasMatch(coreLower))) {
      paymentType = 'Credit';
    } else if (coreLower.contains('wallet') || coreLower.contains('paytm')) {
      paymentType = 'Wallets';
    } else if (coreLower.contains('cash')) {
      paymentType = 'Cash';
    } else if (coreLower.contains('netbanking') || coreLower.contains('net banking')) {
      paymentType = 'Net';
    } else if (coreLower.contains('debit')) {
      paymentType = 'Debit';
    }

    String? account;
    final cardDigitsMatch = RegExp(
      r'\bcard\s+(?:xx+|ending\s+in\s+|no\.?\s*)?(\d{4})\b',
      caseSensitive: false,
    ).firstMatch(coreText);
    final accRegex = RegExp(
      r'(?:using|via|through|from|by|with)\s+([a-zA-Z0-9\s]+?)(?:\s+(?:for|on|dated|at|rs|rupees)|(?:\s*[.,])|$)',
      caseSensitive: false,
    );
    final onCardRegex = RegExp(
      r'\bon\s+([a-zA-Z0-9\s]+?)\s+(?:bank\s+)?(?:credit\s+|debit\s+)?card\b',
      caseSensitive: false,
    );
    final accMatch = accRegex.firstMatch(coreText);
    final onCardMatch = onCardRegex.firstMatch(coreText);

    if (cardDigitsMatch != null) {
      final digits = cardDigitsMatch.group(1)!;
      for (final list in categoryAccounts.values) {
        for (final knownAcc in list) {
          if (knownAcc.contains(digits)) {
            account = knownAcc;
            break;
          }
        }
        if (account != null) break;
      }
    }

    if (account == null && onCardMatch != null) {
      final bankHint = _cleanAccountName(onCardMatch.group(1) ?? '').toLowerCase();
      final cardList = categoryAccounts['Credit Cards'] ?? const <String>[];
      for (final knownCard in cardList) {
        if (bankHint.isNotEmpty && knownCard.toLowerCase().contains(bankHint)) {
          account = knownCard;
          break;
        }
      }
      account ??= cardList.isNotEmpty ? cardList.first : _cleanAccountName(onCardMatch.group(1) ?? '');
    }

    if (account == null && accMatch != null) {
      account = _cleanAccountName(accMatch.group(1) ?? '');
    }

    if (account == null) {
      // Check known accounts
      for (final list in categoryAccounts.values) {
        for (final knownAcc in list) {
          if (coreLower.contains(knownAcc.toLowerCase())) {
            account = knownAcc;
            break;
          }
        }
        if (account != null) break;
      }
    }

    // Purpose detection
    String purpose = 'Others';
    if (coreLower.contains('dmart') ||
        coreLower.contains('avenue supermart') ||
        coreLower.contains('supermart') ||
        coreLower.contains('grocery') ||
        coreLower.contains('groceries') ||
        coreLower.contains('food') ||
        coreLower.contains('supermarket') ||
        coreLower.contains('restaurant') ||
        coreLower.contains('swiggy') ||
        coreLower.contains('zomato')) {
      purpose = _findMatchingPurpose('Groceries', purposes) ??
          _findMatchingPurpose('Food & Groceries', purposes) ??
          'Food & Groceries';
    } else if (coreLower.contains('electricity') ||
        coreLower.contains('current bill') ||
        coreLower.contains('power bill') ||
        coreLower.contains('water bill') ||
        coreLower.contains('wifi') ||
        coreLower.contains('rent') ||
        coreLower.contains('utility') ||
        coreLower.contains('bill')) {
      purpose = _findMatchingPurpose('Rent & Utilities', purposes) ?? 'Rent & Utilities';
    } else if (coreLower.contains('medicine') ||
        coreLower.contains('medical') ||
        coreLower.contains('doctor') ||
        coreLower.contains('hospital')) {
      purpose = _findMatchingPurpose('Medical & Health', purposes) ?? 'Medical & Health';
    } else if (coreLower.contains('petrol') ||
        coreLower.contains('fuel') ||
        coreLower.contains('diesel') ||
        coreLower.contains('uber') ||
        coreLower.contains('ola')) {
      purpose = _findMatchingPurpose('Fuel & Transport', purposes) ?? 'Fuel & Transport';
    } else if (coreLower.contains('salary') || coreLower.contains('income')) {
      purpose = _findMatchingPurpose('Salary & Income', purposes) ?? 'Salary & Income';
    } else if (purposes.isNotEmpty) {
      purpose = purposes.first;
    }

    // Narration construction
    var cleanNarration = coreText;
    // Remove timestamp / date clauses like "On 2026-11-27:14:54:01"
    cleanNarration = cleanNarration.replaceAll(
      RegExp(r'\bon\s+20\d{2}-\d{2}-\d{2}(?:[:T\s]\d{2}:\d{2}(?::\d{2})?)?', caseSensitive: false),
      ' ',
    );
    // Remove "On <Bank> Card <digits>"
    cleanNarration = cleanNarration.replaceAll(
      RegExp(r'\bon\s+[a-zA-Z0-9\s]+?\s+(?:bank\s+)?(?:credit\s+|debit\s+)?card(?:\s+\d{4})?', caseSensitive: false),
      ' ',
    );
    // Remove amount (with a space to avoid joining words)
    cleanNarration = cleanNarration.replaceAll(
      RegExp(r'(?:rs\.?|inr|rupees|₹)?\s*[0-9]+(?:\.[0-9]{1,2})?\s*(?:rs\.?|inr|rupees|₹|bucks)?', caseSensitive: false),
      ' ',
    );
    // Remove "using <account>" or "via <account>"
    cleanNarration = cleanNarration.replaceAll(
      RegExp(r'(?:using|via|through|from|by|with)\s+[a-zA-Z0-9\s]+?(?:\s+credit\s+card|\s+card|\s+account|\s+a/c|(?:\s+for\b)|$)', caseSensitive: false),
      ' ',
    );
    // Remove "for <recipient>"
    cleanNarration = cleanNarration.replaceAll(
      RegExp(r'\bfor\s+[a-zA-Z]+\b', caseSensitive: false),
      ' ',
    );
    // Clean extra whitespace
    cleanNarration = cleanNarration.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleanNarration.isNotEmpty) {
      cleanNarration = cleanNarration[0].toUpperCase() + cleanNarration.substring(1);
    } else {
      cleanNarration = 'Paid at ${purpose.toLowerCase()}';
    }

    return AiParsedTransaction(
      isSelfTransfer: false,
      flow: flow,
      amount: amount,
      narration: cleanNarration,
      purpose: purpose,
      spentFor: spentFor,
      account: account,
      paymentType: paymentType,
      date: smsDate,
      source: 'local_rules',
    );
  }

  static String _cleanAccountName(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'\b(credit\s+card|card|account|a/c|acc|bank)\b', caseSensitive: false), '').trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return s;
    const known = {
      'sbi': 'SBI',
      'hdfc': 'HDFC',
      'icici': 'ICICI',
      'pnb': 'PNB',
      'bob': 'BOB',
      'kotak': 'Kotak',
      'axis': 'Axis',
    };
    return s.split(' ').map((w) {
      if (known.containsKey(w.toLowerCase())) return known[w.toLowerCase()]!;
      if (w != w.toLowerCase()) return w;
      return w.isNotEmpty ? (w[0].toUpperCase() + w.substring(1)) : '';
    }).join(' ');
  }

  static String? _findMentionedBank(String input) {
    final lower = input.toLowerCase();
    final banks = ['kotak', 'sbi', 'hdfc', 'icici', 'axis', 'pnb', 'bob', 'canara', 'indusind', 'paytm'];
    for (final b in banks) {
      if (lower.contains(b)) {
        return b[0].toUpperCase() + b.substring(1);
      }
    }
    return null;
  }

  String? _findMatchingPurpose(String target, List<String> purposes) {
    for (final p in purposes) {
      if (p.toLowerCase() == target.toLowerCase()) return p;
    }
    for (final p in purposes) {
      if (p.toLowerCase().contains(target.toLowerCase()) ||
          target.toLowerCase().contains(p.toLowerCase())) {
        return p;
      }
    }
    return null;
  }
}
