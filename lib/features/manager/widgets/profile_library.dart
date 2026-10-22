import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/providers.dart';
import '../../../core/design_system/components.dart';
import '../../../core/domain/models.dart';
import '../../home/content_details_page.dart';
import '../../home/home_data.dart';
import '../../home/home_widgets.dart';
import '../../home/now_playing.dart';

/// Library of one family profile (Família › integrante), read through the
/// backend (`readProfileLibrary`): only the account linked to the profile or
/// the administrator get it. Items are catalog items (artwork, progress) or
/// saved titles that no catalog offers (kept, as on the Home).
@immutable
class ProfileLibrary {
  const ProfileLibrary({
    this.continueWatching = const [],
    this.favorites = const [],
    this.wishlist = const [],
    this.watched = const [],
  });
  final List<Entry> continueWatching, favorites, wishlist, watched;

  factory ProfileLibrary.fromJson(Map<String, dynamic> json) {
    List<Entry> items(String key) => [
      for (final raw in (json[key] as List? ?? const []))
        if (raw is Map && raw['id'] is String)
          Entry(raw['id'] as String, Map<String, dynamic>.from(raw)),
    ];
    return ProfileLibrary(
      continueWatching: items('continueWatching'),
      favorites: items('favorites'),
      wishlist: items('wishlist'),
      watched: items('watched'),
    );
  }
}

final profileLibraryProvider = FutureProvider.autoDispose
    .family<ProfileLibrary, String>((ref, profileId) async {
      final result = await ref.read(repositoryProvider).mutate(
        'readProfileLibrary',
        {'profileId': profileId},
      );
      return ProfileLibrary.fromJson(Map<String, dynamic>.from(result));
    }, retry: (retryCount, error) => null);

/// The four content sections of a profile, one shared layout.
enum LibraryKind { continueWatching, favorites, wishlist, watched }

/// Data category cleared by `clearProfileData` (the wishlist shares the
/// favorites generation, so it has no clear of its own).
String? clearCategory(LibraryKind kind) => switch (kind) {
  LibraryKind.continueWatching => 'progress',
  LibraryKind.favorites => 'favorites',
  LibraryKind.watched => 'watched',
  LibraryKind.wishlist => null,
};

/// One content section: title, the Busca tabs (Ao vivo, Filmes, Séries),
/// a row of content cards (artwork, name, real complementary data, progress)
/// and, when allowed, a text-only clear action with confirmation.
class LibrarySection extends ConsumerStatefulWidget {
  const LibrarySection({
    super.key,
    required this.kind,
    required this.profileId,
    required this.profileName,
    required this.items,
    required this.canClear,
  });
  final LibraryKind kind;
  final String profileId, profileName;
  final List<Entry> items;
  final bool canClear;

  @override
  ConsumerState<LibrarySection> createState() => _LibrarySectionState();
}

class _LibrarySectionState extends ConsumerState<LibrarySection> {
  static const kinds = ['channel', 'movie', 'series'];
  late String kind = kinds.firstWhere(
    (k) => widget.items.any((i) => i.kind == k),
    orElse: () => 'movie',
  );

  String title(BuildContext context) => switch (widget.kind) {
    LibraryKind.continueWatching => context.l.continueWatching,
    LibraryKind.favorites => context.l.favorites,
    LibraryKind.wishlist => context.l.homeWishlist,
    LibraryKind.watched => context.l.watchedHistory,
  };

  /// Only data the backend returned: episode, time left, date watched.
  String? detail(BuildContext context, Entry item) {
    final episode = episodeLabel(context, ref, item);
    return switch (widget.kind) {
      LibraryKind.continueWatching => () {
        final p = item.data['progress'];
        int? left;
        if (p is Map) {
          final position = (p['position'] as num?) ?? 0;
          final duration = (p['duration'] as num?) ?? 0;
          if (duration > position && position > 0) {
            left = ((duration - position) / 60).ceil();
          }
        }
        final parts = [?episode, if (left != null) context.l.minutesLeft(left)];
        return parts.isEmpty ? null : parts.join(' · ');
      }(),
      LibraryKind.watched => () {
        final at = item.number('watchedAt');
        final parts = [
          ?episode,
          if (at > 0)
            formatCardDateTime(
              context,
              DateTime.fromMillisecondsSinceEpoch(at),
            ),
        ];
        return parts.isEmpty ? null : parts.join(' · ');
      }(),
      _ => null,
    };
  }

  Future<void> clear() async {
    final l = context.l, name = widget.profileName;
    final category = clearCategory(widget.kind)!;
    final (confirmTitle, body, confirm) = switch (widget.kind) {
      LibraryKind.favorites => (
        l.clearFavoritesTitle,
        l.clearFavoritesAndWishlistBody(name),
        l.clearFavorites,
      ),
      LibraryKind.watched => (
        l.clearWatchedTitle,
        l.clearWatchedBody(name),
        l.clearHistory,
      ),
      _ => (
        l.clearProgressTitle,
        l.clearProgressBody(name),
        l.clearContinueWatching,
      ),
    };
    // A fresh requestId per confirmed attempt: the backend deduplicates
    // repeated deliveries of the same request.
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}${Random.secure().nextInt(1 << 32)}';
    final done = await confirmAndRun(
      context,
      title: confirmTitle,
      body: body,
      confirmLabel: confirm,
      operation: () => ref.read(repositoryProvider).mutate('clearProfileData', {
        'profileId': widget.profileId,
        'category': category,
        'requestId': requestId,
      }),
    );
    if (!done || !mounted) return;
    ref.invalidate(profileLibraryProvider(widget.profileId));
    showAppFeedbackSheet(context: context, message: l.dataCleared);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final shown = widget.items.where((i) => i.kind == kind).toList();
    final channel = kind == 'channel';
    final section = widget.kind.name;
    return Column(
      key: ValueKey('library-$section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeToEdge.inset,
          child: SectionHeader(title(context)),
        ),
        AppTabs<String>(
          key: ValueKey('library-$section-tabs'),
          padding: EdgeToEdge.inset,
          options: [
            ('channel', l.filterChannels),
            ('movie', l.filterMovies),
            ('series', l.filterSeries),
          ],
          selected: kind,
          onSelected: (k) => setState(() => kind = k),
        ),
        const SizedBox(height: AppSpacing.md),
        if (shown.isEmpty)
          Padding(
            padding: EdgeToEdge.inset,
            child: Text(
              l.emptyKind,
              key: ValueKey('library-$section-empty'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          SizedBox(
            height:
                (channel
                    ? HomeCardSize.channelHeight
                    : HomeCardSize.posterHeight) +
                AppSpacing.sm +
                HomeCardSize.caption +
                AppSpacing.xs,
            child: ListView.separated(
              key: ValueKey('library-$section-row'),
              scrollDirection: Axis.horizontal,
              padding: EdgeToEdge.inset,
              itemCount: shown.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, i) => HomeCard(
                item: shown[i],
                showCaption: true,
                detail: detail(context, shown[i]),
                onTap: () => openTitle(context, shown[i]),
              ),
            ),
          ),
        if (widget.canClear && clearCategory(widget.kind) != null) ...[
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: EdgeToEdge.inset,
            child: AppButton(
              key: ValueKey('clear-$section'),
              label: switch (widget.kind) {
                LibraryKind.favorites => l.clearFavorites,
                LibraryKind.watched => l.clearHistory,
                _ => l.clearContinueWatching,
              },
              onPressed: widget.items.isEmpty ? null : clear,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}
