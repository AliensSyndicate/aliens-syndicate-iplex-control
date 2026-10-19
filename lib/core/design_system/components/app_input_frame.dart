import 'package:flutter/material.dart';

import '../graphite_surface.dart';
import '../tokens.dart';

/// Fixed label and 56px control. Validation feedback lives below the surface.
class AppInputFrame extends StatelessWidget {
  const AppInputFrame({
    super.key,
    required this.label,
    required this.focusNode,
    required this.child,
    this.errorText,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
  });

  final String label;
  final FocusNode focusNode;
  final Widget child;
  final String? errorText;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: focusNode,
    builder: (context, _) {
      final focused = focusNode.hasFocus;
      final color = focused
          ? Colors.white
          : errorText != null
          ? AppColors.error
          : AppColors.textSecondary;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label.isNotEmpty) ...[
            ExcludeSemantics(
              child: GestureDetector(
                onTap: focusNode.requestFocus,
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Semantics(
            label: label,
            hint: errorText,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: focusNode.requestFocus,
              child: SizedBox(
                height: AppDimensions.input,
                child: GraphiteSurface(
                  recessed: true,
                  radius: AppRadii.pill,
                  child: AnimatedContainer(
                    duration: AppMotion.duration(context, AppMotion.selection),
                    padding: padding,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(
                        color: focused
                            ? Colors.white
                            : errorText != null
                            ? AppColors.error
                            : AppColors.borderLight,
                        width: focused ? 1.5 : AppDimensions.borderWidth,
                      ),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                left: AppSpacing.sm,
                right: AppSpacing.sm,
              ),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  errorText!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ),
            ),
        ],
      );
    },
  );
}
