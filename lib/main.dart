import 'dart:ui';
import 'package:flutter/material.dart';
import 'screens/transaction_form_screen.dart';
import 'services/quick_actions_service.dart';
import 'services/quick_nav_controller.dart';
import 'services/storage_service.dart';
import 'theme/app_theme_colors.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/quick_switch_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.instance.initTheme();
  // Warm up local cache so app renders instantly with zero loading delay
  await StorageService.instance.getTransactions();
  runApp(const DailyFinanceApp());
  QuickActionsService.instance.initialize();
}

class DailyFinanceApp extends StatelessWidget {
  const DailyFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: StorageService.instance.isDarkModeNotifier,
      builder: (context, isDark, child) {
        return MaterialApp(
          navigatorKey: QuickActionsService.instance.navigatorKey,
          navigatorObservers: [QuickNavController.instance.observer],
          title: 'Smart Entry Finance',
          debugShowCheckedModeBanner: false,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          themeAnimationDuration: const Duration(milliseconds: 750),
          themeAnimationCurve: Curves.easeInOutCubic,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            extensions: const [AppThemeColors.light],
            scaffoldBackgroundColor: const Color(0xFFF6F2FF),
            colorScheme: const ColorScheme(
              brightness: Brightness.light,
              primary: Color(0xFFFF5C38),
              onPrimary: Colors.white,
              secondary: Color(0xFF00C9A7),
              onSecondary: Colors.white,
              error: Color(0xFFEF4444),
              onError: Colors.white,
              surface: Color(0xF0FFFFFF),
              onSurface: Color(0xFF0F172A),
              surfaceContainerHighest: Color(0xFFF3EEFF),
            ),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              foregroundColor: Color(0xFF0F172A),
              titleTextStyle: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            cardTheme: CardThemeData(
              color: const Color(0xDBFFFFFF),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xE6FFFFFF), width: 1.2),
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: const Color(0xF5FFFFFF),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Color(0xFFE5DDF6), width: 1.2),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xC2FFFFFF),
              isDense: true,
              constraints: const BoxConstraints(minHeight: 46),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28, maxWidth: 28, maxHeight: 28),
              labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD8DDF0), width: 1.2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD8DDF0), width: 1.2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFF5C38), width: 1.8),
              ),
            ),
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: const Color(0xE6FFFFFF),
              elevation: 0,
              indicatorColor: const Color(0xFFFF5C38).withValues(alpha: 0.16),
              labelTextStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
            ),
            snackBarTheme: SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
              insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            extensions: const [AppThemeColors.dark],
            scaffoldBackgroundColor: const Color(0xFF070A19),
            colorScheme: const ColorScheme(
              brightness: Brightness.dark,
              primary: Color(0xFFA78BFA),
              onPrimary: Color(0xFF070A19),
              secondary: Color(0xFF00E5BE),
              onSecondary: Colors.white,
              error: Color(0xFFF43F5E),
              onError: Colors.white,
              surface: Color(0xEB151B3B),
              onSurface: Color(0xFFF8FAFC),
              surfaceContainerHighest: Color(0xFF1E254D),
            ),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              foregroundColor: Color(0xFFF8FAFC),
              titleTextStyle: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF8FAFC),
              ),
            ),
            cardTheme: CardThemeData(
              color: const Color(0xBD182046),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.14), width: 1.2),
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: const Color(0xF0151C3D),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15), width: 1.2),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xBF1A2146),
              isDense: true,
              constraints: const BoxConstraints(minHeight: 46),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28, maxWidth: 28, maxHeight: 28),
              labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xCC3B4882), width: 1.2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xCC3B4882), width: 1.2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFA78BFA), width: 1.8),
              ),
            ),
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: const Color(0xD9121836),
              elevation: 0,
              indicatorColor: const Color(0xFFA78BFA).withValues(alpha: 0.25),
              labelTextStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFF8FAFC)),
              ),
            ),
            snackBarTheme: SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
              insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
          ),
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final visibleHeight = (mq.size.height - mq.viewInsets.bottom).clamp(240.0, 2000.0);
            final centerBottomInset = (visibleHeight * 0.48).clamp(130.0, 540.0);
            final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

            return Theme(
              data: Theme.of(context).copyWith(
                snackBarTheme: Theme.of(context).snackBarTheme.copyWith(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: isDarkTheme ? const Color(0xFF1E2547) : const Color(0xFF1E293B),
                  contentTextStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  insetPadding: EdgeInsets.fromLTRB(20, 16, 20, centerBottomInset),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                ),
              ),
              child: _DynamicSnackBarMessenger(
                centerBottomInset: centerBottomInset,
                isDark: isDarkTheme,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (PointerDownEvent event) {
                    final currentFocus = FocusManager.instance.primaryFocus;
                    if (currentFocus != null && currentFocus.hasFocus) {
                      final renderObject = currentFocus.context?.findRenderObject();
                      if (renderObject is RenderBox && renderObject.hasSize) {
                        final pos = renderObject.localToGlobal(Offset.zero);
                        final bounds = pos & renderObject.size;
                        if (!bounds.contains(event.position)) {
                          currentFocus.unfocus();
                        }
                      } else {
                        currentFocus.unfocus();
                      }
                    }
                  },
                  child: AppLockGate(
                    child: QuickSwitchOverlay(child: child ?? const SizedBox.shrink()),
                  ),
                ),
              ),
            );
          },
          home: const TransactionFormScreen(),
        );
      },
    );
  }
}

class _DynamicSnackBarMessenger extends ScaffoldMessenger {
  final double centerBottomInset;
  final bool isDark;

  const _DynamicSnackBarMessenger({
    required this.centerBottomInset,
    required this.isDark,
    required super.child,
  });

  @override
  ScaffoldMessengerState createState() => _DynamicSnackBarMessengerState();
}

class _DynamicSnackBarMessengerState extends ScaffoldMessengerState {
  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    final parent = widget as _DynamicSnackBarMessenger;
    final hasExplicitColor = snackBar.backgroundColor != null;
    final baseColor = snackBar.backgroundColor ??
        (parent.isDark ? const Color(0xFF19224D) : const Color(0xFF1E293B));

    final wrappedSnackBar = SnackBar(
      key: snackBar.key,
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      padding: EdgeInsets.zero,
      margin: EdgeInsets.only(bottom: parent.centerBottomInset, left: 20, right: 20),
      duration: snackBar.duration,
      dismissDirection: snackBar.dismissDirection,
      onVisible: snackBar.onVisible,
      clipBehavior: Clip.none,
      content: IgnorePointer(
        ignoring: snackBar.action == null,
        child: Center(
          child: IntrinsicWidth(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: hasExplicitColor
                          ? [baseColor.withValues(alpha: 0.92), baseColor.withValues(alpha: 0.78)]
                          : (parent.isDark
                              ? [const Color(0xDE222B5C), const Color(0xCC13193B)]
                              : [const Color(0xDE1E293B), const Color(0xCC312E81)]),
                    ),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                      width: 1.1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (hasExplicitColor ? baseColor : const Color(0xFF6366F1)).withValues(alpha: 0.30),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: DefaultTextStyle(
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                          child: snackBar.content,
                        ),
                      ),
                      if (snackBar.action != null) ...[
                        const SizedBox(width: 10),
                        snackBar.action!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return super.showSnackBar(
      wrappedSnackBar,
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
  }
}
