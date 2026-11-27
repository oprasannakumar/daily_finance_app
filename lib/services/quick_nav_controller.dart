import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/transaction_model.dart';
import 'quick_actions_service.dart';

class EntryDraft {
  final String? flow;
  final String? purpose;
  final String? spentFor;
  final String? narration;
  final double? amount;
  final bool isSelfTransfer;
  final String? toAccount;
  final String? toPaymentType;
  final String? splitBorrower;

  const EntryDraft({
    this.flow,
    this.purpose,
    this.spentFor,
    this.narration,
    this.amount,
    this.isSelfTransfer = false,
    this.toAccount,
    this.toPaymentType,
    this.splitBorrower,
  });
}

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
    'Invoices',
    'Masters',
  ];

  static const Map<String, String> routeEmojis = {
    'Entry': '✨',
    'Dashboard': '📊',
    'API Keys': '🔑',
    'History': '📜',
    'Borrowers': '🤝',
    'EMIs': '💳',
    'Masters': '⚙️',
    'Balances': '💰',
    'Invoices': '🧾',
    'Hub': '🧩',
  };

  late final NavigatorObserver observer = _QuickNavObserver(this);

  String _currentScreen = 'Entry';
  String get currentScreen => _currentScreen;

  int _popupDepth = 0;
  bool get hasOpenPopup => _popupDepth > 0;

  bool _isQuickSheetOpen = false;
  bool get isQuickSheetOpen => _isQuickSheetOpen;

  final ValueNotifier<EntryDraft?> pendingEntryDraft = ValueNotifier<EntryDraft?>(null);
  final ValueNotifier<List<FinanceTransaction>?> pendingEditTransactions =
      ValueNotifier<List<FinanceTransaction>?>(null);

  void openEntryWithDraft(EntryDraft draft) {
    pendingEntryDraft.value = draft;
    navigateTo('Entry');
  }

  void requestEditTransactions(List<FinanceTransaction> transactions) {
    if (transactions.isEmpty) return;
    pendingEditTransactions.value = List<FinanceTransaction>.from(transactions);
    if (!switchShellTab('Entry')) {
      navigateTo('Entry');
    }
  }

  void Function(String label)? _rootNavigationHandler;
  bool Function(String label)? _shellTabHandler;

  void registerRootHandler(void Function(String label) handler) {
    _rootNavigationHandler = handler;
  }

  void unregisterRootHandler(void Function(String label) handler) {
    if (_rootNavigationHandler == handler) {
      _rootNavigationHandler = null;
    }
  }

  void registerShellTabHandler(bool Function(String label) handler) {
    _shellTabHandler = handler;
  }

  void unregisterShellTabHandler(bool Function(String label) handler) {
    if (_shellTabHandler == handler) {
      _shellTabHandler = null;
    }
  }

  void syncShellScreen(String label) {
    if (_currentScreen != label) {
      _currentScreen = label;
      notifyListeners();
    }
  }

  /// Switches the root MainShell tab to [label] without calling Navigator.popUntil.
  bool switchShellTab(String label) {
    if (_shellTabHandler != null && _shellTabHandler!(label)) {
      syncShellScreen(label);
      return true;
    }
    return false;
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

    // API Keys & Google Sheets are modal sheets/dialogs triggered on root without switching shell tabs.
    if (label == 'API Keys' || label == 'Google Sheets') {
      if (nav.canPop()) {
        nav.popUntil((route) => route.isFirst);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _rootNavigationHandler?.call(label);
        });
        WidgetsBinding.instance.scheduleFrame();
      } else {
        _rootNavigationHandler?.call(label);
      }
      return;
    }

    if (label == 'Entry') {
      nav.popUntil((route) => route.isFirst);
      _shellTabHandler?.call('Entry');
      _currentScreen = 'Entry';
      notifyListeners();
      return;
    }

    if (label == _currentScreen) return;

    final didPop = nav.canPop();
    nav.popUntil((route) => route.isFirst);

    if (_shellTabHandler != null && _shellTabHandler!(label)) {
      _currentScreen = label;
      notifyListeners();
      return;
    }

    _currentScreen = label;
    notifyListeners();
    if (didPop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rootNavigationHandler?.call(label);
      });
      WidgetsBinding.instance.scheduleFrame();
    } else {
      _rootNavigationHandler?.call(label);
    }
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
