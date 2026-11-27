import 'package:flutter/material.dart';

/// App theme colors & gradients extension that supports smooth framework-level lerping
/// between Light ("Aurora Rose & Mint") and Dark ("Cosmic Obsidian & Neon Violet") modes.
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

  // Multi-stop gradient & glassmorphism tokens
  final Color primaryGradStart;
  final Color primaryGradEnd;
  final Color secondaryGradStart;
  final Color secondaryGradEnd;
  final Color heroGradStart;
  final Color heroGradEnd;
  final Color glassSurfaceTop;
  final Color glassSurfaceBottom;
  final Color glassRim;

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
    required this.primaryGradStart,
    required this.primaryGradEnd,
    required this.secondaryGradStart,
    required this.secondaryGradEnd,
    required this.heroGradStart,
    required this.heroGradEnd,
    required this.glassSurfaceTop,
    required this.glassSurfaceBottom,
    required this.glassRim,
  });

  LinearGradient get primaryGradient => LinearGradient(
        colors: [primaryGradStart, primaryGradEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get secondaryGradient => LinearGradient(
        colors: [secondaryGradStart, secondaryGradEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get heroGradient => LinearGradient(
        colors: [heroGradStart, heroGradEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get glassGradient => LinearGradient(
        colors: [glassSurfaceTop, glassSurfaceBottom],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static const light = AppThemeColors(
    pageBg: Color(0xFFF6F2FF),
    cardBg: Color(0xCCFFFFFF),
    cardBorder: Color(0xE6FFFFFF),
    inputBg: Color(0xC2FFFFFF),
    inputBorder: Color(0xFFD8DDF0),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    purpleAccent: Color(0xFF7C3AED),
    actionBtnBg: Color(0xD9FFFFFF),
    actionBtnBorder: Color(0xFFE2E8F0),
    primaryGradStart: Color(0xFFFF5C38),
    primaryGradEnd: Color(0xFFEC4899),
    secondaryGradStart: Color(0xFF00C9A7),
    secondaryGradEnd: Color(0xFF0EA5E9),
    heroGradStart: Color(0xFF6366F1),
    heroGradEnd: Color(0xFFEC4899),
    glassSurfaceTop: Color(0xDBFFFFFF),
    glassSurfaceBottom: Color(0x9EFFF8F5),
    glassRim: Color(0xE6FFFFFF),
  );

  static const dark = AppThemeColors(
    pageBg: Color(0xFF070A19),
    cardBg: Color(0xB8171D3E),
    cardBorder: Color(0x30FFFFFF),
    inputBg: Color(0xBF1A2146),
    inputBorder: Color(0xCC3B4882),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    purpleAccent: Color(0xFFA78BFA),
    actionBtnBg: Color(0xBF1A2146),
    actionBtnBorder: Color(0xCC3B4882),
    primaryGradStart: Color(0xFF8B5CF6),
    primaryGradEnd: Color(0xFFEC4899),
    secondaryGradStart: Color(0xFF00E5BE),
    secondaryGradEnd: Color(0xFF0EA5E9),
    heroGradStart: Color(0xFF312E81),
    heroGradEnd: Color(0xFF0E7490),
    glassSurfaceTop: Color(0xB81E2750),
    glassSurfaceBottom: Color(0x8A101532),
    glassRim: Color(0x2BFFFFFF),
  );

  static AppThemeColors of(BuildContext context) {
    return Theme.of(context).extension<AppThemeColors>() ??
        (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

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
    Color? primaryGradStart,
    Color? primaryGradEnd,
    Color? secondaryGradStart,
    Color? secondaryGradEnd,
    Color? heroGradStart,
    Color? heroGradEnd,
    Color? glassSurfaceTop,
    Color? glassSurfaceBottom,
    Color? glassRim,
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
      primaryGradStart: primaryGradStart ?? this.primaryGradStart,
      primaryGradEnd: primaryGradEnd ?? this.primaryGradEnd,
      secondaryGradStart: secondaryGradStart ?? this.secondaryGradStart,
      secondaryGradEnd: secondaryGradEnd ?? this.secondaryGradEnd,
      heroGradStart: heroGradStart ?? this.heroGradStart,
      heroGradEnd: heroGradEnd ?? this.heroGradEnd,
      glassSurfaceTop: glassSurfaceTop ?? this.glassSurfaceTop,
      glassSurfaceBottom: glassSurfaceBottom ?? this.glassSurfaceBottom,
      glassRim: glassRim ?? this.glassRim,
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
      primaryGradStart: Color.lerp(primaryGradStart, other.primaryGradStart, t)!,
      primaryGradEnd: Color.lerp(primaryGradEnd, other.primaryGradEnd, t)!,
      secondaryGradStart: Color.lerp(secondaryGradStart, other.secondaryGradStart, t)!,
      secondaryGradEnd: Color.lerp(secondaryGradEnd, other.secondaryGradEnd, t)!,
      heroGradStart: Color.lerp(heroGradStart, other.heroGradStart, t)!,
      heroGradEnd: Color.lerp(heroGradEnd, other.heroGradEnd, t)!,
      glassSurfaceTop: Color.lerp(glassSurfaceTop, other.glassSurfaceTop, t)!,
      glassSurfaceBottom: Color.lerp(glassSurfaceBottom, other.glassSurfaceBottom, t)!,
      glassRim: Color.lerp(glassRim, other.glassRim, t)!,
    );
  }
}
