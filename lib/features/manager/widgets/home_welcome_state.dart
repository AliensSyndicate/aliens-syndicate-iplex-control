import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/providers.dart';
import '../../../core/design_system/components.dart';

class HomeWelcomeState extends ConsumerWidget {
  const HomeWelcomeState({super.key, this.catalogEmpty = false});
  final bool catalogEmpty;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).asData?.value;
    final canAdd = ref.watch(canManageResourcesProvider);
    final canManageIptv = ref.watch(canManageIptvProvider);
    final noFamily = account?.familyId == null;
    final isMember =
        ref.watch(familyProvider).asData?.value != null &&
        !canAdd &&
        !canManageIptv;
    final l = context.l;
    return EmptyState(
      title: l.homeWelcome,
      body: isMember
          ? l.memberSetupHint
          : catalogEmpty
          ? l.catalogEmptyBody
          : l.homeSetupBody,
      action: Column(
        children: [
          AppButton(
            label: canAdd || noFamily ? l.addDevice : l.devices,
            icon: AppIcons.devices,
            onPressed: () => context.go(
              ref.watch(adminProvider) ? '/devices/add' : '/devices',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: canManageIptv ? l.configureIptv : l.iptv,
            icon: AppIcons.iptv,
            onPressed: () => context.go('/iptv'),
          ),
        ],
      ),
    );
  }
}
