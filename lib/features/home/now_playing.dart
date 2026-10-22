import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import '../watch_on_tv/watch_on_tv_sheet.dart';
import 'content_details_page.dart';
import 'home_data.dart';
import 'home_widgets.dart';
import 'library.dart';

/// PREVIEW: the bar is shown even when nothing plays on a TV, with the first
/// "Continuar assistindo" title of the account (real data), so the layout
/// can be reviewed. The final rule — only while a TV of this same account
/// is playing — replaces [_previewItem] in [nowPlayingProvider].
const kNowPlayingPreview = true;

/// What the account is watching on a TV: the catalog item, its progress
/// (movies/series) and, for series, the episode.
@immutable
class NowPlaying {
  const NowPlaying({required this.item, this.deviceId});
  final Entry item;

  /// TV that plays it (null in preview).
  final String? deviceId;
}

Entry? _previewItem(HomeData? home) {
  if (home == null) return null;
  return home.continueWatching.firstOrNull ??
      [
        ...home.recentMovies,
        ...home.recentSeries,
        ...home.libraryFavorites.where((i) => !i.isEditorial),
      ].firstOrNull;
}

final nowPlayingProvider = Provider.autoDispose<NowPlaying?>((ref) {
  if (!kNowPlayingPreview) return null;
  final item = _previewItem(ref.watch(currentHomeProvider).asData?.value);
  return item == null ? null : NowPlaying(item: item);
});

/// "Temporada 1 - Episódio 3" of the episode in progress, from the source
/// itself (never guessed).
final _episodeLabelProvider = FutureProvider.autoDispose
    .family<String?, (String, String, String)>((ref, key) async {
      final (sourceId, providerRef, episodeId) = key;
      final result = await ref.read(repositoryProvider).mutate(
        'readSourceSeries',
        {'id': sourceId, 'seriesId': providerRef},
      );
      final episode = parseEpisodes(result['details'])
          .where((e) => e.id == episodeId)
          .firstOrNull;
      return episode == null
          ? null
          : '${episode.season}|${int.tryParse(episode.number) ?? episode.number}';
    }, retry: (retryCount, error) => null);

/// "Now playing" item of the Home (Meu iPlex, between the tabs and the
/// rows): artwork, name, kind with runtime (and episode for series) and the
/// progress for movies/series; a tap opens the title.
class NowPlayingBar extends ConsumerWidget {
  const NowPlayingBar({super.key, required this.playing});
  final NowPlaying playing;

  /// Poster in 2:3 (channel logos keep a square) and the item around it.
  static const posterHeight = 72.0, posterWidth = posterHeight * 2 / 3;
  static const height = posterHeight + 2 * AppSpacing.md;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final item = playing.item;
    final channel = item.isChannel;
    // Movies and series always show the track (empty without progress).
    final progress = channel ? null : (item.progress?.fraction ?? 0);
    // "Filme · 1h 58min", "Série · T1E2 · 45min", "Ao vivo". The runtime is
    // the duration of what is being watched (saved with the progress).
    String? episode;
    final episodeId = item.episodeId;
    if (item.kind == 'series' && episodeId != null) {
      final raw = ref
          .watch(
            _episodeLabelProvider((
              item.sourceId,
              item.text('providerRef'),
              episodeId,
            )),
          )
          .asData
          ?.value;
      if (raw != null) {
        final [season, number] = raw.split('|');
        final n = int.tryParse(number);
        episode = n == null
            ? l.seasonNumber(int.parse(season))
            : l.seasonEpisodeShort(int.parse(season), '$n');
      }
    }
    final seconds = item.progress?.duration;
    final minutes = seconds == null || seconds <= 0
        ? null
        : (seconds / 60).round();
    final subtitle = [
      switch (item.kind) {
        'channel' => l.channelKind,
        'series' => l.seriesKind,
        _ => l.movieKind,
      },
      if (item.kind == 'series') ?episode,
      if (!channel && minutes != null && minutes > 0)
        formatRuntime(context, minutes),
    ].join(' · ');
    return Semantics(
      container: true,
      label: [item.name, subtitle].join(', '),
      child: Container(
        key: const Key('now-playing-bar'),
        height: height,
        decoration: const BoxDecoration(),
        child: Stack(
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => openTitle(context, item),
                    // Same inner padding as the device cards.
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.xs),
                            child: SizedBox(
                              key: const Key('now-playing-art'),
                              width: channel ? posterHeight : posterWidth,
                              height: posterHeight,
                              child: Artwork(
                                item: item,
                                fit: channel ? BoxFit.contain : BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: SizedBox(
                              height: posterHeight,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Name and episode centered in the space
                                  // above the progress.
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          key: const Key('now-playing-title'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.bodyMedium
                                              .copyWith(
                                                fontWeight: FontWeight.w500,
                                                color: AppColors.textPrimary,
                                              ),
                                        ),
                                        if (subtitle.isNotEmpty)
                                          Text(
                                            subtitle,
                                            key: const Key(
                                              'now-playing-subtitle',
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTypography.bodyMedium
                                                .copyWith(
                                                  fontSize: 13,
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Movies and series: progress on the base,
                                  // aligned with the bottom of the poster.
                                  if (progress != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        AppRadii.xs,
                                      ),
                                      child: LinearProgressIndicator(
                                        key: const Key('now-playing-progress'),
                                        value: progress,
                                        minHeight: 3,
                                        // Same colors as the Continue
                                        // watching cards.
                                        color: AppColors.primary,
                                        backgroundColor:
                                            AppColors.surfaceElevated,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
