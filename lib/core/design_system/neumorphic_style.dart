import 'package:flutter/material.dart';
import 'package:flutter_neumorphism_ui/flutter_neumorphism_ui.dart';

import 'tokens.dart';

/// Standard Dark Industrial Neumorphism style configurations using flutter_neumorphism_ui
abstract final class AppNeumorphic {
  static NeumorphismStyle elevated({
    Color color = AppColors.surfaceDefault,
    double depth = 8,
    double borderRadius = AppRadii.card,
    BoxShape shape = BoxShape.rectangle,
  }) => NeumorphismStyle(
    color: color,
    depth: depth,
    type: NeumorphismType.flat,
    borderRadius: borderRadius,
    shape: shape,
    lightShadow: AppColors.shadowLight.withValues(alpha: 0.08),
    darkShadow: AppColors.shadowDark.withValues(alpha: 0.50),
  );

  static NeumorphismStyle recessed({
    Color color = AppColors.surfaceRecessed,
    double depth = 6,
    double borderRadius = AppRadii.card,
    BoxShape shape = BoxShape.rectangle,
  }) => NeumorphismStyle(
    color: color,
    depth: depth,
    type: NeumorphismType.pressed,
    borderRadius: borderRadius,
    shape: shape,
    lightShadow: AppColors.shadowLight.withValues(alpha: 0.08),
    darkShadow: AppColors.shadowDark.withValues(alpha: 0.55),
  );

  static NeumorphismStyle circular({
    bool isPressed = false,
    Color? color,
    double? depth,
  }) => NeumorphismStyle(
    color:
        color ??
        (isPressed ? AppColors.surfaceRecessed : AppColors.surfaceDefault),
    shape: BoxShape.circle,
    type: isPressed ? NeumorphismType.pressed : NeumorphismType.flat,
    depth: depth ?? (isPressed ? 5 : 8),
    lightShadow: AppColors.shadowLight.withValues(alpha: 0.08),
    darkShadow: AppColors.shadowDark.withValues(alpha: 0.50),
  );
}
