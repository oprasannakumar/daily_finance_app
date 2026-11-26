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
            scaffoldBackgroundColor: const Color(0xFFFFF8F3),
            colorScheme: const ColorScheme(
              brightness: Brightness.light,
              primary: Color(0xFFFF5C38),
              onPrimary: Colors.white,
              secondary: Color(0xFF00D2B4),
              onSecondary: Colors.white,
              error: Color(0xFFEF4444),
              onError: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1E293B),
              surfaceContainerHighest: Color(0xFFFBF4ED),
            ),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              elevation: 0,
              backgroundColor: Color(0xFFFFF8F3),
              foregroundColor: Color(0xFF0F172A),
              titleTextStyle: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFF3EBE1), width: 1.2),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              constraints: const BoxConstraints(minHeight: 46),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28, maxWidth: 28, maxHeight: 28),
              labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFF5C38), width: 1.8),
              ),
            ),
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: Colors.white,
              elevation: 3,
              indicatorColor: const Color(0xFFFF5C38).withValues(alpha: 0.15),
              labelTextStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
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
            scaffoldBackgroundColor: const Color(0xFF0B0E1E),
            colorScheme: const ColorScheme(
              brightness: Brightness.dark,
              primary: Color(0xFFA78BFA),
              onPrimary: Color(0xFF0B0E1E),
              secondary: Color(0xFF00E5BE),
              onSecondary: Colors.white,
              error: Color(0xFFF43F5E),
              onError: Colors.white,
              surface: Color(0xFF151932),
              onSurface: Color(0xFFF1F5F9),
              surfaceContainerHighest: Color(0xFF1E2242),
            ),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              elevation: 0,
              backgroundColor: Color(0xFF0B0E1E),
              foregroundColor: Color(0xFFF1F5F9),
              titleTextStyle: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF1F5F9),
              ),
            ),
            cardTheme: CardThemeData(
              color: const Color(0xFF151932),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF262C54), width: 1.2),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF1B2042),
              isDense: true,
              constraints: const BoxConstraints(minHeight: 46),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28, maxWidth: 28, maxHeight: 28),
              labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF2C3360), width: 1.2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF2C3360), width: 1.2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFA78BFA), width: 1.8),
              ),
            ),
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: const Color(0xFF151932),
              elevation: 3,
              indicatorColor: const Color(0xFFA78BFA).withValues(alpha: 0.25),
              labelTextStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFF1F5F9)),
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
            final centerBottomInset = (visibleHeight * 0.42).clamp(110.0, 460.0);
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
    final bgColor = snackBar.backgroundColor ??
        (parent.isDark ? const Color(0xFF1E2547) : const Color(0xFF1E293B));

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
      content: Center(
        child: IntrinsicWidth(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 16,
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
    );

    return super.showSnackBar(
      wrappedSnackBar,
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
  }
}
