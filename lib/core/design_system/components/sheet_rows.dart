import 'package:flutter/material.dart';

import '../tokens.dart';
import 'app_icon.dart';

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

/// One option of a selection sheet (reference: devices, filters): icon box,
/// title, status line and a radio / check on the right. The selected row is
/// highlighted; unavailable rows are dimmed and not tappable.
class SelectionRow extends StatelessWidget {
  const SelectionRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.icon,
    this.leading,
    this.subtitle,
    this.highlightSubtitle = false,
  });
  final String title;
  final String? subtitle;
  final List<List<dynamic>>? icon;
  final Widget? leading;
  final bool selected;

  /// Status line in the main green (e.g. "Conectado").
  final bool highlightSubtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final iconColor = selected || highlightSubtitle
        ? AppColors.primary
        : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: selected ? AppColors.surfaceElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.md),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm + 2),
                child: Row(
                  children: [
                    if (leading != null)
                      leading!
                    else if (icon != null)
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: Center(child: AppIcon(icon!, color: iconColor)),
                      ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty)
                            Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 13,
                                color: highlightSubtitle
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _Radio(selected: selected, enabled: enabled),
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

class _Radio extends StatelessWidget {
  const _Radio({required this.selected, required this.enabled});
  final bool selected, enabled;
  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? AppColors.primary : Colors.transparent,
      border: selected
          ? null
          : Border.all(color: AppColors.textSecondary, width: 1.5),
    ),
    child: selected
        ? const Icon(Icons.check_rounded, size: 16, color: AppColors.onPrimary)
        : !enabled
        ? const Icon(
            Icons.block_rounded,
            size: 14,
            color: AppColors.textSecondary,
          )
        : null,
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
