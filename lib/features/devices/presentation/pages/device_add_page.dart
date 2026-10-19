import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/components.dart';

class DeviceAddPage extends ConsumerWidget {
  const DeviceAddPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;

    return PageTemplate(
      title: l.devices,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.addDeviceInstructionsTitle,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _StepRow(step: '1', text: l.addDeviceStep1),
          const SizedBox(height: AppSpacing.md),
          _StepRow(step: '2', text: l.addDeviceStep2),
          const SizedBox(height: AppSpacing.md),
          _StepRow(step: '3', text: l.addDeviceStep3),
          const SizedBox(height: AppSpacing.md),
          _StepRow(step: '4', text: l.addDeviceStep4),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: l.scanQrCode,
            icon: AppIcons.qr,
            onPressed: () => context.push('/devices/scan'),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: l.enterCodeManually,
            icon: AppIcons.edit,
            onPressed: () => context.push('/devices/code'),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.text});
  final String step;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.surfaceRecessed,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.borderLight, width: 1),
          ),
          child: Center(
            child: Text(
              step,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
