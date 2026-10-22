import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import '../watch_on_tv/watch_on_tv_sheet.dart';
import 'content_details_page.dart';
import 'metadata_service.dart';

/// Episodes of one season, inline on the series page (prototype screen 10):
/// frame with play mark, "1. Nome", runtime. Names, frames and runtimes come
/// from TMDB; only the episodes the IPTV source offers can be played
/// ([onPlay] opens "Assistir na TV"). Without source episodes the TMDB list
/// is shown for information only.
class SeasonEpisodes extends ConsumerStatefulWidget {
  const SeasonEpisodes({
    super.key,
    required this.series,
    required this.season,
    required this.available,
    this.tmdbId,
    this.onPlay,
  });
  final Entry series;
  final int season;
  final List<TvEpisode> available;
  final int? tmdbId;
  final ValueChanged<TvEpisode>? onPlay;

  @override
  ConsumerState<SeasonEpisodes> createState() => _SeasonEpisodesState();
}

class _SeasonEpisodesState extends ConsumerState<SeasonEpisodes> {
  late final Future<List<EpisodeInfo>> editorial = widget.tmdbId == null
      ? Future.value(const [])
      : ref
            .read(metadataServiceProvider)
            .season(widget.series, widget.tmdbId!, widget.season)
            .catchError((_) => const <EpisodeInfo>[]);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<EpisodeInfo>>(
    future: editorial,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const _EpisodeSkeleton();
      }
      final info = {for (final e in snapshot.data ?? const []) e.number: e};
      final available = [
        for (final e in widget.available)
          if (e.season == widget.season) e,
      ];
      final rows = available.isNotEmpty
          ? [
              for (final e in available)
                (e, int.tryParse(e.number), info[int.tryParse(e.number)]),
            ]
          : [
              for (final e in info.values)
                (null, e.number, e) as (TvEpisode?, int?, EpisodeInfo?),
            ];
      return Column(
        key: const Key('season-episodes'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (episode, number, details) in rows)
            _EpisodeRow(
              key: ValueKey('season-episode-${episode?.id ?? 'tmdb-$number'}'),
              number: number,
              fallbackName: episode?.title ?? '',
              details: details,
              onTap: episode == null || widget.onPlay == null
                  ? null
                  : () => widget.onPlay!(episode),
            ),
        ],
      );
    },
  );
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    super.key,
    required this.number,
    required this.fallbackName,
    required this.details,
    required this.onTap,
  });
  final int? number;
  final String fallbackName;
  final EpisodeInfo? details;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = (details?.name.isNotEmpty ?? false)
        ? details!.name
        : fallbackName;
    final still = tmdbSized(details?.still, 'w300');
    final playable = onTap != null;
    final title = [if (number != null) '$number.', name].join(' ').trim();
    return Semantics(
      button: playable,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: playable ? 1 : 0.55,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                  child: SizedBox(
                    width: 112,
                    height: 63,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: AppColors.surfaceElevated,
                          child: still == null
                              ? null
                              : Image.network(
                                  still,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  excludeFromSemantics: true,
                                  errorBuilder: (context, error, stack) =>
                                      const SizedBox.shrink(),
                                ),
                        ),
                        if (playable)
                          const Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.scrim,
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(AppSpacing.xs + 2),
                                child: AppIcon(
                                  AppIcons.play,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (details?.runtimeMinutes case final minutes?)
                        Text(
                          formatRuntime(context, minutes),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      if (details?.overview.isNotEmpty ?? false)
                        Text(
                          details!.overview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Flat, pulsing placeholder shaped like the episode rows.
class _EpisodeSkeleton extends StatefulWidget {
  const _EpisodeSkeleton();
  @override
  State<_EpisodeSkeleton> createState() => _EpisodeSkeletonState();
}

class _EpisodeSkeletonState extends State<_EpisodeSkeleton> {
  Widget _block(double width, double height) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppRadii.xs),
    ),
  );

  @override
  Widget build(BuildContext context) => AppSkeletonPulse(
    key: const Key('season-skeleton'),
    child: Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                _block(112, 63),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _block(160, 14),
                      const SizedBox(height: AppSpacing.sm),
                      _block(60, 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
