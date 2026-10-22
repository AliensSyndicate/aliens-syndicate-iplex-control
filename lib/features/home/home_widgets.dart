import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import 'home_data.dart';
import 'metadata_service.dart';

/// Card sizes: vertical posters for movies/series, landscape tiles for channels.
abstract final class HomeCardSize {
  static const posterWidth = 112.0, posterHeight = 168.0;
  static const channelWidth = 168.0, channelHeight = 96.0;
  static const caption = 40.0;
}

/// One catalog item: artwork + name. Artwork comes from the source (https,
/// credential-free) or a confident TMDB match; otherwise the item's initials.
class HomeCard extends StatelessWidget {
  const HomeCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.width,
    this.showCaption = false,
  });
  final Entry item;
  final VoidCallback onTap;

  /// Library actions (Favoritos / Lista de desejos) without opening the page.
  final VoidCallback? onLongPress;

  /// Grid cell width ("Ver tudo"): titles keep the 2:3 poster, channels a
  /// square tile. Null: the Home row sizes.
  final double? width;

  /// Whether to show the text caption below the poster (default false for Home lists).
  final bool showCaption;

  @override
  Widget build(BuildContext context) {
    final channel = item.isChannel;
    final cell = this.width;
    final width =
        cell ??
        (channel ? HomeCardSize.channelWidth : HomeCardSize.posterWidth);
    final height = cell != null
        ? (channel ? cell : cell * 3 / 2)
        : channel
        ? HomeCardSize.channelHeight
        : HomeCardSize.posterHeight;
    final progress = item.progress;
    return Semantics(
      button: true,
      label: item.name,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('home-card-${item.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Artwork(
                        item: item,
                        fit: channel ? BoxFit.contain : BoxFit.cover,
                      ),
                      // Age rating seal (reference: compact poster cards).
                      if (AgeRatingBadge.normalize(item.text('ageRating'))
                          case final seal?)
                        Positioned(
                          right: AppSpacing.xs,
                          bottom: progress != null
                              ? AppSpacing.md
                              : AppSpacing.xs,
                          child: AgeRatingBadge(seal, size: 18),
                        ),
                      // "⋮": the content options (same as a long press).
                      if (onLongPress != null)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Semantics(
                            button: true,
                            label: context.l.more,
                            child: InkResponse(
                              key: ValueKey('home-card-more-${item.id}'),
                              onTap: onLongPress,
                              radius: 20,
                              child: const SizedBox.square(
                                dimension: 36,
                                child: Center(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: AppColors.scrim,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.all(2),
                                      child: Icon(
                                        Icons.more_vert_rounded,
                                        size: 18,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Progress bar placed at the bottom edge of the poster photo
                      if (progress != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(AppRadii.md),
                            ),
                            child: LinearProgressIndicator(
                              value: progress.fraction,
                              minHeight: 4,
                              color: const Color(0xFF00E676),
                              backgroundColor: const Color(0x66000000),
                            ),
                          ),
                        ),
                      if (!showCaption)
                        Positioned(
                          left: 0,
                          top: 0,
                          width: 0,
                          height: 0,
                          child: IgnorePointer(
                            child: Opacity(opacity: 0, child: Text(item.name)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (showCaption) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  item.name,
                  maxLines: item.year == null ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (item.year case final year?)
                  Text(
                    '$year',
                    maxLines: 1,
                    style: AppTypography.bodyMedium.copyWith(
                      fontSize: 12,
                      height: 1.25,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Source artwork (or the poster of an editorial title), then TMDB poster,
/// then initials. Never a placeholder photo.
class Artwork extends ConsumerStatefulWidget {
  const Artwork({
    super.key,
    required this.item,
    this.fit = BoxFit.cover,
    this.backdrop = false,
    this.alignment = Alignment.center,
    this.background = AppColors.surfaceRecessed,
  });
  final Entry item;
  final BoxFit fit;
  final bool backdrop;

  final Alignment alignment;
  final Color background;

  @override
  ConsumerState<Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends ConsumerState<Artwork> {
  Future<ContentMetadata?>? metadata;

  String? get sourceImage => widget.backdrop
      ? null
      : widget.item.sourceImage ?? widget.item.editorialPoster;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void didUpdateWidget(Artwork old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id ||
        old.backdrop != widget.backdrop ||
        old.item.editorialPoster != widget.item.editorialPoster) {
      _lookup();
    }
  }

  void _lookup() => metadata =
      sourceImage == null &&
          widget.item.isPlayableTitle &&
          !widget.item.isEditorial
      ? ref.read(metadataServiceProvider).summary(widget.item)
      : null;

  @override
  Widget build(BuildContext context) {
    final item = widget.item, source = sourceImage;
    if (source != null) {
      return _NetworkImage(
        url: source,
        fit: widget.fit,
        item: item,
        alignment: widget.alignment,
        background: widget.background,
      );
    }
    if (metadata == null) return _Initials(item: item);
    return FutureBuilder<ContentMetadata?>(
      future: metadata,
      builder: (context, snapshot) {
        final tmdb = widget.backdrop
            ? snapshot.data?.backdrop
            : snapshot.data?.poster;
        final url = tmdb;
        if (url != null) {
          return _NetworkImage(
            url: url,
            fit: widget.fit,
            item: item,
            alignment: widget.alignment,
            background: widget.background,
          );
        }
        // No TMDB cover: the source's own art, cropped, before initials.
        final fallback = widget.backdrop
            ? item.sourceImage ?? item.editorialPoster
            : null;
        if (fallback != null &&
            snapshot.connectionState == ConnectionState.done) {
          return _NetworkImage(
            url: fallback,
            fit: widget.fit,
            item: item,
            alignment: widget.alignment,
            background: widget.background,
          );
        }
        return _Initials(
          item: item,
          loading: snapshot.connectionState != ConnectionState.done,
        );
      },
    );
  }
}

class _NetworkImage extends StatelessWidget {
  const _NetworkImage({
    required this.url,
    required this.fit,
    required this.item,
    this.alignment = Alignment.center,
    this.background = AppColors.surfaceRecessed,
  });
  final String url;
  final BoxFit fit;
  final Entry item;
  final Alignment alignment;
  final Color background;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: background,
    child: Padding(
      padding: fit == BoxFit.contain
          ? const EdgeInsets.all(AppSpacing.md)
          : EdgeInsets.zero,
      child: Image.network(
        url,
        fit: fit,
        alignment: alignment,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => _Initials(item: item),
      ),
    ),
  );
}

class _Initials extends StatelessWidget {
  const _Initials({required this.item, this.loading = false});
  final Entry item;
  final bool loading;

  String get initials {
    final words = item.name
        .replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ')
        .split(RegExp(r'[^A-Za-zÀ-ÿ0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '•';
    return (words.length == 1
            ? words.first.substring(0, words.first.length.clamp(1, 2))
            : '${words[0][0]}${words[1][0]}')
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.surfaceRecessed,
    child: Center(
      child: loading
          ? const SizedBox.shrink()
          : Text(
              initials,
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
    ),
  );
}

/// Section title + independent horizontal list (at most [limit] cards).
class HomeRow extends StatelessWidget {
  const HomeRow({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    this.onLongPress,
    this.limit = 10,
    this.onSeeAll,
  });

  /// "Ver tudo": opens the screen with every item of the section.
  final VoidCallback? onSeeAll;
  final String title;
  final List<Entry> items;
  final ValueChanged<Entry> onTap;
  final ValueChanged<Entry>? onLongPress;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final shown = items.take(limit).toList();
    final channel = shown.every((i) => i.isChannel);
    final height = channel
        ? HomeCardSize.channelHeight
        : HomeCardSize.posterHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.lg),
                child: Semantics(header: true, child: SectionHeader(title)),
              ),
            ),
            if (onSeeAll != null)
              Semantics(
                button: true,
                child: InkResponse(
                  key: ValueKey('home-see-all-$title'),
                  onTap: onSeeAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.l.seeAll,
                          style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: Color(0xFF00E676),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            key: PageStorageKey('home-row-$title'),
            // Edge to edge: no side margin, the same amount inside.
            padding: EdgeToEdge.inset,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            clipBehavior: Clip.none,
            itemCount: shown.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) => HomeCard(
              item: shown[index],
              onTap: () => onTap(shown[index]),
              onLongPress: onLongPress == null
                  ? null
                  : () => onLongPress!(shown[index]),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
