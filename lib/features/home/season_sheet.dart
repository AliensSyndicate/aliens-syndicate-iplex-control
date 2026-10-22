import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import '../watch_on_tv/watch_on_tv_sheet.dart';
import 'content_details_page.dart';
import 'metadata_service.dart';

/// Full-height sheet of one season: every episode with its frame, number,
/// name, synopsis and runtime (TMDB, when it has them). Only episodes the IPTV
/// source offers carry the play mark and can be chosen; choosing one closes
/// the sheet and returns it (the caller opens "Assistir na TV").
Future<TvEpisode?> showSeasonSheet(
  BuildContext context, {
  required Entry series,
  required int season,
  required List<TvEpisode> available,
  int? tmdbId,
}) => showAppModalSheet<TvEpisode>(
  context: context,
  builder: (_) => LayoutBuilder(
    builder: (context, box) => SizedBox(
      height: box.maxHeight,
      child: SeasonSheet(
        series: series,
        season: season,
        available: available,
        tmdbId: tmdbId,
      ),
    ),
  ),
);

class SeasonSheet extends ConsumerStatefulWidget {
  const SeasonSheet({
    super.key,
    required this.series,
    required this.season,
    required this.available,
    this.tmdbId,
  });
  final Entry series;
  final int season;
  final List<TvEpisode> available;
  final int? tmdbId;

  @override
  ConsumerState<SeasonSheet> createState() => _SeasonSheetState();
}

class _SeasonSheetState extends ConsumerState<SeasonSheet> {
  late final Future<List<EpisodeInfo>> editorial = widget.tmdbId == null
      ? Future.value(const [])
      : ref
            .read(metadataServiceProvider)
            .season(widget.series, widget.tmdbId!, widget.season)
            .catchError((_) => const <EpisodeInfo>[]);

  @override
  Widget build(BuildContext context) => AppModalSheet(
    title: context.l.seasonNumber(widget.season),
    content: FutureBuilder<List<EpisodeInfo>>(
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
        // Playable episodes come from the source; without any, the TMDB
        // episodes are listed for information only.
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (episode, number, details) in rows)
              _EpisodeRow(
                key: ValueKey(
                  'season-episode-${episode?.id ?? 'tmdb-$number'}',
                ),
                season: widget.season,
                number: number,
                fallbackName: episode?.title ?? '',
                details: details,
                onTap: episode == null
                    ? null
                    : () => Navigator.of(context).pop(episode),
              ),
          ],
        );
      },
    ),
  );
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    super.key,
    required this.season,
    required this.number,
    required this.fallbackName,
    required this.details,
    required this.onTap,
  });
  final int season;
  final int? number;
  final String fallbackName;
  final EpisodeInfo? details;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final name = (details?.name.isNotEmpty ?? false)
        ? details!.name
        : fallbackName;
    final still = tmdbSized(details?.still, 'w780');
    final playable = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Semantics(
        button: playable,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Opacity(
            opacity: playable ? 1 : 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Episode frame; the play mark only on what the source offers.
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: AppColors.surfaceRecessed,
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
                                color: Color(0x8C000000),
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(AppSpacing.md),
                                child: AppIcon(
                                  AppIcons.play,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  number == null
                      ? l.seasonNumber(season)
                      : l.seasonEpisodeLabel(season, number!),
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (name.isNotEmpty)
                  Text(
                    name,
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                if (details?.overview.isNotEmpty ?? false) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    details!.overview,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ],
                if (details?.runtimeMinutes case final minutes?) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    formatRuntime(context, minutes),
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Loading placeholder shaped like the episode card (frame, number, name,
/// synopsis): flat recessed blocks, no shadow or neumorphism, gently pulsing.
class _EpisodeSkeleton extends StatefulWidget {
  const _EpisodeSkeleton();
  @override
  State<_EpisodeSkeleton> createState() => _EpisodeSkeletonState();
}

class _EpisodeSkeletonState extends State<_EpisodeSkeleton>
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

  Widget _bar(double widthFactor, double height) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: widthFactor,
    child: Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceRecessed,
        borderRadius: BorderRadius.circular(AppRadii.xs),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => FadeTransition(
    key: const Key('season-skeleton'),
    opacity: Tween<double>(begin: 0.45, end: 1).animate(controller),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceRecessed,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _bar(0.4, 12),
                const SizedBox(height: AppSpacing.sm),
                _bar(0.7, 18),
                const SizedBox(height: AppSpacing.sm),
                _bar(1, 12),
                const SizedBox(height: AppSpacing.xs),
                _bar(0.85, 12),
              ],
            ),
          ),
      ],
    ),
  );
}
