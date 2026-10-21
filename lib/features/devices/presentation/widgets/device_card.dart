import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/providers.dart';
import '../../../../core/design_system/components.dart';
import '../../domain/entities/device_entity.dart';

class DeviceCard extends ConsumerWidget {
  const DeviceCard({super.key, required this.device, required this.onTap});

  final DeviceEntity device;
  final VoidCallback onTap;

  List<List<dynamic>> _platformIcon(String platform) {
    switch (platform) {
      case 'tizen':
      case 'webos':
      case 'android_tv':
      default:
        return AppIcons.devices;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final isOnline = device.isOnline(now);
    final locale = Localizations.localeOf(context).toString();

    String formattedDate = '';
    if (device.linkedAt != null) {
      formattedDate = DateFormat.yMd(locale).format(device.linkedAt!);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppSurface(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRecessed,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        border: Border.all(
                          color: AppColors.borderDark,
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: AppIcon(
                          _platformIcon(device.platform),
                          size: AppTokens.xl,
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
                          Text(
                            device.displayName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            device.subtitleInfo,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const AppIcon(
                      AppIcons.right,
                      size: AppTokens.lg,
                      color: AppColors.textDisabled,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Container(height: 1, color: AppColors.borderDark),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    NeumorphicStatusIndicator(online: isOnline),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      isOnline ? l.online : l.offline,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isOnline
                            ? AppColors.textPrimary
                            : AppColors.textDisabled,
                      ),
                    ),
                    const Spacer(),
                    if (formattedDate.isNotEmpty) ...[
                      Text(
                        '${l.linkedAtLabel} $formattedDate',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDisabled,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
