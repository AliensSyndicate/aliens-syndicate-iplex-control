import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/components.dart';
import '../controllers/iptv_sync_controller.dart';

/// Modal bottom sheet presented upon terminal completion or failure of an IPTV sync job.
///
/// Requirement: Shown once per job completion, never opens duplicates simultaneously,
/// styled with the Design System, protects credentials.
class IptvSyncResultSheet extends StatelessWidget {
  const IptvSyncResultSheet({
    super.key,
    required this.jobId,
    required this.sourceId,
    required this.sourceName,
    required this.isSuccess,
    this.errorCode,
    this.onViewSource,
    this.onRetry,
  });

  final String jobId;
  final String sourceId;
  final String sourceName;
  final bool isSuccess;
  final String? errorCode;
  final VoidCallback? onViewSource;
  final VoidCallback? onRetry;

  static bool _isShowing = false;

  /// Safely presents the sync result sheet if not already displaying another sheet.
  static Future<void> show(
    BuildContext context, {
    required String jobId,
    required String sourceId,
    required String sourceName,
    required bool isSuccess,
    String? errorCode,
    VoidCallback? onRetry,
  }) async {
    if (_isShowing || !context.mounted) return;

    _isShowing = true;
    try {
      await showAppModalSheet<void>(
        context: context,
        builder: (sheetContext) => IptvSyncResultSheet(
          jobId: jobId,
          sourceId: sourceId,
          sourceName: sourceName,
          isSuccess: isSuccess,
          errorCode: errorCode,
          onViewSource: () {
            Navigator.of(sheetContext).pop();
            context.push('/iptv/$sourceId');
          },
          onRetry: onRetry,
        ),
      );
    } finally {
      _isShowing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final title = isSuccess ? l.syncSuccessTitle : l.syncFailureTitle;
    final body = isSuccess
        ? l.syncSuccessBody
        : mapIptvErrorCodeToMessage(context, errorCode);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.lg),

            // Status Icon + Badge
            Center(
              child: GraphiteSurface(
                circle: true,
                recessed: true,
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: AppIcon(
                  isSuccess ? AppIcons.check : AppIcons.alert,
                  size: 40,
                  color: isSuccess ? AppColors.brandBlue : AppColors.error,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),

            // Body Message
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Source Name
            Text(
              sourceName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xl),

            // Action Buttons
            if (isSuccess) ...[
              AppButton(
                label: l.viewIptv,
                onPressed: onViewSource ?? () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: l.close,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ] else ...[
              if (onRetry != null) ...[
                AppButton(
                  label: l.retry,
                  onPressed: () {
                    Navigator.of(context).pop();
                    onRetry!();
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              AppButton(
                label: l.close,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
