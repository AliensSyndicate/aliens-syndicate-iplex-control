import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/data/providers.dart';
import '../../../core/design_system/components.dart';
import '../../../core/domain/models.dart';

class IptvSourceCard extends ConsumerWidget {
  const IptvSourceCard({super.key, required this.entry});
  final Entry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    // Retryable failures stay queued and are retried by the worker: pending, not failed.
    final isRetrying =
        entry.text('status') == 'queued' && entry.text('errorCode').isNotEmpty;
    final isError =
        entry.text('status') == 'error' ||
        (entry.text('errorCode').isNotEmpty && !isRetrying);
    final isSyncing =
        entry.text('status') == 'syncing' ||
        entry.text('status') == 'validating' ||
        isRetrying;
    final isReady =
        entry.text('status') == 'ready' || entry.text('status') == 'online';
    final isOnline =
        !isError && !isSyncing && isReady && entry.data['enabled'] != false;
    final isProtected = entry.data['isProtected'] == true;

    final lastSyncTimestamp = (entry.data['lastSuccessfulSyncAt'] != null
        ? entry.number('lastSuccessfulSyncAt')
        : entry.number('lastSyncAt'));
    final String syncInfo;
    if (lastSyncTimestamp > 0) {
      final locale = Localizations.localeOf(context).toString();
      final formattedTime =
          (locale.startsWith('pt')
                  ? DateFormat("dd/MM/yyyy 'às' HH:mm", locale)
                  : DateFormat.yMd(locale).add_Hm())
              .format(DateTime.fromMillisecondsSinceEpoch(lastSyncTimestamp));
      syncInfo = l.lastSync(formattedTime);
    } else {
      syncInfo = l.neverSynced;
    }

    final counts = isReady && !isSyncing && !isError
        ? l.catalogKinds(
            entry.number('channelCount'),
            entry.number('movieCount'),
            entry.number('seriesCount'),
          )
        : null;
    // Reference: "Card de IPTV".
    return InfoCard(
      icon: AppIcons.iptv,
      title: entry.name,
      titlePrefix: isProtected
          ? const AppIcon(AppIcons.lock, size: 14, color: AppColors.primary)
          : null,
      status: isSyncing
          ? l.sourceSyncing
          : isError
          ? l.sourceFailure
          : (isOnline ? l.online : l.offline),
      statusColor: isError
          ? AppColors.error
          : isSyncing
          ? AppColors.primary
          : null,
      extra: counts,
      footnote: syncInfo,
      // Reference "Card de IPTV": neutral icon box; state on the dot.
      dot: NeumorphicStatusIndicator(
        status: isError
            ? IndicatorStatus.error
            : isOnline
            ? IndicatorStatus.online
            : IndicatorStatus.offline,
      ),
      trailing: isSyncing
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            )
          : null,
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
