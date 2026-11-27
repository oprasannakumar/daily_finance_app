import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/quick_nav_controller.dart';
import '../theme/app_theme_colors.dart';
import 'account_balances_screen.dart';
import 'borrowers_ledger_screen.dart';
import 'transaction_form_screen.dart';
import 'transaction_history_screen.dart';
import 'workspace_hub_screen.dart';

/// Root multi-workspace shell featuring a floating frosted-glass bottom capsule dock
/// for instant 1-tap switching across Entry, History, Balances, Borrowers, and Command Hub.
class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  static const List<String> _tabLabels = [
    'Entry',
    'History',
    'Balances',
    'Borrowers',
    'Hub',
  ];

  int _currentIndex = 0;
  final Set<int> _visitedTabs = {0};
  final List<int> _tabHistory = [0];
  final ValueNotifier<int> _historyRefreshNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    QuickNavController.instance.registerShellTabHandler(_handleShellTabRequest);
  }

  @override
  void dispose() {
    QuickNavController.instance.unregisterShellTabHandler(_handleShellTabRequest);
    _historyRefreshNotifier.dispose();
    super.dispose();
  }

  void _pushTabHistory(int idx) {
    if (_tabHistory.isEmpty || _tabHistory.last != idx) {
      _tabHistory.add(idx);
      if (_tabHistory.length > 20) {
        _tabHistory.removeAt(0);
      }
    }
  }

  bool _handleShellTabRequest(String label) {
    final idx = _tabLabels.indexOf(label);
    if (idx == -1) return false;
    if (mounted) {
      setState(() {
        _currentIndex = idx;
        _visitedTabs.add(idx);
        _pushTabHistory(idx);
      });
    }
    return true;
  }

  void _selectTab(int idx) {
    HapticFeedback.selectionClick();
    if (_currentIndex != idx) {
      setState(() {
        _currentIndex = idx;
        _visitedTabs.add(idx);
        _pushTabHistory(idx);
      });
      QuickNavController.instance.syncShellScreen(_tabLabels[idx]);
    }
  }

  void _handleBackNavigation() {
    HapticFeedback.selectionClick();
    if (_tabHistory.length > 1) {
      setState(() {
        _tabHistory.removeLast();
        final prevIdx = _tabHistory.last;
        _currentIndex = prevIdx;
        _visitedTabs.add(prevIdx);
      });
      QuickNavController.instance.syncShellScreen(_tabLabels[_currentIndex]);
    } else if (_currentIndex != 0) {
      setState(() {
        _currentIndex = 0;
        _tabHistory
          ..clear()
          ..add(0);
      });
      QuickNavController.instance.syncShellScreen(_tabLabels[0]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isKeyboardOpen = mq.viewInsets.bottom > 80;
    const dockHeight = 64.0;
    final bottomPad = dockHeight + 24.0;

    return PopScope(
      canPop: _currentIndex == 0 && _tabHistory.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Stack(
        children: [
        IndexedStack(
          index: _currentIndex,
          children: [
            TransactionFormScreen(
              bottomContentPadding: bottomPad,
              onTransactionSaved: () => _historyRefreshNotifier.value++,
            ),
            _visitedTabs.contains(1)
                ? TransactionHistoryScreen(
                    refreshListenable: _historyRefreshNotifier,
                    bottomContentPadding: bottomPad,
                  )
                : const SizedBox.shrink(),
            _visitedTabs.contains(2)
                ? AccountBalancesScreen(bottomContentPadding: bottomPad)
                : const SizedBox.shrink(),
            _visitedTabs.contains(3)
                ? BorrowersLedgerScreen(bottomContentPadding: bottomPad)
                : const SizedBox.shrink(),
            _visitedTabs.contains(4)
                ? WorkspaceHubScreen(bottomContentPadding: bottomPad)
                : const SizedBox.shrink(),
          ],
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: 16,
          right: 16,
          bottom: isKeyboardOpen ? -100 : (mq.padding.bottom + 10),
          child: IgnorePointer(
            ignoring: isKeyboardOpen,
            child: _FloatingGlassDock(
              currentIndex: _currentIndex,
              onSelect: _selectTab,
            ),
          ),
        ),
      ],
      ),
    );
  }
}

class _FloatingGlassDock extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const _FloatingGlassDock({
    required this.currentIndex,
    required this.onSelect,
  });

  static const List<({String label, IconData icon, IconData activeIcon})> _items = [
    (label: 'Entry', icon: Icons.add_circle_outline_rounded, activeIcon: Icons.add_circle_rounded),
    (label: 'History', icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long_rounded),
    (label: 'Wallet', icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet_rounded),
    (label: 'People', icon: Icons.people_outline_rounded, activeIcon: Icons.people_rounded),
    (label: 'Hub', icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppThemeColors.of(context);

    return Container(
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.55)
                : colors.heroGradStart.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xE0171E42), const Color(0xCC0D122C)]
                    : [const Color(0xEBFFFFFF), const Color(0xDDF8FAFF)],
              ),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.95),
                width: 1.3,
              ),
            ),
            child: Row(
              children: List.generate(_items.length, (i) {
                final item = _items[i];
                final active = i == currentIndex;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: active ? colors.primaryGradient : null,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: colors.primaryGradStart.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            active ? item.activeIcon : item.icon,
                            size: active ? 21 : 20,
                            color: active
                                ? Colors.white
                                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                              color: active
                                  ? Colors.white
                                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
