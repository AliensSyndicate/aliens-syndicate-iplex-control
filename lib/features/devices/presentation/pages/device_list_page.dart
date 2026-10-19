import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/providers.dart';
import '../../../../core/design_system/components.dart';
import '../../../../core/domain/models/device_model.dart';
import '../../domain/entities/device_entity.dart';
import '../widgets/device_card.dart';

class DeviceListPage extends ConsumerWidget {
  const DeviceListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;

    return PageTemplate(
      title: l.devices,
      hasBottomNav: true,
      action: CircularButton(
        label: l.add,
        icon: AppIcons.add,
        size: AppDimensions.touch,
        onPressed: () => context.push('/devices/add'),
      ),
      child: Consumer(
        builder: (context, ref, _) {
          final entriesAsync = ref.watch(entriesProvider('devices'));

          return entriesAsync.when(
            loading: () => const AppLoadingSkeleton(rows: 3),
            error: (error, _) => ErrorState(
              onRetry: () => ref.invalidate(entriesProvider('devices')),
            ),
            data: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  title: l.emptyDevices,
                  body: l.emptyDevicesBody,
                  action: AppButton(
                    label: l.add,
                    icon: AppIcons.add,
                    onPressed: () => context.push('/devices/add'),
                  ),
                );
              }

                final devices = items.map((e) {
                  final model = DeviceModel.fromMap(e.id, e.data);
                  return DeviceEntity(
                    id: model.id,
                    familyId: model.familyId,
                    displayName: model.displayName,
                    platform: model.platform,
                    status: model.status,
                    manufacturer: model.manufacturer,
                    model: model.model,
                    nativeIdentityFingerprint: model.nativeIdentityFingerprint,
                    identitySource: model.identitySource,
                    identityScope: model.identityScope,
                    identityStability: model.identityStability,
                    linkedAt: model.linkedAt,
                    lastSeenAt: model.lastSeenAt,
                    linkedByUid: model.linkedByUid,
                    onlineUntil: model.onlineUntil,
                    sessionId: model.sessionId,
                    createdAt: model.createdAt,
                    updatedAt: model.updatedAt,
                  );
                }).toList();

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: devices.length,
                  itemBuilder: (ctx, i) {
                    final device = devices[i];
                    return DeviceCard(
                      key: ValueKey(device.id),
                      device: device,
                      onTap: () => context.push('/devices/${device.id}'),
                    );
                  },
                );
              },
            );
          },
        ),
    );
  }
}
