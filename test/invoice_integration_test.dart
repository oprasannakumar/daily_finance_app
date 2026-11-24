import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/models/invoice_model.dart';
import 'package:daily_finance_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('InvoiceItemRecord & DealerPriceItem Tests', () {
    test('parses standard row with default Self recipient', () {
      final row = ['2026-11-24', 'D-Mart Supermarket', 'INV-20261124-001', 'Basmati Rice 5kg', '2', '250.00', '500.00'];
      final item = InvoiceItemRecord.fromSheetRow(row);

      expect(item.billNo, 'INV-20261124-001');
      expect(item.shopName, 'D-Mart Supermarket');
      expect(item.itemName, 'Basmati Rice 5kg');
      expect(item.quantity, 2.0);
      expect(item.price, 250.0);
      expect(item.total, 500.0);
      expect(item.recipient, 'Self');
    });

    test('parses 8th column recipient when present', () {
      final row = ['2026-11-24', 'D-Mart Supermarket', 'INV-20261124-001', 'Olive Oil', '1', '400.00', '400.00', 'Karthik'];
      final item = InvoiceItemRecord.fromSheetRow(row);

      expect(item.itemName, 'Olive Oil');
      expect(item.recipient, 'Karthik');
      expect(item.total, 400.0);
    });

    test('parses embedded recipient in item name (e.g. Item (Borrower))', () {
      final row = ['2026-11-24', 'D-Mart Supermarket', 'INV-20261124-001', 'Coffee Powder (Prasad)', '2', '75.00', '150.00'];
      final item = InvoiceItemRecord.fromSheetRow(row);

      expect(item.itemName, 'Coffee Powder');
      expect(item.recipient, 'Prasad');
      expect(item.total, 150.0);
    });

    test('serializes to sheet row correctly', () {
      final item = InvoiceItemRecord(
        id: 'test_1',
        billDate: DateTime(2026, 11, 24),
        shopName: 'Metro',
        billNo: 'INV-99',
        itemName: 'Sugar',
        quantity: 3,
        price: 45,
        total: 135,
        recipient: 'Friends',
      );
      final row = item.toSheetRow();

      expect(row[0], '2026-11-24');
      expect(row[1], 'Metro');
      expect(row[2], 'INV-99');
      expect(row[3], 'Sugar');
      expect(row[4], 3.0);
      expect(row[5], 45.0);
      expect(row[6], 135.0);
      expect(row[7], 'Friends');
    });

    test('DealerPriceItem parses and serializes correctly', () {
      final row = ['Wheat Flour 10kg', 'Metro Cash & Carry', '380.00', '2026-11-24 10:30'];
      final dp = DealerPriceItem.fromSheetRow(row);

      expect(dp.item, 'Wheat Flour 10kg');
      expect(dp.dealer, 'Metro Cash & Carry');
      expect(dp.price, 380.0);

      final outRow = dp.toSheetRow();
      expect(outRow[0], 'Wheat Flour 10kg');
      expect(outRow[1], 'Metro Cash & Carry');
      expect(outRow[2], 380.0);
    });
  });

  group('InvoiceSummary & Borrower Split Detection Tests', () {
    test('single invoice without borrowers computes selfShare = totalAmount and hasBorrowers = false', () {
      final items = [
        InvoiceItemRecord(
          id: '1',
          billDate: DateTime(2026, 11, 24),
          shopName: 'SuperMart',
          billNo: 'INV-101',
          itemName: 'Item A',
          quantity: 1,
          price: 100,
          recipient: 'Self',
        ),
        InvoiceItemRecord(
          id: '2',
          billDate: DateTime(2026, 11, 24),
          shopName: 'SuperMart',
          billNo: 'INV-101',
          itemName: 'Item B',
          quantity: 2,
          price: 50,
          recipient: 'Self',
        ),
      ];

      final grouped = InvoiceSummary.groupItems(items);
      expect(grouped.length, 1);

      final summary = grouped.first;
      expect(summary.billNo, 'INV-101');
      expect(summary.totalAmount, 200.0);
      expect(summary.hasBorrowers, false);
      expect(summary.selfShare, 200.0);
      expect(summary.borrowerShares.isEmpty, true);
    });

    test('invoice with multiple borrowers computes shares correctly for automatic split', () {
      final items = [
        InvoiceItemRecord(
          id: '1',
          billDate: DateTime(2026, 11, 24),
          shopName: 'HyperMarket',
          billNo: 'INV-202',
          itemName: 'Milk',
          quantity: 2,
          price: 30, // 60
          recipient: 'Self',
        ),
        InvoiceItemRecord(
          id: '2',
          billDate: DateTime(2026, 11, 24),
          shopName: 'HyperMarket',
          billNo: 'INV-202',
          itemName: 'Cooking Oil',
          quantity: 1,
          price: 180, // 180
          recipient: 'Prasad',
        ),
        InvoiceItemRecord(
          id: '3',
          billDate: DateTime(2026, 11, 24),
          shopName: 'HyperMarket',
          billNo: 'INV-202',
          itemName: 'Chocolates',
          quantity: 3,
          price: 50, // 150
          recipient: 'Karthik',
        ),
        InvoiceItemRecord(
          id: '4',
          billDate: DateTime(2026, 11, 24),
          shopName: 'HyperMarket',
          billNo: 'INV-202',
          itemName: 'Bread',
          quantity: 1,
          price: 40, // 40
          recipient: 'Self',
        ),
      ];

      final grouped = InvoiceSummary.groupItems(items);
      expect(grouped.length, 1);

      final summary = grouped.first;
      expect(summary.billNo, 'INV-202');
      expect(summary.totalAmount, 430.0); // 60 + 180 + 150 + 40
      expect(summary.hasBorrowers, true);
      expect(summary.selfShare, 100.0); // 60 + 40
      expect(summary.borrowerShares['Prasad'], 180.0);
      expect(summary.borrowerShares['Karthik'], 150.0);

      // Verify that Self share + Borrower shares sum exactly to totalAmount
      final totalShares = summary.selfShare + summary.borrowerShares.values.fold(0.0, (s, a) => s + a);
      expect(totalShares, summary.totalAmount);
    });
  });

  group('StorageService Local Caching Tests', () {
    test('saves and loads cached invoices and dealer prices', () async {
      final storage = StorageService.instance;

      final items = [
        InvoiceItemRecord(
          id: 'c1',
          billDate: DateTime(2026, 11, 24),
          shopName: 'Shop 1',
          billNo: 'INV-LOCAL-1',
          itemName: 'Rice',
          quantity: 1,
          price: 60,
          recipient: 'Self',
        ),
      ];

      await storage.saveCachedInvoices(items);
      final retrieved = await storage.getCachedInvoices();
      expect(retrieved.length, 1);
      expect(retrieved.first.billNo, 'INV-LOCAL-1');

      final prices = [
        DealerPriceItem(item: 'Tea', dealer: 'Tata', price: 120),
      ];

      await storage.saveCachedDealerPrices(prices);
      final retrievedPrices = await storage.getCachedDealerPrices();
      expect(retrievedPrices.length, 1);
      expect(retrievedPrices.first.item, 'Tea');
      expect(retrievedPrices.first.dealer, 'Tata');
      expect(retrievedPrices.first.price, 120.0);
    });
  });

  group('Invoice Date Parsing & Form Date Filtering Tests', () {
    test('InvoiceItemRecord.parseDateSafe parses all Google Sheet date formats accurately', () {
      final formats = [
        '24-Nov-2026',
        '24/Nov/2026',
        '24-Nov-26',
        '24/11/2026',
        '24-11-2026',
        '2026-11-24',
        '2026/11/24',
        '46350', // Excel serial date
      ];

      for (final s in formats) {
        final parsed = InvoiceItemRecord.parseDateSafe(s);
        expect(parsed.year, 2026, reason: 'Year failed for $s');
        expect(parsed.month, 11, reason: 'Month failed for $s');
        expect(parsed.day, 24, reason: 'Day failed for $s');
      }
    });

    test('filters invoices by exact matching form date and excludes mismatched dates', () {
      final items = [
        InvoiceItemRecord(
          id: '1',
          billDate: DateTime(2026, 11, 24),
          shopName: 'Shop A',
          billNo: 'INV-TODAY-1',
          itemName: 'Item 1',
          quantity: 1,
          price: 100,
        ),
        InvoiceItemRecord(
          id: '2',
          billDate: DateTime(2026, 11, 23),
          shopName: 'Shop B',
          billNo: 'INV-YESTERDAY-1',
          itemName: 'Item 2',
          quantity: 1,
          price: 200,
        ),
        InvoiceItemRecord(
          id: '3',
          billDate: DateTime(2026, 11, 24),
          shopName: 'Shop C',
          billNo: 'INV-TODAY-2',
          itemName: 'Item 3',
          quantity: 2,
          price: 50,
        ),
      ];

      final formDate = DateTime(2026, 11, 24);
      final filtered = items.where((it) =>
        it.billDate.year == formDate.year &&
        it.billDate.month == formDate.month &&
        it.billDate.day == formDate.day
      ).toList();

      expect(filtered.length, 2);
      expect(filtered.any((it) => it.billNo == 'INV-YESTERDAY-1'), isFalse);
      expect(filtered.map((it) => it.billNo).toList(), containsAll(['INV-TODAY-1', 'INV-TODAY-2']));
    });

    test('InvoiceSummary.groupItems sorts invoices descending with most recent on top', () {
      final items = [
        InvoiceItemRecord(
          id: '1',
          billDate: DateTime(2026, 9, 29),
          shopName: 'Old Shop',
          billNo: 'INV-SEP-29',
          itemName: 'Item Sep',
          quantity: 1,
          price: 100,
        ),
        InvoiceItemRecord(
          id: '2',
          billDate: DateTime(2026, 11, 24),
          shopName: 'Today Shop',
          billNo: 'INV-NOV-24-B',
          itemName: 'Item Today 2',
          quantity: 1,
          price: 200,
        ),
        InvoiceItemRecord(
          id: '3',
          billDate: DateTime(2026, 11, 20),
          shopName: 'Mid Shop',
          billNo: 'INV-NOV-20',
          itemName: 'Item Mid',
          quantity: 1,
          price: 150,
        ),
        InvoiceItemRecord(
          id: '4',
          billDate: DateTime(2026, 11, 24),
          shopName: 'Today Shop',
          billNo: 'INV-NOV-24-A',
          itemName: 'Item Today 1',
          quantity: 1,
          price: 50,
        ),
      ];

      final grouped = InvoiceSummary.groupItems(items);
      expect(grouped.length, 4);
      // Top should be 24-Nov-2026, then 20-Nov-2026, and bottom should be 29-Sep-2026
      expect(grouped[0].billDate, DateTime(2026, 11, 24));
      expect(grouped[1].billDate, DateTime(2026, 11, 24));
      expect(grouped[2].billDate, DateTime(2026, 11, 20));
      expect(grouped[3].billDate, DateTime(2026, 9, 29));
      expect(grouped.last.billNo, 'INV-SEP-29');
    });

    test('Dealer filtering and invoice search query matching', () {
      final dealerPrices = [
        DealerPriceItem(item: 'Groundnut Oil', dealer: 'Babu oil mill', price: 202),
        DealerPriceItem(item: 'Gingelly oil', dealer: 'Babu oil mill', price: 165),
        DealerPriceItem(item: 'Toor Dal', dealer: 'Prabhakar Traders', price: 155),
        DealerPriceItem(item: 'Moong Dal', dealer: 'Prabhakar Traders', price: 110),
      ];

      // Test dealer filter helper logic
      List<DealerPriceItem> filterByDealer(String dealer) {
        final d = dealer.trim().toLowerCase();
        if (d.isEmpty) return dealerPrices;
        final matching = dealerPrices.where((dp) => dp.dealer.trim().toLowerCase() == d).toList();
        return matching.isNotEmpty ? matching : dealerPrices;
      }

      final babuItems = filterByDealer('Babu oil mill');
      expect(babuItems.length, 2);
      expect(babuItems.every((dp) => dp.dealer == 'Babu oil mill'), isTrue);

      final prabhakarItems = filterByDealer('Prabhakar Traders');
      expect(prabhakarItems.length, 2);
      expect(prabhakarItems.every((dp) => dp.dealer == 'Prabhakar Traders'), isTrue);

      // Test invoice search query matching logic
      final invoices = InvoiceSummary.groupItems([
        InvoiceItemRecord(
          id: '1',
          billDate: DateTime(2026, 11, 24),
          shopName: 'Babu oil mill',
          billNo: 'INV-1795506205151',
          itemName: 'Groundnut oil',
          quantity: 4,
          price: 202,
          recipient: 'Grand Father',
        ),
        InvoiceItemRecord(
          id: '2',
          billDate: DateTime(2026, 11, 20),
          shopName: 'Prabhakar Traders',
          billNo: 'INV-1795172002210',
          itemName: 'Pesalu Moong Dal',
          quantity: 1,
          price: 110,
          recipient: 'Self',
        ),
      ]);

      List<InvoiceSummary> search(String query) {
        final q = query.toLowerCase().trim();
        return invoices.where((inv) {
          if (q.isEmpty) return true;
          final matchBill = inv.billNo.toLowerCase().contains(q);
          final matchShop = inv.shopName.toLowerCase().contains(q);
          final matchItem = inv.items.any((it) => it.itemName.toLowerCase().contains(q));
          final matchBorrower = inv.items.any((it) => it.recipient.toLowerCase().contains(q));
          return matchBill || matchShop || matchItem || matchBorrower;
        }).toList();
      }

      expect(search('Babu').length, 1);
      expect(search('Babu').first.billNo, 'INV-1795506205151');
      expect(search('Moong').length, 1);
      expect(search('Moong').first.shopName, 'Prabhakar Traders');
      expect(search('Grand Father').length, 1);
      expect(search('Grand Father').first.shopName, 'Babu oil mill');
      expect(search('1795172002210').length, 1);
    });
  });
}
