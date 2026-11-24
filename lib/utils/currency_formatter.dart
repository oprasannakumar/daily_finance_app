import 'package:intl/intl.dart';

class IndianCurrency {
  static final NumberFormat _withDecimals = NumberFormat('#,##,##,##0.00', 'en_IN');
  static final NumberFormat _withoutDecimals = NumberFormat('#,##,##,##0', 'en_IN');

  /// Formats amount in Indian format: 12,34,56,789.00 (or 12,34,56,789 if showDecimals is false).
  static String format(num amount, {bool showDecimals = true}) {
    if (showDecimals) {
      return _withDecimals.format(amount);
    }
    return _withoutDecimals.format(amount);
  }

  /// Automatically shows decimals if non-zero, or integer format if exact whole number:
  /// e.g. 123456789 -> 12,34,56,789
  /// e.g. 12345.50 -> 12,345.50
  static String formatSmart(num amount) {
    if ((amount % 1).abs() < 0.001) {
      return _withoutDecimals.format(amount);
    }
    return _withDecimals.format(amount);
  }
}
