import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import 'iptv_page.dart';
import 'iptv_source_status.dart';

class _DeviceStatusRow extends ConsumerWidget {
  const _DeviceStatusRow({required this.entry});
  final Entry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final isOnline = ref.watch(
      clockProvider.select(
        (time) => entry.onlineAt(time.value ?? DateTime.now()),
      ),
    );
    return Row(
      children: [
        NeumorphicStatusIndicator(online: isOnline),
        const SizedBox(width: 8),
        Text(
          isOnline ? l.online : l.offline,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _DeviceRemoteAction extends ConsumerWidget {
  const _DeviceRemoteAction({required this.entry});
  final Entry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final isOnline = ref.watch(
      clockProvider.select(
        (time) => entry.onlineAt(time.value ?? DateTime.now()),
      ),
    );
    if (!isOnline) return const SizedBox.shrink();
    return AppButton(
      label: l.remote,
      icon: AppIcons.devices,
      onPressed: () => context.push('/devices/${entry.id}/remote'),
    );
  }
}

class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({super.key, required this.collection, required this.id});
  final String collection, id;
  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  bool busy = false;
  Future<void> remove() async {
    if (!await confirmRemoval(context) || !mounted) return;
    setState(() => busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .mutate(
            switch (widget.collection) {
              'devices' => 'deleteDevice',
              'sources' => 'deleteSource',
              'members' => 'removeMember',
              _ => 'deleteProfile',
            },
            {'id': widget.id},
          );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collection == 'sources') {
      return IptvPage(id: widget.id);
    }
    final l = context.l,
        key = (collection: widget.collection, id: widget.id),
        admin = (widget.collection == 'members' ? ref.watch(adminProvider) : ref.watch(canManageResourcesProvider));
    return Scaffold(
      body: ref
          .watch(entryProvider(key))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) =>
                ErrorState(onRetry: () => ref.invalidate(entryProvider(key))),
            data: (e) {
              if (e == null) return Center(child: Text(l.notFound));
              final removable =
                  admin &&
                  (widget.collection != 'members' || e.text('role') != 'admin');
              return PageTemplate(
                title: e.name,
                showBack: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.collection == 'devices') ...[
                      AppSurface(
                        child: Row(
                          children: [
                            const AppIcon(
                              AppIcons.devices,
                              size: AppTokens.xxl,
                            ),
                            const SizedBox(width: AppTokens.lg),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _DeviceStatusRow(entry: e),
                                  if (e.number('lastSeenAt') > 0) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${l.lastSeen}: ${DateFormat.yMd(Localizations.localeOf(context).toString()).add_Hm().format(DateTime.fromMillisecondsSinceEpoch(e.number('lastSeenAt')))}',
                                      style: const TextStyle(
                                        color: AppTokens.secondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppTokens.xl),
                      _DeviceRemoteAction(entry: e),
                    ],
                    if (widget.collection == 'sources') ...[
                      AppSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const AppIcon(
                                  AppIcons.iptv,
                                  size: AppTokens.xxl,
                                ),
                                const SizedBox(width: AppTokens.lg),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.text('host'),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          NeumorphicStatusIndicator(
                                            online: e.text('status') == 'ready',
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            iptvSourceStatus(context, e),
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppTokens.md),
                            Text(
                              l.itemCount(e.number('count')),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (widget.collection == 'profiles') ...[
                      EntryTile(
                        title: l.favorites,
                        icon: AppIcons.favorite,
                        onTap: () => context.push('/users/${e.id}/favorites'),
                      ),
                      EntryTile(
                        title: l.continueWatching,
                        icon: AppIcons.play,
                        onTap: () => context.push('/users/${e.id}/progress'),
                      ),
                    ],
                    if (admin && widget.collection != 'members') ...[
                      const SizedBox(height: AppTokens.xl),
                      AppButton(
                        label: l.edit,
                        onPressed: () => context.push(
                          '/${switch (widget.collection) {
                            'sources' => 'iptv',
                            'profiles' => 'users',
                            _ => 'devices',
                          }}/${e.id}/edit',
                          extra: e.name,
                        ),
                      ),
                    ],
                    if (removable) ...[
                      const SizedBox(height: AppTokens.xl),
                      AppButton(label: l.remove, busy: busy, onPressed: remove),
                    ],
                  ],
                ),
              );
            },
          ),
    );
  }
}
