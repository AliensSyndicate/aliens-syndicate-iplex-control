import 'package:flutter/material.dart';
import '../../../../core/design_system/components.dart';

Future<bool> showDeviceUnlinkModal(
  BuildContext context, {
  required String deviceName,
}) async {
  final result = await showAppModalSheet<bool>(
    context: context,
    builder: (ctx) {
      final l = ctx.l;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surfaceRecessed,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: const Center(
                  child: AppIcon(
                    AppIcons.delete,
                    size: AppTokens.lg,
                    color: AppColors.error,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l.unlinkConfirmTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l.unlinkConfirmBody,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: l.unlinkDevice,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: l.cancel,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ],
      );
    },
  );
  return result == true;
}
