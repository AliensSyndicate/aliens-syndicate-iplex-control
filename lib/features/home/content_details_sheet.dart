import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import '../watch_on_tv/watch_on_tv_sheet.dart';
import 'home_data.dart';
import 'home_widgets.dart';
import 'metadata_service.dart';

/// Details of a catalog item. Actions start a title on a paired TV (the
/// existing "Assistir na TV" flow) or change the profile's lists — the
/// Control never becomes a remote control (no pause/seek/stop/volume).
Future<void> showContentDetails(
  BuildContext context, {
  required Entry item,
  required HomeProfile? profile,
  required bool favorite,
  required VoidCallback onLibraryChanged,
}) => showAppModalSheet<void>(
  context: context,
  builder: (_) => ContentDetailsSheet(
    item: item,
    profile: profile,
    favorite: favorite,
    onLibraryChanged: onLibraryChanged,
  ),
);

class ContentDetailsSheet extends ConsumerStatefulWidget {
  const ContentDetailsSheet({
    super.key,
    required this.item,
    required this.profile,
    required this.favorite,
    required this.onLibraryChanged,
  });
  final Entry item;
  final HomeProfile? profile;
  final bool favorite;
  final VoidCallback onLibraryChanged;

  @override
  ConsumerState<ContentDetailsSheet> createState() =>
      _ContentDetailsSheetState();
}

class _ContentDetailsSheetState extends ConsumerState<ContentDetailsSheet> {
  late bool favorite = widget.favorite;
  bool busy = false;
  Future<ContentMetadata?>? metadata;
  Future<List<_Programme>>? guide;

  Entry get item => widget.item;

  @override
  void initState() {
    super.initState();
    if (item.isPlayableTitle) {
      metadata = ref.read(metadataServiceProvider).details(item);
    }
    final epgId = item.text('epgId');
    if (item.isChannel && epgId.isNotEmpty) guide = _loadGuide(epgId);
  }

  Future<List<_Programme>> _loadGuide(String epgId) async {
    final result = await ref.read(repositoryProvider).mutate('readSourceEpg', {
      'id': item.sourceId,
      'channelId': epgId,
    });
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      for (final raw in (result['programmes'] as List? ?? const []))
        if (raw is Map &&
            raw['title'] is String &&
            (raw['endAt'] as num? ?? 0) > now)
          _Programme(
            '${raw['title']}',
            DateTime.fromMillisecondsSinceEpoch(
              (raw['startAt'] as num).toInt(),
            ),
            DateTime.fromMillisecondsSinceEpoch((raw['endAt'] as num).toInt()),
          ),
    ].take(3).toList();
  }

  Future<void> toggleFavorite() async {
    final profile = widget.profile;
    if (profile == null || busy) return;
    setState(() => busy = true);
    try {
      await ref.read(repositoryProvider).mutate('favorite', {
        'profileId': profile.id,
        'contentId': item.id,
        'title': item.name,
        'generation': profile.favoritesGeneration,
        if (favorite) 'remove': true,
      });
      if (!mounted) return;
      setState(() => favorite = !favorite);
      widget.onLibraryChanged();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void watchOnTv({bool resume = false}) {
    final navigator = Navigator.of(context);
    final host = navigator.context;
    navigator.pop();
    showWatchOnTv(
      host,
      item,
      resume: resume,
      episodeId: resume ? item.episodeId : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: FutureBuilder<ContentMetadata?>(
            future: metadata,
            builder: (context, snapshot) {
              final meta = snapshot.data;
              final loading =
                  metadata != null &&
                  snapshot.connectionState != ConnectionState.done;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (meta?.backdrop != null)
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Artwork(item: item, backdrop: true),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  AppColors.surfaceDefault,
                                ],
                                stops: [0.55, 1],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(item: item, meta: meta),
                        if (loading) ...[
                          const SizedBox(height: AppSpacing.lg),
                          const AppLoadingSkeleton(rows: 1),
                        ],
                        ..._body(context, meta),
                        const SizedBox(height: AppSpacing.lg),
                        ..._actions(context),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, ContentMetadata? meta) {
    final l = context.l;
    final synopsis = (meta?.overview.isNotEmpty ?? false)
        ? meta!.overview
        : item.text('plot');
    return [
      if (synopsis.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        Text(
          synopsis,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
            height: 1.45,
          ),
        ),
      ],
      if (meta != null && meta.cast.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        Text(
          '${l.castLabel}: ${meta.cast.take(6).join(', ')}',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
      if (guide != null)
        FutureBuilder<List<_Programme>>(
          future: guide,
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const <_Programme>[];
            if (rows.isEmpty) return const SizedBox.shrink();
            final local = MaterialLocalizations.of(context);
            String time(DateTime t) =>
                local.formatTimeOfDay(TimeOfDay.fromDateTime(t));
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (index, p) in rows.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        '${index == 0 && !p.start.isAfter(DateTime.now()) ? l.onAirNow : l.upNext} · ${time(p.start)}–${time(p.end)} · ${p.title}',
                        style: AppTypography.bodyMedium.copyWith(
                          color: index == 0
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
    ];
  }

  List<Widget> _actions(BuildContext context) {
    final l = context.l;
    final profile = widget.profile;
    final progress = item.progress;
    return [
      if (progress != null && !item.isChannel) ...[
        AppButton(
          key: const Key('details-continue'),
          label: l.continueWatchingOnTv,
          icon: AppIcons.play,
          onPressed: () => watchOnTv(resume: true),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      AppButton(
        key: const Key('details-watch-on-tv'),
        label: l.watchOnTv,
        icon: AppIcons.devices,
        onPressed: watchOnTv,
      ),
      if (profile != null && profile.persistent) ...[
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const Key('details-favorite'),
          busy: busy,
          label: item.isChannel
              ? (favorite ? l.removeFromFavorites : l.addToFavorites)
              : (favorite ? l.removeFromMyList : l.addToMyList),
          icon: item.isChannel
              ? AppIcons.favorite
              : (favorite ? AppIcons.check : AppIcons.add),
          onPressed: toggleFavorite,
        ),
      ],
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item, required this.meta});
  final Entry item;
  final ContentMetadata? meta;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final channel = item.isChannel;
    final year = meta?.year ?? item.year;
    final age =
        meta?.certification ??
        (item.text('ageRating').isEmpty ? null : item.text('ageRating'));
    final facts = <String>[
      if (channel) l.liveChannel,
      if (!channel && year != null) '$year',
      if (meta?.runtimeMinutes != null && item.kind == 'movie')
        l.runtimeMinutes(meta!.runtimeMinutes!),
      if (meta?.seasonCount != null && item.kind == 'series')
        l.seasonsCount(meta!.seasonCount!),
      if (age != null) l.ageRatingLabel(age),
    ];
    final genres = meta?.genres ?? const <String>[];
    final category = item.text('category');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: SizedBox(
            width: channel ? 112 : 80,
            height: channel ? 64 : 120,
            child: Artwork(
              item: item,
              fit: channel ? BoxFit.contain : BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: AppTypography.titleLarge.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              if (facts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  facts.join(' · '),
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (genres.isNotEmpty || category.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  genres.isNotEmpty ? genres.take(3).join(', ') : category,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (item.text('sourceName').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.text('sourceName'),
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Programme {
  const _Programme(this.title, this.start, this.end);
  final String title;
  final DateTime start, end;
}
