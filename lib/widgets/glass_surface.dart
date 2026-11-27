import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme_colors.dart';

/// Full-screen luminous multi-stop aurora gradient mesh canvas behind every screen
/// so translucent glassmorphism cards, headers, and docks refract vivid ambient color.
class GlassBackdrop extends StatelessWidget {
  final Widget child;

  const GlassBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [Color(0xFF070A19), Color(0xFF0E1333), Color(0xFF081B2C)]
                    : const [Color(0xFFF3EEFF), Color(0xFFFFF1EC), Color(0xFFE6FCF8)],
              ),
            ),
          ),
        ),
        Positioned(
          top: -110,
          left: -80,
          child: IgnorePointer(
            child: _AmbientGlowOrb(
              size: 320,
              color: isDark
                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.25)
                  : const Color(0xFFFF6B4A).withValues(alpha: 0.20),
            ),
          ),
        ),
        Positioned(
          top: 90,
          right: -100,
          child: IgnorePointer(
            child: _AmbientGlowOrb(
              size: 290,
              color: isDark
                  ? const Color(0xFF06B6D4).withValues(alpha: 0.20)
                  : const Color(0xFF8B5CF6).withValues(alpha: 0.18),
            ),
          ),
        ),
        Positioned(
          bottom: -120,
          left: 30,
          child: IgnorePointer(
            child: _AmbientGlowOrb(
              size: 340,
              color: isDark
                  ? const Color(0xFFEC4899).withValues(alpha: 0.16)
                  : const Color(0xFF00D2B4).withValues(alpha: 0.17),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _AmbientGlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _AmbientGlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0.0)],
          stops: const [0.0, 0.72],
        ),
      ),
    );
  }
}

/// Real frosted glassmorphic container with BackdropFilter blur, specular gradient fill,
/// luminous hairline border, and soft colored elevation shadow.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius borderRadius;
  final double blurSigma;
  final List<Color>? gradientColors;
  final Color? borderColor;
  final double borderWidth;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.constraints,
    this.padding,
    this.margin,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.blurSigma = 18.0,
    this.gradientColors,
    this.borderColor,
    this.borderWidth = 1.25,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppThemeColors.of(context);
    final grad = gradientColors ?? [colors.glassSurfaceTop, colors.glassSurfaceBottom];

    return Container(
      width: width,
      constraints: constraints,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.42)
                : const Color(0xFF6366F1).withValues(alpha: 0.09),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: grad,
              ),
              border: Border.all(
                color: borderColor ?? colors.glassRim,
                width: borderWidth,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Lightweight frosted glass BoxDecoration (without BackdropFilter shader per list row)
/// ideal for scrollable list cards and inner sub-cards.
BoxDecoration glassTileDecoration(
  BuildContext context, {
  BorderRadius borderRadius = const BorderRadius.all(Radius.circular(18)),
  Color? borderColor,
  List<Color>? gradientColors,
  double borderWidth = 1.2,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    borderRadius: borderRadius,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: gradientColors ??
          (isDark
              ? [const Color(0xCC1E264F), const Color(0xA6131838)]
              : [const Color(0xDBFFFFFF), const Color(0xB8FFF8F5)]),
    ),
    border: Border.all(
      color: borderColor ??
          (isDark ? Colors.white.withValues(alpha: 0.13) : Colors.white.withValues(alpha: 0.92)),
      width: borderWidth,
    ),
    boxShadow: [
      BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: 0.28)
            : const Color(0xFF6366F1).withValues(alpha: 0.06),
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

/// Frosted glass flexibleSpace for Scaffold AppBars so scrolled lists blur softly underneath.
Widget buildGlassAppBarFlexibleSpace(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xD9101533), const Color(0xBF0B1228)]
                : [const Color(0xD9FFFFFF), const Color(0xBFFFF5F8)],
          ),
          border: Border(
            bottom: BorderSide(
              color: isDark ? Colors.white.withValues(alpha: 0.10) : const Color(0xFFE2DDF4),
              width: 1.0,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Gradient-filled primary CTA button with colored glow shadow.
class GlassGradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final List<Color>? colors;
  final BorderRadius borderRadius;
  final double height;
  final EdgeInsetsGeometry padding;

  const GlassGradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.colors,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.height = 46,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = AppThemeColors.of(context);
    final activeColors = colors ?? [themeColors.primaryGradStart, themeColors.primaryGradEnd];
    final disabled = onPressed == null;

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: disabled
              ? activeColors.map((c) => c.withValues(alpha: 0.45)).toList()
              : activeColors,
        ),
        boxShadow: disabled
            ? null
            : [
                BoxShadow(
                  color: activeColors.first.withValues(alpha: 0.34),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: borderRadius,
          child: Padding(
            padding: padding,
            child: Center(
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                child: IconTheme.merge(
                  data: const IconThemeData(color: Colors.white),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gradient text shader wrapper for branding titles.
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Gradient gradient;

  const GradientText(
    this.text, {
    super.key,
    required this.style,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(text, style: style),
    );
  }
}
