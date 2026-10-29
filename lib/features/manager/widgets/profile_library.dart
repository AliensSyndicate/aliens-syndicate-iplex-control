import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/providers.dart';
import '../../../core/design_system/components.dart';
import '../../../core/domain/models.dart';
import '../../home/content_details_page.dart';
import '../../home/home_data.dart';
import '../../home/home_widgets.dart';
import '../../home/home_page.dart' show catalogColumns;
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

/// The four content lists of a profile.
enum LibraryKind { continueWatching, favorites, wishlist, watched }

/// Data category cleared by `clearProfileData` (one generation per list).
String clearCategory(LibraryKind kind) => switch (kind) {
  LibraryKind.continueWatching => 'progress',
  LibraryKind.favorites => 'favorites',
  LibraryKind.wishlist => 'wishlist',
  LibraryKind.watched => 'watched',
};

extension ProfileLibraryItems on ProfileLibrary {
  List<Entry> of(LibraryKind kind) => switch (kind) {
    LibraryKind.continueWatching => continueWatching,
    LibraryKind.favorites => favorites,
    LibraryKind.wishlist => wishlist,
    LibraryKind.watched => watched,
  };
}

String libraryTitle(BuildContext context, LibraryKind kind) => switch (kind) {
  LibraryKind.continueWatching => context.l.continueWatching,
  LibraryKind.favorites => context.l.favorites,
  LibraryKind.wishlist => context.l.homeWishlist,
  LibraryKind.watched => context.l.watchedHistory,
};

/// Família › integrante › one list: the titles as a catalog grid (Ao vivo,
/// Filmes, Séries tabs) and, when allowed, "Limpar" in the app bar with a
/// confirmation that only closes after the backend cleared the data.
class ProfileLibraryPage extends ConsumerStatefulWidget {
  const ProfileLibraryPage({
    super.key,
    required this.profileId,
    required this.kind,
  });
  final String profileId;
  final LibraryKind kind;

  @override
  ConsumerState<ProfileLibraryPage> createState() => _ProfileLibraryPageState();
}

class _ProfileLibraryPageState extends ConsumerState<ProfileLibraryPage> {
  static const kinds = ['channel', 'movie', 'series'];
  String? kind;

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

  Future<void> clear(String profileName) async {
    final l = context.l;
    final (title, body, confirm) = switch (widget.kind) {
      LibraryKind.favorites => (
        l.clearFavoritesTitle,
        l.clearFavoritesBody(profileName),
        l.clearFavorites,
      ),
      LibraryKind.wishlist => (
        l.clearWishlistTitle,
        l.clearWishlistBody(profileName),
        l.clearWishlist,
      ),
      LibraryKind.watched => (
        l.clearWatchedTitle,
        l.clearWatchedBody(profileName),
        l.clearHistory,
      ),
      LibraryKind.continueWatching => (
        l.clearProgressTitle,
        l.clearProgressBody(profileName),
        l.clearContinueWatching,
      ),
    };
    // A fresh requestId per confirmed attempt: the backend deduplicates
    // repeated deliveries of the same request.
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}${Random.secure().nextInt(1 << 32)}';
    final done = await confirmAndRun(
      context,
      title: title,
      body: body,
      confirmLabel: confirm,
      operation: () => ref.read(repositoryProvider).mutate('clearProfileData', {
        'profileId': widget.profileId,
        'category': clearCategory(widget.kind),
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
    final account = ref.watch(accountProvider).asData?.value;
    final admin = ref.watch(canManageResourcesProvider);
    final profile = ref
        .watch(entryProvider((collection: 'profiles', id: widget.profileId)))
        .asData
        ?.value;
    // The administrator clears any profile; a member only its own.
    final canClear =
        admin ||
        (profile?.data['linkedUid'] != null &&
            profile?.data['linkedUid'] == account?.uid);
    final data = ref.watch(profileLibraryProvider(widget.profileId));
    final items = data.asData?.value.of(widget.kind) ?? const <Entry>[];
    final selected =
        kind ??
        kinds.firstWhere(
          (k) => items.any((i) => i.kind == k),
          orElse: () => 'movie',
        );
    final shown = items.where((i) => i.kind == selected).toList();

    return Scaffold(
      body: PageTemplate(
        title: libraryTitle(context, widget.kind),
        showBack: true,
        action: canClear && items.isNotEmpty
            ? CircularButton(
                key: const Key('library-clear'),
                label: switch (widget.kind) {
                  LibraryKind.favorites => l.clearFavorites,
                  LibraryKind.wishlist => l.clearWishlist,
                  LibraryKind.watched => l.clearHistory,
                  LibraryKind.continueWatching => l.clearContinueWatching,
                },
                icon: AppIcons.delete,
                size: AppDimensions.touch,
                onPressed: () => clear(profile?.name ?? ''),
              )
            : null,
        child: data.when(
          loading: () => const AppLoadingSkeleton(rows: 3),
          error: (e, s) => ErrorState(
            onRetry: () =>
                ref.invalidate(profileLibraryProvider(widget.profileId)),
          ),
          data: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTabs<String>(
                key: const Key('library-tabs'),
                options: [
                  ('channel', l.filterChannels),
                  ('movie', l.filterMovies),
                  ('series', l.filterSeries),
                ],
                selected: selected,
                onSelected: (k) => setState(() => kind = k),
              ),
              const SizedBox(height: AppSpacing.md),
              if (shown.isEmpty)
                EmptyState(
                  key: const Key('library-empty'),
                  title: libraryTitle(context, widget.kind),
                  body: l.emptyKind,
                  icon: AppIcons.iptv,
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = AppSpacing.sm;
                    final cell =
                        (constraints.maxWidth - gap * (catalogColumns - 1)) /
                        catalogColumns;
                    return Wrap(
                      key: const Key('library-grid'),
                      spacing: gap,
                      runSpacing: AppSpacing.md,
                      children: [
                        for (final item in shown)
                          SizedBox(
                            width: cell,
                            child: HomeCard(
                              item: item,
                              width: cell,
                              showCaption: true,
                              detail: detail(context, item),
                              onTap: () => openTitle(context, item),
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
