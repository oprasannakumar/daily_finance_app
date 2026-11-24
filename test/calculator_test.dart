import 'package:flutter_test/flutter_test.dart';
import 'package:daily_finance_app/widgets/calculator_keyboard_sheet.dart';

void main() {
  group('Calculator Keyboard Evaluator Tests', () {
    test('Standard operations and precedence', () {
      expect(CalculatorKeyboardSheet.evaluateExpression('100 + 200'), 300.0);
      expect(CalculatorKeyboardSheet.evaluateExpression('500 - 150'), 350.0);
      expect(CalculatorKeyboardSheet.evaluateExpression('25 * 4'), 100.0);
      expect(CalculatorKeyboardSheet.evaluateExpression('100 / 4'), 25.0);
      expect(CalculatorKeyboardSheet.evaluateExpression('10 + 20 * 2'), 50.0);
      expect(CalculatorKeyboardSheet.evaluateExpression('(10 + 20) * 2'), 60.0);
    });

    test('Negative numbers and unary minus', () {
      expect(CalculatorKeyboardSheet.evaluateExpression('-50'), -50.0);
      expect(CalculatorKeyboardSheet.evaluateExpression('100 + -50'), 50.0);
      expect(CalculatorKeyboardSheet.evaluateExpression('-100 * 2'), -200.0);
    });

    test('Percentage calculation', () {
      expect(CalculatorKeyboardSheet.evaluateExpression('1000 * 18%'), 180.0);
      expect(CalculatorKeyboardSheet.evaluateExpression('50%'), 0.5);
    });

    test('Edge cases and trailing operators do not hang or crash', () {
      expect(CalculatorKeyboardSheet.evaluateExpression(''), 0.0);
      expect(CalculatorKeyboardSheet.evaluateExpression('+'), 0.0);
      expect(CalculatorKeyboardSheet.evaluateExpression('-'), 0.0);
      expect(CalculatorKeyboardSheet.evaluateExpression('100+'), 100.0);
      expect(CalculatorKeyboardSheet.evaluateExpression('100*'), 100.0);
      expect(CalculatorKeyboardSheet.evaluateExpression('100/'), 100.0);
      expect(CalculatorKeyboardSheet.evaluateExpression('('), 0.0);
      expect(CalculatorKeyboardSheet.evaluateExpression('(100'), 100.0);
    });
  });
}
