import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quick_actions/quick_actions.dart';
import '../screens/borrowers_ledger_screen.dart';
import '../screens/invoice_manager_screen.dart';

class QuickActionsService {
  static final QuickActionsService instance = QuickActionsService._internal();
  QuickActionsService._internal();

  final QuickActions _quickActions = const QuickActions();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static const MethodChannel _widgetChannel = MethodChannel('com.example.finance/widget_channel');

  String? _pendingShortcut;

  void initialize() {
    try {
      _quickActions.initialize((String shortcutType) {
        debugPrint('QuickAction triggered: $shortcutType');
        _pendingShortcut = shortcutType;
        handleShortcut(shortcutType);
      });

      _quickActions.setShortcutItems(<ShortcutItem>[
        const ShortcutItem(
          type: 'action_quick_add',
          localizedTitle: '➕ Quick Add',
          icon: 'ic_launcher',
        ),
        const ShortcutItem(
          type: 'action_scan_receipt',
          localizedTitle: '📷 Scan Receipt (AI)',
          icon: 'ic_launcher',
        ),
        const ShortcutItem(
          type: 'action_borrowers',
          localizedTitle: '👥 Borrowers Ledger',
          icon: 'ic_launcher',
        ),
      ]);

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
      case 'action_quick_add':
        nav.popUntil((route) => route.isFirst);
        break;

      case 'action_scan_receipt':
        nav.push(
          MaterialPageRoute(
            builder: (_) => const InvoiceManagerScreen(autoStartScan: true),
          ),
        );
        break;

      case 'action_borrowers':
        nav.push(
          MaterialPageRoute(
            builder: (_) => const BorrowersLedgerScreen(),
          ),
        );
        break;
    }
  }
}
