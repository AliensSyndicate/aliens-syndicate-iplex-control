import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../iptv/presentation/controllers/iptv_sync_controller.dart';

class IptvPage extends ConsumerStatefulWidget {
  const IptvPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<IptvPage> createState() => _IptvPageState();
}

class _IptvPageState extends ConsumerState<IptvPage> {
  bool syncBusy = false;
  bool deleteBusy = false;

  Future<void> syncNow() async {
    if (syncBusy) return;
    setState(() => syncBusy = true);
    try {
      await ref.read(repositoryProvider).mutate('syncSource', {
        'id': widget.id,
      });
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => syncBusy = false);
    }
  }

  Future<void> deleteSource() async {
    if (deleteBusy) return;
    final confirmed = await confirmRemoval(
      context,
      title: context.l.confirmDeleteSourceTitle,
      body: context.l.confirmDeleteSourceBody,
    );
    if (!confirmed || !mounted) return;

    setState(() => deleteBusy = true);
    try {
      await ref.read(repositoryProvider).mutate('deleteSource', {
        'id': widget.id,
      });
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => deleteBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final key = (collection: 'sources', id: widget.id);
    final admin = ref.watch(canManageIptvProvider);

    return Scaffold(
      body: ref
          .watch(entryProvider(key))
          .when(
            loading: () => const AppLoadingSkeleton(),
            error: (e, s) =>
                ErrorState(onRetry: () => ref.invalidate(entryProvider(key))),
            data: (e) {
              if (e == null) return Center(child: Text(l.notFound));

              final isProtected = e.data['isProtected'] == true;
              final isUnlocked = ref
                  .watch(unlockedSourcesProvider)
                  .contains(widget.id);

              if (isProtected && !isUnlocked) {
                return PageTemplate(
                  title: e.name,
                  subtitle: l.enterPinTitle,
                  showBack: true,
                  child: Column(
                    children: [
                      const SizedBox(height: AppSpacing.xl),
                      GraphiteSurface(
                        circle: true,
                        recessed: true,
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: const AppIcon(
                          AppIcons.lock,
                          size: 48,
                          color: AppColors.brandBlue,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        l.enterPinTitle,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        l.enterPinBody,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AppButton(
                        label: l.unlock,
                        onPressed: () =>
                            showPinUnlockDialog(context, ref, widget.id),
                      ),
                    ],
                  ),
                );
              }

              // A retryable failure keeps the source queued: the worker tries again
              // by itself, so it is shown as pending, not as a final failure.
              final isRetrying =
                  e.text('status') == 'queued' && e.text('errorCode').isNotEmpty;
              final isError = e.text('status') == 'error' ||
                  (e.text('errorCode').isNotEmpty && !isRetrying);
              final isSyncing =
                  e.text('status') == 'syncing' ||
                  e.text('status') == 'validating' ||
                  isRetrying;
              final isReady =
                  e.text('status') == 'ready' || e.text('status') == 'online';
              final isOnline =
                  !isError && !isSyncing && isReady && e.data['enabled'] != false;
              final formatName = switch (e.text('format')) {
                'file' => l.sourceFormatFile,
                'xtream' => l.sourceFormatXtream,
                'other_m3u8' => l.sourceFormatOtherM3u8,
                'url' => l.sourceFormatUrl,
                _ => l.sourceFormatM3u,
              };
              final locale = Localizations.localeOf(context).toString();

              final lastSyncTimestamp = (e.data['lastSuccessfulSyncAt'] != null ? e.number('lastSuccessfulSyncAt') : e.number('lastSyncAt'));
              final String lastSyncStr;
              if (lastSyncTimestamp > 0) {
                lastSyncStr = (locale.startsWith('pt') ? DateFormat("dd/MM/yyyy 'às' HH:mm", locale) : DateFormat.yMd(locale).add_Hm()).format(
                  DateTime.fromMillisecondsSinceEpoch(lastSyncTimestamp),
                );
              } else {
                lastSyncStr = l.neverSynced;
              }

              final itemCount = e.number('count');
              final isSingleStream = e.data['isSingleStream'] == true;

              return PageTemplate(
                title: '',
                showBack: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                    Text(
                                      e.name,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Row(
                                      children: [
                                        if (isSyncing) ...[
                                          const SizedBox.square(
                                            dimension: 10,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              color: AppColors.brandBlue,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              isRetrying ? l.sourceRetrying : l.sourceSyncing,
                                              style: const TextStyle(
                                                color: AppColors.brandBlue,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ] else if (isError) ...[
                                          const NeumorphicStatusIndicator(
                                            status: IndicatorStatus.error,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              l.sourceFailure,
                                              style: const TextStyle(
                                                color: AppColors.error,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ] else if (isOnline) ...[
                                          const NeumorphicStatusIndicator(
                                            status: IndicatorStatus.online,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              l.online,
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ] else ...[
                                          const NeumorphicStatusIndicator(
                                            status: IndicatorStatus.offline,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              l.offline,
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (isProtected)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: AppSpacing.xxs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceRecessed,
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.xs,
                                    ),
                                    border: Border.all(
                                      color: AppColors.borderLight,
                                      width: AppDimensions.borderWidth,
                                    ),
                                  ),
                                  child: Text(
                                    l.protectedBadge,
                                    style: const TextStyle(
                                      color: AppColors.brandBlue,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          const Divider(
                            color: AppColors.borderLight,
                            height: 1,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _SourceDetailRow(
                            label: l.sourceType,
                            value: formatName,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _SourceDetailRow(
                            label: e.text('format') == 'file'
                                ? l.sourceFile
                                : l.sourceHost,
                            value: e.text('format') == 'file'
                                ? (e.text('fileName').isNotEmpty
                                      ? e.text('fileName')
                                      : e.text('host'))
                                : e.text('host'),
                          ),
                          if (e.data['hasEpg'] == true) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _SourceDetailRow(
                              label: l.epgUrl,
                              value: l.iptvEpgConfigured,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          _SourceDetailRow(
                            label: lastSyncTimestamp > 0 ? l.lastSync(lastSyncStr) : l.neverSynced,
                            value: '',
                            isFullLabel: true,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _SourceDetailRow(
                            label: l.catalogSummary,
                            value: isSingleStream
                                ? l.singleStream
                                : l.itemCount(itemCount),
                          ),
                          if (!isSingleStream && e.data['channelCount'] is num) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _SourceDetailRow(
                              label: l.catalogKinds(
                                e.number('channelCount'),
                                e.number('movieCount'),
                                e.number('seriesCount'),
                              ),
                              value: '',
                              isFullLabel: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isError || isRetrying) ...[
                      const SizedBox(height: AppSpacing.lg),
                      AppSurface(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const AppIcon(
                              AppIcons.alert,
                              size: AppDimensions.icon,
                              color: AppColors.error,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    [
                                      mapIptvErrorCodeToMessage(context, e.text('errorCode')),
                                      if (e.text('version').isNotEmpty) l.previousCatalogKept,
                                    ].join(' '),
                                    key: const Key('source-error-message'),
                                    style: const TextStyle(
                                      color: AppColors.error,
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                  ),
                                  if (e.text('errorReason').isNotEmpty) ...[
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      l.technicalDetail(e.text('errorReason')),
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (admin) ...[
                      const SizedBox(height: AppTokens.xl),
                      AppButton(
                        label: l.syncNow,
                        busy: syncBusy,
                        onPressed: syncNow,
                      ),
                      const SizedBox(height: AppTokens.md),
                      AppButton(
                        label: l.editSource,
                        onPressed: () =>
                            context.push('/iptv/${e.id}/edit', extra: e.name),
                      ),
                      const SizedBox(height: AppTokens.md),
                      AppButton(
                        label: l.deleteSource,
                        busy: deleteBusy,
                        onPressed: deleteSource,
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

class _SourceDetailRow extends StatelessWidget {
  const _SourceDetailRow({
    required this.label,
    required this.value,
    this.isFullLabel = false,
  });
  final String label, value;
  final bool isFullLabel;

  @override
  Widget build(BuildContext context) => isFullLabel || value.isEmpty
      ? Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        )
      : Row(
          children: [
            Text(
              '$label: ',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
}

/// Backward compatibility alias
typedef IptvSourceDetailsPage = IptvPage;
