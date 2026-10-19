import 'package:flutter/material.dart';

import '../../../../core/design_system/components.dart';

/// Loading indicator adhering to Dark Industrial Neumorphism.
class LegalDocumentLoadingIndicator extends StatelessWidget {
  const LegalDocumentLoadingIndicator({
    super.key,
    required this.progress,
    this.message,
  });

  /// Loading progress from 0 to 100.
  final int progress;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final double value = (progress.clamp(0, 100)) / 100.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeumorphicSurface(
              circle: true,
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  value: value > 0 && value < 1.0 ? value : null,
                  strokeWidth: 3,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.accent),
                  backgroundColor: AppColors.borderLight,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message ?? context.l.legalLoading,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            if (value > 0 && value < 1.0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${(value * 100).toInt()}%',
                style: const TextStyle(
                  color: AppColors.textDisabled,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
