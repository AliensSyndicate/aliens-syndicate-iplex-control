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
    final isError = entry.text('status') == 'error' ||
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

    final lastSyncTimestamp = (entry.data['lastSuccessfulSyncAt'] != null ? entry.number('lastSuccessfulSyncAt') : entry.number('lastSyncAt'));
    final String syncInfo;
    if (lastSyncTimestamp > 0) {
      final locale = Localizations.localeOf(context).toString();
      final formattedTime = (locale.startsWith('pt') ? DateFormat("dd/MM/yyyy 'às' HH:mm", locale) : DateFormat.yMd(locale).add_Hm())
          .format(DateTime.fromMillisecondsSinceEpoch(lastSyncTimestamp));
      syncInfo = l.lastSync(formattedTime);
    } else {
      syncInfo = l.neverSynced;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GraphiteSurface(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.card),
            onTap: () async {
              if (isProtected &&
                  !ref.read(unlockedSourcesProvider).contains(entry.id)) {
                final unlocked = await showPinUnlockDialog(
                  context,
                  ref,
                  entry.id,
                );
                if (!unlocked || !context.mounted) return;
              }
              if (context.mounted) {
                context.push('/iptv/${entry.id}');
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const GraphiteSurface(
                    circle: true,
                    recessed: true,
                    padding: EdgeInsets.all(
                      AppSpacing.sm + AppSpacing.xs,
                    ),
                    child: AppIcon(
                      AppIcons.iptv,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isProtected) ...[
                              const AppIcon(
                                AppIcons.lock,
                                size: 14,
                                color: AppColors.brandBlue,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                entry.name,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          isSyncing
                              ? l.sourceSyncing
                              : (isError
                                  ? l.sourceFailure
                                  : (isOnline
                                      ? l.online
                                      : l.offline)),
                          style: TextStyle(
                            color: isError
                                ? AppColors.error
                                : (isSyncing
                                    ? AppColors.brandBlue
                                    : AppColors.textSecondary),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          syncInfo,
                          style: const TextStyle(
                            color: AppColors.textDisabled,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (isSyncing)
                    const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.brandBlue,
                      ),
                    )
                  else if (isError)
                    const NeumorphicStatusIndicator(
                      status: IndicatorStatus.error,
                    )
                  else if (isOnline)
                    const NeumorphicStatusIndicator(
                      status: IndicatorStatus.online,
                    )
                  else
                    const NeumorphicStatusIndicator(
                      status: IndicatorStatus.offline,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
