import 'package:flutter/material.dart';

import 'components.dart';

/// Gentle pulse shared by every skeleton of the app (still when the system
/// asks for reduced motion).
class AppSkeletonPulse extends StatefulWidget {
  const AppSkeletonPulse({super.key, required this.child});
  final Widget child;
  @override
  State<AppSkeletonPulse> createState() => _AppSkeletonPulseState();
}

class _AppSkeletonPulseState extends State<AppSkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller
        ..stop()
        ..value = 1;
    } else if (!controller.isAnimating) {
      controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.45, end: 1).animate(controller),
    child: widget.child,
  );
}

/// One flat skeleton block (no card, no shadow).
class AppSkeletonBlock extends StatelessWidget {
  const AppSkeletonBlock({
    super.key,
    this.width,
    required this.height,
    this.radius = AppRadii.xs,
    this.circle = false,
  });
  final double? width;
  final double height, radius;
  final bool circle;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: AppColors.surfaceElevated,
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : BorderRadius.circular(radius),
    ),
  );
}

/// Generic list skeleton (rows of avatar + two lines). Loading layout only:
/// no invented titles, images or live content; one loading announcement.
class AppLoadingSkeleton extends StatelessWidget {
  const AppLoadingSkeleton({super.key, this.rows = 3});
  final int rows;
  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l.loading,
    liveRegion: true,
    child: ExcludeSemantics(
      child: AppSkeletonPulse(
        child: Column(
          children: List.generate(
            rows,
            (index) => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  AppSkeletonBlock(
                    width: AppDimensions.touch,
                    height: AppDimensions.touch,
                    circle: true,
                  ),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FractionallySizedBox(
                          widthFactor: 0.7,
                          child: AppSkeletonBlock(height: 14),
                        ),
                        SizedBox(height: AppSpacing.sm),
                        FractionallySizedBox(
                          widthFactor: 0.45,
                          child: AppSkeletonBlock(height: 12),
                        ),
                      ],
                    ),
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
