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
  const HomeCard({super.key, required this.item, required this.onTap});
  final Entry item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final channel = item.isChannel;
    final width = channel
        ? HomeCardSize.channelWidth
        : HomeCardSize.posterWidth;
    final height = channel
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
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Artwork(
                    item: item,
                    fit: channel ? BoxFit.contain : BoxFit.cover,
                  ),
                ),
              ),
              if (progress != null) ...[
                const SizedBox(height: AppSpacing.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                  child: LinearProgressIndicator(
                    value: progress.fraction,
                    minHeight: 3,
                    color: AppColors.textPrimary,
                    backgroundColor: AppColors.surfaceRecessed,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(
                  fontSize: 13,
                  height: 1.25,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Source artwork, then TMDB poster, then initials. Never a placeholder photo.
class Artwork extends ConsumerStatefulWidget {
  const Artwork({
    super.key,
    required this.item,
    this.fit = BoxFit.cover,
    this.backdrop = false,
  });
  final Entry item;
  final BoxFit fit;
  final bool backdrop;

  @override
  ConsumerState<Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends ConsumerState<Artwork> {
  Future<ContentMetadata?>? metadata;

  String? get sourceImage => widget.backdrop ? null : widget.item.sourceImage;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void didUpdateWidget(Artwork old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id || old.backdrop != widget.backdrop) {
      _lookup();
    }
  }

  void _lookup() =>
      metadata = sourceImage == null && widget.item.isPlayableTitle
      ? ref.read(metadataServiceProvider).summary(widget.item)
      : null;

  @override
  Widget build(BuildContext context) {
    final item = widget.item, source = sourceImage;
    if (source != null) {
      return _NetworkImage(url: source, fit: widget.fit, item: item);
    }
    if (metadata == null) return _Initials(item: item);
    return FutureBuilder<ContentMetadata?>(
      future: metadata,
      builder: (context, snapshot) {
        final url = widget.backdrop
            ? snapshot.data?.backdrop
            : snapshot.data?.poster;
        if (url != null) {
          return _NetworkImage(url: url, fit: widget.fit, item: item);
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
  });
  final String url;
  final BoxFit fit;
  final Entry item;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.surfaceRecessed,
    child: Padding(
      padding: fit == BoxFit.contain
          ? const EdgeInsets.all(AppSpacing.md)
          : EdgeInsets.zero,
      child: Image.network(
        url,
        fit: fit,
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

/// Section title + independent horizontal list (at most 10 cards).
class HomeRow extends StatelessWidget {
  const HomeRow({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
  });
  final String title;
  final List<Entry> items;
  final ValueChanged<Entry> onTap;

  @override
  Widget build(BuildContext context) {
    final shown = items.take(10).toList();
    final channel = shown.every((i) => i.isChannel);
    final progress = shown.any((i) => i.progress != null);
    final height =
        (channel ? HomeCardSize.channelHeight : HomeCardSize.posterHeight) +
        HomeCardSize.caption +
        AppSpacing.sm +
        (progress ? AppSpacing.xs + 3 : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: SectionHeader(title)),
        SizedBox(
          height: height,
          child: ListView.separated(
            key: PageStorageKey('home-row-$title'),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            clipBehavior: Clip.none,
            itemCount: shown.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) =>
                HomeCard(item: shown[index], onTap: () => onTap(shown[index])),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
