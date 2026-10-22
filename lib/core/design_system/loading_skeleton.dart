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

/// List skeleton with the exact geometry of an [EntryTile] (card, 20 dp
/// padding, 48 dp avatar, title and subtitle lines). Loading layout only: no
/// invented titles, images or live content; one loading announcement.
class AppLoadingSkeleton extends StatelessWidget {
  const AppLoadingSkeleton({super.key, this.rows = 3});
  final int rows;
  @override
  Widget build(BuildContext context) => _announced(
    context,
    Column(
      children: List.generate(
        rows,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceDefault,
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.card),
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
                          child: AppSkeletonBlock(height: 16),
                        ),
                        SizedBox(height: AppSpacing.sm),
                        FractionallySizedBox(
                          widthFactor: 0.45,
                          child: AppSkeletonBlock(height: 13),
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

Widget _announced(BuildContext context, Widget child) => Semantics(
  label: context.l.loading,
  liveRegion: true,
  child: ExcludeSemantics(child: AppSkeletonPulse(child: child)),
);

/// One poster card: artwork block and two caption lines (same sizes as
/// [HomeCard]).
class _PosterSkeleton extends StatelessWidget {
  const _PosterSkeleton();
  static const width = 112.0, height = 168.0;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSkeletonBlock(
          width: width,
          height: height,
          radius: AppRadii.md,
        ),
        const SizedBox(height: AppSpacing.sm),
        const AppSkeletonBlock(width: width * 0.8, height: 13),
        const SizedBox(height: AppSpacing.xs),
        const AppSkeletonBlock(width: width * 0.45, height: 12),
      ],
    ),
  );
}

/// Home rows while loading: section title + a horizontal strip of posters,
/// like the real "Continuar assistindo" / "Filmes" rows.
class PosterRowsSkeleton extends StatelessWidget {
  const PosterRowsSkeleton({super.key, this.rows = 2});
  final int rows;
  @override
  Widget build(BuildContext context) => _announced(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var row = 0; row < rows; row++) ...[
          const AppSkeletonBlock(width: 160, height: 20),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 168 + AppSpacing.sm + 13 + AppSpacing.xs + 12,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 6,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, index) => const _PosterSkeleton(),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ],
    ),
  );
}

/// Catalog / search results while loading: the same wrapped poster grid as
/// the real result.
class PosterGridSkeleton extends StatelessWidget {
  const PosterGridSkeleton({super.key, this.count = 9});
  final int count;
  @override
  Widget build(BuildContext context) => _announced(
    context,
    Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [for (var i = 0; i < count; i++) const _PosterSkeleton()],
    ),
  );
}
