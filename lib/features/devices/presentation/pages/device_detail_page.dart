import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/providers.dart';
import '../../../../core/design_system/components.dart';
import '../controllers/device_controller.dart';
import '../widgets/device_unlink_modal.dart';

class DeviceDetailPage extends ConsumerStatefulWidget {
  const DeviceDetailPage({super.key, required this.deviceId});
  final String deviceId;

  @override
  ConsumerState<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends ConsumerState<DeviceDetailPage> {
  bool unlinking = false;

  Future<void> unlink(String displayName) async {
    final confirmed = await showDeviceUnlinkModal(
      context,
      deviceName: displayName,
    );
    if (!confirmed || !mounted) return;

    setState(() => unlinking = true);
    try {
      final repo = ref.read(deviceRepositoryProvider);
      await repo.unlinkDevice(widget.deviceId);
      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        showFailure(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => unlinking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final deviceAsync = ref.watch(deviceDetailStreamProvider(widget.deviceId));
    final admin = ref.watch(canManageResourcesProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final locale = Localizations.localeOf(context).toString();

    return Scaffold(
      backgroundColor: AppColors.backgroundDeep,
      body: deviceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          onRetry: () =>
              ref.invalidate(deviceDetailStreamProvider(widget.deviceId)),
        ),
        data: (device) {
          if (device == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.notFound),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: l.backToDevices,
                    onPressed: () => context.go('/devices'),
                  ),
                ],
              ),
            );
          }

          final isOnline = device.isOnline(now);

          String linkedDateStr = '-';
          if (device.linkedAt != null) {
            linkedDateStr = DateFormat.yMd(locale).format(device.linkedAt!);
          }

          String lastSeenStr = l.neverActive;
          if (device.lastSeenAt != null &&
              device.lastSeenAt!.millisecondsSinceEpoch > 0) {
            lastSeenStr = DateFormat.yMd(locale)
                .add_Hm()
                .format(device.lastSeenAt!);
          }

          return PageTemplate(
            title: device.displayName,
            showBack: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.sm,
                                ),
                              ),
                              child: Center(
                                child: AppIcon(
                                  AppIcons.devices,
                                  size: AppTokens.xxl,
                                  color: isOnline
                                      ? AppColors.accent
                                      : AppColors.textDisabled,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      NeumorphicStatusIndicator(
                                        online: isOnline,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isOnline ? l.online : l.offline,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: isOnline
                                              ? AppColors.textPrimary
                                              : AppColors.textDisabled,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${l.lastSeen}: $lastSeenStr',
                                    style: const TextStyle(
                                      fontSize: 12,
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
                        _InfoRow(
                          label: l.platformLabel,
                          value: device.platformLabel,
                        ),
                        if (device.manufacturer.isNotEmpty)
                          _InfoRow(
                            label: l.manufacturerLabel,
                            value: device.manufacturer,
                          ),
                        if (device.model.isNotEmpty)
                          _InfoRow(label: l.modelLabel, value: device.model),
                        _InfoRow(label: l.linkedAtLabel, value: linkedDateStr),
                        _InfoRow(
                          label: l.maskedIdLabel,
                          value: device.maskedId,
                        ),
                      ],
                    ),
                  ),
                ),
                if (admin) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: l.editDeviceName,
                    icon: AppIcons.edit,
                    onPressed: () => context.push(
                      '/devices/${device.id}/edit',
                      extra: device.displayName,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: l.unlinkDevice,
                    icon: AppIcons.delete,
                    busy: unlinking,
                    onPressed: () => unlink(device.displayName),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
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
