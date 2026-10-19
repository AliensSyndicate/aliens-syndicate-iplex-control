import 'package:flutter/material.dart';

import 'components.dart';

/// Loading layout only. No invented titles, images or live content.
/// Static bones respect reduced motion and expose one loading announcement.
class AppLoadingSkeleton extends StatelessWidget {
  const AppLoadingSkeleton({super.key, this.rows = 3});
  final int rows;
  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l.loading,
    liveRegion: true,
    child: ExcludeSemantics(
      child: Column(
        children: List.generate(
          rows,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.md),
            child: AppSurface(
              padding: const EdgeInsets.all(AppTokens.md),
              child: Row(
                children: [
                  const _SkeletonBone(
                    width: AppTokens.touch,
                    height: AppTokens.touch,
                    circle: true,
                  ),
                  const SizedBox(width: AppTokens.md),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FractionallySizedBox(
                          widthFactor: 0.7,
                          child: _SkeletonBone(height: AppTokens.md),
                        ),
                        SizedBox(height: AppTokens.sm),
                        FractionallySizedBox(
                          widthFactor: 0.45,
                          child: _SkeletonBone(height: AppTokens.sm),
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

class _SkeletonBone extends StatelessWidget {
  const _SkeletonBone({this.width, required this.height, this.circle = false});
  final double? width;
  final double height;
  final bool circle;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: AppColors.borderLight,
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : BorderRadius.circular(AppRadii.sm),
    ),
  );
}
