import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/screens/transaction_form_screen.dart';
import 'package:daily_finance_app/services/storage_service.dart';
import 'package:daily_finance_app/widgets/popup_select_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Split mode: Enabled via top button and My Share is distinct with no remove button', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TransactionFormScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap top Split button (💸) to enable split mode
    final splitModeBtn = find.text('💸');
    expect(splitModeBtn, findsOneWidget);
    await tester.tap(splitModeBtn);
    await tester.pumpAndSettle();

    // Verify "My Share (You)" is visible
    expect(find.text('My Share (You)'), findsOneWidget);

    // Verify no remove button (close icon) on My Share exists
    final removeMyShareBtn = find.descendant(
      of: find.widgetWithText(Row, 'My Share (You)'),
      matching: find.byIcon(Icons.close_rounded),
    );
    expect(removeMyShareBtn, findsNothing);

    // Verify My Share CAN be dismissed by swiping
    final myShareDismissible = find.ancestor(
      of: find.text('My Share (You)'),
      matching: find.byType(Dismissible),
    );
    expect(myShareDismissible, findsOneWidget);
    await tester.drag(myShareDismissible, const Offset(-500.0, 0.0));
    await tester.pumpAndSettle();
    expect(find.text('My Share (You)'), findsNothing);
  });

  testWidgets('Split mode: Throws error message if main amount and total of splits do not match on Save', (tester) async {
    tester.view.physicalSize = const Size(1080, 3500);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TransactionFormScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Set Flow -> Withdraw
    final flowFinder = find.byWidgetPredicate(
      (w) => w is PopupSelectField && w.label == 'Flow',
    );
    await tester.tap(flowFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Withdraw').last);
    await tester.pumpAndSettle();

    // Set Purpose -> Loan Given
    final purposeFinder = find.byWidgetPredicate(
      (w) => w is PopupSelectField && w.label == 'Purpose',
    );
    await tester.tap(purposeFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Loan Given').last);
    await tester.pumpAndSettle();

    // Select Payment Type -> Cash
    final typeFinder = find.byWidgetPredicate(
      (w) => w is PopupSelectField && w.label == 'Type',
    );
    await tester.tap(typeFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash').last);
    await tester.pumpAndSettle();

    // Tap top Split button (💸) to enable split mode
    final splitModeBtn = find.text('💸');
    expect(splitModeBtn, findsOneWidget);
    await tester.tap(splitModeBtn);
    await tester.pumpAndSettle();

    // Set cash amount to 1000
    final count500Field = find.widgetWithText(TextField, '0');
    if (count500Field.evaluate().isNotEmpty) {
      await tester.enterText(count500Field.first, '2');
      await tester.pumpAndSettle();
    }

    // Dismiss the other recipient so split sum becomes 500 while total is 1000
    final dismissibleFinder = find.byWidgetPredicate(
      (w) => w is Dismissible && w.key.toString().contains('split_dismiss'),
    );
    expect(dismissibleFinder, findsNWidgets(2));
    await tester.drag(dismissibleFinder.last, const Offset(-500.0, 0.0));
    await tester.pumpAndSettle();

    // Tap Save button
    await tester.scrollUntilVisible(
      find.text('Save'),
      300.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify error message snackbar is shown
    expect(find.textContaining('Split amount mismatch!'), findsOneWidget);

    // Verify transaction was NOT saved in storage
    final transactions = await StorageService.instance.getTransactions();
    expect(transactions.isEmpty, true);
  });

  testWidgets('Split mode: When a member is selected in Spent For (not Split), container is hidden and 100% is assigned to that person', (tester) async {
    tester.view.physicalSize = const Size(1080, 3500);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TransactionFormScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Set Flow -> Withdraw
    final flowFinder = find.byWidgetPredicate(
      (w) => w is PopupSelectField && w.label == 'Flow',
    );
    await tester.tap(flowFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Withdraw').last);
    await tester.pumpAndSettle();

    // Select Payment Type -> Cash
    final typeFinder = find.byWidgetPredicate(
      (w) => w is PopupSelectField && w.label == 'Type',
    );
    await tester.tap(typeFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash').last);
    await tester.pumpAndSettle();

    // Set cash amount to 1000
    final count500Field = find.widgetWithText(TextField, '0');
    if (count500Field.evaluate().isNotEmpty) {
      await tester.enterText(count500Field.first, '2');
      await tester.pumpAndSettle();
    }

    // Tap top Split button (💸) to enable split mode
    final splitModeBtn = find.text('💸');
    await tester.tap(splitModeBtn);
    await tester.pumpAndSettle();

    // Select Spent For -> 'Friends' (instead of 'Split')
    final spentForFinder = find.byWidgetPredicate(
      (w) => w is PopupSelectField && w.key.toString().contains('spentFor_'),
    );
    await tester.tap(spentForFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Friends').last);
    await tester.pumpAndSettle();

    // Split container must NOT be visible since 'Split' is not selected in Spent For
    expect(find.text('My Share (You)'), findsNothing);

    // Tap Save button
    await tester.scrollUntilVisible(
      find.text('Save'),
      300.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Verify transaction was saved in storage
    final transactions = await StorageService.instance.getTransactions();
    expect(transactions.length, 1);
    final saved = transactions.first;
    expect(saved.isSplitMode, true);
    expect(saved.spentFor, 'Friends');
    expect(saved.splitRecipients, isNotNull);
    expect(saved.splitRecipients!.length, 1);
    expect(saved.splitRecipients!.first.name, 'Friends');
    expect(saved.splitRecipients!.first.amount, 1000.0);
    expect(saved.splitRecipients!.first.percentage, 100.0);
    expect(saved.splitRecipients!.first.isPersonal, false);
  });
}
