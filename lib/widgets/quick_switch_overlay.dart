import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/quick_actions_service.dart';
import '../services/quick_nav_controller.dart';

/// Universal bottom floating pill and swipe-up Quick-Switch sheet rendered
/// above the Navigator so any screen is 1 gesture away.
class QuickSwitchOverlay extends StatelessWidget {
  final Widget child;

  const QuickSwitchOverlay({super.key, required this.child});

  static const List<List<Map<String, String>>> _menuRows = [
    [
      {'emoji': '📊', 'label': 'Dashboard'},
      {'emoji': '🔑', 'label': 'API Keys'},
    ],
    [
      {'emoji': '📜', 'label': 'History'},
      {'emoji': '🤝', 'label': 'Borrowers'},
    ],
    [
      {'emoji': '💳', 'label': 'EMIs'},
      {'emoji': '⚙️', 'label': 'Masters'},
    ],
    [
      {'emoji': '💰', 'label': 'Balances'},
      {'emoji': '🧾', 'label': 'Invoices'},
    ],
  ];

  void _openQuickSwitchSheet() {
    final navContext = QuickActionsService.instance.navigatorKey.currentContext;
    if (navContext == null) return;

    final controller = QuickNavController.instance;
    if (controller.isQuickSheetOpen) return;

    HapticFeedback.lightImpact();
    controller.setQuickSheetOpen(true);

    final isDark = Theme.of(navContext).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF151932) : Colors.white;
    final tileBg = isDark ? const Color(0xFF1E2448) : const Color(0xFFF8FAFC);
    final tileBorder = isDark ? const Color(0xFF2E376E) : const Color(0xFFE2E8F0);
    final accent = isDark ? const Color(0xFFA78BFA) : const Color(0xFFFF5C38);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final activeScreen = controller.currentScreen;

    showModalBottomSheet<void>(
      context: navContext,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        Widget buildTile(Map<String, String> item) {
          final label = item['label']!;
          final isActive = label == activeScreen;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (label == controller.currentScreen) {
                  Navigator.of(sheetCtx).pop();
                } else {
                  controller.navigateTo(label);
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isActive ? accent.withValues(alpha: isDark ? 0.2 : 0.1) : tileBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive ? accent : tileBorder,
                    width: isActive ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Text(item['emoji']!, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                          color: isActive ? accent : textPrimary,
                        ),
                      ),
                    ),
                    if (isActive)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        final isEntryActive = activeScreen == 'Entry';

        return Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(
              top: BorderSide(color: tileBorder, width: 1.2),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            MediaQuery.of(sheetCtx).padding.bottom + 14,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: textSecondary.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Quick Switch',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (isEntryActive) {
                          Navigator.of(sheetCtx).pop();
                        } else {
                          controller.navigateTo('Entry');
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isEntryActive
                              ? accent.withValues(alpha: isDark ? 0.2 : 0.12)
                              : tileBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isEntryActive ? accent : tileBorder,
                            width: isEntryActive ? 1.4 : 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('✨', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 6),
                            Text(
                              'Smart Entry',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: isEntryActive ? accent : textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < _menuRows.length; i++) ...[
                Row(
                  children: [
                    Expanded(child: buildTile(_menuRows[i][0])),
                    const SizedBox(width: 8),
                    Expanded(child: buildTile(_menuRows[i][1])),
                  ],
                ),
                if (i < _menuRows.length - 1) const SizedBox(height: 8),
              ],
              const SizedBox(height: 10),
              Text(
                'Tip: Flick the bottom pill left or right to cycle screens',
                style: TextStyle(fontSize: 11, color: textSecondary),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() => controller.setQuickSheetOpen(false));
  }

  @override
  Widget build(BuildContext context) {
    final controller = QuickNavController.instance;
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Stack(
      children: [
        child,
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final shouldHide =
                keyboardVisible || controller.hasOpenPopup || controller.isQuickSheetOpen;
            if (shouldHide) {
              return const SizedBox.shrink();
            }

            final isDark = Theme.of(context).brightness == Brightness.dark;
            final pillBg = isDark
                ? const Color(0xFF1B2042).withValues(alpha: 0.94)
                : Colors.white.withValues(alpha: 0.94);
            final borderColor = isDark ? const Color(0xFF36417A) : const Color(0xFFE2E8F0);
            final textColor = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);
            final mutedColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
            final current = controller.currentScreen;
            final emoji = QuickNavController.routeEmojis[current] ?? '✨';

            return Positioned(
              left: 0,
              right: 0,
              bottom: bottomPadding + 6,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: GestureDetector(
                    onTap: _openQuickSwitchSheet,
                    onVerticalDragEnd: (details) {
                      if ((details.primaryVelocity ?? 0) < -120) {
                        _openQuickSwitchSheet();
                      }
                    },
                    onHorizontalDragEnd: (details) {
                      final v = details.primaryVelocity ?? 0;
                      if (v < -180) {
                        controller.cycleScreen(1);
                      } else if (v > 180) {
                        controller.cycleScreen(-1);
                      }
                    },
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor, width: 1.1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chevron_left_rounded, size: 15, color: mutedColor),
                          const SizedBox(width: 4),
                          Text(emoji, style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 5),
                          Text(
                            current,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.keyboard_arrow_up_rounded, size: 15, color: mutedColor),
                          Icon(Icons.chevron_right_rounded, size: 15, color: mutedColor),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
