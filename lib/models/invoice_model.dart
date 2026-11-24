import 'package:intl/intl.dart';

class InvoiceItemRecord {
  final String id;
  final DateTime billDate;
  final String shopName;
  final String billNo;
  final String itemName;
  final double quantity;
  final double price;
  final double total;
  final String recipient; // 'Self' or borrower name (e.g. 'Mother', 'Family', etc.)

  InvoiceItemRecord({
    required this.id,
    required this.billDate,
    required this.shopName,
    required this.billNo,
    required this.itemName,
    required this.quantity,
    required this.price,
    double? total,
    this.recipient = 'Self',
  }) : total = total ?? (quantity * price);

  factory InvoiceItemRecord.fromSheetRow(List<dynamic> row, {int rowIndex = 0}) {
    // Expected header: Bill Date | Shop Name | Bill No | Item Name | Quantity | Price | Total | [Recipient]
    final dateRaw = row.isNotEmpty ? row[0].toString().trim() : '';
    final parsedDate = parseDateSafe(dateRaw);

    final shop = row.length > 1 ? row[1].toString().trim() : '';
    final billNo = row.length > 2 ? row[2].toString().trim() : '';
    var item = row.length > 3 ? row[3].toString().trim() : '';
    final qty = row.length > 4 ? (double.tryParse(row[4].toString().replaceAll(',', '').trim()) ?? 1.0) : 1.0;
    final price = row.length > 5 ? (double.tryParse(row[5].toString().replaceAll(',', '').trim()) ?? 0.0) : 0.0;
    final total = row.length > 6 ? (double.tryParse(row[6].toString().replaceAll(',', '').trim()) ?? (qty * price)) : (qty * price);

    // Recipient extraction:
    // 1. Column 8 (index 7) if present
    // 2. Check if item has encoded recipient like "Item (Borrower)" or "Item [Borrower]"
    String recip = 'Self';
    if (row.length > 7 && row[7].toString().trim().isNotEmpty) {
      recip = row[7].toString().trim();
    } else {
      final matchParen = RegExp(r'\(([^)]+)\)$').firstMatch(item);
      final matchBracket = RegExp(r'\[([^\]]+)\]$').firstMatch(item);
      if (matchParen != null) {
        recip = matchParen.group(1)!.trim();
        item = item.substring(0, matchParen.start).trim();
      } else if (matchBracket != null) {
        recip = matchBracket.group(1)!.trim();
        item = item.substring(0, matchBracket.start).trim();
      }
    }

    return InvoiceItemRecord(
      id: '${billNo}_${rowIndex}_${item.hashCode}',
      billDate: parsedDate,
      shopName: shop,
      billNo: billNo,
      itemName: item,
      quantity: qty,
      price: price,
      total: total,
      recipient: recip.isEmpty ? 'Self' : recip,
    );
  }

  List<dynamic> toSheetRow() {
    // Bill Date | Shop Name | Bill No | Item Name | Quantity | Price | Total | Recipient
    final dateStr = DateFormat('yyyy-MM-dd').format(billDate);
    return <dynamic>[
      dateStr,
      shopName,
      billNo,
      itemName,
      quantity,
      price,
      total,
      recipient.trim().isEmpty ? 'Self' : recipient.trim(),
    ];
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'billDate': billDate.toIso8601String(),
    'shopName': shopName,
    'billNo': billNo,
    'itemName': itemName,
    'quantity': quantity,
    'price': price,
    'total': total,
    'recipient': recipient,
  };

