import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/quick_actions_service.dart';
import '../services/quick_nav_controller.dart';

/// Universal movable translucent trackball with:
/// - Hold & swipe radial gesture selector (8 screens around the ball)
/// - Configurable Single-Tap, Double-Tap, Auto-Hide, and Transparency
/// - 5-second Screenshot Hide mode
class QuickSwitchOverlay extends StatefulWidget {
  final Widget child;

  const QuickSwitchOverlay({super.key, required this.child});

  @override
  State<QuickSwitchOverlay> createState() => _QuickSwitchOverlayState();
}

class _QuickSwitchOverlayState extends State<QuickSwitchOverlay> {
  static const String _prefKeyX = 'quick_switch_trackball_x';
  static const String _prefKeyY = 'quick_switch_trackball_y';
  static const String _prefKeyOpacity = 'quick_switch_trackball_opacity';
  static const String _prefKeyAutoHide = 'quick_switch_trackball_autohide';
  static const String _prefKeySingleTap = 'quick_switch_trackball_single_tap';
  static const String _prefKeyDoubleTap = 'quick_switch_trackball_double_tap';

  static const double _ballSize = 46.0;
  static const double _radialRadius = 66.0;

  static const List<Map<String, String>> _radialItems = [
    {'emoji': '📊', 'label': 'Dashboard'},
    {'emoji': '🔑', 'label': 'API Keys'},
    {'emoji': '🤝', 'label': 'Borrowers'},
    {'emoji': '💳', 'label': 'EMIs'},
    {'emoji': '⚙️', 'label': 'Masters'},
    {'emoji': '💰', 'label': 'Balances'},
    {'emoji': '🧾', 'label': 'Invoices'},
  ];

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

  static const List<String> _actionOptions = [
    'Quick-Switch Menu',
    'Entry ↔ History',
    'Entry',
    'History',
    'Balances',
    'EMIs',
    'Dashboard',
    'Borrowers',
    'Invoices',
    'Masters',
    'API Keys',
    'None',
  ];

  Offset? _position;
  bool _isDragging = false;

  // Customization state
  double _opacity = 0.40;
  bool _autoHide = false;
  String _singleTapAction = 'Quick-Switch Menu';
  String _doubleTapAction = 'None';

  // Auto-hide & screenshot hide timers
  bool _isIdleFaded = false;
  Timer? _idleTimer;
  bool _hiddenForScreenshot = false;
  Timer? _screenshotHideTimer;

  // Radial gesture & pointer state
  bool _isRadialOpen = false;
  Offset _radialOrigin = Offset.zero;
  int? _selectedRadialIndex;
  Timer? _holdTimer;
  Offset? _pointerDownPos;
  Offset? _lastPointerPos;
  int? _activePointerId;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _screenshotHideTimer?.cancel();
    _holdTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble(_prefKeyX);
      final y = prefs.getDouble(_prefKeyY);
      final opacity = prefs.getDouble(_prefKeyOpacity);
      final autoHide = prefs.getBool(_prefKeyAutoHide);
      final singleTap = prefs.getString(_prefKeySingleTap);
      final doubleTap = prefs.getString(_prefKeyDoubleTap);

