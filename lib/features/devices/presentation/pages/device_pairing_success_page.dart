import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/components.dart';
import '../controllers/device_controller.dart';

class DevicePairingSuccessPage extends ConsumerWidget {
  const DevicePairingSuccessPage({super.key, this.deviceName});
  final String? deviceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final pairingState = ref.watch(devicePairingProvider);
    final name = deviceName ?? pairingState.linkedDevice?.displayName ?? 'TV';
    final deviceId = pairingState.linkedDevice?.id;

    return PageTemplate(
      title: l.pairingCompleted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surfaceRecessed,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.success, width: 2),
              ),
              child: const Center(
                child: AppIcon(
                  AppIcons.check,
                  size: AppTokens.xxl,
                  color: AppColors.success,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            l.deviceLinked,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l.deviceLinkedBody(name),
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          if (deviceId != null && deviceId.isNotEmpty) ...[
            AppButton(
              label: l.viewDetails,
              onPressed: () {
                ref.read(devicePairingProvider.notifier).reset();
                context.go('/devices/$deviceId');
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          AppButton(
            label: l.backToDevices,
            onPressed: () {
              ref.read(devicePairingProvider.notifier).reset();
              context.go('/devices');
            },
          ),
        ],
      ),
    );
  }
}
