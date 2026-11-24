import 'package:flutter/material.dart';

/// App theme colors extension that natively supports smooth framework-level lerping
@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color pageBg;
  final Color cardBg;
  final Color cardBorder;
  final Color inputBg;
  final Color inputBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color purpleAccent;
  final Color actionBtnBg;
  final Color actionBtnBorder;

  const AppThemeColors({
    required this.pageBg,
    required this.cardBg,
    required this.cardBorder,
    required this.inputBg,
    required this.inputBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.purpleAccent,
    required this.actionBtnBg,
    required this.actionBtnBorder,
  });

  static const light = AppThemeColors(
    pageBg: Color(0xFFFFF8F3),
    cardBg: Colors.white,
    cardBorder: Color(0xFFF1E5DC),
    inputBg: Colors.white,
    inputBorder: Color(0xFFCBD5E1),
    textPrimary: Color(0xFF1E293B),
    textSecondary: Color(0xFF64748B),
    purpleAccent: Color(0xFF8B5CF6),
    actionBtnBg: Colors.white,
    actionBtnBorder: Color(0xFFE2E8F0),
  );

  static const dark = AppThemeColors(
    pageBg: Color(0xFF0B0E1E),
    cardBg: Color(0xFF151932),
    cardBorder: Color(0xFF262C54),
    inputBg: Color(0xFF1B2042),
    inputBorder: Color(0xFF2C3360),
    textPrimary: Colors.white,
    textSecondary: Color(0xFF94A3B8),
    purpleAccent: Color(0xFFA78BFA),
    actionBtnBg: Color(0xFF1B2042),
    actionBtnBorder: Color(0xFF2C3360),
  );

  @override
  AppThemeColors copyWith({
    Color? pageBg,
    Color? cardBg,
    Color? cardBorder,
    Color? inputBg,
    Color? inputBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? purpleAccent,
    Color? actionBtnBg,
    Color? actionBtnBorder,
  }) {
    return AppThemeColors(
      pageBg: pageBg ?? this.pageBg,
      cardBg: cardBg ?? this.cardBg,
      cardBorder: cardBorder ?? this.cardBorder,
      inputBg: inputBg ?? this.inputBg,
      inputBorder: inputBorder ?? this.inputBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      purpleAccent: purpleAccent ?? this.purpleAccent,
      actionBtnBg: actionBtnBg ?? this.actionBtnBg,
      actionBtnBorder: actionBtnBorder ?? this.actionBtnBorder,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      pageBg: Color.lerp(pageBg, other.pageBg, t)!,
      cardBg: Color.lerp(cardBg, other.cardBg, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      inputBg: Color.lerp(inputBg, other.inputBg, t)!,
      inputBorder: Color.lerp(inputBorder, other.inputBorder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      purpleAccent: Color.lerp(purpleAccent, other.purpleAccent, t)!,
      actionBtnBg: Color.lerp(actionBtnBg, other.actionBtnBg, t)!,
      actionBtnBorder: Color.lerp(actionBtnBorder, other.actionBtnBorder, t)!,
    );
  }
}
