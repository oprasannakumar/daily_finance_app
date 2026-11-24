import 'package:intl/intl.dart';

class ParsedTransactionDraft {
  final DateTime date;
  final String referenceId;
  final String narration;
  final String flow; // 'Withdraw' or 'Deposit'
  final String purpose;
  final String spentFor;
  final String paymentType;
  final String account;
  final double amount;
  final double charges;
  final String invoice;
  final String app;
  final String rawId;

  ParsedTransactionDraft({
    required this.date,
    required this.referenceId,
    required this.narration,
    required this.flow,
    required this.purpose,
    required this.spentFor,
    required this.paymentType,
    required this.account,
    required this.amount,
    this.charges = 0.0,
    this.invoice = '',
    this.app = '',
    this.rawId = '',
  });
}

class ClipboardTransactionParser {
  /// Parses multiple transactions or single transaction from clipboard text
  static List<ParsedTransactionDraft> parse(String text) {
    if (text.trim().isEmpty) return [];

    final List<String> blocks = [];

    // Check if delimited by --- Transaction X ---
    final delimiterRegex = RegExp(r'---\s*Transaction(?:\s+\d+)?\s*---', caseSensitive: false);
    if (delimiterRegex.hasMatch(text)) {
      final splits = text.split(delimiterRegex);
      for (final s in splits) {
        if (s.trim().isNotEmpty) {
          blocks.add(s.trim());
        }
      }
    } else {
      // Split by double line breaks or repeated Date fields
      final rawBlocks = text.split(RegExp(r'\n\s*\n+'));
      for (final b in rawBlocks) {
        if (b.trim().isNotEmpty) {
          blocks.add(b.trim());
        }
      }
    }

    final List<ParsedTransactionDraft> results = [];

    for (final block in blocks) {
      final draft = _parseSingleBlock(block);
      if (draft != null) {
        results.add(draft);
      }
    }

    return results;
  }

  static ParsedTransactionDraft? _parseSingleBlock(String block) {
    final lines = block.split('\n');

    DateTime? date;
    String app = '';
    String name = '';
    String id = '';
    String msg = '';
    double? amount;
    double charges = 0.0;
    String direction = 'OUT';
    String type = '';
    String account = '';
    String category = '';
    String ref = '';

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Extract key and val
      final colonIndex = line.indexOf(':');
      if (colonIndex == -1) continue;

      final rawKey = line.substring(0, colonIndex).trim();
      final val = line.substring(colonIndex + 1).trim();

      // Clean key of emojis
      final key = rawKey.replaceAll(RegExp(r'[^\w\s]'), '').trim().toLowerCase();

      switch (key) {
        case 'date':
          date = _parseDate(val);
          break;
        case 'app':
          app = val;
          break;
        case 'name':
          name = val;
          break;
        case 'id':
          id = val;
          break;
        case 'msg':
        case 'message':
        case 'note':
          msg = val;
          break;
        case 'amount':
          amount = _parseAmount(val);
          break;
        case 'charges':
          charges = _parseAmount(val) ?? 0.0;
          break;
        case 'direction':
          direction = val.toUpperCase();
          break;
        case 'type':
          type = val;
          break;
        case 'account':
          account = val;
          break;
        case 'category':
        case 'purpose':
          category = val;
          break;
        case 'ref':
        case 'reference':
          ref = val;
          break;
      }
    }

    // Must have at least an amount or name or date to be considered a transaction
    if (amount == null && name.isEmpty && ref.isEmpty) {
      return null;
    }

    final finalDate = date ?? DateTime.now();
    final isDeposit = direction.contains('IN') || direction.contains('GREEN') || direction.contains('CREDIT');
    final flow = isDeposit ? 'Deposit' : 'Withdraw';

    // Construct Narration
    String narration;
    if (name.isNotEmpty) {
      if (flow == 'Withdraw') {
        narration = 'Paid to $name';
      } else {
        narration = 'Received from $name';
      }
      if (msg.isNotEmpty && !narration.contains(msg)) {
        narration = '$narration - $msg';
      }
    } else if (msg.isNotEmpty) {
      narration = msg;
    } else {
      narration = 'Transaction';
    }

    // Normalize Payment Type
    String normalizedType = _normalizePaymentType(type);

    return ParsedTransactionDraft(
      date: finalDate,
      referenceId: ref,
      narration: narration,
      flow: flow,
      purpose: category.isNotEmpty ? category : 'Others',
      spentFor: 'Select',
      paymentType: normalizedType,
      account: account,
      amount: amount ?? 0.0,
      charges: charges,
      invoice: 'No invoice',
      app: app,
      rawId: id,
    );
  }

  static String _normalizePaymentType(String raw) {
    final lower = raw.trim().toLowerCase();
    if (lower.contains('credit')) {
      return 'Credit Card';
    }
    if (lower.contains('debit')) {
      return 'Debit Card';
    }
    if (lower.contains('upi')) {
      return 'UPI';
    }
    if (lower.contains('cash')) {
      return 'Cash';
    }
    if (lower.contains('net')) {
      return 'Net';
    }
    if (lower.contains('wallet')) {
      return 'Wallets';
    }
    if (lower.contains('reward')) {
      return 'Rewards';
    }
    return raw.isNotEmpty ? raw : 'UPI';
  }

  static DateTime? _parseDate(String dateStr) {
    final cleaned = dateStr.replaceAll(RegExp(r'[^\w\-\/]'), '').trim();
    final formats = [
      'dd-MM-yyyy',
      'd-M-yyyy',
      'dd/MM/yyyy',
      'd/M/yyyy',
      'yyyy-MM-dd',
      'dd-MMM-yyyy',
      'd-MMM-yyyy',
    ];

    for (final fmt in formats) {
      try {
        return DateFormat(fmt).parseLoose(cleaned);
      } catch (_) {}
    }
    return null;
  }

  static double? _parseAmount(String amtStr) {
    final s = amtStr.trim();
    if (s.isEmpty) return null;
    final isNegative = s.contains('-') || (s.contains('(') && s.contains(')'));
    final cleaned = s.replaceAll(RegExp(r'[^\d.]'), '');
    final val = double.tryParse(cleaned);
    if (val == null) return null;
    return isNegative ? -val : val;
  }
}
