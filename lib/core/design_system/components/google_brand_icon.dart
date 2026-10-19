import 'package:flutter/material.dart';

/// Precise mathematical vector painter for official Google G mark
class GoogleBrandIcon extends StatelessWidget {
  const GoogleBrandIcon({super.key, this.size = 22.0});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      size: Size.square(size),
      painter: const _GoogleBrandPainter(),
    ),
  );
}

class _GoogleBrandPainter extends CustomPainter {
  const _GoogleBrandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final strokeWidth = w * 0.22;
    final center = Offset(w / 2, h / 2);
    final radius = (w - strokeWidth) / 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    // Blue arc (right)
    strokePaint.color = const Color(0xFF4285F4);
    canvas.drawArc(arcRect, -0.75, 1.45, false, strokePaint);

    // Green arc (bottom)
    strokePaint.color = const Color(0xFF34A853);
    canvas.drawArc(arcRect, 0.7, 1.65, false, strokePaint);

    // Yellow arc (bottom left)
    strokePaint.color = const Color(0xFFFBBC05);
    canvas.drawArc(arcRect, 2.35, 1.05, false, strokePaint);

    // Red arc (top)
    strokePaint.color = const Color(0xFFEA4335);
    canvas.drawArc(arcRect, 3.4, 1.35, false, strokePaint);

    // Blue horizontal bar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final barRect = Rect.fromLTWH(
      center.dx - w * 0.05,
      center.dy - strokeWidth / 2,
      w / 2 + w * 0.05,
      strokeWidth,
    );
    canvas.drawRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
