import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A precise vector icon representing an authentic Finance Accounting Ledger.
/// Illustrates an open two-page ledger book with ruled Debit and Credit columns,
/// accounting grid entries, a central red bookmark ribbon, and a slender gold accounting pencil.
class FinanceLedgerIcon extends StatelessWidget {
  final double size;
  final Color? primaryColor;
  final Color? accentColor;
  final bool showBadge;

  const FinanceLedgerIcon({
    super.key,
    this.size = 48.0,
    this.primaryColor,
    this.accentColor,
    this.showBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = primaryColor ?? const Color(0xFF1E3A8A); // Deep navy
    final goldColor = accentColor ?? const Color(0xFFF59E0B); // Amber / Gold

    if (!showBadge) {
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _PreciseLedgerPainter(
            coverColor: baseColor,
            accentGold: goldColor,
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.26),
        color: const Color(0xFF0F172A), // Sleek dark squircle
        border: Border.all(
          color: goldColor.withValues(alpha: 0.4),
          width: math.max(1.0, size * 0.025),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: size * 0.15,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.14),
      child: CustomPaint(
        painter: _PreciseLedgerPainter(
          coverColor: baseColor,
          accentGold: goldColor,
        ),
      ),
    );
  }
}

class _PreciseLedgerPainter extends CustomPainter {
  final Color coverColor;
  final Color accentGold;

  _PreciseLedgerPainter({
    required this.coverColor,
    required this.accentGold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Hardbound Open Book Backing / Cover Border (Deep Green/Navy)
    final bookBacking = Paint()
      ..color = const Color(0xFF064E3B) // Dark Forest Green
      ..style = PaintingStyle.fill;

    final backingRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.04, h * 0.12, w * 0.92, h * 0.76),
      Radius.circular(w * 0.08),
    );
    canvas.drawRRect(backingRect, bookBacking);

    // Left Page (Debit Page) - Warm White
    final pagePaint = Paint()
      ..color = const Color(0xFFFFFDF5)
      ..style = PaintingStyle.fill;

    final pageBorderPaint = Paint()
      ..color = const Color(0xFFD1D5DB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, w * 0.01);

    final leftPage = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.08, h * 0.15, w * 0.40, h * 0.70),
      topLeft: Radius.circular(w * 0.05),
      bottomLeft: Radius.circular(w * 0.05),
    );
    canvas.drawRRect(leftPage, pagePaint);
    canvas.drawRRect(leftPage, pageBorderPaint);

    // Right Page (Credit Page) - Warm White
    final rightPage = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.52, h * 0.15, w * 0.40, h * 0.70),
      topRight: Radius.circular(w * 0.05),
      bottomRight: Radius.circular(w * 0.05),
    );
    canvas.drawRRect(rightPage, pagePaint);
    canvas.drawRRect(rightPage, pageBorderPaint);

    // Center Spine Binding Shadow
    final spineShadow = Paint()
      ..shader = const LinearGradient(
        colors: [Colors.black26, Colors.transparent, Colors.black26],
      ).createShader(Rect.fromLTWH(w * 0.47, h * 0.14, w * 0.06, h * 0.72));
    canvas.drawRect(Rect.fromLTWH(w * 0.47, h * 0.14, w * 0.06, h * 0.72), spineShadow);

    // Ruled Column Lines (Classic T-Account Ledger Grid)
    final gridLine = Paint()
      ..color = const Color(0xFF94A3B8).withValues(alpha: 0.6)
      ..strokeWidth = math.max(0.6, w * 0.01);

    final redHeaderLine = Paint()
      ..color = const Color(0xFFEF4444).withValues(alpha: 0.6)
      ..strokeWidth = math.max(0.8, w * 0.012);

    // Red ledger header line across both pages
    canvas.drawLine(Offset(w * 0.10, h * 0.28), Offset(w * 0.46, h * 0.28), redHeaderLine);
    canvas.drawLine(Offset(w * 0.54, h * 0.28), Offset(w * 0.90, h * 0.28), redHeaderLine);

    // Vertical column divider on Left page (Date | Particulars | Debit)
    canvas.drawLine(Offset(w * 0.35, h * 0.20), Offset(w * 0.35, h * 0.80), gridLine);
    // Vertical column divider on Right page (Credit | Balance)
    canvas.drawLine(Offset(w * 0.72, h * 0.20), Offset(w * 0.72, h * 0.80), gridLine);

    // Horizontal Entry Rows (Accounting entries)
    final entryLine = Paint()
      ..color = const Color(0xFF64748B).withValues(alpha: 0.45)
      ..strokeWidth = math.max(0.6, w * 0.009);

    for (int i = 0; i < 4; i++) {
      final y = h * (0.38 + i * 0.10);
      // Left page entries
      canvas.drawLine(Offset(w * 0.12, y), Offset(w * 0.32, y), entryLine);
      canvas.drawLine(Offset(w * 0.37, y), Offset(w * 0.45, y), entryLine);

      // Right page entries
      canvas.drawLine(Offset(w * 0.56, y), Offset(w * 0.69, y), entryLine);
      canvas.drawLine(Offset(w * 0.75, y), Offset(w * 0.88, y), entryLine);
    }

    // Bookmark Ribbon (Red satin down the middle)
    final ribbonPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.fill;

    final ribbonPath = Path();
    ribbonPath.moveTo(w * 0.48, h * 0.12);
    ribbonPath.lineTo(w * 0.52, h * 0.12);
    ribbonPath.lineTo(w * 0.52, h * 0.88);
    ribbonPath.lineTo(w * 0.50, h * 0.83); // Chevron notch
    ribbonPath.lineTo(w * 0.48, h * 0.88);
    ribbonPath.close();
    canvas.drawPath(ribbonPath, ribbonPaint);

    // Accounting Pencil (Resting diagonally across bottom right)
    final pencilBody = Paint()
      ..color = const Color(0xFFFBBF24) // Yellow pencil
      ..strokeWidth = math.max(2.0, w * 0.035)
      ..strokeCap = StrokeCap.butt;

    final startPencil = Offset(w * 0.68, h * 0.78);
    final endPencil = Offset(w * 0.94, h * 0.52);
    canvas.drawLine(startPencil, endPencil, pencilBody);

    // Pencil Tip (wood + graphite)
    final pencilTip = Paint()
      ..color = const Color(0xFF1E293B) // Dark graphite
      ..strokeWidth = math.max(2.0, w * 0.035)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(startPencil, Offset(w * 0.66, h * 0.80), pencilTip);

    // Pencil Eraser (Pink eraser band at the back)
    final eraser = Paint()
      ..color = const Color(0xFFF472B6)
      ..strokeWidth = math.max(2.0, w * 0.035)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(endPencil, Offset(w * 0.96, h * 0.50), eraser);
  }

  @override
  bool shouldRepaint(covariant _PreciseLedgerPainter oldDelegate) {
    return oldDelegate.coverColor != coverColor || oldDelegate.accentGold != accentGold;
  }
}