      if (!mounted) return;
      setState(() {
        if (x != null && y != null) _position = Offset(x, y);
        if (opacity != null) _opacity = opacity.clamp(0.15, 0.95);
        if (autoHide != null) _autoHide = autoHide;
        if (singleTap != null && _actionOptions.contains(singleTap)) {
          _singleTapAction = singleTap;
        }
        if (doubleTap != null && _actionOptions.contains(doubleTap)) {
          _doubleTapAction = doubleTap;
        }
      });
      _resetIdleTimer();
    } catch (_) {}
  }

  Future<void> _savePosition(Offset pos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefKeyX, pos.dx);
      await prefs.setDouble(_prefKeyY, pos.dy);
    } catch (_) {}
  }

  Future<void> _saveCustomization() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefKeyOpacity, _opacity);
      await prefs.setBool(_prefKeyAutoHide, _autoHide);
      await prefs.setString(_prefKeySingleTap, _singleTapAction);
      await prefs.setString(_prefKeyDoubleTap, _doubleTapAction);
    } catch (_) {}
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_isIdleFaded && mounted) {
      setState(() => _isIdleFaded = false);
    }
    if (_autoHide) {
      _idleTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _autoHide && !_isDragging && !_isRadialOpen) {
          setState(() => _isIdleFaded = true);
        }
      });
    }
  }

  void _hideTemporarilyForScreenshot() {
    _screenshotHideTimer?.cancel();
    setState(() => _hiddenForScreenshot = true);
    _screenshotHideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _hiddenForScreenshot = false);
        _resetIdleTimer();
      }
    });
  }

  Offset _clampPosition(Offset raw, Size screenSize, EdgeInsets padding) {
    const minX = 8.0;
    final maxX = (screenSize.width - _ballSize - 8.0).clamp(minX, double.infinity);
    final minY = padding.top + 8.0;
    final maxY = (screenSize.height - padding.bottom - _ballSize - 8.0).clamp(minY, double.infinity);
    return Offset(
      raw.dx.clamp(minX, maxX),
      raw.dy.clamp(minY, maxY),
    );
  }

  void _executeAction(String action) {
    _resetIdleTimer();
    final controller = QuickNavController.instance;
    switch (action) {
      case 'None':
        return;
      case 'Quick-Switch Menu':
        _openQuickSwitchSheet();
        return;
      case 'Entry ↔ History':
        HapticFeedback.selectionClick();
        if (controller.currentScreen == 'Entry') {
          controller.navigateTo('History');
        } else {
          controller.navigateTo('Entry');
        }
        return;
      default:
        controller.navigateTo(action);
        return;
    }
  }

  List<Offset> _computeRadialPositions(Offset ballCenter, Size screenSize, EdgeInsets padding) {
    const double safeMargin = 10.0;
    const double iconHalf = 22.0; // half of selected 44px orb
    final double minX = safeMargin + iconHalf;
    final double maxX = (screenSize.width - safeMargin - iconHalf).clamp(minX, double.infinity);
    final double minY = padding.top + safeMargin + iconHalf;
    final double maxY = (screenSize.height - padding.bottom - safeMargin - iconHalf).clamp(minY, double.infinity);

    final bool fitsLeft = ballCenter.dx - _radialRadius >= minX;
    final bool fitsRight = ballCenter.dx + _radialRadius <= maxX;
    final bool fitsTop = ballCenter.dy - _radialRadius >= minY;
    final bool fitsBottom = ballCenter.dy + _radialRadius <= maxY;

    final int count = _radialItems.length;
    final List<Offset> positions = [];

    if (fitsLeft && fitsRight && fitsTop && fitsBottom) {
      // Full 360° ring around the ball
      for (int i = 0; i < count; i++) {
        final angle = -math.pi / 2 + (i * 2 * math.pi / count);
        positions.add(Offset(
          (ballCenter.dx + _radialRadius * math.cos(angle)).clamp(minX, maxX),
          (ballCenter.dy + _radialRadius * math.sin(angle)).clamp(minY, maxY),
        ));
      }
      return positions;
    }

    // Edge or corner: fan icons completely toward the open inward side
    final double dx = !fitsRight ? -1.0 : (!fitsLeft ? 1.0 : 0.0);
    final double dy = !fitsBottom ? -1.0 : (!fitsTop ? 1.0 : 0.0);
    final double centerAngle = math.atan2(dy, dx);
    final bool isCorner = dx != 0.0 && dy != 0.0;

    if (!isCorner) {
      // Single edge (left, right, top, or bottom): crisp 170° semi-circle on open side
      const double edgeRadius = 82.0;
      const double span = math.pi * 0.94;
      final double startAngle = centerAngle - span / 2;
      for (int i = 0; i < count; i++) {
        final t = count > 1 ? i / (count - 1) : 0.5;
        final angle = startAngle + t * span;
        positions.add(Offset(
          (ballCenter.dx + edgeRadius * math.cos(angle)).clamp(minX, maxX),
          (ballCenter.dy + edgeRadius * math.sin(angle)).clamp(minY, maxY),
        ));
      }
    } else {
      // Corner: 2 clean concentric arcs inside the open quadrant (3 inner + 4 outer)
      final int innerCount = count ~/ 2; // 3
      final int outerCount = count - innerCount; // 4
      const double innerRadius = 56.0;
      const double outerRadius = 104.0;
      const double innerSpan = math.pi * 0.48;
      const double outerSpan = math.pi * 0.56;

      for (int i = 0; i < innerCount; i++) {
        final t = innerCount > 1 ? i / (innerCount - 1) : 0.5;
        final angle = (centerAngle - innerSpan / 2) + t * innerSpan;
        positions.add(Offset(
          (ballCenter.dx + innerRadius * math.cos(angle)).clamp(minX, maxX),
          (ballCenter.dy + innerRadius * math.sin(angle)).clamp(minY, maxY),
        ));
      }
      for (int i = 0; i < outerCount; i++) {
        final t = outerCount > 1 ? i / (outerCount - 1) : 0.5;
        final angle = (centerAngle - outerSpan / 2) + t * outerSpan;
        positions.add(Offset(
          (ballCenter.dx + outerRadius * math.cos(angle)).clamp(minX, maxX),
          (ballCenter.dy + outerRadius * math.sin(angle)).clamp(minY, maxY),
        ));
      }
    }

    return positions;
  }

  void _updateRadialSelection(Offset fingerPos, Size screenSize, EdgeInsets padding) {
    if ((fingerPos - _radialOrigin).distance < 20.0) {
      if (_selectedRadialIndex != null) {
        setState(() => _selectedRadialIndex = null);
      }
      return;
    }

    final positions = _computeRadialPositions(_radialOrigin, screenSize, padding);
    int bestIndex = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < positions.length; i++) {
      final d = (fingerPos - positions[i]).distance;
      if (d < bestDist) {
        bestDist = d;
        bestIndex = i;
      }
    }

    if (_selectedRadialIndex != bestIndex) {
      HapticFeedback.selectionClick();
      setState(() => _selectedRadialIndex = bestIndex);
    }
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
                  Expanded(
                    child: Text(
                      'Quick Switch',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _openCustomizeSheet();
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: tileBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: tileBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tune_rounded, size: 13, color: textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              'Customize',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                'Tip: Hold & swipe the trackball to quick-jump • Drag anywhere to move',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: textSecondary),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      controller.setQuickSheetOpen(false);
      _resetIdleTimer();
    });
  }

  void _openCustomizeSheet() {
    final navContext = QuickActionsService.instance.navigatorKey.currentContext;
    if (navContext == null) return;

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
            Widget buildDropdownRow(
              String label,
              String value,
              ValueChanged<String> onChanged,
            ) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tileBorder),
                ),
                child: Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const Spacer(),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: value,
                        isDense: true,
                        dropdownColor: sheetBg,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                        items: _actionOptions
                            .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          onChanged(v);
                          setSheetState(() {});
                          setState(() {});
                          unawaited(_saveCustomization());
                        },
                      ),
                    ),
                  ],
                ),
              );
            }

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
                      Icon(Icons.control_camera_rounded, size: 18, color: accent),
                      const SizedBox(width: 8),
                      Text(
                        'Trackball Settings',
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
                  // Transparency Slider
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
                              '${(_opacity * 100).round()}%',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _opacity,
                          min: 0.15,
                          max: 0.95,
                          activeColor: accent,
                          onChanged: (val) {
                            setSheetState(() => _opacity = val);
                            setState(() => _opacity = val);
                          },
                          onChangeEnd: (_) => unawaited(_saveCustomization()),
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
                  const SizedBox(height: 8),
                  buildDropdownRow(
                    'Single Tap',
                    _singleTapAction,
                    (v) => _singleTapAction = v,
                  ),
                  const SizedBox(height: 8),
                  buildDropdownRow(
                    'Double Tap',
                    _doubleTapAction,
                    (v) => _doubleTapAction = v,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
    final ballCenter = Offset(effectivePos.dx + _ballSize / 2, effectivePos.dy + _ballSize / 2);

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
            final outerBg = isDark ? const Color(0xFF151932) : Colors.white;
            final borderColor = _isDragging || _isRadialOpen
                ? accent
                : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1));
            final displayOpacity = _isDragging || _isRadialOpen
                ? 0.95
                : (_isIdleFaded && _autoHide ? 0.14 : _opacity);

            final radialPositions = _isRadialOpen
                ? _computeRadialPositions(_radialOrigin, screenSize, padding)
                : const <Offset>[];

            double labelTop = padding.top + 12.0;
            if (radialPositions.isNotEmpty) {
              final minIconY = radialPositions.map((p) => p.dy).reduce(math.min);
              final maxIconY = radialPositions.map((p) => p.dy).reduce(math.max);
              final candidateAbove = minIconY - 58.0;
              if (candidateAbove >= padding.top + 8.0) {
                labelTop = candidateAbove;
              } else {
                labelTop = (maxIconY + 32.0).clamp(
                  padding.top + 8.0,
                  screenSize.height - padding.bottom - 40.0,
                );
              }
            }

            return Stack(
              children: [
                if (_isRadialOpen) ...[
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.25),
                      ),
                    ),
                  ),
                  // Selected radial label pill (automatically above or below icons within safe area)
                  if (_selectedRadialIndex != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      top: labelTop,
                      child: IgnorePointer(
                        child: Center(
                          child: Material(
                            type: MaterialType.transparency,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1B2042) : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: accent, width: 1.4),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: Text(
                                '${_radialItems[_selectedRadialIndex!]['emoji']} ${_radialItems[_selectedRadialIndex!]['label']}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: accent,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Radial icons positioned safely inside screen bounds
                  for (int i = 0; i < radialPositions.length; i++)
                    () {
                      final pt = radialPositions[i];
                      final isSelected = _selectedRadialIndex == i;
                      final itemSize = isSelected ? 44.0 : 38.0;
                      return Positioned(
                        left: pt.dx - itemSize / 2,
                        top: pt.dy - itemSize / 2,
                        child: IgnorePointer(
                          child: Material(
                            type: MaterialType.transparency,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              width: itemSize,
                              height: itemSize,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? accent
                                    : (isDark ? const Color(0xFF1B2042) : Colors.white),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? Colors.white : borderColor,
                                  width: isSelected ? 2.0 : 1.1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isSelected ? 0.35 : 0.15),
                                    blurRadius: isSelected ? 12 : 6,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  _radialItems[i]['emoji']!,
                                  style: TextStyle(
                                    fontSize: isSelected ? 19 : 15,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }(),
                ],
                Positioned(
                  left: effectivePos.dx,
                  top: effectivePos.dy,
                  child: Material(
                    color: Colors.transparent,
                    child: AnimatedOpacity(
                      opacity: displayOpacity,
                      duration: const Duration(milliseconds: 220),
                      child: Listener(
                        onPointerDown: (event) {
                          if (_activePointerId != null) return;
                          _activePointerId = event.pointer;
                          _pointerDownPos = event.position;
                          _lastPointerPos = event.position;
                          _resetIdleTimer();
                          _holdTimer?.cancel();
                          _holdTimer = Timer(const Duration(milliseconds: 300), () {
                            if (!mounted || _activePointerId == null || _isDragging) return;
                            HapticFeedback.mediumImpact();
                            setState(() {
                              _isRadialOpen = true;
                              _radialOrigin = ballCenter;
                              _selectedRadialIndex = null;
                            });
                          });
                        },
                        onPointerMove: (event) {
                          if (event.pointer != _activePointerId) return;
                          final delta = event.position - (_lastPointerPos ?? event.position);
                          _lastPointerPos = event.position;

                          if (_isRadialOpen) {
                            _updateRadialSelection(event.position, screenSize, padding);
                            return;
                          }

                          final movedFromDown =
                              (event.position - (_pointerDownPos ?? event.position)).distance;
                          if (!_isDragging && movedFromDown > 12.0) {
                            _holdTimer?.cancel();
                            HapticFeedback.selectionClick();
                            setState(() {
                              _isDragging = true;
                              _position ??= effectivePos;
                            });
                          }

                          if (_isDragging) {
                            setState(() {
                              final next = (_position ?? effectivePos) + delta;
                              _position = _clampPosition(next, screenSize, padding);
                            });
                          }
                        },
                        onPointerUp: (event) {
                          if (event.pointer != _activePointerId) return;
                          _holdTimer?.cancel();
                          _activePointerId = null;
                          _pointerDownPos = null;
                          _lastPointerPos = null;

                          if (_isRadialOpen) {
                            final selected = _selectedRadialIndex;
                            setState(() {
                              _isRadialOpen = false;
                              _selectedRadialIndex = null;
                            });
                            _resetIdleTimer();
                            if (selected != null) {
                              controller.navigateTo(_radialItems[selected]['label']!);
                            }
                            return;
                          }

                          if (_isDragging) {
                            setState(() => _isDragging = false);
                            _resetIdleTimer();
                            if (_position != null) {
                              unawaited(_savePosition(_position!));
                            }
                          }
                        },
                        onPointerCancel: (event) {
                          if (event.pointer != _activePointerId) return;
                          _holdTimer?.cancel();
                          _activePointerId = null;
                          _pointerDownPos = null;
                          _lastPointerPos = null;
                          if (_isRadialOpen || _isDragging) {
                            setState(() {
                              _isRadialOpen = false;
                              _selectedRadialIndex = null;
                              _isDragging = false;
                            });
                          }
                          _resetIdleTimer();
                        },
                        child: GestureDetector(
                          key: const Key('quick_switch_trackball'),
                          onTap: () {
                            if (_isRadialOpen || _isDragging) return;
                            _executeAction(_singleTapAction);
                          },
                          onDoubleTap: _doubleTapAction == 'None'
                              ? null
                              : () {
                                  if (_isRadialOpen || _isDragging) return;
                                  _executeAction(_doubleTapAction);
                                },
                          child: AnimatedScale(
                          scale: _isDragging || _isRadialOpen ? 1.12 : 1.0,
                          duration: const Duration(milliseconds: 120),
                          child: Container(
                            width: _ballSize,
                            height: _ballSize,
                            decoration: BoxDecoration(
                              color: outerBg,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: borderColor,
                                width: _isDragging || _isRadialOpen ? 2.0 : 1.3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.18),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.55),
                                    width: 1.2,
                                  ),
                                ),
                                child: Center(
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: accent,
                                      shape: BoxShape.circle,
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
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
