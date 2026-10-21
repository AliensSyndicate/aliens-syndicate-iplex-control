import 'package:flutter/material.dart';

import '../core/design_system/components.dart';
import '../features/manager/widgets/account_avatar.dart';

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
                        // The Account button carries the account's avatar instead of an icon.
                        icon: i == 4 ? null : icons[i],
                        size: AppDimensions.touch,
                        selected: selected == i,
                        onPressed: () => onSelected(i),
                        child: i == 4
                            ? const AccountAvatarFace(
                                size: AppDimensions.touch - 2 * AppSpacing.xs,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Opaque menu background: the very same [GraphiteBackdrop] that sits under every
/// screen, painted at full-screen size and cropped to the bar, so the color at each
/// point of the menu equals the color of the screen at that point (no seam).
class _MenuBackground extends StatelessWidget {
  const _MenuBackground();
  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // The menu rides up with the keyboard; the backdrop stays where the screen is.
    final lift = MediaQuery.viewInsetsOf(context).bottom;
    return ExcludeSemantics(
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.bottomCenter,
          minWidth: screen.width,
          maxWidth: screen.width,
          minHeight: screen.height,
          maxHeight: screen.height,
          child: Transform.translate(
            offset: Offset(0, lift),
            child: const GraphiteBackdrop(child: SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}
