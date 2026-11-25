import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/main.dart';
import 'package:daily_finance_app/screens/transaction_form_screen.dart';
import 'package:daily_finance_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.setGrokApiKey('');
    await StorageService.instance.setGeminiApiKey('');
  });

  testWidgets('API Keys dialog saves Grok and Gemini keys', (tester) async {
    await tester.pumpWidget(const DailyFinanceApp());
    await tester.pumpAndSettle();

    // Tap bottom Quick-Switch pill
    final menuBtn = find.byIcon(Icons.keyboard_arrow_up_rounded);
    expect(menuBtn, findsOneWidget);
    await tester.tap(menuBtn);
    await tester.pumpAndSettle();

    // Tap 'API Keys' menu item
    final apiKeysItem = find.text('API Keys');
    expect(apiKeysItem, findsOneWidget);
    await tester.tap(apiKeysItem);
    await tester.pumpAndSettle();

    // Verify dialog title
    expect(find.text('AI API Keys'), findsOneWidget);
    expect(find.text('⚡ Grok API Key'), findsOneWidget);
    expect(find.text('✨ Gemini API Key'), findsOneWidget);

    // Enter API keys inside AlertDialog
    final dialogTextFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(dialogTextFields, findsNWidgets(2));

    await tester.enterText(dialogTextFields.at(0), 'grok-test-key-120b');
    await tester.enterText(dialogTextFields.at(1), 'gemini-test-key-3.6');

    // Tap Save Keys
    await tester.tap(find.text('Save Keys'));
    await tester.pumpAndSettle();

    // Verify persisted
    final savedGrok = await StorageService.instance.getGrokApiKey();
    final savedGemini = await StorageService.instance.getGeminiApiKey();
    expect(savedGrok, 'grok-test-key-120b');
    expect(savedGemini, 'gemini-test-key-3.6');
  });

  testWidgets('Typing "paid 600 rupees electricity bill via hdfc New account" and tapping ✨ auto-fills form', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    await StorageService.instance.setGrokApiKey('');
    await StorageService.instance.setGeminiApiKey('');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TransactionFormScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter natural language text in Narration field
    final narrationField = find.widgetWithText(TextFormField, 'Type command & tap ✨');
    expect(narrationField, findsOneWidget);
    await tester.enterText(narrationField, 'paid 600 rupees electricity bill via hdfc New account');
    await tester.pump();

    // Tap ✨ button next to Narration
    final sparkleBtn = find.byWidgetPredicate(
      (w) => w is Text && w.data == '✨' && w.style?.fontSize == 18,
    );
    expect(sparkleBtn, findsOneWidget);
    await tester.tap(sparkleBtn);
    await tester.pumpAndSettle();

    // Verify Narration updated
    expect(find.text('Paid electricity bill'), findsOneWidget);

    // Verify Purpose updated to Rent & Utilities
    expect(find.text('Rent & Utilities'), findsWidgets);

    expect(find.text('₹ 600'), findsOneWidget);
  });
}
