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

/// "Lançamento em destaque" at the top of Meu iPlex (same rule as the TV):
/// one release per day and profile, remembered on the device. A release
/// without any image (no TMDB match and no source cover) is skipped for the
/// next one; when none has an image, the first is shown on the plain
/// background (never stuck loading).
class ReleaseHero extends ConsumerStatefulWidget {
  const ReleaseHero({
    super.key,
    required this.candidates,
    required this.greeting,
    required this.storageKey,
    required this.top,
    required this.onOpen,
  });
  final List<Entry> candidates;
  final String greeting;

  /// Device preference key of the daily pick (per account, scope and profile).
  final String storageKey;

  /// Room for the floating app bar over the artwork.
  final Widget top;
  final ValueChanged<Entry> onOpen;

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
      final image =
          summary?.backdrop ?? summary?.poster ?? candidate.sourceImage;
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
    // Below the app bar and tabs (their background stays the page's). The
    // height follows the text; the artwork fills the block, with at least
    // this much image above the text.
    final imageGap = MediaQuery.sizeOf(context).width * 0.5;
    return Column(
      key: const Key('home-hero'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.top,
        Stack(
          children: [
            Positioned.fill(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item != null)
                    Artwork(
                      key: ValueKey('home-hero-art-${item.id}'),
                      item: item,
                      backdrop: true,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      background: AppColors.backgroundPrimary,
                    )
                  else if (!resolved)
                    const AppSkeletonPulse(
                      child: AppSkeletonBlock(
                        height: double.infinity,
                        radius: 0,
                      ),
                    ),
                  // Legibility only over the image, in the page colour.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: const Alignment(0, -0.1),
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
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: imageGap),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.greeting,
                        key: const Key('home-hero-greeting'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          shadows: textShadow,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l.homeFeaturedRelease,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFD0D0D0),
                          shadows: textShadow,
                        ),
                      ),
                      if (title != null) ...[
                        const SizedBox(height: 8),
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
                      ],
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
                      AppButton(
                        key: const Key('home-hero-open'),
                        width: 180,
                        label: l.viewDetails,
                        onPressed: item == null
                            ? null
                            : () => widget.onOpen(item),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
