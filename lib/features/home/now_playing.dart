import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import '../watch_on_tv/watch_on_tv_sheet.dart';
import 'content_details_page.dart';
import 'home_data.dart';

/// A TV reports its status at least this often while it plays; an older one
/// (TV off, app closed, network lost) is not shown.
const nowPlayingFresh = Duration(seconds: 120);

/// What the account is watching on a TV: the catalog item, its progress
/// (movies/series) and, for series, the episode.
@immutable
class NowPlaying {
  const NowPlaying({required this.item, required this.deviceId});
  final Entry item;

  /// TV that plays it.
  final String deviceId;
}

/// The TV of this family that is playing right now (published by the TV
/// through `reportPlayback`), or null: the bar only exists while a TV plays.
final nowPlayingProvider = Provider.autoDispose<NowPlaying?>((ref) {
  final devices = ref.watch(entriesProvider('devices')).asData?.value;
  // Re-evaluated every 15 s so a silent TV drops out without a new event.
  ref.watch(
    clockProvider.select(
      (c) => (c.value?.millisecondsSinceEpoch ?? 0) ~/ 15000,
    ),
  );
  if (devices == null) return null;
  final now = DateTime.now().millisecondsSinceEpoch;
  NowPlaying? best;
  var bestAt = 0;
  for (final device in devices) {
    final raw = device.data['nowPlaying'];
    if (raw is! Map || device.text('status') == 'unlinked') continue;
    final status = Map<String, dynamic>.from(raw);
    final at = (status['updatedAt'] as num?)?.toInt() ?? 0;
    final state = status['state'];
    final itemId = status['itemId'];
    if ((state != 'playing' && state != 'paused') ||
        itemId is! String ||
        now - at > nowPlayingFresh.inMilliseconds ||
        at <= bestAt) {
      continue;
    }
    final position = status['positionSec'], duration = status['durationSec'];
    bestAt = at;
    best = NowPlaying(
      deviceId: device.id,
      item: Entry(itemId, {
        'title': status['title'],
        'kind': status['kind'],
        'sourceId': status['sourceId'],
        'providerRef': status['providerRef'],
        'imageRef': status['imageRef'],
        'year': status['year'],
        'episodeId': status['episodeId'],
        if (position is num && duration is num && duration > 0)
          'progress': {'position': position, 'duration': duration},
      }),
    );
  }
  return best;
});

/// "Temporada 1 - Episódio 3" of the episode in progress, from the source
/// itself (never guessed).
final episodeLabelProvider = FutureProvider.autoDispose
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

/// "T1E3" (or "Temporada 1") of [item]'s episode, from the source itself;
/// null while unknown or without an episode (never guessed).
String? episodeLabel(BuildContext context, WidgetRef ref, Entry item) {
  final episodeId = item.episodeId;
  if (item.kind != 'series' || episodeId == null) return null;
  final raw = ref
      .watch(
        episodeLabelProvider((
          item.sourceId,
          item.text('providerRef'),
          episodeId,
        )),
      )
      .asData
      ?.value;
  if (raw == null) return null;
  final [season, number] = raw.split('|');
  final n = int.tryParse(number);
  return n == null
      ? context.l.seasonNumber(int.parse(season))
      : context.l.seasonEpisodeShort(int.parse(season), '$n');
}

/// "Now playing" item of the Home (Meu iPlex, between the tabs and the
/// rows): artwork, name, kind with runtime (and episode for series) and the
/// progress for movies/series; a tap opens the title.
class NowPlayingBar extends ConsumerWidget {
  const NowPlayingBar({super.key, required this.playing});
  final NowPlaying playing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final item = playing.item;
    final channel = item.isChannel;
    final progress = channel ? null : (item.progress?.fraction ?? 0);
    String? episode;
    final episodeId = item.episodeId;
    if (item.kind == 'series' && episodeId != null) {
      final raw = ref
          .watch(
            episodeLabelProvider((
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

    final devices =
        ref.watch(entriesProvider('devices')).asData?.value ?? const [];
    final device =
        devices.where((d) => d.id == playing.deviceId).firstOrNull ??
        devices.firstOrNull;
    final deviceName = device != null && device.name.isNotEmpty
        ? device.name
        : 'Sala de Estar';

    String? remainingText;
    if (item.progress case final p?
        when p.duration > p.position && p.position > 0) {
      final remMin = ((p.duration - p.position) / 60).round();
      if (remMin > 0) remainingText = '$remMin min restantes';
    }

    const textShadow = [
      Shadow(offset: Offset(0, 1), blurRadius: 4, color: Color(0x99000000)),
    ];

    return Semantics(
      container: true,
      button: true,
      label: [item.name, subtitle].join(', '),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Container(
          key: const Key('now-playing-bar'),
          decoration: const BoxDecoration(),
          child: InkWell(
            onTap: () => openTitle(context, item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Reproduzindo em $deviceName',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    shadows: textShadow,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  item.name,
                  key: const Key('now-playing-title'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: Colors.white,
                    height: 1.2,
                    shadows: textShadow,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  key: const Key('now-playing-subtitle'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFFD0D0D0),
                    shadows: textShadow,
                  ),
                ),
                if (!channel) ...[
                  const SizedBox(height: 14),
                  AppProgressBar(
                    key: const Key('now-playing-progress'),
                    value: progress ?? 0,
                  ),
                ],
                if (remainingText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    remainingText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF999999),
                      fontWeight: FontWeight.w400,
                      shadows: textShadow,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
