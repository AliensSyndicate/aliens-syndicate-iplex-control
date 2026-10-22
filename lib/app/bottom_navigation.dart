import 'package:flutter/material.dart';

import '../core/design_system/components.dart';

/// Main menu (fixed, five items): Home, Busca, Família, Dispositivos, IPTV.
/// [selected] is the item index (null on screens outside the menu, such as
/// the account); flat icons, the selected one in the main green, over a
/// slightly translucent background that also covers the system navigation bar.
class BottomNavigation extends StatelessWidget {
  const BottomNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final int? selected;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    final l = context.l,
        labels = [l.home, l.searchTab, l.familyTitle, l.devices, l.iptv],
        icons = [
          AppIcons.home,
          AppIcons.search,
          AppIcons.users,
          AppIcons.devices,
          AppIcons.iptv,
        ];
    return Stack(
      children: [
        const Positioned.fill(child: _MenuBackground()),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.sm,
              right: AppSpacing.sm,
              top: AppSpacing.sm,
              bottom: AppSpacing.sm,
            ),
            child: Row(
              children: List.generate(5, (i) {
                final active = selected == i;
                final color = active
                    ? AppColors.primary
                    : AppColors.textSecondary;
                return Expanded(
                  child: Semantics(
                    button: true,
                    selected: active,
                    label: labels[i],
                    excludeSemantics: true,
                    child: InkResponse(
                      key: ValueKey('main-menu-$i'),
                      onTap: () => onSelected(i),
                      // Icon only; the label stays for accessibility.
                      child: SizedBox(
                        height: AppDimensions.touch,
                        child: Center(
                          child: AppIcon(icons[i], color: color, size: 26),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

/// Slightly translucent menu background: the screen content stays visible
/// behind the menu. It also covers the (transparent, edge-to-edge) system
/// navigation bar, so both look the same.
class _MenuBackground extends StatelessWidget {
  const _MenuBackground();
  @override
  Widget build(BuildContext context) =>
      const ExcludeSemantics(child: ColoredBox(color: AppColors.navigationBar));
}
