import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quick_actions/quick_actions.dart';
import '../screens/account_balances_screen.dart';
import 'storage_service.dart';

class QuickActionsService {
  static final QuickActionsService instance = QuickActionsService._internal();
  QuickActionsService._internal();

  final QuickActions _quickActions = const QuickActions();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static const MethodChannel _widgetChannel = MethodChannel('com.example.finance/widget_channel');

  String? _pendingShortcut;

  void initialize() {
    try {
      // Clear app icon shortcuts as requested
      _quickActions.setShortcutItems(<ShortcutItem>[]);

      _quickActions.initialize((String shortcutType) {
        debugPrint('QuickAction triggered: $shortcutType');
        _pendingShortcut = shortcutType;
        handleShortcut(shortcutType);
      });

      _widgetChannel.setMethodCallHandler((call) async {
        if (call.method == 'onWidgetAction') {
          final action = call.arguments as String?;
          if (action != null) {
            handleShortcut(action);
          }
        }
      });

      _checkInitialWidgetAction();
    } catch (e) {
      debugPrint('QuickActions init error: $e');
    }
  }

  Future<void> _checkInitialWidgetAction() async {
    try {
      final initialAction = await _widgetChannel.invokeMethod<String>('getInitialAction');
      if (initialAction != null && initialAction.isNotEmpty) {
        handleShortcut(initialAction);
      }
    } catch (_) {}
  }

  void handleShortcut(String shortcutType) {
    final nav = navigatorKey.currentState;
    if (nav == null) {
      _pendingShortcut = shortcutType;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pendingShortcut != null) {
          final s = _pendingShortcut!;
          _pendingShortcut = null;
          handleShortcut(s);
        }
      });
      return;
    }

    _pendingShortcut = null;

    switch (shortcutType) {
      case 'action_refresh_widget':
        StorageService.instance.syncWidgetBalances();
        break;

      case 'action_view_balances':
        nav.push(
          MaterialPageRoute(
            builder: (_) => const AccountBalancesScreen(),
          ),
        );
        break;

      default:
        // Unknown or standard launch action; do nothing
        break;
    }
  }
}
