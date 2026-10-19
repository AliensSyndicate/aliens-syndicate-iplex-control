import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../tokens.dart';

/// Thin stroke monochrome icon mapping directly to Hugeicons
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.color = AppColors.textPrimary,
    this.size = AppDimensions.icon,
  });
  final List<List<dynamic>> icon;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) =>
      HugeIcon(icon: icon, color: color, size: size, strokeWidth: 1.5);
}
