import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/providers.dart';
import '../../../core/design_system/components.dart';
import '../../../core/domain/models.dart';
import 'iptv_source_status.dart';

class IptvSourceCard extends ConsumerWidget {
  const IptvSourceCard({super.key, required this.entry});
  final Entry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final isProtected = entry.data['isProtected'] == true;

    final lastSyncTimestamp = (entry.data['lastSuccessfulSyncAt'] != null
        ? entry.number('lastSuccessfulSyncAt')
        : entry.number('lastSyncAt'));
    final syncInfo = lastSyncTimestamp > 0
        ? formatCardDateTime(
            context,
            DateTime.fromMillisecondsSinceEpoch(lastSyncTimestamp),
          )
        : l.neverSynced;

    // Reference: "Card de IPTV".
    return InfoCard(
      icon: AppIcons.iptv,
      title: entry.name,
      titlePrefix: isProtected
          ? const AppIcon(AppIcons.lock, size: 14, color: AppColors.primary)
          : null,
      // Name and the date/time of the last sync; the state is the
      // indicator on the right.
      status: syncInfo,
      // The state is only the indicator (green / red / grey).
      dot: IptvSourceIndicator(source: entry),
      onTap: () async {
        if (isProtected &&
            !ref.read(unlockedSourcesProvider).contains(entry.id)) {
          final unlocked = await showPinUnlockDialog(context, ref, entry.id);
          if (!unlocked || !context.mounted) return;
        }
        if (context.mounted) context.push('/iptv/${entry.id}');
      },
    );
  }
}
