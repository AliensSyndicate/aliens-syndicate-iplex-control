import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/components.dart';
import '../controllers/device_controller.dart';

class DeviceConfirmPairingPage extends ConsumerStatefulWidget {
  const DeviceConfirmPairingPage({super.key});

  @override
  ConsumerState<DeviceConfirmPairingPage> createState() =>
      _DeviceConfirmPairingPageState();
}

class _DeviceConfirmPairingPageState
    extends ConsumerState<DeviceConfirmPairingPage> {
  bool busy = false;

  Future<void> confirm() async {
    setState(() => busy = true);
    try {
      final device = await ref
          .read(devicePairingProvider.notifier)
          .confirmLink();
      if (!mounted) return;
      context.pushReplacement('/devices/success', extra: device.displayName);
    } catch (e) {
      if (mounted) {
        showDeviceConnectionFailure(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final pairingState = ref.watch(devicePairingProvider);
    final session = pairingState.session;

    if (session == null) {
      return PageTemplate(
        title: l.confirmPairingTitle,
        showBack: true,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.invalidCode),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: l.backToDevices,
                onPressed: () => context.go('/devices'),
              ),
            ],
          ),
        ),
      );
    }

    final isOtherFamily = session.isAlreadyLinked && !session.isSameFamily;

    return PageTemplate(
      title: l.confirmPairingTitle,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isOtherFamily) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.error),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppIcon(
                    AppIcons.alert,
                    color: AppColors.error,
                    size: AppTokens.xl,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      l.deviceAlreadyLinkedOtherFamily,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (session.isSameFamily) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.warning),
              ),
              child: Row(
                children: [
                  const AppIcon(
                    AppIcons.alert,
                    color: AppColors.warning,
                    size: AppTokens.xl,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      l.deviceAlreadyLinkedSameFamily,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          AppSurface(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: const Center(
                          child: AppIcon(
                            AppIcons.devices,
                            size: AppTokens.xl,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.displayName.isNotEmpty
                                  ? session.displayName
                                  : 'iPlex TV',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              session.platformLabel,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Container(height: 1, color: AppColors.borderDark),
                  const SizedBox(height: AppSpacing.md),
                  _DetailRow(label: l.tvNameLabel, value: session.displayName),
                  _DetailRow(
                    label: l.platformLabel,
                    value: session.platformLabel,
                  ),
                  if (session.manufacturer.isNotEmpty)
                    _DetailRow(
                      label: l.manufacturerLabel,
                      value: session.manufacturer,
                    ),
                  if (session.model.isNotEmpty)
                    _DetailRow(label: l.modelLabel, value: session.model),
                  if (session.nativeIdentityMasked.isNotEmpty)
                    _DetailRow(
                      label: l.maskedIdLabel,
                      value: session.nativeIdentityMasked,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (!isOtherFamily) ...[
            AppButton.primary(
              label: l.confirmLinkButton,
              busy: busy,
              onPressed: confirm,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          AppButton(
            label: l.cancelLinkButton,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textDisabled,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
