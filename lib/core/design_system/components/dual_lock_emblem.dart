import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import 'app_icon.dart';

/// Exact visual reproduction of the reference hardware image's center lock emblem
class DualLockEmblem extends StatelessWidget {
  const DualLockEmblem({
    super.key,
    this.color = AppColors.textPrimary,
    this.size = 28.0,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconSize = size * 0.48;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AppIcon(AppIcons.lock, size: iconSize, color: color),
        const SizedBox(width: 3),
        Container(
          width: 1.0,
          height: iconSize * 0.8,
          color: color.withValues(alpha: 0.45),
        ),
        const SizedBox(width: 3),
        AppIcon(AppIcons.unlock, size: iconSize, color: color),
      ],
    );
  }
}
