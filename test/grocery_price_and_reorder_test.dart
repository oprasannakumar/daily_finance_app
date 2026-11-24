import 'package:flutter_test/flutter_test.dart';
import 'package:daily_finance_app/models/invoice_model.dart';

void main() {
  group('GroceryItemPriceHistory Tests', () {
    test('computes price hike and price drop correctly', () {
      final List<InvoiceItemRecord> records = [
        // Milk: price increased from 50 to 60
        InvoiceItemRecord(
          id: '1',
          billNo: 'B002',
          shopName: 'Green Grocers',
          billDate: DateTime(2026, 11, 20),
          itemName: 'Full Cream Milk',
          quantity: 2,
          price: 60.0,
          total: 120.0,
        ),
        InvoiceItemRecord(
          id: '2',
          billNo: 'B001',
          shopName: 'Green Grocers',
          billDate: DateTime(2026, 11, 5),
          itemName: 'Full Cream Milk',
          quantity: 2,
          price: 50.0,
          total: 100.0,
        ),

        // Apples: price dropped from 150 to 120
        InvoiceItemRecord(
          id: '3',
          billNo: 'B002',
          shopName: 'Fresh Fruit Mart',
          billDate: DateTime(2026, 11, 20),
          itemName: 'Shimla Apples',
          quantity: 1.5,
          price: 120.0,
          total: 180.0,
        ),
        InvoiceItemRecord(
          id: '4',
          billNo: 'B001',
          shopName: 'Fresh Fruit Mart',
          billDate: DateTime(2026, 11, 5),
          itemName: 'Shimla Apples',
          quantity: 1,
          price: 150.0,
          total: 150.0,
        ),

        // Salt: unchanged price
        InvoiceItemRecord(
          id: '5',
          billNo: 'B002',
          shopName: 'Super Mart',
          billDate: DateTime(2026, 11, 20),
          itemName: 'Iodized Salt',
          quantity: 1,
          price: 28.0,
          total: 28.0,
        ),
        InvoiceItemRecord(
          id: '6',
          billNo: 'B001',
          shopName: 'Super Mart',
          billDate: DateTime(2026, 11, 5),
          itemName: 'Iodized Salt',
          quantity: 1,
          price: 28.0,
          total: 28.0,
        ),

        // Single purchase item (e.g. Honey)
        InvoiceItemRecord(
          id: '7',
          billNo: 'B002',
          shopName: 'Super Mart',
          billDate: DateTime(2026, 11, 20),
          itemName: 'Pure Honey',
          quantity: 1,
          price: 250.0,
          total: 250.0,
        ),
      ];

      final histories = GroceryItemPriceHistory.computeFrom(
        records,
        now: DateTime(2026, 11, 24),
      );

      final milk = histories.firstWhere((h) => h.itemName == 'Full Cream Milk');
      expect(milk.latestPrice, 60.0);
      expect(milk.previousPrice, 50.0);
      expect(milk.priceDelta, 10.0);
      expect(milk.percentChange, closeTo(20.0, 0.01));
      expect(milk.hasPriceHike, isTrue);
      expect(milk.hasPriceDrop, isFalse);

      final apples = histories.firstWhere((h) => h.itemName == 'Shimla Apples');
      expect(apples.latestPrice, 120.0);
      expect(apples.previousPrice, 150.0);
      expect(apples.priceDelta, -30.0);
      expect(apples.percentChange, closeTo(-20.0, 0.01));
      expect(apples.hasPriceHike, isFalse);
      expect(apples.hasPriceDrop, isTrue);

      final salt = histories.firstWhere((h) => h.itemName == 'Iodized Salt');
      expect(salt.latestPrice, 28.0);
      expect(salt.previousPrice, 28.0); // same price on earlier purchase
      expect(salt.priceDelta, 0.0);
      expect(salt.percentChange, 0.0);
      expect(salt.hasPriceHike, isFalse);
      expect(salt.hasPriceDrop, isFalse);

      final honey = histories.firstWhere((h) => h.itemName == 'Pure Honey');
      expect(honey.latestPrice, 250.0);
      expect(honey.previousPrice, isNull);
      expect(honey.priceDelta, 0.0);
      expect(honey.hasPriceHike, isFalse);
      expect(honey.hasPriceDrop, isFalse);
    });

    test('finds best deal across invoice history and catalog dealer prices', () {
      final List<InvoiceItemRecord> records = [
        InvoiceItemRecord(
          id: '1',
          billNo: 'B101',
          shopName: 'Local Corner Store',
          billDate: DateTime(2026, 11, 10),
          itemName: 'Olive Oil 1L',
          quantity: 1,
          price: 850.0,
          total: 850.0,
        ),
      ];

      final catalog = [
        DealerPriceItem(
          item: 'Olive Oil 1L',
          dealer: 'Wholesale Depot',
          price: 720.0,
        ),
      ];

      final histories = GroceryItemPriceHistory.computeFrom(
        records,
        catalog: catalog,
        now: DateTime(2026, 11, 24),
      );

      final oil = histories.firstWhere((h) => h.itemName == 'Olive Oil 1L');
      expect(oil.latestPrice, 850.0);
      expect(oil.latestDealer, 'Local Corner Store');
      expect(oil.bestPrice, 720.0);
      expect(oil.bestDealer, 'Wholesale Depot');
    });

    test('calculates purchase interval and triggers due for re-order accurately', () {
      final List<InvoiceItemRecord> records = [
        // Purchased every 7 days: Oct 10, Oct 17, Oct 24
        InvoiceItemRecord(
          id: '1',
          billNo: 'B1',
          shopName: 'Daily Mart',
          billDate: DateTime(2026, 10, 24),
          itemName: 'Eggs 12-pack',
          quantity: 1,
          price: 90.0,
          total: 90.0,
        ),
        InvoiceItemRecord(
          id: '2',
          billNo: 'B2',
          shopName: 'Daily Mart',
          billDate: DateTime(2026, 10, 17),
          itemName: 'Eggs 12-pack',
          quantity: 1,
          price: 90.0,
          total: 90.0,
        ),
        InvoiceItemRecord(
          id: '3',
          billNo: 'B3',
          shopName: 'Daily Mart',
          billDate: DateTime(2026, 10, 10),
          itemName: 'Eggs 12-pack',
          quantity: 1,
          price: 90.0,
          total: 90.0,
        ),
      ];

      // If current date is Oct 26 (only 2 days later) -> not due
      final earlyHistories = GroceryItemPriceHistory.computeFrom(
        records,
        now: DateTime(2026, 10, 26),
      );
      final earlyEggs = earlyHistories.firstWhere((h) => h.itemName == 'Eggs 12-pack');
      expect(earlyEggs.averageIntervalDays, 7);
      expect(earlyEggs.isDueForReorder, isFalse);

      // If current date is Nov 2 (9 days later, >= 7 days interval and >= 5) -> DUE!
      final dueHistories = GroceryItemPriceHistory.computeFrom(
        records,
        now: DateTime(2026, 11, 2),
      );
      final dueEggs = dueHistories.firstWhere((h) => h.itemName == 'Eggs 12-pack');
      expect(dueEggs.averageIntervalDays, 7);
      expect(dueEggs.isDueForReorder, isTrue);
    });

    test('calculates typical quantity, total quantities and total amounts correctly', () {
      final List<InvoiceItemRecord> records = [
        InvoiceItemRecord(
          id: '1',
          billNo: 'B1',
          shopName: 'Spice House',
          billDate: DateTime(2026, 11, 1),
          itemName: 'Turmeric 500g',
          quantity: 2.0,
          price: 110.0,
          total: 220.0,
        ),
        InvoiceItemRecord(
          id: '2',
          billNo: 'B2',
          shopName: 'Spice House',
          billDate: DateTime(2026, 11, 15),
          itemName: 'Turmeric 500g',
          quantity: 4.0,
          price: 115.0,
          total: 460.0,
        ),
      ];

      final histories = GroceryItemPriceHistory.computeFrom(
        records,
        now: DateTime(2026, 11, 24),
      );

      final turmeric = histories.firstWhere((h) => h.itemName == 'Turmeric 500g');
      expect(turmeric.totalQuantityPurchased, 6.0);
      expect(turmeric.totalAmountSpent, 680.0);
      expect(turmeric.typicalQuantity, 3.0); // (2 + 4) / 2 = 3.0
    });
  });
}
