import 'package:flutter/material.dart';

import '../tokens.dart';

/// The app's only tab / filter / segmented control (reference: Busca):
/// a horizontal row of pills; the selected one filled with the main green,
/// the others on [AppColors.surfaceElevated]. Used for the Home tabs, the
/// Busca filters, the series and person tabs and the IPTV format selector.
class AppTabs<T> extends StatelessWidget {
  const AppTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.padding = EdgeInsets.zero,
  });

  /// Value and label of each tab, in order.
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final bool enabled;
  final EdgeInsetsGeometry padding;

  static const height = 36.0;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: padding,
    child: Row(
      children: [
        for (final (i, (value, label)) in options.indexed) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          _Pill(
            key: ValueKey('tab-$value'),
            label: label,
            selected: value == selected,
            onTap: enabled ? () => onSelected(value) : null,
          ),
        ],
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Opacity(
      opacity: onTap == null && !selected ? 0.45 : 1,
      child: Material(
        color: selected ? AppColors.primary : AppColors.surfaceElevated,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.duration(context, AppMotion.selection),
            height: AppTabs.height,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: selected ? AppColors.onPrimary : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
