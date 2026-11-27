import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme_colors.dart';
import 'glass_surface.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/quick_actions_service.dart';
import '../services/quick_nav_controller.dart';

/// Sleek Android Smart-Sidebar style Side Edge Pill overlay:
/// - Vertical translucent pill docked on the right or left screen edge
/// - Tap or swipe inward to slide out a vertical dock of all 9 screens
/// - Drag vertically along the edge (or across to switch Left/Right side)
/// - Inverted Transparency slider (higher % = more transparent), Auto-Hide, and 5s Screenshot Hide
class QuickSwitchOverlay extends StatefulWidget {
  final Widget child;

  const QuickSwitchOverlay({super.key, required this.child});

  @override
  State<QuickSwitchOverlay> createState() => _QuickSwitchOverlayState();
}

class _QuickSwitchOverlayState extends State<QuickSwitchOverlay> {
  static const String _prefKeyY = 'quick_switch_edge_pill_y';
  static const String _prefKeyIsRight = 'quick_switch_edge_pill_right';
  static const String _prefKeyTransparency = 'quick_switch_edge_pill_transparency';
  static const String _prefKeyAutoHide = 'quick_switch_trackball_autohide';
  static const String _prefKeyOrder = 'quick_switch_dock_order';

  static const double _pillWidth = 22.0;
  static const double _pillHeight = 76.0;
  static const double _dockWidth = 72.0;

  static const List<Map<String, dynamic>> _dockItems = [
    {'emoji': '✍️', 'label': 'Entry', 'color': Color(0xFF6366F1)},
    {'emoji': '📜', 'label': 'History', 'color': Color(0xFF0EA5E9)},
    {'emoji': '💰', 'label': 'Balances', 'color': Color(0xFF10B981)},
    {'emoji': '📊', 'label': 'Dashboard', 'color': Color(0xFF8B5CF6)},
    {'emoji': '💳', 'label': 'EMIs', 'color': Color(0xFFF59E0B)},
    {'emoji': '🤝', 'label': 'Borrowers', 'color': Color(0xFFEC4899)},
    {'emoji': '🧾', 'label': 'Invoices', 'color': Color(0xFF14B8A6)},
    {'emoji': '⚙️', 'label': 'Masters', 'color': Color(0xFF64748B)},
    {'emoji': '🔑', 'label': 'API Keys', 'color': Color(0xFFEF4444)},
  ];

  double? _pillTop;
  bool _isRightEdge = true;
  final bool _isDragging = false;
  bool _isDockOpen = false;
  bool _isHoldSelecting = false;
  int? _hoveredDockIndex;

  List<String> _orderedLabels = _dockItems.map((e) => e['label'] as String).toList();
  final Map<int, GlobalKey> _dockItemKeys = {};

  List<Map<String, dynamic>> get _orderedDockItems {
    final byLabel = {for (final item in _dockItems) item['label'] as String: item};
    final result = <Map<String, dynamic>>[];
    for (final label in _orderedLabels) {
      final item = byLabel[label];
      if (item != null) result.add(item);
    }
    for (final item in _dockItems) {
      if (!result.any((r) => r['label'] == item['label'])) {
        result.add(item);
      }
    }
    return result;
  }

  // Customization state: higher transparency => lower opacity
  double _transparency = 0.55;
  bool _autoHide = false;

  // Auto-hide & screenshot hide timers
  bool _isIdleFaded = false;
  Timer? _idleTimer;
  bool _hiddenForScreenshot = false;
  Timer? _screenshotHideTimer;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _screenshotHideTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final y = prefs.getDouble(_prefKeyY);
      final isRight = prefs.getBool(_prefKeyIsRight);
      final trans = prefs.getDouble(_prefKeyTransparency);
      final autoHide = prefs.getBool(_prefKeyAutoHide);
      final order = prefs.getStringList(_prefKeyOrder);

