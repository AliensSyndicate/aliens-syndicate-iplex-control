import 'package:flutter/material.dart';

import '../core/design_system/components.dart';

class BottomNavigation extends StatelessWidget {
  const BottomNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    final l = context.l,
        labels = [l.home, l.familyTitle, l.devices, l.iptv, l.account],
        icons = [
          AppIcons.home,
          AppIcons.users,
          AppIcons.devices,
          AppIcons.iptv,
          AppIcons.account,
        ];
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.backgroundPrimary,
        borderRadius: BorderRadius.zero,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            top: AppSpacing.sm,
            bottom: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(
              5,
              (i) => Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularButton(
                      label: labels[i],
                      icon: icons[i],
                      size: AppDimensions.touch,
                      selected: selected == i,
                      onPressed: () => onSelected(i),
                    ),
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
