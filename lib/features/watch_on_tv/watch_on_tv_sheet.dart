import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';

/// "Assistir na TV": the Control searches and asks a linked TV to START a
/// title (contract v1, docs/CONTRACTS.md). It is not a remote control: no
/// pause, seek, stop, volume or TV navigation exists here.
///
/// [resume] ("Continuar assistindo") asks the TV to resume from its active
/// profile's saved progress; [episodeId] preselects that series episode.
Future<void> showWatchOnTv(
  BuildContext context,
  Entry item, {
  bool resume = false,
  String? episodeId,
}) => showAppModalSheet<void>(
  context: context,
  builder: (_) =>
      WatchOnTvSheet(item: item, resume: resume, episodeId: episodeId),
);

/// One episode the phone can ask the TV to start.
@immutable
class TvEpisode {
  const TvEpisode(this.id, this.season, this.number, this.title);
  final String id, title;
  final int season;
  final String number;
  String label(BuildContext context) => [
    '${context.l.seasonNumber(season)} ${context.l.episodeNumber(number)}',
    if (title.isNotEmpty) title,
  ].join(' · ');
}

/// Series details from readSourceSeries (`{seasons, episodes: {season: [...]}}`).
List<TvEpisode> parseEpisodes(Object? details) {
  if (details is! Map) return const [];
  final episodes = details['episodes'];
  if (episodes is! Map) return const [];
  final rows = <TvEpisode>[];
  for (final entry in episodes.entries) {
    if (entry.value is! List) continue;
    for (final raw in entry.value as List) {
      if (raw is! Map || (raw['id'] is! String && raw['id'] is! num)) continue;
      final season =
          int.tryParse('${raw['season'] ?? entry.key}') ??
          int.tryParse('${entry.key}') ??
          0;
      final number = '${raw['episodeNum'] ?? raw['episode_num'] ?? ''}';
      rows.add(
        TvEpisode('${raw['id']}', season, number, '${raw['title'] ?? ''}'),
      );
    }
  }
  rows.sort(
    (a, b) => a.season != b.season
        ? a.season.compareTo(b.season)
        : (int.tryParse(a.number) ?? 9999).compareTo(
            int.tryParse(b.number) ?? 9999,
          ),
  );
  return rows;
}

String _requestId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class WatchOnTvSheet extends ConsumerStatefulWidget {
  const WatchOnTvSheet({
    super.key,
    required this.item,
    this.resume = false,
    this.episodeId,
  });
  final Entry item;
  final bool resume;
  final String? episodeId;
  @override
  ConsumerState<WatchOnTvSheet> createState() => _WatchOnTvSheetState();
}

class _WatchOnTvSheetState extends ConsumerState<WatchOnTvSheet> {
  String? deviceId;
  TvEpisode? episode;
  Future<List<TvEpisode>>? episodes;
  bool busy = false;
  Object? error;
  ({String deviceId, String deviceName, String id})? sent;

  bool get isSeries => widget.item.text('kind') == 'series';

  @override
  void initState() {
    super.initState();
    if (isSeries) episodes = loadEpisodes();
  }

  Future<List<TvEpisode>> loadEpisodes() async {
    final result = await ref.read(repositoryProvider).mutate(
      'readSourceSeries',
      {
        'id': widget.item.text('sourceId'),
        'seriesId': widget.item.text('providerRef'),
      },
    );
    final list = parseEpisodes(result['details']);
    final preset = widget.episodeId;
    if (preset != null && episode == null && mounted) {
      final match = list.where((e) => e.id == preset).firstOrNull;
      if (match != null) setState(() => episode = match);
    }
    return list;
  }

