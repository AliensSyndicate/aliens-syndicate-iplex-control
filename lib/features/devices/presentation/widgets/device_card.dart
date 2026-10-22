import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    // Reference: "Card de dispositivo".
    return InfoCard(
      icon: _platformIcon(device.platform),
      title: device.displayName,
      status: isOnline ? l.connectedStatus : l.offline,
      extra: device.subtitleInfo,
      active: isOnline,
      dot: NeumorphicStatusIndicator(online: isOnline),
      onTap: onTap,
    );
  }
}