  factory InvoiceItemRecord.fromJson(Map<String, dynamic> json) => InvoiceItemRecord(
    id: json['id'] as String? ?? '',
    billDate: DateTime.tryParse(json['billDate'] as String? ?? '') ?? DateTime.now(),
    shopName: json['shopName'] as String? ?? '',
    billNo: json['billNo'] as String? ?? '',
    itemName: json['itemName'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
    price: (json['price'] as num?)?.toDouble() ?? 0.0,
    total: (json['total'] as num?)?.toDouble(),
    recipient: json['recipient'] as String? ?? 'Self',
  );

  static final Map<String, int> _monthMap = {
    'jan': 1, 'january': 1,
    'feb': 2, 'february': 2,
    'mar': 3, 'march': 3,
    'apr': 4, 'april': 4,
    'may': 5,
    'jun': 6, 'june': 6,
    'jul': 7, 'july': 7,
    'aug': 8, 'august': 8,
    'sep': 9, 'september': 9,
    'oct': 10, 'october': 10,
    'nov': 11, 'november': 11,
    'dec': 12, 'december': 12,
  };

  static DateTime parseDateSafe(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return DateTime(1970, 1, 1);
    final trimmed = dateStr.trim();

    // 1. Check numeric Google Sheets / Excel serial date (e.g. 45618 or 46348)
    final numVal = double.tryParse(trimmed);
    if (numVal != null && numVal > 30000 && numVal < 70000) {
      final base = DateTime(1899, 12, 30);
      final days = numVal.floor();
      final ms = ((numVal - days) * 86400000).round();
      return base.add(Duration(days: days, milliseconds: ms));
    }

    try {
      // 2. Check if string contains month names (e.g. 24-Nov-2026, 24/Nov/26, 2026-Nov-24)
      if (RegExp(r'[a-zA-Z]').hasMatch(trimmed)) {
        final tokens = trimmed.split(RegExp(r'[-/.\s,]+')).where((s) => s.isNotEmpty).toList();
        if (tokens.length >= 3) {
          int? day;
          int? month;
          int? year;

          for (final t in tokens) {
            final lower = t.toLowerCase();
            if (_monthMap.containsKey(lower)) {
              month = _monthMap[lower];
            } else {
              final n = int.tryParse(t);
              if (n != null) {
                if (n > 31) {
                  year = n;
                } else if (day == null) {
                  day = n;
                } else {
                  year = n;
                }
              }
            }
          }

          if (day != null && month != null && year != null) {
            if (year < 100) {
              year = year < 70 ? year + 2000 : year + 1900;
            }
            return DateTime(year, month, day);
          }
        }
      }

      // 3. Pure numeric parts (e.g. 2026-11-24, 24/11/2026, 24-11-26, 24.11.26)
      final parts = trimmed.split(RegExp(r'[-/.\s,]+')).where((s) => s.isNotEmpty).toList();
      if (parts.length >= 3) {
        int? day;
        int? month;
        int? year;

        if (parts[0].length == 4) {
          year = int.tryParse(parts[0]);
          month = int.tryParse(parts[1]);
          day = int.tryParse(parts[2]);
        } else {
          day = int.tryParse(parts[0]);
          month = int.tryParse(parts[1]);
          year = int.tryParse(parts[2]);
        }

        if (day != null && month != null && year != null) {
          if (year < 100) {
            year = year < 70 ? year + 2000 : year + 1900;
          }
          return DateTime(year, month, day);
        }
      }

      return DateTime.tryParse(trimmed) ?? DateTime(1970, 1, 1);
    } catch (_) {
      return DateTime.tryParse(trimmed) ?? DateTime(1970, 1, 1);
    }
  }
}

class DealerPriceItem {
  final String item;
  final String dealer;
  final double price;
  final DateTime? lastUpdated;

  DealerPriceItem({
    required this.item,
    required this.dealer,
    required this.price,
    this.lastUpdated,
  });

  factory DealerPriceItem.fromSheetRow(List<dynamic> row) {
    // Item | Dealer | Price | LastUpdated
    final it = row.isNotEmpty ? row[0].toString().trim() : '';
    final d = row.length > 1 ? row[1].toString().trim() : '';
    final p = row.length > 2 ? (double.tryParse(row[2].toString().replaceAll(',', '').trim()) ?? 0.0) : 0.0;
    DateTime? dt;
    if (row.length > 3 && row[3].toString().trim().isNotEmpty) {
      dt = DateTime.tryParse(row[3].toString().trim());
    }
    return DealerPriceItem(
      item: it,
      dealer: d,
      price: p,
      lastUpdated: dt,
    );
  }