  Future<void> send(Entry device) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ref.read(repositoryProvider).mutate(
        'requestPlayback',
        {
          'deviceId': device.id,
          'sourceId': widget.item.text('sourceId'),
          'itemId': widget.item.id,
          if (episode != null) 'episodeId': episode!.id,
          if (episode != null) 'episodeLabel': episode!.label(context),
          if (widget.resume && widget.item.text('kind') != 'channel')
            'resume': true,
          'requestId': _requestId(),
        },
      );
      if (!mounted) return;
      setState(
        () => sent = (
          deviceId: device.id,
          deviceName: device.name,
          id: result['id'] as String,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final request = sent;
    if (request != null) {
      return PlayRequestStatus(
        deviceId: request.deviceId,
        deviceName: request.deviceName,
        requestId: request.id,
      );
    }
    final devices = ref.watch(entriesProvider('devices'));
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    return AppModalSheet(
      content: devices.when(
        loading: () => const AppLoadingSkeleton(rows: 2),
        error: (e, s) => ErrorState(
          onRetry: () => ref.invalidate(entriesProvider('devices')),
        ),
        data: (all) {
          final tvs = all
              .where((d) => d.text('status') != 'unlinked')
              .toList(growable: false);
          if (tvs.isEmpty) {
            return EmptyState(
              title: l.noTvLinked,
              body: l.noTvLinkedBody,
              icon: AppIcons.devices,
              action: AppButton(
                label: l.addDevice,
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/devices/add');
                },
              ),
            );
          }
          // A single TV is chosen for the user; with more, they pick one.
          final selected =
              tvs.where((d) => d.id == deviceId).firstOrNull ??
              (tvs.length == 1 ? tvs.first : null);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Reference: "Modal Sheet – Seleção" (device selection).
              SheetHeader(
                icon: AppIcons.devices,
                title: l.watchOnTv,
                subtitle: [widget.item.name, l.selectDevice].join(' · '),
              ),
              for (final tv in tvs)
                SelectionRow(
                  key: Key('tv-${tv.id}'),
                  title: tv.name,
                  subtitle: tv.onlineAt(now)
                      ? l.connectedStatus
                      : l.availableStatus,
                  highlightSubtitle: tv.onlineAt(now),
                  icon: AppIcons.devices,
                  selected: tv.id == selected?.id,
                  onTap: () => setState(() => deviceId = tv.id),
                ),
              // Episode already chosen (season sheet, continue, start over).
              if (isSeries && widget.episodeId == null) ...[
                SectionHeader(l.chooseEpisode),
                FutureBuilder<List<TvEpisode>>(
                  future: episodes,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return ErrorState(
                        onRetry: () =>
                            setState(() => episodes = loadEpisodes()),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const AppLoadingSkeleton(rows: 2);
                    }
                    final list = snapshot.data!;
                    if (list.isEmpty) return Text(l.noEpisodes);
                    return Column(
                      children: [
                        for (final e in list)
                          SelectionRow(
                            key: Key('episode-${e.id}'),
                            title: e.label(context),
                            icon: AppIcons.play,
                            selected: e.id == episode?.id,
                            onTap: () => setState(() => episode = e),
                          ),
                      ],
                    );
                  },
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    failureText(context, error!),
                    style: const TextStyle(color: AppColors.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        AppButton.primary(
          key: const Key('send-to-tv'),
          label: l.watchOnTv,
          icon: AppIcons.play,
          busy: busy,
          onPressed: () {
            final tvs = (devices.asData?.value ?? const <Entry>[])
                .where((d) => d.text('status') != 'unlinked')
                .toList();
            final tv =
                tvs.where((d) => d.id == deviceId).firstOrNull ??
                (tvs.length == 1 ? tvs.first : null);
            if (tv == null) return;
            if (isSeries && episode == null) {
              setState(() => error = const AppFailure('episode-required'));
              return;
            }
            send(tv);
          },
        ),
        AppButton(
          label: l.cancel,
          onPressed: busy ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Live status of one request (`devices/{id}/play_requests/{rid}`), written
/// only by the backend; the phone never decides the outcome itself.
class PlayRequestStatus extends ConsumerWidget {
  const PlayRequestStatus({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.requestId,
  });
  final String deviceId, deviceName, requestId;

  static String message(
    BuildContext context,
    Entry? request,
    String tv,
    DateTime now,
  ) {
    final l = context.l;
    final status = request?.text('status') ?? 'pending';
    final code = request?.text('errorCode') ?? '';
    final late =
        request != null &&
        request.number('expiresAt') + 3000 < now.millisecondsSinceEpoch;
    return switch (status) {
      'pending' => late ? l.tvDidNotRespond : l.sendingToTv(tv),
      'delivered' => l.tvReceivedRequest(tv),
      'confirming' => l.waitingTvConfirmation(tv),
      'started' =>
        request!.text('kind') == 'series' && request.text('episodeId').isEmpty
            ? l.openedOnTv(tv)
            : l.playingOnTv(tv),
      'declined' => code == 'no-answer' ? l.tvNoAnswer : l.tvKeptCurrent,
      'expired' => l.playRequestExpired,
      'superseded' => l.playRequestSuperseded,
      'failed' => switch (code) {
        'content-not-allowed' => l.contentNotAllowedOnTv,
        'source-protected' => l.sourceProtectedOnTv,
        'stream-unavailable' => l.streamUnavailableOnTv,
        'format-unsupported' => l.formatUnsupportedOnTv,
        'subscription-required' => l.playbackSubscriptionRequired,
        'session-limit' => l.sessionLimit(''),
        _ => l.playRequestFailed,
      },
      _ => l.playRequestFailed,
    };
  }

  static bool isFinal(Entry? request, DateTime now) {
    final status = request?.text('status') ?? 'pending';
    if (['pending', 'delivered', 'confirming'].contains(status)) {
      return status == 'pending' &&
          request != null &&
          request.number('expiresAt') + 3000 < now.millisecondsSinceEpoch;
    }
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final request = ref.watch(
      entryProvider((
        collection: 'devices/$deviceId/play_requests',
        id: requestId,
      )),
    );
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final entry = request.asData?.value;
    final done = isFinal(entry, now);
    final ok = entry?.text('status') == 'started';
    return AppModalSheet(
      leading: done
          ? AppIcon(
              ok ? AppIcons.check : AppIcons.alert,
              size: AppDimensions.iconLarge,
              color: ok ? AppColors.accent : AppColors.warning,
            )
          : const SizedBox(
              width: AppDimensions.iconLarge,
              height: AppDimensions.iconLarge,
              child: CircularProgressIndicator(color: AppColors.textPrimary),
            ),
      title: l.watchOnTv,
      content: Semantics(
        liveRegion: true,
        child: Text(
          message(context, entry, deviceName, now),
          key: const Key('play-request-status'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
      actions: [
        AppButton(
          label: done ? l.tvDone : l.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
