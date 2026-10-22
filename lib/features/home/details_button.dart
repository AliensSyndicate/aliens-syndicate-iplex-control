import 'package:flutter/material.dart';

import '../../core/design_system/components.dart';

/// Action of the details action row (prototype): icon over a short label,
/// optional second line (the TV name under "Assistir na TV"). [primary] is the
/// filled green circle of the main action.
class DetailsAction extends StatelessWidget {
  const DetailsAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.material,
    this.caption,
    this.primary = false,
    this.active = false,
    this.busy = false,
  });
  final String label;
  final String? caption;
  final VoidCallback? onPressed;
  final List<List<dynamic>>? icon;
  final IconData? material;
  final bool primary, active, busy;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textPrimary;
    final glyph = busy
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: primary ? AppColors.onPrimary : AppColors.textPrimary,
            ),
          )
        : material != null
        ? Icon(
            material,
            size: primary ? 32 : 26,
            color: primary ? AppColors.onPrimary : color,
          )
        : AppIcon(
            icon!,
            size: primary ? 28 : 24,
            color: primary ? AppColors.onPrimary : color,
          );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: [label, ?caption].join(', '),
      excludeSemantics: true,
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: InkResponse(
          onTap: busy ? null : onPressed,
          radius: 36,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 56,
                child: primary
                    ? DecoratedBox(
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Center(child: glyph),
                      )
                    : Center(child: glyph),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  color: AppColors.textPrimary,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
