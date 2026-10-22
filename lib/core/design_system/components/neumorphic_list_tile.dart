import 'package:flutter/material.dart';

import '../graphite_surface.dart';
import '../icons.dart';
import '../localized_context.dart';
import '../tokens.dart';
import 'app_icon.dart';
import 'neumorphic_status_indicator.dart';

/// Every icon sits in the same background circle (the Family profile card).
/// The list card of the whole app (reference: the Family member card):
/// secondary surface, 20 padding, white title, no chevron. A selected card
/// gets a white border; a status (dot, spinner…) sits on the right, centered.
/// [InfoCard] (devices, IPTV) and [SelectionRow] (sheets) are this card.
class NeumorphicListTile extends StatelessWidget {
  const NeumorphicListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.subtitleColor,
    this.lines = const [],
    this.icon = AppIcons.account,
    this.iconColor = AppColors.textSecondary,
    this.onTap,
    this.online,
    this.trailing,
    this.leading,
    this.titlePrefix,
    this.selected = false,
    this.enabled = true,
    this.showLeading = true,
  });
  final String title;
  final String? subtitle;

  /// Custom second line (replaces [subtitle]).
  final Widget? subtitleWidget;

  /// Overrides the second line color (errors, connected).
  final Color? subtitleColor;

  /// Further lines under the subtitle (e.g. counts, last sync).
  final List<String> lines;
  final List<List<dynamic>> icon;

  /// Icon color inside the circle (e.g. highlighted when connected).
  final Color iconColor;
  final VoidCallback? onTap;

  /// Online / offline dot on the right.
  final bool? online;

  /// Status on the right (replaces the [online] dot).
  final Widget? trailing;

  /// Replaces the icon (for example an avatar or an icon box).
  final Widget? leading;

  /// Small mark before the title (e.g. a lock).
  final Widget? titlePrefix;

  /// Chosen option: white border.
  final bool selected;

  /// Unavailable option: dimmed and not tappable.
  final bool enabled;

  /// False: no icon/avatar column (text-only options).
  final bool showLeading;

  @override
  Widget build(BuildContext context) {
    final status =
        trailing ??
        (online == null
            ? null
            : Semantics(
                label: online! ? context.l.online : context.l.offline,
                child: NeumorphicStatusIndicator(online: online!),
              ));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Semantics(
        button: onTap != null,
        selected: selected,
        enabled: enabled,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: AppColors.surfaceDefault,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.card),
              side: selected
                  ? const BorderSide(color: AppColors.textPrimary, width: 1.5)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.card),
                child: Row(
                  children: [
                    if (showLeading) ...[
                      leading ??
                          GraphiteSurface(
                            circle: true,
                            recessed: true,
                            padding: const EdgeInsets.all(
                              AppSpacing.sm + AppSpacing.xs,
                            ),
                            child: AppIcon(icon, color: iconColor),
                          ),
                      const SizedBox(width: AppSpacing.md),
                    ],
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
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (subtitleWidget != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            subtitleWidget!,
                          ] else if (subtitle != null &&
                              subtitle!.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              subtitle!,
                              style: TextStyle(
                                color: subtitleColor ?? AppColors.textSecondary,
                              ),
                            ),
                          ],
                          for (final line in lines)
                            if (line.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                line,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                        ],
                      ),
                    ),
                    if (status != null) ...[
                      const SizedBox(width: AppSpacing.md),
                      status,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Backward compatibility alias for NeumorphicListTile
typedef EntryTile = NeumorphicListTile;
