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
  backgroundColor: Colors.black,
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
  List<TvEpisode> episodes = const [];

  Entry get item => widget.item;

  @override
  void initState() {
    super.initState();
    if (item.isPlayableTitle) {
      metadata = ref.read(metadataServiceProvider).details(item);
    }
    final epgId = item.text('epgId');
    if (item.isChannel && epgId.isNotEmpty) guide = _loadGuide(epgId);
    if (item.kind == 'series') _loadEpisodes();
  }

  /// Seasons and episodes come from the source itself (never from TMDB), so
  /// they show even when no TMDB match exists.
  Future<void> _loadEpisodes() async {
    try {
      final result = await ref.read(repositoryProvider).mutate(
        'readSourceSeries',
        {'id': item.sourceId, 'seriesId': item.text('providerRef')},
      );
      final list = parseEpisodes(result['details']);
      if (mounted) setState(() => episodes = list);
    } catch (_) {
      // Optional section: the sheet stays complete without it.
    }
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

  /// The one episode shown for a series: the one in progress, else the first
  /// available. Never the whole list.
  TvEpisode? get _episode {
    if (item.kind != 'series' || episodes.isEmpty) return null;
    return episodes.where((e) => e.id == item.episodeId).firstOrNull ??
        episodes.first;
  }

  void watchOnTv({bool resume = false}) {
    final navigator = Navigator.of(context);
    final host = navigator.context;
    navigator.pop();
    showWatchOnTv(
      host,
      item,
      resume: resume,
      episodeId: resume ? item.episodeId : _episode?.id,
    );
  }

  /// "1h 58min" / "45 min" — locale-neutral.
  String _duration(int minutes) => minutes >= 60
      ? '${minutes ~/ 60}h${minutes % 60 == 0 ? '' : ' ${minutes % 60}min'}'
      : context.l.runtimeMinutes(minutes);

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final channel = item.isChannel;
    // showAppModalSheet keeps the top margin equal to the status bar, so the
    // available height is the full-screen sheet.
    return LayoutBuilder(
      builder: (context, box) => SizedBox(
        height: box.maxHeight,
        child: FutureBuilder<ContentMetadata?>(
          future: metadata,
          builder: (context, snapshot) {
            final meta = snapshot.data;
            final loading =
                metadata != null &&
                snapshot.connectionState != ConnectionState.done;
            return Stack(
              fit: StackFit.expand,
              children: [
                // Fixed artwork over the whole sheet; only the content scrolls.
                Positioned.fill(
                  // Full width; the height follows the image and the rest of the
                  // sheet is the deep background the gradient fades into.
                  child: Artwork(
                    item: item,
                    fit: channel ? BoxFit.contain : BoxFit.fitWidth,
                    alignment: Alignment.topCenter,
                    background: Colors.black,
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0),
                          Colors.black.withValues(alpha: 0.75),
                          Colors.black,
                        ],
                        stops: const [0.35, 0.62, 0.8],
                      ),
                    ),
                  ),
                ),
                SheetDragDismiss(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      box.maxHeight * 0.55,
                      AppSpacing.lg,
                      AppSpacing.xl + padding.bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ..._summary(context, meta),
                        if (loading) ...[
                          const SizedBox(height: AppSpacing.lg),
                          const _TextSkeleton(),
                        ],
                        ..._details(context, meta),
                        const SizedBox(height: AppSpacing.lg),
                        ..._actions(context),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Title, "2021 | Gênero | 1h 25min", rating stars and the play control.
  List<Widget> _summary(BuildContext context, ContentMetadata? meta) {
    final l = context.l;
    final channel = item.isChannel;
    final resume = item.progress != null && !channel;
    final year = meta?.year ?? item.year;
    final genres = meta?.genres ?? const <String>[];
    final category = item.text('category');
    final minutes = meta?.runtimeMinutes;
    final facts = <String>[
      if (channel) l.liveChannel,
      if (!channel && year != null) '$year',
      if (genres.isNotEmpty)
        genres.first
      else if (category.isNotEmpty)
        category,
      if (minutes != null && item.kind == 'movie') _duration(minutes),
      if (_episode case final e?)
        e.number.isEmpty
            ? l.seasonNumber(e.season)
            : l.seasonEpisodeShort(e.season, e.number)
      else if (item.kind == 'series' && _seasons(meta) > 0)
        l.seasonsCount(_seasons(meta)),
    ];
    final score = meta?.rating ?? double.tryParse(item.text('rating'));
    final stars = score == null || channel
        ? null
        : (score.clamp(0, 10) / 2).toDouble();
    return [
      Text(
        item.name,
        textAlign: TextAlign.center,
        style: AppTypography.headlineMedium.copyWith(
          color: AppColors.textPrimary,
        ),
      ),
      if (facts.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          facts.join(' | '),
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
      if (stars != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Row(
          key: const Key('details-stars'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 5; i++)
              Icon(
                stars >= i + 1
                    ? Icons.star_rounded
                    : stars >= i + 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
                size: 22,
                color: AppColors.warning,
              ),
          ],
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      AppButton(
        key: Key(resume ? 'details-continue' : 'details-watch-on-tv'),
        label: resume ? l.continueWatchingOnTv : l.watchOnTv,
        onPressed: () => watchOnTv(resume: resume),
      ),
      const SizedBox(height: AppSpacing.lg),
    ];
  }

  int _seasons(ContentMetadata? meta) =>
      meta?.seasonCount ?? {for (final e in episodes) e.season}.length;

  /// Everything else, revealed by "Show more".
  List<Widget> _details(BuildContext context, ContentMetadata? meta) {
    final l = context.l;
    final age =
        meta?.certification ??
        (item.text('ageRating').isEmpty ? null : item.text('ageRating'));
    final genres = meta?.genres ?? const <String>[];
    final category = item.text('category');
    final rows = <(String, bool)>[
      if (age != null) (l.ageRatingLabel(age), true),
      if (meta?.runtimeMinutes != null && item.kind != 'movie')
        (_duration(meta!.runtimeMinutes!), true),
      if (item.kind == 'series' && episodes.isNotEmpty)
        (l.episodesCount(episodes.length), true),
      if (genres.isNotEmpty) (genres.take(6).join(', '), false),
      if (category.isNotEmpty &&
          !genres.any((g) => g.toLowerCase() == category.toLowerCase()))
        (category, false),
    ];
    // One item per line, in a single column.
    return [
      for (final (text, primary) in rows) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          text,
          style: AppTypography.bodyMedium.copyWith(
            color: primary ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ],
      ..._body(context, meta),
    ];
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
          '${l.castLabel}: ${meta.cast.take(10).join(', ')}',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
      if (_episode case final e?) ...[
        const SizedBox(height: AppSpacing.lg),
        Text(
          l.episodesTitle,
          style: AppTypography.titleLarge.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          [
            l.seasonNumber(e.season),
            if (e.number.isNotEmpty) l.episodeNumber(e.number),
            if (e.title.isNotEmpty) e.title,
          ].join(' · '),
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
    return [
      if (profile != null && profile.persistent) ...[
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const Key('details-favorite'),
          busy: busy,
          label: item.isChannel
              ? (favorite ? l.removeFromFavorites : l.addToFavorites)
              : (favorite ? l.removeFromMyList : l.addToMyList),
          onPressed: toggleFavorite,
        ),
      ],
    ];
  }
}

class _Programme {
  const _Programme(this.title, this.start, this.end);
  final String title;
  final DateTime start, end;
}

/// Loading placeholder for this sheet: text only, no boxes.
class _TextSkeleton extends StatefulWidget {
  const _TextSkeleton();
  @override
  State<_TextSkeleton> createState() => _TextSkeletonState();
}

class _TextSkeletonState extends State<_TextSkeleton>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.35, end: 1).animate(controller),
    child: Text(
      '${context.l.loading}…',
      textAlign: TextAlign.center,
      style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
    ),
  );
}
