import 'package:flutter/material.dart';

import 'tokens.dart';

enum GraphiteFinish { panel, button, disc, center }

/// A painted bevel and clipped inner shadow, with one light source throughout.
/// Unlike a drop shadow alone, the recessed finish actually shadows inside.
class GraphiteSurface extends StatelessWidget {
  const GraphiteSurface({
    super.key,
    required this.child,
    this.circle = false,
    this.recessed = false,
    this.radius = AppRadii.card,
    this.finish = GraphiteFinish.panel,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final bool circle, recessed;
  final double radius;
  final GraphiteFinish finish;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: GraphiteMaterialPainter(
        circle: circle,
        recessed: recessed,
        radius: radius,
        finish: finish,
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class GraphiteMaterialPainter extends CustomPainter {
  const GraphiteMaterialPainter({
    this.circle = false,
    this.recessed = false,
    this.radius = AppRadii.card,
    this.finish = GraphiteFinish.panel,
  });
  final bool circle, recessed;
  final double radius;
  final GraphiteFinish finish;

  static final Paint _groovePaint = Paint()..color = AppColors.groove;
  static const _bevelOuterGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.groove, AppColors.edgeShadow, AppColors.edgeLight],
    stops: [0, 0.52, 1],
  );

  Path _shape(Rect rect) => circle
      ? (Path()..addOval(rect))
      : (Path()
          ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius))));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(0.75);
    final shape = _shape(rect);
    final disc = finish == GraphiteFinish.disc;
    final button =
        finish == GraphiteFinish.button || finish == GraphiteFinish.center;
    final depth = disc
        ? 1.65
        : button
        ? 1.0
        : 0.6;
    if (!recessed) {
      canvas.drawPath(
        shape.shift(Offset(5 * depth, 7 * depth)),
        Paint()
          ..color = AppColors.castShadow
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * depth),
      );
      canvas.drawPath(
        shape.shift(Offset(-3 * depth, -3 * depth)),
        Paint()
          ..color = AppColors.ambientHighlight
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * depth),
      );
    }
    // Hairline dark groove around the hardware's edge.
    canvas.drawPath(shape, _groovePaint);
    final faceRect = rect.deflate(button || disc ? 2.2 : 0.7);
    final face = _shape(faceRect);
    final colors = recessed
        ? AppColors.pressedGradient
        : disc
        ? AppColors.padOuterGradient
        : finish == GraphiteFinish.center
        ? AppColors.padCenterGradient
        : button
        ? AppColors.buttonGradient
        : AppColors.panelGradient;
    canvas.drawPath(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(rect),
    );
    // Bevel: dark upper lip and a narrow reflected rim at lower right.
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = button || disc ? 1.3 : 0.65
        ..shader = _bevelOuterGradient.createShader(rect),
    );
    canvas.drawPath(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: recessed
              ? const [AppColors.groove, AppColors.edgeLight]
              : const [AppColors.faceLight, AppColors.edgeShadow],
        ).createShader(rect),
    );
    if (recessed) {
      _innerShadow(
        canvas,
        face,
        faceRect,
        const Offset(4, 5),
        6,
        AppColors.insetShadow,
      );
      _innerShadow(
        canvas,
        face,
        faceRect,
        const Offset(-3, -3),
        4,
        AppColors.insetHighlight,
      );
    }
  }

  void _innerShadow(
    Canvas canvas,
    Path shape,
    Rect rect,
    Offset offset,
    double blur,
    Color color,
  ) {
    canvas.save();
    canvas.clipPath(shape);
    final spread = (blur * 2.5 + offset.distance).ceilToDouble();
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(spread))
      ..addPath(shape, offset);
    canvas.drawPath(
      outside,
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(GraphiteMaterialPainter old) =>
      old.circle != circle ||
      old.recessed != recessed ||
      old.radius != radius ||
      old.finish != finish;
}
