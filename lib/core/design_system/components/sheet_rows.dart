import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import 'app_icon.dart';
import 'neumorphic_list_tile.dart';

/// Left-aligned sheet header (reference: "Assistir na TV / Selecione um
/// dispositivo"): an icon or artwork, the title and an optional subtitle.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
  });
  final String title;
  final String? subtitle;
  final List<List<dynamic>>? icon;

  /// Artwork instead of the icon (poster of a title).
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Row(
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: AppSpacing.md),
        ] else if (icon != null) ...[
          AppIcon(icon!, size: 28),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// One action of an actions sheet (reference: "Assistir na TV",
/// "Adicionar aos favoritos"…): icon and label, hairline divider above.
class SheetActionRow extends StatelessWidget {
  const SheetActionRow({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.active = false,
    this.material,
  });
  final List<List<dynamic>>? icon;

  /// Filled/outlined state glyph (favorite, saved).
  final IconData? material;
  final String label;
  final VoidCallback? onTap;

  /// Already applied (saved, favorited): icon in the main green.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textPrimary;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: AppDimensions.button,
          child: Row(
            children: [
              SizedBox(
                width: AppDimensions.touch,
                child: material != null
                    ? Icon(material, size: 24, color: color)
                    : AppIcon(icon!, color: color),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One option of a selection sheet (devices, sources, seasons): the list
/// card ([NeumorphicListTile]); the chosen one has the white border,
/// unavailable ones are dimmed and not tappable.
class SelectionRow extends StatelessWidget {
  const SelectionRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.icon,
    this.leading,
    this.subtitle,
    this.subtitleWidget,
    this.highlightSubtitle = false,
  });
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final List<List<dynamic>>? icon;
  final Widget? leading;
  final bool selected;

  /// Status line in the main color (e.g. "Conectado").
  final bool highlightSubtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => NeumorphicListTile(
    title: title,
    subtitle: subtitle,
    subtitleWidget: subtitleWidget,
    subtitleColor: highlightSubtitle ? AppColors.primary : null,
    selected: selected,
    enabled: onTap != null,
    onTap: onTap,
    showLeading: leading != null || icon != null,
    leading: leading,
    icon: icon ?? AppIcons.account,
    iconColor: AppColors.textPrimary,
  );
}

/// Red trash mark of destructive confirmations.
class DangerMark extends StatelessWidget {
  const DangerMark({super.key, required this.icon});
  final List<List<dynamic>> icon;
  @override
  Widget build(BuildContext context) => Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.error.withValues(alpha: 0.15),
    ),
    child: Center(child: AppIcon(icon, size: 28, color: AppColors.error)),
  );
}
