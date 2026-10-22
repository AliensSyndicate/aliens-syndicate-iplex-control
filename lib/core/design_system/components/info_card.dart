import 'package:flutter/material.dart';

import '../graphite_surface.dart';
import '../icons.dart';
import '../tokens.dart';
import 'app_icon.dart';

/// Card of a managed resource (reference: "Card de dispositivo", "Card de
/// IPTV"): icon box (green when active), title, status line, optional extra
/// line, status dot on the top right and a chevron (or a custom trailing).
class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.status,
    this.extra,
    this.footnote,
    this.active = false,
    this.statusColor,
    this.dot,
    this.trailing,
    this.titlePrefix,
  });
  final List<List<dynamic>> icon;
  final String title;
  final String? status, extra;

  /// Last line (e.g. last sync).
  final String? footnote;

  /// Connected / online: green icon box.
  final bool active;

  /// Overrides the status line color (errors, syncing).
  final Color? statusColor;

  /// Status dot on the top right (null: none).
  final Widget? dot;
  final Widget? trailing;

  /// Small mark before the title (e.g. a lock).
  final Widget? titlePrefix;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: GraphiteSurface(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.card),
          onTap: onTap,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Center(
                        child: AppIcon(
                          icon,
                          size: 30,
                          color: active
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (titlePrefix != null) ...[
                                titlePrefix!,
                                const SizedBox(width: AppSpacing.xs),
                              ],
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (status != null && status!.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              status!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: statusColor ?? AppColors.textSecondary,
                              ),
                            ),
                          ],
                          if (extra != null && extra!.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              extra!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textDisabled,
                              ),
                            ),
                          ],
                          if (footnote != null && footnote!.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              footnote!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textDisabled,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    trailing ??
                        const AppIcon(
                          AppIcons.right,
                          size: AppDimensions.iconSmall,
                          color: AppColors.textSecondary,
                        ),
                  ],
                ),
              ),
              if (dot != null)
                Positioned(
                  top: AppSpacing.sm + 2,
                  right: AppSpacing.sm + 2,
                  child: dot!,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
