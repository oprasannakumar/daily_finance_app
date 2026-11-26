import 'dart:async';
import 'package:flutter/material.dart';
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

  static const double _pillWidth = 22.0;
  static const double _pillHeight = 76.0;
  static const double _dockWidth = 104.0;

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
  bool _isDragging = false;
  bool _isDockOpen = false;

  // Customization state: higher transparency => lower opacity
  double _transparency = 0.55;
  bool _autoHide = false;

  // Auto-hide & screenshot hide timers
  bool _isIdleFaded = false;
  Timer? _idleTimer;
  bool _hiddenForScreenshot = false;
  Timer? _screenshotHideTimer;

  // Drag / inward swipe tracking
  Offset? _dragStartPos;
  bool _swipedInward = false;

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

      if (!mounted) return;
      setState(() {
        if (y != null) _pillTop = y;
        if (isRight != null) _isRightEdge = isRight;
        if (trans != null) _transparency = trans.clamp(0.10, 0.90);
        if (autoHide != null) _autoHide = autoHide;
      });
      _resetIdleTimer();
    } catch (_) {}
  }

  Future<void> _savePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_pillTop != null) await prefs.setDouble(_prefKeyY, _pillTop!);
      await prefs.setBool(_prefKeyIsRight, _isRightEdge);
    } catch (_) {}
  }

  Future<void> _saveCustomization() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefKeyTransparency, _transparency);
      await prefs.setBool(_prefKeyAutoHide, _autoHide);
      await prefs.setBool(_prefKeyIsRight, _isRightEdge);
    } catch (_) {}
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
    final sheetBg = isDark ? const Color(0xFF151932) : Colors.white;
    final tileBg = isDark ? const Color(0xFF1E2448) : const Color(0xFFF8FAFC);
    final tileBorder = isDark ? const Color(0xFF2E376E) : const Color(0xFFE2E8F0);
    final accent = isDark ? const Color(0xFFA78BFA) : const Color(0xFFFF5C38);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    showModalBottomSheet<void>(
      context: navContext,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                border: Border(top: BorderSide(color: tileBorder, width: 1.2)),
              ),
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
                  Text(
                    'Tip: Tap or swipe inward on the side pill to open the sidebar • Hold & drag up/down to move',
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
    final dockBg = isDark ? const Color(0xFF151932) : Colors.white;
    final tileBg = isDark ? const Color(0xFF1E2448) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF2E376E) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
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
            child: Container(
              width: _dockWidth,
              constraints: BoxConstraints(maxHeight: maxDockHeight),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                color: dockBg.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: borderColor, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _dockItems.map((item) {
                          final label = item['label'] as String;
                          final emoji = item['emoji'] as String;
                          final color = item['color'] as Color;
                          final isActive = controller.currentScreen == label;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _navigateTo(label),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: isActive ? accent : tileBg,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isActive ? Colors.white : color.withValues(alpha: 0.35),
                                        width: isActive ? 1.6 : 1.0,
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
                                  const SizedBox(height: 3),
                                  Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                                      color: isActive ? accent : textPrimary,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
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
                if (!_isDockOpen)
                  Positioned(
                    right: _isRightEdge ? 0 : null,
                    left: _isRightEdge ? null : 0,
                    top: effectiveTop,
                    child: Material(
                      color: Colors.transparent,
                      child: AnimatedOpacity(
                        opacity: displayOpacity,
                        duration: const Duration(milliseconds: 220),
                        child: GestureDetector(
                          key: const Key('quick_switch_trackball'),
                          onTap: () {
                            _resetIdleTimer();
                            HapticFeedback.selectionClick();
                            setState(() => _isDockOpen = true);
                          },
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            _openCustomizeSheet();
                          },
                          onPanStart: (details) {
                            _dragStartPos = details.globalPosition;
                            _swipedInward = false;
                            _resetIdleTimer();
                          },
                          onPanUpdate: (details) {
                            final start = _dragStartPos;
                            if (start != null && !_isDragging && !_swipedInward) {
                              final dx = details.globalPosition.dx - start.dx;
                              final dy = (details.globalPosition.dy - start.dy).abs();
                              final inwardSwipe = _isRightEdge ? dx < -18.0 : dx > 18.0;
                              if (inwardSwipe && dx.abs() > dy) {
                                _swipedInward = true;
                                HapticFeedback.selectionClick();
                                setState(() => _isDockOpen = true);
                                return;
                              }
                            }
                            if (!_swipedInward) {
                              setState(() {
                                _isDragging = true;
                                _pillTop = _clampTop(
                                  (_pillTop ?? effectiveTop) + details.delta.dy,
                                  screenSize,
                                  padding,
                                );
                                if (details.globalPosition.dx < screenSize.width * 0.25) {
                                  _isRightEdge = false;
                                } else if (details.globalPosition.dx > screenSize.width * 0.75) {
                                  _isRightEdge = true;
                                }
                              });
                            }
                          },
                          onPanEnd: (_) {
                            _dragStartPos = null;
                            _swipedInward = false;
                            if (_isDragging) {
                              setState(() => _isDragging = false);
                              unawaited(_savePosition());
                            }
                            _resetIdleTimer();
                          },
                          onPanCancel: () {
                            _dragStartPos = null;
                            _swipedInward = false;
                            if (_isDragging) {
                              setState(() => _isDragging = false);
                            }
                            _resetIdleTimer();
                          },
                          child: Container(
                            width: _pillWidth,
                            height: _pillHeight,
                            decoration: BoxDecoration(
                              color: pillBg,
                              borderRadius: _isRightEdge
                                  ? const BorderRadius.horizontal(left: Radius.circular(14))
                                  : const BorderRadius.horizontal(right: Radius.circular(14)),
                              border: Border.all(
                                color: borderColor,
                                width: _isDragging ? 1.8 : 1.1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.14),
                                  blurRadius: 8,
                                  offset: Offset(_isRightEdge ? -2 : 2, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Container(
                                width: 4,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(4),
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
