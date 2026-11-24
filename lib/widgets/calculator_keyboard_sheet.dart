import 'package:flutter/material.dart';

/// Interactive calculator bottom sheet keyboard designed specifically for the Amount field.
/// Supports numbers, parentheses, operators (+, -, *, /, %), backspace, clear,
/// and live calculation with an "Apply" button to send the computed amount.
class CalculatorKeyboardSheet extends StatefulWidget {
  final double initialAmount;

  const CalculatorKeyboardSheet({
    super.key,
    required this.initialAmount,
  });

  static Future<double?> show(BuildContext context, {required double initialAmount}) {
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CalculatorKeyboardSheet(initialAmount: initialAmount),
    );
  }

  /// Evaluates an algebraic expression with safe Shunting-Yard parser
  static double evaluateExpression(String expr) {
    return _CalculatorKeyboardSheetState.evaluateExpression(expr);
  }

  @override
  State<CalculatorKeyboardSheet> createState() => _CalculatorKeyboardSheetState();
}

class _CalculatorKeyboardSheetState extends State<CalculatorKeyboardSheet> {
  String _expression = '';
  String _previewResult = '0.00';
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialAmount != 0) {
      if (widget.initialAmount == widget.initialAmount.roundToDouble()) {
        _expression = widget.initialAmount.toInt().toString();
      } else {
        _expression = widget.initialAmount.toString();
      }
      _evaluate();
    }
  }

  void _onKeyPress(String key) {
    setState(() {
      if (key == 'C') {
        _expression = '';
        _previewResult = '0.00';
        _hasError = false;
        return;
      }

      if (key == '⌫') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
        _evaluate();
        return;
      }

      if (key == '=') {
        _evaluate(finalize: true);
        return;
      }

      // Avoid consecutive duplicate operators (except minus which can be negative)
      if (_expression.isNotEmpty) {
        final lastChar = _expression[_expression.length - 1];
        const ops = ['+', '*', '/', '%'];
        if (ops.contains(key) && ops.contains(lastChar)) {
          _expression = _expression.substring(0, _expression.length - 1) + key;
          _evaluate();
          return;
        }
      }

      _expression += key;
      _evaluate();
    });
  }

  void _evaluate({bool finalize = false}) {
    if (_expression.trim().isEmpty) {
      _previewResult = '0.00';
      _hasError = false;
      return;
    }

    try {
      final evaluated = evaluateExpression(_expression);
      if (evaluated.isNaN || evaluated.isInfinite) {
        _hasError = true;
        _previewResult = 'Error';
      } else {
        _hasError = false;
        if (evaluated == evaluated.roundToDouble()) {
          _previewResult = evaluated.toInt().toString();
        } else {
          _previewResult = evaluated.toStringAsFixed(2);
        }

        if (finalize) {
          _expression = _previewResult;
        }
      }
    } catch (_) {
      _hasError = true;
    }
  }

  void _confirmAndApply() {
    try {
      final evaluated = evaluateExpression(_expression);
      if (!evaluated.isNaN && !evaluated.isInfinite) {
        Navigator.of(context).pop(evaluated);
        return;
      }
    } catch (_) {}

    final fallback = double.tryParse(_previewResult);
    if (fallback != null) {
      Navigator.of(context).pop(fallback);
    } else {
      Navigator.of(context).pop(widget.initialAmount);
    }
  }

  /// Evaluates an algebraic expression with safe Shunting-Yard parser
  static double evaluateExpression(String expr) {
    String clean = expr.replaceAll(' ', '');
    if (clean.isEmpty) return 0.0;

    // Convert percentages: e.g. "1000*18%" => "1000*(18*0.01)"
    final percentRegex = RegExp(r'(\d+(?:\.\d+)?)\s*%');
    clean = clean.replaceAllMapped(percentRegex, (match) {
      final numVal = double.tryParse(match.group(1) ?? '0') ?? 0.0;
      return '($numVal*0.01)';
    });

    List<String> tokens = [];
    int i = 0;
    while (i < clean.length) {
      final c = clean[i];
      if (c == '+' || c == '*' || c == '/' || c == '(' || c == ')') {
        tokens.add(c);
        i++;
      } else if (c == '-') {
        // Unary minus if at start or immediately after another operator / '('
        bool isUnary = tokens.isEmpty ||
            tokens.last == '(' ||
            tokens.last == '+' ||
            tokens.last == '-' ||
            tokens.last == '*' ||
            tokens.last == '/';
        if (isUnary) {
          int start = i;
          i++;
          while (i < clean.length && RegExp(r'[0-9.]').hasMatch(clean[i])) {
            i++;
          }
          if (i > start + 1) {
            tokens.add(clean.substring(start, i));
          } else {
            tokens.add('-');
          }
        } else {
          tokens.add('-');
          i++;
        }
      } else if (RegExp(r'[0-9.]').hasMatch(c)) {
        int start = i;
        while (i < clean.length && RegExp(r'[0-9.]').hasMatch(clean[i])) {
          i++;
        }
        tokens.add(clean.substring(start, i));
      } else {
        i++;
      }
    }

    List<double> values = [];
    List<String> ops = [];

    int precedence(String op) {
      if (op == '+' || op == '-') return 1;
      if (op == '*' || op == '/') return 2;
      return 0;
    }

    void applyOp() {
      if (ops.isEmpty) return;
      final op = ops.removeLast();
      if (values.length < 2) return;
      final b = values.removeLast();
      final a = values.removeLast();
      switch (op) {
        case '+':
          values.add(a + b);
          break;
        case '-':
          values.add(a - b);
          break;
        case '*':
          values.add(a * b);
          break;
        case '/':
          values.add(b != 0 ? a / b : 0.0);
          break;
      }
    }

    for (final token in tokens) {
      final parsedNum = double.tryParse(token);
      if (parsedNum != null) {
        values.add(parsedNum);
      } else if (token == '(') {
        ops.add('(');
      } else if (token == ')') {
        while (ops.isNotEmpty && ops.last != '(') {
          if (values.length < 2) {
            ops.removeLast();
            break;
          }
          applyOp();
        }
        if (ops.isNotEmpty && ops.last == '(') {
          ops.removeLast();
        }
      } else if (token == '+' || token == '-' || token == '*' || token == '/') {
        while (ops.isNotEmpty && ops.last != '(' && precedence(ops.last) >= precedence(token)) {
          if (values.length < 2) {
            ops.removeLast();
            break;
          }
          applyOp();
        }
        ops.add(token);
      }
    }

    while (ops.isNotEmpty) {
      if (ops.last == '(') {
        ops.removeLast();
      } else {
        if (values.length < 2) {
          ops.removeLast();
          break;
        }
        applyOp();
      }
    }

    return values.isNotEmpty ? values.last : 0.0;
  }

  Widget _buildKey(String label, {Color? bg, Color? fg, int flex = 1, VoidCallback? onTap}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(3.0),
        child: Material(
          color: bg ?? Colors.white,
          borderRadius: BorderRadius.circular(10),
          elevation: 1,
          shadowColor: Colors.black12,
          child: InkWell(
            onTap: onTap ?? () => _onKeyPress(label),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: label.length > 2 ? 14 : 18,
                  fontWeight: FontWeight.bold,
                  color: fg ?? const Color(0xFF1E293B),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -2)),
        ],
      ),
      padding: const EdgeInsets.only(left: 12, right: 12, top: 10, bottom: 16),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Calculator Display Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Expression row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Text(
                      _expression.isEmpty ? '0' : _expression,
                      style: TextStyle(
                        fontSize: 16,
                        color: _expression.isEmpty ? Colors.grey : const Color(0xFF334155),
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Real-time evaluated result
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'CALCULATED AMOUNT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F766E),
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        '= ₹ $_previewResult',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _hasError ? Colors.red : const Color(0xFF0F766E),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Keypad Rows
            // Row 1: ( , ) , % , ⌫
            Row(
              children: [
                _buildKey('(', bg: const Color(0xFFF1F5F9)),
                _buildKey(')', bg: const Color(0xFFF1F5F9)),
                _buildKey('%', bg: const Color(0xFFF1F5F9), fg: const Color(0xFF0F766E)),
                _buildKey('⌫', bg: const Color(0xFFFEE2E2), fg: const Color(0xFFDC2626)),
              ],
            ),

            // Row 2: C , / , * , -
            Row(
              children: [
                _buildKey('C', bg: const Color(0xFFFEE2E2), fg: const Color(0xFFDC2626)),
                _buildKey('/', bg: const Color(0xFFF1F5F9), fg: const Color(0xFF0F766E)),
                _buildKey('*', bg: const Color(0xFFF1F5F9), fg: const Color(0xFF0F766E)),
                _buildKey('-', bg: const Color(0xFFF1F5F9), fg: const Color(0xFF0F766E)),
              ],
            ),

            // Row 3: 7 , 8 , 9 , +
            Row(
              children: [
                _buildKey('7'),
                _buildKey('8'),
                _buildKey('9'),
                _buildKey('+', bg: const Color(0xFFF1F5F9), fg: const Color(0xFF0F766E)),
              ],
            ),

            // Row 4: 4 , 5 , 6 , =
            Row(
              children: [
                _buildKey('4'),
                _buildKey('5'),
                _buildKey('6'),
                _buildKey('=', bg: const Color(0xFFCCFBF1), fg: const Color(0xFF0F766E)),
              ],
            ),

            // Row 5: 1 , 2 , 3 , .
            Row(
              children: [
                _buildKey('1'),
                _buildKey('2'),
                _buildKey('3'),
                _buildKey('.'),
              ],
            ),

            // Row 6: 0 , 00 , Apply Button
            Row(
              children: [
                _buildKey('0', flex: 1),
                _buildKey('00', flex: 1),
                _buildKey(
                  'Apply Amount (✓)',
                  flex: 2,
                  bg: const Color(0xFF0F766E),
                  fg: Colors.white,
                  onTap: _confirmAndApply,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
