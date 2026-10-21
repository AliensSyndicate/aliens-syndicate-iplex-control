import 'package:flutter/material.dart';

import '../graphite_surface.dart';
import '../icons.dart';
import '../localized_context.dart';
import '../tokens.dart';
import 'app_icon.dart';
import 'neumorphic_status_indicator.dart';

/// Neumorphic Physical List Tile
class NeumorphicListTile extends StatelessWidget {
  const NeumorphicListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = AppIcons.account,
    this.onTap,
    this.online,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final List<List<dynamic>> icon;
  final VoidCallback? onTap;
  final bool? online;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: GraphiteSurface(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GraphiteSurface(
                  circle: true,
                  recessed: true,
                  padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
                  child: AppIcon(icon, color: AppColors.textSecondary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (trailing != null)
                  trailing!
                else if (online != null)
                  Semantics(
                    label: online! ? context.l.online : context.l.offline,
                    child: NeumorphicStatusIndicator(online: online!),
                  )
                else if (onTap != null)
                  const AppIcon(
                    AppIcons.right,
                    size: AppDimensions.iconSmall,
                    color: AppColors.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Backward compatibility alias for NeumorphicListTile
typedef EntryTile = NeumorphicListTile;
