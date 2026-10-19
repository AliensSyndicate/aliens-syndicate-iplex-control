import 'package:flutter/material.dart';

import '../graphite_surface.dart';
import '../icons.dart';
import '../localized_context.dart';
import '../tokens.dart';
import 'app_icon.dart';

class FormatOption {
  const FormatOption({
    required this.id,
    required this.label,
    required this.icon,
  });
  final String id;
  final String label;
  final List<List<dynamic>> icon;
}

/// Tactile Horizontal Segmented Tab Selector for IPTV Formats
class NeumorphicFormatSelector extends StatelessWidget {
  const NeumorphicFormatSelector({
    super.key,
    required this.selectedFormat,
    required this.onFormatSelected,
    this.disabled = false,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.xs,
    ),
  });

  final String selectedFormat;
  final ValueChanged<String> onFormatSelected;
  final bool disabled;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final options = [
      FormatOption(id: 'url', label: l.sourceFormatUrl, icon: AppIcons.link),
      FormatOption(id: 'file', label: l.sourceFormatFile, icon: AppIcons.file),
      FormatOption(
        id: 'xtream',
        label: l.sourceFormatXtream,
        icon: AppIcons.server,
      ),
      FormatOption(
        id: 'other_m3u8',
        label: l.sourceFormatOtherM3u8,
        icon: AppIcons.play,
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: padding,
      child: Row(
        children: options.asMap().entries.map((entry) {
          final i = entry.key;
          final opt = entry.value;
          // Support 'm3u' matching 'url'
          final isSelected =
              selectedFormat == opt.id ||
              (opt.id == 'url' && selectedFormat == 'm3u');
          final isLast = i == options.length - 1;
          return Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : AppSpacing.sm),
            child: _FormatTabPill(
              option: opt,
              isSelected: isSelected,
              disabled: disabled,
              onTap: () {
                if (!disabled && !isSelected) {
                  onFormatSelected(opt.id);
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FormatTabPill extends StatelessWidget {
  const _FormatTabPill({
    required this.option,
    required this.isSelected,
    required this.disabled,
    required this.onTap,
  });

  final FormatOption option;
  final bool isSelected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: option.label,
      child: GraphiteSurface(
        radius: AppRadii.pill,
        recessed: isSelected,
        finish: isSelected ? GraphiteFinish.button : GraphiteFinish.panel,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            onTap: disabled ? null : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(
                  color: isSelected
                      ? AppColors.borderLight
                      : Colors.transparent,
                  width: AppDimensions.borderWidth,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    option.icon,
                    size: AppDimensions.iconSmall,
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