  List<dynamic> toSheetRow() {
    return [
      item,
      dealer,
      price,
      lastUpdated != null ? DateFormat('yyyy-MM-dd HH:mm').format(lastUpdated!) : '',
    ];
  }

  Map<String, dynamic> toJson() => {
    'item': item,
    'dealer': dealer,
    'price': price,
    'lastUpdated': lastUpdated?.toIso8601String(),
  };

  factory DealerPriceItem.fromJson(Map<String, dynamic> json) => DealerPriceItem(
    item: json['item'] as String? ?? '',
    dealer: json['dealer'] as String? ?? '',
    price: (json['price'] as num?)?.toDouble() ?? 0.0,
    lastUpdated: DateTime.tryParse(json['lastUpdated'] as String? ?? ''),
  );
}

class InvoiceSummary {
  final String billNo;
  final String shopName;
  final DateTime billDate;
  final List<InvoiceItemRecord> items;

  InvoiceSummary({
    required this.billNo,
    required this.shopName,
    required this.billDate,
    required this.items,
  });

  double get totalAmount => items.fold(0.0, (sum, it) => sum + it.total);

  Map<String, double> get recipientTotals {
    final map = <String, double>{};
    for (var it in items) {
      final r = it.recipient.trim().isEmpty ? 'Self' : it.recipient.trim();
      map[r] = (map[r] ?? 0.0) + it.total;
    }
    return map;
  }

  bool get hasBorrowers {
    return recipientTotals.keys.any((r) => r.toLowerCase() != 'self' && r.isNotEmpty);
  }

  double get selfShare {
    for (var e in recipientTotals.entries) {
      if (e.key.toLowerCase() == 'self') return e.value;
    }
    return 0.0;
  }

  Map<String, double> get borrowerShares {
    final res = <String, double>{};
    for (var e in recipientTotals.entries) {
      if (e.key.toLowerCase() != 'self') {
        res[e.key] = e.value;
      }
    }
    return res;
  }

  static List<InvoiceSummary> groupItems(List<InvoiceItemRecord> items) {
    final map = <String, List<InvoiceItemRecord>>{};
    for (var it in items) {
      final key = it.billNo.trim();
      map.putIfAbsent(key, () => []).add(it);
    }
    final list = map.entries.map((e) {
      final first = e.value.first;
      return InvoiceSummary(
        billNo: e.key,
        shopName: first.shopName,
        billDate: first.billDate,
        items: e.value,
      );
    }).toList();
    list.sort((a, b) {
      final cmp = b.billDate.compareTo(a.billDate);
      if (cmp != 0) return cmp;
      return b.billNo.compareTo(a.billNo);
    });
    return list;
  }
}

class GroceryItemPriceHistory {
  final String itemName;
  final List<InvoiceItemRecord> history; // sorted by billDate desc
  final double latestPrice;
  final double? previousPrice;
  final String latestDealer;
  final DateTime latestDate;
  final String bestDealer;
  final double bestPrice;
  final double typicalQuantity;
  final int averageIntervalDays;
  final bool isDueForReorder;
  final double totalQuantityPurchased;
  final double totalAmountSpent;

  GroceryItemPriceHistory({
    required this.itemName,
    required this.history,
    required this.latestPrice,
    this.previousPrice,
    required this.latestDealer,
    required this.latestDate,
    required this.bestDealer,
    required this.bestPrice,
    this.typicalQuantity = 1.0,
    this.averageIntervalDays = 14,
    this.isDueForReorder = false,
    this.totalQuantityPurchased = 0.0,
    this.totalAmountSpent = 0.0,
  });

