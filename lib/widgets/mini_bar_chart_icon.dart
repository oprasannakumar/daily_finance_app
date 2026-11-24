import 'package:flutter/material.dart';

/// Mini 3-bar chart icon matching the design in media_1794923590114_ece2a827.png
class MiniBarChartIcon extends StatelessWidget {
  final double size;

  const MiniBarChartIcon({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Stack(
        children: [
          // Faint horizontal grid lines
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Container(height: 0.6, color: const Color(0xFFE2E8F0)),
              Container(height: 0.6, color: const Color(0xFFE2E8F0)),
              Container(height: 0.6, color: const Color(0xFFE2E8F0)),
            ],
          ),
          // 3 vertical bars: Green, Red, Blue
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: size * 0.16,
                    height: size * 0.52,
                    decoration: const BoxDecoration(
                      color: Color(0xFF84CC16), // Green bar
                      borderRadius: BorderRadius.vertical(top: Radius.circular(1)),
                    ),
                  ),
                  Container(
                    width: size * 0.16,
                    height: size * 0.38,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444), // Red bar
                      borderRadius: BorderRadius.vertical(top: Radius.circular(1)),
                    ),
                  ),
                  Container(
                    width: size * 0.16,
                    height: size * 0.78,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0EA5E9), // Blue bar
                      borderRadius: BorderRadius.vertical(top: Radius.circular(1)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
