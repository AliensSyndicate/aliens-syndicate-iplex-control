import 'package:flutter/material.dart';

import '../tokens.dart';

/// Progress bar of the whole app (watch progress): rounded, 8 px tall by
/// default, [margin] around it (none by default).
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.value,
    this.height = 8,
    this.margin = EdgeInsets.zero,
    this.color = AppColors.primary,
    this.trackColor = const Color(0x33FFFFFF),
  });

  /// 0..1 (clamped).
  final double value;
  final double height;
  final EdgeInsets margin;
  final Color color, trackColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        color: color,
        backgroundColor: trackColor,
      ),
    ),
  );
}
