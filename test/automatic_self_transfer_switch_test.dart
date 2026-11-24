import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/screens/transaction_form_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Typing narration allows manual form filling; tapping ✨ AI button switches to Self Transfer mode', (tester) async {
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

    // Verify initially NOT in Self Transfer mode
    expect(find.text('🏦 FROM (SOURCES)'), findsNothing);

    // Enter text in Narration field
    final narrationField = find.widgetWithText(TextFormField, 'Type command & tap ✨');
    expect(narrationField, findsOneWidget);
    await tester.enterText(narrationField, 'paid 5660 HDFC PhonePe credit card bill using SBI account');
    await tester.pump();

    // While typing, mode does NOT change (allows manual form filling)
    expect(find.text('🏦 FROM (SOURCES)'), findsNothing);

    // Tap the ✨ AI Auto-Fill button
    final aiButton = find.text('✨').last;
    await tester.tap(aiButton);
    await tester.pumpAndSettle();

    // Now switched to Self Transfer mode!
    expect(find.text('🏦 FROM (SOURCES)'), findsOneWidget);
    expect(find.text('🏦 TO (DESTINATIONS)'), findsOneWidget);

    // Verify From: SBI (e.g. SBI Savings A/c)
    expect(find.textContaining('SBI'), findsWidgets);
  });

  testWidgets('Tapping ✨ on "10000 cash withdrawn from kotak" switches to Self Transfer mode and populates fields', (tester) async {
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

    final narrationField = find.widgetWithText(TextFormField, 'Type command & tap ✨');
    await tester.enterText(narrationField, '10000 cash withdrawn from kotak');
    await tester.pump();

    // Manual form filling is preserved
    expect(find.text('🏦 FROM (SOURCES)'), findsNothing);

    // User taps ✨
    await tester.tap(find.text('✨').last);
    await tester.pumpAndSettle();

    expect(find.text('🏦 FROM (SOURCES)'), findsOneWidget);
    expect(find.text('🏦 TO (DESTINATIONS)'), findsOneWidget);
    expect(find.textContaining('Kotak'), findsWidgets);
  });

  testWidgets('Tapping ✨ on "5000 cash deposited into kotak" switches to Self Transfer mode', (tester) async {
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

    final narrationField = find.widgetWithText(TextFormField, 'Type command & tap ✨');
    await tester.enterText(narrationField, '5000 cash deposited into kotak');
    await tester.pump();

    expect(find.text('🏦 FROM (SOURCES)'), findsNothing);

    await tester.tap(find.text('✨').last);
    await tester.pumpAndSettle();

    expect(find.text('🏦 FROM (SOURCES)'), findsOneWidget);
    expect(find.text('🏦 TO (DESTINATIONS)'), findsOneWidget);
    expect(find.textContaining('Kotak'), findsWidgets);
  });

  testWidgets('Tapping ✨ on "paid 658 at dmart using HDFC PhonePe credit card" fills regular withdrawal without switching to Self Transfer', (tester) async {
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

    final narrationField = find.widgetWithText(TextFormField, 'Type command & tap ✨');
    await tester.enterText(narrationField, 'paid 658 at dmart using HDFC PhonePe credit card');
    await tester.pump();

    await tester.tap(find.text('✨').last);
    await tester.pumpAndSettle();

    // Must NOT switch to Self Transfer mode
    expect(find.text('🏦 FROM (SOURCES)'), findsNothing);

    // Purpose should be Food & Groceries
    expect(find.text('Food & Groceries'), findsWidgets);
  });

  testWidgets('Tapping ✨ on "paid 658 at dmart using HDFC PhonePe credit card for mother" sets Spent For to Other and fills text block with Mother', (tester) async {
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

    final narrationField = find.widgetWithText(TextFormField, 'Type command & tap ✨');
    await tester.enterText(narrationField, 'paid 658 at dmart using HDFC PhonePe credit card for mother');
    await tester.pump();

    await tester.tap(find.text('✨').last);
    await tester.pumpAndSettle();

    // Must NOT switch to Self Transfer mode
    expect(find.text('🏦 FROM (SOURCES)'), findsNothing);

    // Mother is not in available options, so it must use 'Other' and fill the custom text field with 'Mother'!
    expect(find.text('Mother'), findsWidgets);
  });
}
