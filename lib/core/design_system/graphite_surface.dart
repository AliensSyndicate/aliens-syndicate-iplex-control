import 'package:flutter/material.dart';

import 'tokens.dart';

/// Surface role: [panel] cards and tiles; [button], [disc] and [center]
/// controls. Kept as names of the roles used across the app.
enum GraphiteFinish { panel, button, disc, center }

/// Flat surface of the Design System (dark minimalist, no bevels or drop
/// shadows): cards use [AppColors.surfaceDefault], controls
/// [AppColors.surfaceElevated]; [recessed] marks the pressed / selected /
/// input state ([AppColors.surfacePressed] for controls).
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

  /// Fill of a surface for its role and state.
  static Color fill(GraphiteFinish finish, bool recessed) {
    final control = finish != GraphiteFinish.panel;
    if (control) {
      return recessed ? AppColors.surfacePressed : AppColors.surfaceElevated;
    }
    // Inputs and selected panels are recessed panels.
    return recessed ? AppColors.surfaceElevated : AppColors.surfaceDefault;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final paint = Paint()..color = fill(finish, recessed);
    if (circle) {
      canvas.drawOval(rect, paint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(GraphiteMaterialPainter old) =>
      old.circle != circle ||
      old.recessed != recessed ||
      old.radius != radius ||
      old.finish != finish;
}
