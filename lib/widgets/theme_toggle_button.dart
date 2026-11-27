import 'package:flutter/material.dart';
import '../theme/app_theme_colors.dart';

/// 360-degree rotating theme toggle button with smooth icon morph and gradient glass transition
class ThemeToggleRotatingButton extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggle;

  const ThemeToggleRotatingButton({
    super.key,
    required this.isDark,
    required this.onToggle,
  });

  @override
  State<ThemeToggleRotatingButton> createState() => _ThemeToggleRotatingButtonState();
}

class _ThemeToggleRotatingButtonState extends State<ThemeToggleRotatingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _rotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void didUpdateWidget(covariant ThemeToggleRotatingButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark && !_controller.isAnimating) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward(from: 0.0);
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final colors = AppThemeColors.of(context);

    return InkWell(
      onTap: _handleTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 750),
        curve: Curves.easeInOutCubic,
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    colors.primaryGradStart.withValues(alpha: 0.34),
                    colors.primaryGradEnd.withValues(alpha: 0.24),
                  ]
                : [
                    const Color(0xFFFFFBEB).withValues(alpha: 0.92),
                    const Color(0xFFFFEDD5).withValues(alpha: 0.85),
                  ],
          ),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark
                ? colors.primaryGradStart.withValues(alpha: 0.65)
                : const Color(0xFFF59E0B).withValues(alpha: 0.45),
            width: 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: (isDark ? colors.primaryGradStart : const Color(0xFFF59E0B))
                  .withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: RotationTransition(
            turns: _rotationAnimation,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Text(
                isDark ? '☀️' : '🌙',
                key: ValueKey<bool>(isDark),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
