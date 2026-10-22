import 'package:flutter/material.dart';

import '../graphite_surface.dart';
import '../tokens.dart';

/// Flat card surface of the Design System ([GraphiteSurface]).
class NeumorphicSurface extends StatelessWidget {
  const NeumorphicSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.recessed = false,
    this.circle = false,
    this.radius = AppRadii.card,
    this.border,
  });
  final Widget child;
  final EdgeInsets padding;
  final bool recessed, circle;
  final double radius;
  final BoxBorder? border;
  @override
  Widget build(BuildContext context) => GraphiteSurface(
    circle: circle,
    recessed: recessed,
    radius: radius,
    padding: padding,
    finish: circle ? GraphiteFinish.button : GraphiteFinish.panel,
    child: child,
  );
}

/// Backward compatibility alias for NeumorphicSurface
typedef AppSurface = NeumorphicSurface;
