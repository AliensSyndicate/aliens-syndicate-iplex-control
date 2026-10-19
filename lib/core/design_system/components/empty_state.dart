import 'package:flutter/material.dart';

import '../tokens.dart';
import 'app_icon.dart';
import 'neumorphic_surface.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    this.icon,
    this.action,
  });

  final String title, body;
  final List<List<dynamic>>? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
    child: Column(
      children: [
        if (icon != null) ...[
          NeumorphicSurface(
            circle: true,
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: AppIcon(
              icon!,
              size: AppDimensions.iconLarge,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        if (action != null) ...[const SizedBox(height: AppSpacing.xl), action!],
      ],
    ),
  );
}
