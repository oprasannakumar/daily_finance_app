import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/quick_actions_service.dart';
import '../services/quick_nav_controller.dart';

/// Universal movable translucent trackball with:
/// - Tap to open a compact floating Quick-Jump menu anchored right next to the ball
/// - Long-press (or Settings button in menu) to open Trackball Settings
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
  static const double _menuWidth = 228.0;
  static const double _menuHeight = 232.0;

  static const List<Map<String, String>> _menuItems = [
    {'emoji': '📊', 'label': 'Dashboard'},
    {'emoji': '🔑', 'label': 'API Keys'},
    {'emoji': '🤝', 'label': 'Borrowers'},
    {'emoji': '💳', 'label': 'EMIs'},
    {'emoji': '⚙️', 'label': 'Masters'},
    {'emoji': '💰', 'label': 'Balances'},
    {'emoji': '🧾', 'label': 'Invoices'},
    {'emoji': '🔄', 'label': 'Entry ↔ History'},
  ];

  static const List<String> _actionOptions = [
    'Quick Menu',
    'Trackball Settings',
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
  bool _isMenuOpen = false;

  // Customization state
  double _opacity = 0.40;
  bool _autoHide = false;
  String _singleTapAction = 'Quick Menu';
  String _doubleTapAction = 'None';

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
        if (mounted && _autoHide && !_isDragging && !_isMenuOpen) {
          setState(() => _isIdleFaded = true);
        }
      });
    }
  }

  void _hideTemporarilyForScreenshot() {
    _screenshotHideTimer?.cancel();
    setState(() {
      _isMenuOpen = false;
      _hiddenForScreenshot = true;
    });
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

  Offset _computeMenuOrigin(Offset ballTopLeft, Size screenSize, EdgeInsets padding) {
    final ballCenterX = ballTopLeft.dx + _ballSize / 2;
    final rawLeft = ballCenterX >= screenSize.width / 2
        ? ballTopLeft.dx + _ballSize - _menuWidth
        : ballTopLeft.dx;
    final maxLeft = (screenSize.width - _menuWidth - 12.0).clamp(12.0, double.infinity);
    final left = rawLeft.clamp(12.0, maxLeft);

    final minTop = padding.top + 12.0;
    final maxTop = (screenSize.height - padding.bottom - _menuHeight - 12.0)
        .clamp(minTop, double.infinity);
    final aboveTop = ballTopLeft.dy - _menuHeight - 10.0;
    final top = aboveTop >= minTop
        ? aboveTop
        : (ballTopLeft.dy + _ballSize + 10.0).clamp(minTop, maxTop);

    return Offset(left, top);
  }

  void _executeAction(String action) {
    _resetIdleTimer();
    final controller = QuickNavController.instance;
    switch (action) {
      case 'None':
        return;
      case 'Quick Menu':
        HapticFeedback.selectionClick();
        setState(() => _isMenuOpen = !_isMenuOpen);
        return;
      case 'Trackball Settings':
        setState(() => _isMenuOpen = false);
        _openCustomizeSheet();
        return;
      case 'Entry ↔ History':
        HapticFeedback.selectionClick();
        setState(() => _isMenuOpen = false);
        if (controller.currentScreen == 'Entry') {
          controller.navigateTo('History');
        } else {
          controller.navigateTo('Entry');
        }
        return;
      default:
        setState(() => _isMenuOpen = false);
        controller.navigateTo(action);
        return;
    }
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
    ).whenComplete(() {
      controller.setQuickSheetOpen(false);
      _resetIdleTimer();
    });
  }

  Widget _buildFloatingMenu(
    BuildContext context,
    QuickNavController controller,
    Offset menuOrigin,
    bool isDark,
    Color accent,
  ) {
    final cardBg = isDark ? const Color(0xFF151932) : Colors.white;
    final tileBg = isDark ? const Color(0xFF1E2448) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF2E376E) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Positioned(
      left: menuOrigin.dx,
      top: menuOrigin.dy,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.92, end: 1.0),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: ((scale - 0.92) / 0.08).clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
        child: Material(
          key: const Key('quick_switch_floating_menu'),
          type: MaterialType.transparency,
          child: Container(
            width: _menuWidth,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(
              color: cardBg.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Quick Jump',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: textSecondary,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _hideTemporarilyForScreenshot,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.visibility_off_outlined,
                          size: 16,
                          color: textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    InkWell(
                      key: const Key('quick_switch_menu_settings_btn'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() => _isMenuOpen = false);
                        _openCustomizeSheet();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.tune_rounded,
                          size: 16,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (int row = 0; row < (_menuItems.length / 2).ceil(); row++) ...[
                  if (row > 0) const SizedBox(height: 6),
                  Row(
                    children: [
                      for (int col = 0; col < 2; col++) ...[
                        if (col > 0) const SizedBox(width: 6),
                        Expanded(
                          child: () {
                            final idx = row * 2 + col;
                            if (idx >= _menuItems.length) {
                              return const SizedBox.shrink();
                            }
                            final item = _menuItems[idx];
                            final label = item['label']!;
                            final isActive = controller.currentScreen == label;
                            return InkWell(
                              borderRadius: BorderRadius.circular(11),
                              onTap: () => _executeAction(label),
                              child: Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: isActive ? accent.withValues(alpha: 0.16) : tileBg,
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                    color: isActive ? accent : borderColor,
                                    width: isActive ? 1.3 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      item['emoji']!,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: isActive ? accent : textPrimary,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }(),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
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
            final borderColor = _isDragging || _isMenuOpen
                ? accent
                : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1));
            final displayOpacity = _isDragging || _isMenuOpen
                ? 0.95
                : (_isIdleFaded && _autoHide ? 0.14 : _opacity);

            final menuOrigin = _computeMenuOrigin(effectivePos, screenSize, padding);

            return Stack(
              children: [
                if (_isMenuOpen) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => setState(() => _isMenuOpen = false),
                      child: Container(
                        color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                      ),
                    ),
                  ),
                  _buildFloatingMenu(context, controller, menuOrigin, isDark, accent),
                ],
                Positioned(
                  left: effectivePos.dx,
                  top: effectivePos.dy,
                  child: Material(
                    color: Colors.transparent,
                    child: AnimatedOpacity(
                      opacity: displayOpacity,
                      duration: const Duration(milliseconds: 220),
                      child: GestureDetector(
                        key: const Key('quick_switch_trackball'),
                        onTap: () {
                          if (_isDragging) return;
                          _executeAction(_singleTapAction);
                        },
                        onDoubleTap: _doubleTapAction == 'None'
                            ? null
                            : () {
                                if (_isDragging) return;
                                _executeAction(_doubleTapAction);
                              },
                        onLongPress: () {
                          if (_isDragging) return;
                          HapticFeedback.mediumImpact();
                          setState(() => _isMenuOpen = false);
                          _openCustomizeSheet();
                        },
                        onPanStart: (_) {
                          _resetIdleTimer();
                          HapticFeedback.selectionClick();
                          setState(() {
                            _isDragging = true;
                            _isMenuOpen = false;
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
                          _resetIdleTimer();
                          if (_position != null) {
                            unawaited(_savePosition(_position!));
                          }
                        },
                        onPanCancel: () {
                          setState(() => _isDragging = false);
                          _resetIdleTimer();
                        },
                        child: AnimatedScale(
                          scale: _isDragging || _isMenuOpen ? 1.10 : 1.0,
                          duration: const Duration(milliseconds: 120),
                          child: Container(
                            width: _ballSize,
                            height: _ballSize,
                            decoration: BoxDecoration(
                              color: outerBg,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: borderColor,
                                width: _isDragging || _isMenuOpen ? 2.0 : 1.3,
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
              ],
            );
          },
        ),
      ],
    );
  }
}
