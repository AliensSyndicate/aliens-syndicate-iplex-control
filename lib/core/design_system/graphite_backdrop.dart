import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Shared matte material. Its grain is painted once below the route tree.
class GraphiteBackdrop extends StatelessWidget {
  const GraphiteBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const Positioned.fill(
        child: RepaintBoundary(child: CustomPaint(painter: _GraphiteGrain())),
      ),
      child,
    ],
  );
}

/// Opaque slice of the [GraphiteBackdrop] for a widget anchored to the bottom
/// of the screen. It paints the backdrop at full screen size, aligned to the
/// bottom and clipped to the widget, so the slice matches the page pixel for
/// pixel instead of showing the content scrolling underneath.
class GraphiteBackdropSlice extends StatelessWidget {
  const GraphiteBackdropSlice({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.bottomCenter,
              minWidth: screen.width,
              maxWidth: screen.width,
              minHeight: screen.height,
              maxHeight: screen.height,
              child: const RepaintBoundary(
                child: CustomPaint(painter: _GraphiteGrain()),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _GraphiteGrain extends CustomPainter {
  const _GraphiteGrain();

  static Size? _cachedSize;
  static List<Offset>? _cachedLightPoints;
  static List<Offset>? _cachedDarkPoints;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.backgroundGradient,
        ).createShader(bounds),
    );

    if (_cachedSize != size ||
        _cachedLightPoints == null ||
        _cachedDarkPoints == null) {
      _cachedSize = size;
      final random = math.Random(27);
      // Calibrated density: ~1 point per 32 square pixels ensures uniform matte texture
      final count = (size.width * size.height / 32).round().clamp(800, 12000);
      final light = <Offset>[];
      final dark = <Offset>[];
      for (var i = 0; i < count; i++) {
        final pt = Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        );
        if (i.isEven) {
          light.add(pt);
        } else {
          dark.add(pt);
        }
      }
      _cachedLightPoints = light;
      _cachedDarkPoints = dark;
    }

    final lightPaint = Paint()
      ..color = AppColors.grainLight
      ..strokeWidth = 0.72
      ..strokeCap = StrokeCap.round;
    final darkPaint = Paint()
      ..color = AppColors.grainDark
      ..strokeWidth = 0.72
      ..strokeCap = StrokeCap.round;

    canvas.drawPoints(ui.PointMode.points, _cachedLightPoints!, lightPaint);
    canvas.drawPoints(ui.PointMode.points, _cachedDarkPoints!, darkPaint);
  }

  @override
  bool shouldRepaint(_GraphiteGrain oldDelegate) => false;
}