  double get priceDelta => previousPrice != null ? latestPrice - previousPrice! : 0.0;
  double get percentChange => previousPrice != null && previousPrice! > 0
      ? ((latestPrice - previousPrice!) / previousPrice!) * 100
      : 0.0;
  bool get hasPriceHike => priceDelta > 0.05;
  bool get hasPriceDrop => priceDelta < -0.05;

  int get daysSinceLastPurchase => DateTime.now().difference(latestDate).inDays;

  static List<GroceryItemPriceHistory> computeFrom(
    List<InvoiceItemRecord> records, {
    List<DealerPriceItem> catalog = const [],
    DateTime? now,
  }) {
    final refNow = now ?? DateTime.now();
    // Group records by clean itemName (case-insensitive)
    final grouped = <String, List<InvoiceItemRecord>>{};
    for (final r in records) {
      final name = r.itemName.trim();
      if (name.isEmpty) continue;
      grouped.putIfAbsent(name.toLowerCase(), () => []).add(r);
    }

    final result = <GroceryItemPriceHistory>[];

    for (final entry in grouped.entries) {
      final list = entry.value;
      list.sort((a, b) => b.billDate.compareTo(a.billDate));

      final first = list.first;
      final displayName = first.itemName.trim();
      final latestPrice = first.price;
      final latestDealer = first.shopName.trim().isEmpty ? 'Direct' : first.shopName.trim();
      final latestDate = first.billDate;

      // Previous price from distinct previous entry
      double? prevPrice;
      for (int i = 1; i < list.length; i++) {
        if (list[i].price != latestPrice || list[i].billDate != latestDate) {
          prevPrice = list[i].price;
          break;
        }
      }

      // Best price and dealer across history and catalog
      double bestP = latestPrice;
      String bestD = latestDealer;

      for (final it in list) {
        if (it.price > 0 && (bestP == 0 || it.price < bestP)) {
          bestP = it.price;
          bestD = it.shopName.trim().isNotEmpty ? it.shopName.trim() : bestD;
        }
      }

      for (final cp in catalog) {
        if (cp.item.trim().toLowerCase() == entry.key && cp.price > 0) {
          if (bestP == 0 || cp.price < bestP) {
            bestP = cp.price;
            bestD = cp.dealer.trim().isNotEmpty ? cp.dealer.trim() : bestD;
          }
        }
      }

      // Totals & intervals
      double totalQty = 0.0;
      double totalAmt = 0.0;
      final dates = <DateTime>[];

      for (final it in list) {
        totalQty += it.quantity;
        totalAmt += it.total;
        if (!dates.any((d) => d.year == it.billDate.year && d.month == it.billDate.month && d.day == it.billDate.day)) {
          dates.add(DateTime(it.billDate.year, it.billDate.month, it.billDate.day));
        }
      }

      dates.sort((a, b) => a.compareTo(b));

      int avgInterval = 14;
      if (dates.length >= 2) {
        int totalDays = dates.last.difference(dates.first).inDays;
        int intervals = dates.length - 1;
        if (intervals > 0 && totalDays > 0) {
          avgInterval = (totalDays / intervals).round().clamp(3, 90);
        }
      }

      final daysSince = refNow.difference(latestDate).inDays;
      final isDue = daysSince >= avgInterval && daysSince >= 5;
      final typicalQty = (totalQty / list.length).clamp(0.5, 100.0);

      result.add(GroceryItemPriceHistory(
        itemName: displayName,
        history: list,
        latestPrice: latestPrice,
        previousPrice: prevPrice,
        latestDealer: latestDealer,
        latestDate: latestDate,
        bestDealer: bestD,
        bestPrice: bestP,
        typicalQuantity: typicalQty,
        averageIntervalDays: avgInterval,
        isDueForReorder: isDue,
        totalQuantityPurchased: totalQty,
        totalAmountSpent: totalAmt,
      ));
    }

    result.sort((a, b) {
      if (a.isDueForReorder != b.isDueForReorder) {
        return a.isDueForReorder ? -1 : 1;
      }
      return b.latestDate.compareTo(a.latestDate);
    });

    return result;
  }
}
