import 'package:flutter/material.dart';

import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';

/// Physical Neumorphic Directional Pad based directly on the reference hardware image
class RemoteDirectionalPad extends StatelessWidget {
  const RemoteDirectionalPad({
    super.key,
    required this.onCommand,
    this.useReferenceLock = false,
  });
  final ValueChanged<RemoteCommand>? onCommand;
  final bool useReferenceLock;
  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.maxWidth;
          final centerSize = size * 0.39;
          final directions = [
            (
              label: l.up,
              icon: AppIcons.up,
              command: RemoteCommand.up,
              alignment: const Alignment(0, -0.78),
            ),
            (
              label: l.down,
              icon: AppIcons.down,
              command: RemoteCommand.down,
              alignment: const Alignment(0, 0.78),
            ),
            (
              label: l.left,
              icon: AppIcons.left,
              command: RemoteCommand.left,
              alignment: const Alignment(-0.78, 0),
            ),
            (
              label: l.right,
              icon: AppIcons.right,
              command: RemoteCommand.right,
              alignment: const Alignment(0.78, 0),
            ),
          ];
          return GraphiteSurface(
            circle: true,
            finish: GraphiteFinish.disc,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.square(
                  dimension: size * 0.54,
                  child: GraphiteSurface(
                    circle: true,
                    recessed: true,
                    finish: GraphiteFinish.button,
                    child: Center(
                      child: SizedBox.square(
                        dimension: centerSize,
                        child: CircularButton(
                          label: l.ok,
                          finish: GraphiteFinish.center,
                          size: centerSize,
                          onPressed: onCommand == null
                              ? null
                              : () => onCommand!(RemoteCommand.ok),
                          child: Text(
                            l.ok,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w400,
                                  color: onCommand == null
                                      ? AppColors.textDisabled
                                      : AppColors.textPrimary,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                for (final direction in directions)
                  Align(
                    alignment: direction.alignment,
                    child: CircularButton(
                      label: direction.label,
                      icon: direction.icon,
                      size: (size * 0.20).clamp(AppDimensions.touch, 72),
                      onPad: true,
                      onPressed: onCommand == null
                          ? null
                          : () => onCommand!(direction.command),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
