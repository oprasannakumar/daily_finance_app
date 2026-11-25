import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/quick_actions_service.dart';
import '../services/quick_nav_controller.dart';

/// Universal movable floating trackball and Quick-Switch sheet rendered
/// above the Navigator so any screen is 1 tap away from anywhere.
class QuickSwitchOverlay extends StatefulWidget {
  final Widget child;

  const QuickSwitchOverlay({super.key, required this.child});

  @override
  State<QuickSwitchOverlay> createState() => _QuickSwitchOverlayState();
}

class _QuickSwitchOverlayState extends State<QuickSwitchOverlay> {
  static const String _prefKeyX = 'quick_switch_trackball_x';
  static const String _prefKeyY = 'quick_switch_trackball_y';
  static const double _ballSize = 46.0;

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

  Offset? _position;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _loadSavedPosition();
  }

  Future<void> _loadSavedPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble(_prefKeyX);
      final y = prefs.getDouble(_prefKeyY);
      if (x != null && y != null && mounted) {
        setState(() {
          _position = Offset(x, y);
        });
      }
    } catch (_) {}
  }

  Future<void> _savePosition(Offset pos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefKeyX, pos.dx);
      await prefs.setDouble(_prefKeyY, pos.dy);
    } catch (_) {}
  }

  Offset _clampPosition(Offset raw, Size screenSize, EdgeInsets padding) {
    final minX = 8.0;
    final maxX = (screenSize.width - _ballSize - 8.0).clamp(minX, double.infinity);
    final minY = padding.top + 8.0;
    final maxY = (screenSize.height - padding.bottom - _ballSize - 8.0).clamp(minY, double.infinity);
    return Offset(
      raw.dx.clamp(minX, maxX),
      raw.dy.clamp(minY, maxY),
    );
  }

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
                'Tip: Drag trackball anywhere • Long-press to jump Entry ↔ History',
                textAlign: TextAlign.center,
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
    final mq = MediaQuery.of(context);
    final keyboardVisible = mq.viewInsets.bottom > 0;
    final screenSize = mq.size;
    final padding = mq.padding;

    final defaultPos = Offset(
      screenSize.width - _ballSize - 14.0,
      screenSize.height - padding.bottom - _ballSize - 70.0,
    );
    final effectivePos = _clampPosition(_position ?? defaultPos, screenSize, padding);

    return Stack(
      children: [
        widget.child,
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final shouldHide =
                keyboardVisible || controller.hasOpenPopup || controller.isQuickSheetOpen;
            if (shouldHide) {
              return const SizedBox.shrink();
            }

            final isDark = Theme.of(context).brightness == Brightness.dark;
            final accent = isDark ? const Color(0xFFA78BFA) : const Color(0xFFFF5C38);
            final outerBg = isDark
                ? const Color(0xFF151932).withValues(alpha: 0.90)
                : Colors.white.withValues(alpha: 0.92);
            final innerBg = isDark
                ? const Color(0xFF232A54)
                : const Color(0xFFFFF3EE);
            final borderColor = _isDragging
                ? accent
                : (isDark ? const Color(0xFF3E498A) : const Color(0xFFE2E8F0));
            final current = controller.currentScreen;
            final emoji = QuickNavController.routeEmojis[current] ?? '✨';

            return Positioned(
              left: effectivePos.dx,
              top: effectivePos.dy,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  key: const Key('quick_switch_trackball'),
                  onTap: _openQuickSwitchSheet,
                  onLongPress: () {
                    HapticFeedback.mediumImpact();
                    if (controller.currentScreen == 'Entry') {
                      controller.navigateTo('History');
                    } else {
                      controller.navigateTo('Entry');
                    }
                  },
                  onPanStart: (_) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _isDragging = true;
                      _position ??= effectivePos;
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      final next = (_position ?? effectivePos) + details.delta;
                      _position = _clampPosition(next, screenSize, padding);
                    });
                  },
                  onPanEnd: (_) {
                    setState(() => _isDragging = false);
                    if (_position != null) {
                      unawaited(_savePosition(_position!));
                    }
                  },
                  child: AnimatedScale(
                    scale: _isDragging ? 1.12 : 1.0,
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      width: _ballSize,
                      height: _ballSize,
                      decoration: BoxDecoration(
                        color: outerBg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: borderColor,
                          width: _isDragging ? 2.0 : 1.3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
                            blurRadius: _isDragging ? 16 : 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: innerBg,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: accent.withValues(alpha: 0.45),
                              width: 1.0,
                            ),
                          ),
                          child: Center(
                            child: Text(emoji, style: const TextStyle(fontSize: 14)),
                          ),
                        ),
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
