import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_finance_app/main.dart';
import 'package:daily_finance_app/screens/transaction_form_screen.dart';
import 'package:daily_finance_app/services/quick_nav_controller.dart';
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

    // Navigate to API Keys via QuickNavController
    QuickNavController.instance.navigateTo('API Keys');
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
}
