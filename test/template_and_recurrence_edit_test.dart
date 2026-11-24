import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/main.dart';
import 'package:daily_finance_app/models/transaction_model.dart';
import 'package:daily_finance_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.saveAllRecurringTransactions([]);
    await StorageService.instance.saveAllTemplates([]);
  });

  testWidgets('Swiping template left-to-right loads template for edit and updates it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    final storage = StorageService.instance;

    final initialTemplate = TransactionTemplate(
      id: 'template_rent',
      name: 'Monthly Rent',
      narration: 'House Rent Payment',
      flow: 'Withdraw',
      purpose: 'Rent & Utilities',
      spentFor: 'Self',
      breakdowns: [PaymentBreakdown(paymentType: 'UPI', account: 'HDFC Bank A/c', amount: 15000)],
    );
    await storage.saveTemplate(initialTemplate);

    await tester.pumpWidget(const DailyFinanceApp());
    await tester.pumpAndSettle();

    // Open top right menu -> Templates
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Templates'));
    await tester.pumpAndSettle();

    // Verify Manage Masters is open on Templates tab
    expect(find.text('Manage Masters'), findsOneWidget);
    expect(find.text('Monthly Rent'), findsOneWidget);

    // SWIPE from LEFT to RIGHT on the template card to load for EDIT
    await tester.drag(find.text('Monthly Rent'), const Offset(500, 0));
    await tester.pumpAndSettle();

    // Verify form shows Editing Template banner because it was swiped!
    expect(find.text('Editing Template: Monthly Rent'), findsOneWidget);
    expect(find.text('Update Template'), findsOneWidget);

    // Tap Update Template button
    await tester.tap(find.text('Update Template'));
    await tester.pumpAndSettle();

    // Dialog should show 'Update Template' title and 'Update' button
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);

    // Tap 'Update'
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    // Verify template was updated and NO duplicate was created
    final templates = await storage.getTemplates();
    final rentTemplates = templates.where((t) => t.name == 'Monthly Rent').toList();
    expect(rentTemplates.length, 1);
    expect(rentTemplates.first.id, 'template_rent');
  });

  testWidgets('Tapping template loads data for regular transaction and Save records transaction', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    final storage = StorageService.instance;

    final initialTemplate = TransactionTemplate(
      id: 'template_groceries',
      name: 'Groceries',
      narration: 'Supermarket shopping',
      flow: 'Withdraw',
      purpose: 'Food & Dining',
      spentFor: 'Self',
      breakdowns: [PaymentBreakdown(paymentType: 'UPI', account: 'HDFC Bank A/c', amount: 2500)],
    );
    await storage.saveTemplate(initialTemplate);

    await tester.pumpWidget(const DailyFinanceApp());
    await tester.pumpAndSettle();

    // Open top right menu -> Templates
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Templates'));
    await tester.pumpAndSettle();

    // TAP (without swiping) on the template card
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();

    // Verify form is NOT in template edit mode!
    expect(find.text('Editing Template: Groceries'), findsNothing);
    expect(find.text('Update Template'), findsNothing);
    expect(find.text('Save as Template'), findsOneWidget);

    // Form fields are populated with template data
    expect(find.text('Supermarket shopping'), findsOneWidget);

    // Tap Save button -> directly saves as regular transaction
    await tester.scrollUntilVisible(
      find.text('Save'),
      300.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Verify regular transaction was saved
    final txs = await storage.getTransactions();
    expect(txs.any((t) => t.narration == 'Supermarket shopping'), isTrue);

    // Verify template count is unchanged (no new template created)
    final templates = await storage.getTemplates();
    expect(templates.where((t) => t.name == 'Groceries').length, 1);
  });

  testWidgets('Recurrence allows saving with blank/optional fields', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    final storage = StorageService.instance;

    await tester.pumpWidget(const DailyFinanceApp());
    await tester.pumpAndSettle();

    // Switch to Recurrence mode by tapping ⌛ sand timer
    await tester.tap(find.text('⌛'));
    await tester.pumpAndSettle();

    // Verify recurrence frequency dropdown is visible
    expect(find.text('⏳ RECURRENCE FREQUENCY'), findsOneWidget);

    // Scroll down to Save button and tap Save
    await tester.scrollUntilVisible(
      find.text('Save'),
      300.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Verify recurring transaction was saved without any mandatory field blocking error!
    final recurringList = await storage.getRecurringTransactions();
    expect(recurringList.isNotEmpty, isTrue);
    expect(recurringList.first.frequency, 'Month');
  });

  testWidgets('Future and paused recurrences are not shown in Bell icon badge or popup', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    final storage = StorageService.instance;

    final now = DateTime.now();
    final futureDate = now.add(const Duration(days: 10));
    final pastDate = now.subtract(const Duration(days: 1));

    // 1. Future recurrence (active, but date not yet reached)
    await storage.saveRecurringTransaction(
      RecurringTransaction(
        id: 'future_rec',
        narration: 'Future Insurance',
        nextDueDate: futureDate,
        frequency: 'Yearly',
        totalAmount: 5000,
        flow: 'Withdraw',
        purpose: 'Others',
        spentFor: 'Self',
        breakdowns: [],
        isPaused: false,
      ),
    );

    // 2. Past recurrence but PAUSED
    await storage.saveRecurringTransaction(
      RecurringTransaction(
        id: 'paused_rec',
        narration: 'Paused Gym Fee',
        nextDueDate: pastDate,
        frequency: 'Month',
        totalAmount: 1200,
        flow: 'Withdraw',
        purpose: 'Others',
        spentFor: 'Self',
        breakdowns: [],
        isPaused: true,
      ),
    );

    await tester.pumpWidget(const DailyFinanceApp());
    await tester.pumpAndSettle();

    // Verify bell icon is NOT shown when there are no badges (dueCount == 0)
    expect(find.text('🔔'), findsNothing);
    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsNothing);

    // Open Menu -> Recurring to verify both exist in Manage Masters
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recurring'));
    await tester.pumpAndSettle();

    // Verify both items show in Recurring tab of Manage Masters
    expect(find.text('Future Insurance'), findsOneWidget);
    expect(find.text('Paused Gym Fee'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('PAUSED'), findsOneWidget);

    // Toggle pause on Gym fee (tap play button to resume)
    await tester.tap(find.byTooltip('Resume recurrence'));
    await tester.pumpAndSettle();

    // Now Gym fee is ACTIVE and past date, so it should be due!
    final updatedList = await storage.getRecurringTransactions();
    final gymRec = updatedList.firstWhere((r) => r.id == 'paused_rec');
    expect(gymRec.isPaused, isFalse);
  });

  testWidgets('Tapping recurring transaction loads as regular transaction while swiping loads for edit', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    final storage = StorageService.instance;

    await storage.saveRecurringTransaction(
      RecurringTransaction(
        id: 'rec_wifi',
        narration: 'WiFi Fiber Internet',
        nextDueDate: DateTime.now(),
        frequency: 'Month',
        totalAmount: 999,
        flow: 'Withdraw',
        purpose: 'Rent & Utilities',
        spentFor: 'Self',
        breakdowns: [PaymentBreakdown(paymentType: 'UPI', account: 'HDFC Bank A/c', amount: 999)],
        isPaused: false,
      ),
    );

    await tester.pumpWidget(const DailyFinanceApp());
    await tester.pumpAndSettle();

    // 1. Open Menu -> Recurring
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recurring'));
    await tester.pumpAndSettle();

    // 2. TAP on the recurring transaction -> MUST load as regular transaction
    await tester.tap(find.text('WiFi Fiber Internet'));
    await tester.pumpAndSettle();

    // Verify it is NOT in recurrence edit mode!
    expect(find.text('⏳ RECURRENCE FREQUENCY'), findsNothing);
    expect(find.text('WiFi Fiber Internet'), findsOneWidget);

    // Save as regular transaction
    await tester.scrollUntilVisible(
      find.text('Save'),
      300.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Verify transaction recorded
    final txs = await storage.getTransactions();
    expect(txs.any((t) => t.narration == 'WiFi Fiber Internet'), isTrue);

    // 3. Open Menu -> Recurring again
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recurring'));
    await tester.pumpAndSettle();

    // 4. SWIPE left-to-right -> MUST load for EDIT!
    await tester.drag(find.text('WiFi Fiber Internet'), const Offset(500, 0));
    await tester.pumpAndSettle();

    // Verify it IS in recurrence edit mode!
    expect(find.text('⏳ RECURRENCE FREQUENCY'), findsOneWidget);
  });
}
