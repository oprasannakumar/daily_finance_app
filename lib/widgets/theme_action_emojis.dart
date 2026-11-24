import 'package:flutter/material.dart';

/// Custom theme-matched Save emoji/icon replacing default OS floppy disk emoji
class SaveThemeEmoji extends StatelessWidget {
  final double size;
  final Color? color;
  final Color? accentColor;

  const SaveThemeEmoji({
    super.key,
    this.size = 20,
    this.color,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SaveDiskPainter(isDark: isDark),
      ),
    );
  }
}

class _SaveDiskPainter extends CustomPainter {
  final bool isDark;

  _SaveDiskPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Subtle 3D bottom bevel / base shadow
    final bevelPaint = Paint()
      ..color = const Color(0xFF1E3A8A)
      ..style = PaintingStyle.fill;
    final bevelRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, h * 0.06, w, h * 0.94),
      Radius.circular(w * 0.14),
    );
    canvas.drawRRect(bevelRRect, bevelPaint);

    // 2. Main Diskette Body (Rich Royal Blue gradient)
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final cut = w * 0.22; // 45-degree top-right chamfer
    final r = w * 0.12;

    final bodyPath = Path()
      ..moveTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..lineTo(w - cut, 0)
      ..lineTo(w, cut)
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
      ..close();
    canvas.drawPath(bodyPath, bodyPaint);

    // 3. Top-right bevel highlight line
    final chamferHighlight = Paint()
      ..color = const Color(0xFF93C5FD)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05;
    canvas.drawLine(Offset(w - cut, 0), Offset(w, cut), chamferHighlight);

    // 4. Metal Shutter Plate (Top slider)
    final shutterPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFCBD5E1), Color(0xFF94A3B8)],
      ).createShader(Rect.fromLTWH(w * 0.20, 0, w * 0.58, h * 0.38));

    final shutterRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.20, 0, w * 0.58, h * 0.38),
      bottomLeft: Radius.circular(w * 0.06),
      bottomRight: Radius.circular(w * 0.06),
    );
    canvas.drawRRect(shutterRect, shutterPaint);

    // 5. Shutter Rectangular Window (revealing black magnetic disk inside)
    final windowPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    final windowRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.32, h * 0.07, w * 0.15, h * 0.24),
      Radius.circular(w * 0.03),
    );
    canvas.drawRRect(windowRect, windowPaint);

    // 6. Paper Label (Bottom)
    final labelBgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final labelShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    // Label subtle shadow
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(w * 0.15, h * 0.45, w * 0.70, h * 0.49),
        topLeft: Radius.circular(w * 0.06),
        topRight: Radius.circular(w * 0.06),
        bottomLeft: Radius.circular(w * 0.04),
        bottomRight: Radius.circular(w * 0.04),
      ),
      labelShadowPaint,
    );

    // Label face
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(w * 0.15, h * 0.44, w * 0.70, h * 0.48),
        topLeft: Radius.circular(w * 0.06),
        topRight: Radius.circular(w * 0.06),
        bottomLeft: Radius.circular(w * 0.04),
        bottomRight: Radius.circular(w * 0.04),
      ),
      labelBgPaint,
    );

    // 7. Label Header Red/Coral Stripe (classic floppy disk stripe!)
    final redStripePaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(w * 0.20, h * 0.48, w * 0.60, h * 0.07),
        topLeft: Radius.circular(w * 0.02),
        topRight: Radius.circular(w * 0.02),
      ),
      redStripePaint,
    );

    // 8. Label Index Lines
    final linePaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(w * 0.24, h * 0.66),
      Offset(w * 0.76, h * 0.66),
      linePaint,
    );
    canvas.drawLine(
      Offset(w * 0.24, h * 0.78),
      Offset(w * 0.60, h * 0.78),
      linePaint,
    );

    // 9. Write protect notch on bottom right
    final notchPaint = Paint()
      ..color = const Color(0xFF1E3A8A)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(w * 0.88, h * 0.80, w * 0.08, h * 0.14),
      notchPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SaveDiskPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// Custom theme-matched Repeat emoji/icon replacing default OS repeat emoji
class RepeatThemeEmoji extends StatelessWidget {
  final double size;
  final Color? color;

  const RepeatThemeEmoji({
    super.key,
    this.size = 18,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = color ?? (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0F766E));

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RepeatArrowsPainter(color: primaryColor),
      ),
    );
  }
}

class _RepeatArrowsPainter extends CustomPainter {
  final Color color;

  _RepeatArrowsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w * 0.36;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.125
      ..strokeCap = StrokeCap.round;

    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Top Arc: from ~195 deg to 340 deg
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      3.4,
      2.1,
      false,
      strokePaint,
    );

    // Top Arrow Head
    final topArrowHead = Path()
      ..moveTo(w * 0.82, h * 0.16)
      ..lineTo(w * 1.0, h * 0.38)
      ..lineTo(w * 0.68, h * 0.38)
      ..close();
    canvas.drawPath(topArrowHead, arrowPaint);

    // Bottom Arc: from ~15 deg to 160 deg
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0.26,
      2.1,
      false,
      strokePaint,
    );

    // Bottom Arrow Head
    final bottomArrowHead = Path()
      ..moveTo(w * 0.18, h * 0.84)
      ..lineTo(w * 0.0, h * 0.62)
      ..lineTo(w * 0.32, h * 0.62)
      ..close();
    canvas.drawPath(bottomArrowHead, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _RepeatArrowsPainter oldDelegate) =>
      oldDelegate.color != color;
}
