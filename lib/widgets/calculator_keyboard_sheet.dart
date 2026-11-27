import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme_colors.dart';

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

  Widget _buildKey(
    String label, {
    Color? bg,
    Color? fg,
    List<Color>? gradientColors,
    int flex = 1,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppThemeColors.of(context);
    final defaultBg = isDark ? const Color(0xCC1E264F) : Colors.white.withValues(alpha: 0.88);
    final borderCol = gradientColors != null
        ? Colors.white.withValues(alpha: 0.25)
        : (isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0));

    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(3.5),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: gradientColors == null ? (bg ?? defaultBg) : null,
            gradient: gradientColors != null
                ? LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            border: Border.all(color: borderCol, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: gradientColors != null
                    ? gradientColors.first.withValues(alpha: 0.32)
                    : Colors.black.withValues(alpha: isDark ? 0.24 : 0.05),
                blurRadius: gradientColors != null ? 10 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap ?? () => _onKeyPress(label),
              borderRadius: BorderRadius.circular(12),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: label.length > 2 ? 14 : 18,
                    fontWeight: FontWeight.bold,
                    color: fg ?? colors.textPrimary,
                  ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppThemeColors.of(context);
    final opBg = isDark ? const Color(0xCC263163) : const Color(0xFFF1F5F9);
    final opFg = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0F766E);
    final dangerBg = isDark ? const Color(0x55F43F5E) : const Color(0xFFFEE2E2);
    final dangerFg = isDark ? const Color(0xFFFDA4AF) : const Color(0xFFDC2626);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [const Color(0xEB182046), const Color(0xE60D122C)]
                  : [const Color(0xF5FFFFFF), const Color(0xEBEEF9FF)],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.16) : Colors.white,
                width: 1.3,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 12, right: 12, top: 10, bottom: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: colors.textSecondary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Frosted Glass Calculator Display Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xCC111735), const Color(0xCC1B2452)]
                          : [Colors.white.withValues(alpha: 0.92), const Color(0xFFF0FDFA).withValues(alpha: 0.90)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? colors.purpleAccent.withValues(alpha: 0.4) : colors.inputBorder,
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Text(
                          _expression.isEmpty ? '0' : _expression,
                          style: TextStyle(
                            fontSize: 16,
                            color: _expression.isEmpty ? colors.textSecondary : colors.textPrimary,
                            fontFamily: 'monospace',
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'CALCULATED AMOUNT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFF00E5BE) : const Color(0xFF0F766E),
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            '= ₹ $_previewResult',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: _hasError
                                  ? const Color(0xFFEF4444)
                                  : (isDark ? const Color(0xFF00E5BE) : const Color(0xFF0F766E)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    _buildKey('(', bg: opBg),
                    _buildKey(')', bg: opBg),
                    _buildKey('%', bg: opBg, fg: opFg),
                    _buildKey('⌫', bg: dangerBg, fg: dangerFg),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('C', bg: dangerBg, fg: dangerFg),
                    _buildKey('/', bg: opBg, fg: opFg),
                    _buildKey('*', bg: opBg, fg: opFg),
                    _buildKey('-', bg: opBg, fg: opFg),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('7'),
                    _buildKey('8'),
                    _buildKey('9'),
                    _buildKey('+', bg: opBg, fg: opFg),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('4'),
                    _buildKey('5'),
                    _buildKey('6'),
                    _buildKey('=', bg: opFg.withValues(alpha: 0.16), fg: opFg),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('1'),
                    _buildKey('2'),
                    _buildKey('3'),
                    _buildKey('.'),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('0', flex: 1),
                    _buildKey('00', flex: 1),
                    _buildKey(
                      'Apply Amount (✓)',
                      flex: 2,
                      gradientColors: [colors.secondaryGradStart, colors.secondaryGradEnd],
                      fg: Colors.white,
                      onTap: _confirmAndApply,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
