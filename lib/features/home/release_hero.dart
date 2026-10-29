import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import 'home_data.dart';
import 'home_providers.dart';
import 'home_widgets.dart';
import 'metadata_service.dart';

/// Local day (YYYY-MM-DD): the featured release changes once a day.
String heroDay([DateTime? now]) {
  final d = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// Featured release at the top of Meu iPlex (same rule as the TV): one
/// release per day and profile, remembered on the device. The portrait art
/// (9:16) fills the block up to the status bar, under the floating app bar,
/// as when a title is playing. A release without any image (no TMDB match
/// and no source cover) is skipped for the next one; when none has an
/// image, the first is shown on the plain background (never stuck loading).
class ReleaseHero extends ConsumerStatefulWidget {
  const ReleaseHero({
    super.key,
    required this.candidates,
    required this.storageKey,
    required this.top,
    required this.onOpen,
    required this.onPlay,
    required this.onWatchOnTv,
  });
  final List<Entry> candidates;

  /// Device preference key of the daily pick (per account, scope and profile).
  final String storageKey;

  /// App bar (or the room for the floating one) drawn over the artwork.
  final Widget top;
  final ValueChanged<Entry> onOpen;

  /// Plays the release on this phone.
  final ValueChanged<Entry> onPlay;

  /// Sends the release to a linked TV.
  final ValueChanged<Entry> onWatchOnTv;
  @override
  ConsumerState<ReleaseHero> createState() => _ReleaseHeroState();
}

class _ReleaseHeroState extends ConsumerState<ReleaseHero> {
  Entry? item;
  ContentMetadata? meta;
  bool resolved = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ReleaseHero old) {
    super.didUpdateWidget(old);
    // The shown title stays while the rows refresh; only a list that no
    // longer has it (other source or profile) picks again.
    if (old.storageKey != widget.storageKey ||
        (item != null && !widget.candidates.any((c) => c.id == item!.id))) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final candidates = widget.candidates, key = widget.storageKey;
    String? daily;
    try {
      final saved = await (await ref.read(preferencesProvider.future))
          .getString(key);
      final parts = saved?.split('|');
      if (parts != null && parts.length == 2 && parts[0] == heroDay()) {
        daily = parts[1];
      }
    } catch (_) {
      // Preference only: without it a new release is drawn.
    }
    final known = candidates.indexWhere((c) => c.id == daily);
    final start = known >= 0 ? known : Random().nextInt(candidates.length);
    final rotated = [...candidates.skip(start), ...candidates.take(start)];
    final metadata = ref.read(metadataServiceProvider);
    for (final candidate in rotated) {
      ContentMetadata? summary;
      try {
        summary = await metadata.summary(candidate);
      } catch (_) {}
      if (!mounted || key != widget.storageKey) return;
      // Portrait art, as the block shows it (see [Artwork]).
      final image =
          candidate.sourceImage ?? candidate.editorialPoster ?? summary?.poster;
      if (image == null) continue;
      setState(() {
        item = candidate;
        meta = summary;
        resolved = true;
      });
      try {
        await (await ref.read(preferencesProvider.future))
            .setString(key, '${heroDay()}|${candidate.id}');
      } catch (_) {}
      return;
    }
    if (mounted) {
      setState(() {
        item = rotated.first;
        meta = null;
        resolved = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final item = this.item;
    const textShadow = [
      Shadow(offset: Offset(0, 1), blurRadius: 4, color: Color(0x99000000)),
    ];
    final title = (meta?.title?.isNotEmpty ?? false)
        ? meta!.title!
        : item?.name;
    final overview = meta?.overview ?? '';
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      key: const Key('home-hero'),
      height: width * 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item != null)
            Artwork(
              key: ValueKey('home-hero-art-${item.id}'),
              item: item,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              background: AppColors.backgroundPrimary,
              decodeWidth: 1080,
            )
          else if (!resolved)
            const AppSkeletonPulse(
              child: AppSkeletonBlock(height: double.infinity, radius: 0),
            ),
          // Legibility of the app bar over the image (as when playing).
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment(0, -0.5),
                colors: [Color(0xB3000000), Colors.transparent],
              ),
            ),
          ),
          // And of the text, fading into the page colour.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: const Alignment(0, 0.1),
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.backgroundPrimary.withValues(alpha: 0.85),
                  AppColors.backgroundPrimary,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: widget.top),
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.md,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  Text(
                    title,
                    key: const Key('home-hero-title'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.15,
                      color: Colors.white,
                      shadows: textShadow,
                    ),
                  ),
                if (overview.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    overview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      color: const Color(0xFFD0D0D0),
                      shadows: textShadow,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: AppButton.primary(
                        key: const Key('home-hero-play'),
                        icon: AppIcons.play,
                        label: l.playHere,
                        onPressed: item == null
                            ? null
                            : () => widget.onPlay(item),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    CircularButton(
                      key: const Key('home-hero-open'),
                      icon: AppIcons.details,
                      label: l.viewDetails,
                      onPressed: item == null
                          ? null
                          : () => widget.onOpen(item),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    CircularButton(
                      key: const Key('home-hero-tv'),
                      icon: AppIcons.devices,
                      label: l.watchOnTv,
                      onPressed: item == null
                          ? null
                          : () => widget.onWatchOnTv(item),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