      if (!mounted) return;
      setState(() {
        if (y != null) _pillTop = y;
        if (isRight != null) _isRightEdge = isRight;
        if (trans != null) _transparency = trans.clamp(0.10, 0.90);
        if (autoHide != null) _autoHide = autoHide;
        if (order != null && order.isNotEmpty) _orderedLabels = order;
      });
      _resetIdleTimer();
    } catch (_) {}
  }

  Future<void> _saveCustomization() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefKeyTransparency, _transparency);
      await prefs.setBool(_prefKeyAutoHide, _autoHide);
      await prefs.setBool(_prefKeyIsRight, _isRightEdge);
      await prefs.setStringList(_prefKeyOrder, _orderedLabels);
    } catch (_) {}
  }

  void _updateHoveredDockIndex(Offset globalPos) {
    final items = _orderedDockItems;
    int? hit;
    for (int i = 0; i < items.length; i++) {
      final key = _dockItemKeys[i];
      final ctx = key?.currentContext;
      if (ctx == null) continue;
      final ro = ctx.findRenderObject();
      if (ro is RenderBox && ro.hasSize) {
        final topLeft = ro.localToGlobal(Offset.zero);
        if (globalPos.dy >= topLeft.dy && globalPos.dy <= topLeft.dy + ro.size.height) {
          hit = i;
          break;
        }
      }
    }
    if (hit != _hoveredDockIndex) {
      if (hit != null) {
        HapticFeedback.selectionClick();
      }
      setState(() => _hoveredDockIndex = hit);
    }
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_isIdleFaded && mounted) {
      setState(() => _isIdleFaded = false);
    }
    if (_autoHide) {
      _idleTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _autoHide && !_isDragging && !_isDockOpen) {
          setState(() => _isIdleFaded = true);
        }
      });
    }
  }

  void _hideTemporarilyForScreenshot() {
    _screenshotHideTimer?.cancel();
    setState(() {
      _isDockOpen = false;
      _hiddenForScreenshot = true;
    });
    _screenshotHideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _hiddenForScreenshot = false);
        _resetIdleTimer();
      }
    });
  }

  double _clampTop(double rawTop, Size screenSize, EdgeInsets padding) {
    final minY = padding.top + 60.0;
    final maxY = (screenSize.height - padding.bottom - _pillHeight - 60.0)
        .clamp(minY, double.infinity);
    return rawTop.clamp(minY, maxY);
  }

  void _navigateTo(String label) {
    _resetIdleTimer();
    setState(() => _isDockOpen = false);
    QuickNavController.instance.navigateTo(label);
  }

  void _openCustomizeSheet() {
    final navContext = QuickActionsService.instance.navigatorKey.currentContext;
    if (navContext == null) return;

    final controller = QuickNavController.instance;
    if (controller.isQuickSheetOpen) return;

    HapticFeedback.lightImpact();
    controller.setQuickSheetOpen(true);

    final isDark = Theme.of(navContext).brightness == Brightness.dark;
    final colors = AppThemeColors.of(navContext);
    final sheetBg = colors.glassSurfaceTop;
    final tileBg = colors.inputBg;
    final tileBorder = colors.inputBorder;
    final accent = isDark ? colors.purpleAccent : colors.primaryGradStart;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    showModalBottomSheet<void>(
      context: navContext,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return GlassContainer(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              borderColor: tileBorder,
              blurSigma: 20,
              gradientColors: [
                sheetBg,
                colors.glassSurfaceBottom.withValues(alpha: isDark ? 0.88 : 0.92),
              ],
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                MediaQuery.of(sheetCtx).padding.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: textSecondary.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.view_sidebar_rounded, size: 18, color: accent),
                      const SizedBox(width: 8),
                      Text(
                        'Side Pill Settings',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          _hideTemporarilyForScreenshot();
                        },
                        icon: Icon(Icons.screenshot_rounded, size: 15, color: accent),
                        label: Text(
                          'Hide 5s',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accent),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Transparency Slider (higher % = more transparent)
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    decoration: BoxDecoration(
                      color: tileBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tileBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Transparency',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                            Text(
                              '${(_transparency * 100).round()}%',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _transparency,
                          min: 0.10,
                          max: 0.90,
                          activeColor: accent,
                          onChanged: (val) {
                            setSheetState(() => _transparency = val);
                            setState(() => _transparency = val);
                          },
                          onChangeEnd: (_) => unawaited(_saveCustomization()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Screen Edge Switcher
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: tileBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tileBorder),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Edge Side',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
                        ),
                        const Spacer(),
                        ChoiceChip(
                          label: const Text('Left'),
                          selected: !_isRightEdge,
                          onSelected: (_) {
                            setSheetState(() => _isRightEdge = false);
                            setState(() => _isRightEdge = false);
                            unawaited(_saveCustomization());
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Right'),
                          selected: _isRightEdge,
                          onSelected: (_) {
                            setSheetState(() => _isRightEdge = true);
                            setState(() => _isRightEdge = true);
                            unawaited(_saveCustomization());
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Auto-Hide Toggle
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: tileBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tileBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Auto-Hide When Idle',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                              ),
                              Text(
                                'Fades out after 3s of inactivity',
                                style: TextStyle(fontSize: 11, color: textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _autoHide,
                          activeThumbColor: accent,
                          onChanged: (val) {
                            setSheetState(() => _autoHide = val);
                            setState(() {
                              _autoHide = val;
                              if (!val) _isIdleFaded = false;
                            });
                            _resetIdleTimer();
                            unawaited(_saveCustomization());
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Reorder Menu Items
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    decoration: BoxDecoration(
                      color: tileBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tileBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reorder Side Pill Menu',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 180,
                          child: ReorderableListView.builder(
                            buildDefaultDragHandles: false,
                            proxyDecorator: (child, index, animation) => Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              elevation: 4,
                              child: child,
                            ),
                            itemCount: _orderedDockItems.length,
                            onReorderItem: (oldIndex, newIndex) {
                              final items = _orderedDockItems.map((e) => e['label'] as String).toList();
                              final moved = items.removeAt(oldIndex);
                              items.insert(newIndex, moved);
                              setSheetState(() => _orderedLabels = items);
                              setState(() => _orderedLabels = items);
                              unawaited(_saveCustomization());
                            },
                            itemBuilder: (ctx, i) {
                              final item = _orderedDockItems[i];
                              final lbl = item['label'] as String;
                              final emj = item['emoji'] as String;
                              return Container(
                                key: ValueKey('dock_order_$lbl'),
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF151932) : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: tileBorder),
                                ),
                                child: Row(
                                  children: [
                                    Text(emj, style: const TextStyle(fontSize: 15)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        lbl,
                                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: textPrimary),
                                      ),
                                    ),
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: Icon(Icons.drag_handle_rounded, size: 18, color: textSecondary),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tip: Tap or swipe inward to open • Hold & slide on the pill to quick-pick a screen',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: textSecondary),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      controller.setQuickSheetOpen(false);
      _resetIdleTimer();
    });
  }

  Widget _buildSideDock(
    BuildContext context,
    QuickNavController controller,
    Size screenSize,
    EdgeInsets padding,
    bool isDark,
    Color accent,
  ) {
    final colors = AppThemeColors.of(context);
    final dockBg = colors.glassSurfaceTop;
    final tileBg = colors.inputBg;
    final borderColor = colors.inputBorder;
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final maxDockHeight = (screenSize.height - padding.top - padding.bottom - 36).clamp(240.0, 620.0);

    return Positioned(
      right: _isRightEdge ? 10.0 : null,
      left: _isRightEdge ? null : 10.0,
      top: padding.top + 18.0,
      bottom: padding.bottom + 18.0,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.90, end: 1.0),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          builder: (context, val, child) {
            return Transform.translate(
              offset: Offset((_isRightEdge ? 1 : -1) * (1.0 - val) * 24, 0),
              child: Opacity(
                opacity: ((val - 0.90) / 0.10).clamp(0.0, 1.0),
                child: child,
              ),
            );
          },
          child: Material(
            key: const Key('quick_switch_side_dock'),
            type: MaterialType.transparency,
            child: GlassContainer(
              width: _dockWidth,
              constraints: BoxConstraints(maxHeight: maxDockHeight),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              borderRadius: BorderRadius.circular(26),
              blurSigma: 22,
              borderColor: borderColor,
              gradientColors: [
                dockBg.withValues(alpha: 0.92),
                colors.glassSurfaceBottom.withValues(alpha: 0.84),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: GestureDetector(
                      onVerticalDragStart: (details) {
                        setState(() => _isHoldSelecting = true);
                        _updateHoveredDockIndex(details.globalPosition);
                      },
                      onVerticalDragUpdate: (details) {
                        if (_isHoldSelecting) {
                          _updateHoveredDockIndex(details.globalPosition);
                        }
                      },
                      onVerticalDragEnd: (_) {
                        final chosen = _hoveredDockIndex;
                        final items = _orderedDockItems;
                        setState(() {
                          _isHoldSelecting = false;
                          _hoveredDockIndex = null;
                        });
                        if (chosen != null && chosen >= 0 && chosen < items.length) {
                          _navigateTo(items[chosen]['label'] as String);
                        }
                      },
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: _orderedDockItems.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final item = entry.value;
                            final label = item['label'] as String;
                            final emoji = item['emoji'] as String;
                            final color = item['color'] as Color;
                            final isActive = controller.currentScreen == label;
                            final isHovered = _isHoldSelecting && _hoveredDockIndex == idx;
                            final itemKey = _dockItemKeys.putIfAbsent(idx, () => GlobalKey());
                            return Padding(
                              key: itemKey,
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Tooltip(
                                message: label,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _navigateTo(label),
                                  child: AnimatedScale(
                                    scale: isHovered ? 1.14 : 1.0,
                                    duration: const Duration(milliseconds: 90),
                                    child: Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: (isActive || isHovered) ? accent : tileBg,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: (isActive || isHovered) ? Colors.white : color.withValues(alpha: 0.35),
                                          width: (isActive || isHovered) ? 1.8 : 1.0,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          emoji,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                  Divider(height: 12, color: borderColor),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _hideTemporarilyForScreenshot,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.visibility_off_outlined, size: 18, color: textSecondary),
                        ),
                      ),
                      InkWell(
                        key: const Key('quick_switch_menu_settings_btn'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          setState(() => _isDockOpen = false);
                          _openCustomizeSheet();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.tune_rounded, size: 18, color: accent),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = QuickNavController.instance;
    final mq = MediaQuery.of(context);
    final keyboardVisible = mq.viewInsets.bottom > 0;
    final screenSize = mq.size;
    final padding = mq.padding;

    final defaultTop = screenSize.height * 0.34;
    final effectiveTop = _clampTop(_pillTop ?? defaultTop, screenSize, padding);

    return Stack(
      children: [
        widget.child,
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final shouldHide = keyboardVisible ||
                controller.hasOpenPopup ||
                controller.isQuickSheetOpen ||
                _hiddenForScreenshot;
            if (shouldHide) {
              return const SizedBox.shrink();
            }

            final isDark = Theme.of(context).brightness == Brightness.dark;
            final accent = isDark ? const Color(0xFFA78BFA) : const Color(0xFFFF5C38);
            final pillBg = isDark ? const Color(0xFF151932) : Colors.white;
            final borderColor = _isDragging || _isDockOpen
                ? accent
                : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1));
            final baseOpacity = (1.0 - _transparency).clamp(0.10, 0.90);
            final displayOpacity = _isDragging || _isDockOpen
                ? 0.95
                : (_isIdleFaded && _autoHide ? 0.12 : baseOpacity);

            return Stack(
              children: [
                if (_isDockOpen) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => setState(() => _isDockOpen = false),
                      child: Container(
                        color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                      ),
                    ),
                  ),
                  _buildSideDock(context, controller, screenSize, padding, isDark, accent),
                ],
                Positioned(
                  right: _isRightEdge ? 0 : null,
                  left: _isRightEdge ? null : 0,
                  top: effectiveTop,
                  child: IgnorePointer(
                    ignoring: _isDockOpen && !_isHoldSelecting,
                    child: Material(
                      color: Colors.transparent,
                      child: AnimatedOpacity(
                        opacity: _isDockOpen ? 0.0 : displayOpacity,
                        duration: const Duration(milliseconds: 180),
                        child: GestureDetector(
                          key: const Key('quick_switch_trackball'),
                          onTap: () {
                            _resetIdleTimer();
                            HapticFeedback.selectionClick();
                            setState(() => _isDockOpen = true);
                          },
                          onLongPressStart: (details) {
                            _resetIdleTimer();
                            HapticFeedback.mediumImpact();
                            setState(() {
                              _isDockOpen = true;
                              _isHoldSelecting = true;
                            });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && _isHoldSelecting) {
                                _updateHoveredDockIndex(details.globalPosition);
                              }
                            });
                          },
                          onLongPressMoveUpdate: (details) {
                            if (_isHoldSelecting) {
                              _updateHoveredDockIndex(details.globalPosition);
                            }
                          },
                          onLongPressEnd: (_) {
                            final chosen = _hoveredDockIndex;
                            final items = _orderedDockItems;
                            setState(() {
                              _isHoldSelecting = false;
                              _hoveredDockIndex = null;
                            });
                            if (chosen != null && chosen >= 0 && chosen < items.length) {
                              _navigateTo(items[chosen]['label'] as String);
                            } else {
                              setState(() => _isDockOpen = false);
                            }
                            _resetIdleTimer();
                          },
                          onLongPressCancel: () {
                            setState(() {
                              _isHoldSelecting = false;
                              _hoveredDockIndex = null;
                            });
                          },
                          child: ClipRRect(
                            borderRadius: _isRightEdge
                                ? const BorderRadius.horizontal(left: Radius.circular(14))
                                : const BorderRadius.horizontal(right: Radius.circular(14)),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                              child: Container(
                                width: _pillWidth,
                                height: _pillHeight,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      pillBg.withValues(alpha: isDark ? 0.84 : 0.90),
                                      (isDark ? const Color(0xFF0E1330) : const Color(0xFFFFF1EC))
                                          .withValues(alpha: 0.80),
                                    ],
                                  ),
                                  borderRadius: _isRightEdge
                                      ? const BorderRadius.horizontal(left: Radius.circular(14))
                                      : const BorderRadius.horizontal(right: Radius.circular(14)),
                                  border: Border.all(
                                    color: _isDragging ? accent : borderColor,
                                    width: _isDragging ? 1.8 : 1.1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (isDark ? accent : Colors.black)
                                          .withValues(alpha: isDark ? 0.30 : 0.14),
                                      blurRadius: 10,
                                      offset: Offset(_isRightEdge ? -2 : 2, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Container(
                                    width: 4,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          accent,
                                          AppThemeColors.of(context).primaryGradEnd,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
