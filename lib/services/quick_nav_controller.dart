import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'quick_actions_service.dart';

/// Tracks the active top-level screen and modal state so the universal
/// bottom Quick-Switch pill can jump between any screen in one gesture.
class QuickNavController extends ChangeNotifier {
  QuickNavController._internal();
  static final QuickNavController instance = QuickNavController._internal();

  /// Core screens cycled when flicking the bottom pill left or right.
  static const List<String> cycleOrder = [
    'Entry',
    'History',
    'Balances',
    'EMIs',
    'Borrowers',
    'Dashboard',
  ];

  static const Map<String, String> routeEmojis = {
    'Entry': '✨',
    'Dashboard': '📊',
    'API Keys': '🔑',
    'History': '📜',
    'Borrowers': '🤝',
    'Templates': '📋',
    'Recurring': '⌛',
    'EMIs': '💳',
    'Masters': '⚙️',
    'Balances': '💰',
    'Invoices': '🧾',
  };

  late final NavigatorObserver observer = _QuickNavObserver(this);

  String _currentScreen = 'Entry';
  String get currentScreen => _currentScreen;

  int _popupDepth = 0;
  bool get hasOpenPopup => _popupDepth > 0;

  bool _isQuickSheetOpen = false;
  bool get isQuickSheetOpen => _isQuickSheetOpen;

  void Function(String label)? _rootNavigationHandler;

  void registerRootHandler(void Function(String label) handler) {
    _rootNavigationHandler = handler;
  }

  void unregisterRootHandler(void Function(String label) handler) {
    if (_rootNavigationHandler == handler) {
      _rootNavigationHandler = null;
    }
  }

  void setQuickSheetOpen(bool open) {
    if (_isQuickSheetOpen != open) {
      _isQuickSheetOpen = open;
      notifyListeners();
    }
  }

  void _updateFromRoute(Route<dynamic>? route) {
    if (route == null || route is PopupRoute) return;
    final name = route.settings.name;
    final resolved = (name == null || name.isEmpty || name == '/') ? 'Entry' : name;
    if (_currentScreen != resolved) {
      _currentScreen = resolved;
      notifyListeners();
    }
  }

  void _onPopupPushed() {
    _popupDepth++;
    notifyListeners();
  }

  void _onPopupPopped() {
    if (_popupDepth > 0) _popupDepth--;
    notifyListeners();
  }

  /// Navigates cleanly to [label] from any screen without stacking routes.
  void navigateTo(String label) {
    HapticFeedback.selectionClick();
    final nav = QuickActionsService.instance.navigatorKey.currentState;
    if (nav == null) return;

    // API Keys is a dialog on the root screen rather than a full-screen route.
    if (label == 'API Keys') {
      nav.popUntil((route) => route.isFirst);
      _currentScreen = 'Entry';
      notifyListeners();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rootNavigationHandler?.call('API Keys');
      });
      return;
    }

    if (label == _currentScreen) return;

    nav.popUntil((route) => route.isFirst);
    if (label == 'Entry') {
      _currentScreen = 'Entry';
      notifyListeners();
      return;
    }

    _currentScreen = label;
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rootNavigationHandler?.call(label);
    });
  }

  /// Cycles through [cycleOrder] when the user flicks the pill left (+1) or right (-1).
  void cycleScreen(int delta) {
    final idx = cycleOrder.indexOf(_currentScreen);
    final base = idx == -1 ? 0 : idx;
    final nextIdx = (base + delta) % cycleOrder.length;
    final wrappedIdx = nextIdx < 0 ? nextIdx + cycleOrder.length : nextIdx;
    navigateTo(cycleOrder[wrappedIdx]);
  }
}

class _QuickNavObserver extends NavigatorObserver {
  final QuickNavController _controller;
  _QuickNavObserver(this._controller);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      _controller._onPopupPushed();
    } else {
      _controller._updateFromRoute(route);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      _controller._onPopupPopped();
    } else {
      _controller._updateFromRoute(previousRoute);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is! PopupRoute) {
      _controller._updateFromRoute(newRoute);
    }
  }
}
