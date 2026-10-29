import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import '../../core/data/app_sharing.dart';
import '../watch_on_tv/watch_on_tv_sheet.dart';
import 'content_details_page.dart';
import 'home_data.dart';
import 'home_widgets.dart';
import 'home_providers.dart';
import 'metadata_service.dart';

/// Home data of the source the Home is showing (same selection rules), so
/// detail and person pages know the profile and what is already saved.
/// Without any ready source the library still loads (`sourceId: null`).
final currentHomeProvider = Provider.autoDispose<AsyncValue<HomeData>>((ref) {
  // No family scope (left or removed): no Home data at all, so a late reply
  // of the previous family can never be shown anywhere.
  final scope = ref.watch(
    accountProvider.select((a) => a.asData?.value?.iptvScopeId),
  );
  if (scope == null) return const AsyncData(HomeData());
  final sources = ref.watch(entriesProvider('sources')).asData?.value;
  if (sources == null) return const AsyncLoading();
  final ready = readySources(sources, ref.watch(unlockedSourcesProvider));
  return ref.watch(
    homeProvider(effectiveSourceId(ref.watch(selectedSourceProvider), ready)),
  );
});

/// Adds or removes [item] from one list of the account's own profile.
/// Availability on IPTV is never a condition: editorial titles are saved by
/// their TMDB identity, catalog items also carry their catalog link.
Future<void> saveToLibrary(
  WidgetRef ref, {
  required LibraryList list,
  required Entry item,
  required HomeProfile profile,
  required bool remove,
  ContentMetadata? metadata,
}) async {
  final tmdbId = item.tmdbId ?? metadata?.tmdbId;
  final title = (metadata?.title ?? item.name).trim();
  final poster = metadata?.poster ?? item.editorialPoster;
  final year = metadata?.year ?? item.year;
  await ref.read(repositoryProvider).mutate('saveLibraryItem', {
    'profileId': profile.id,
    'generation': list == LibraryList.wishlist
        ? profile.wishlistGeneration
        : profile.favoritesGeneration,
    'list': list.name,
    'kind': item.kind,
    if (!item.isEditorial) ...{'contentId': item.id, 'sourceId': item.sourceId},
    if (tmdbId != null && !item.isChannel) 'tmdbId': tmdbId,
    if (remove) 'remove': true,
    if (!remove) ...{
      'title': title.length > 300 ? title.substring(0, 300) : title,
      if (metadata?.originalTitle case final original?
          when original != title && original.length <= 300)
        'originalTitle': original,
      if (year != null && year >= 1870 && year <= 2100) 'year': year,
      'poster': ?poster,
    },
  });
  ref.invalidate(homeProvider);
}

/// "Favoritos" + "Lista de desejos" toggles. Both are independent; a channel
/// only has Favoritos. Shown for persistent profiles only (never the guest).
class LibraryButtons extends ConsumerStatefulWidget {
  const LibraryButtons({
    super.key,
    required this.item,
    required this.profile,
    required this.saved,
    this.metadata,
    this.pageStyle = false,
  });

  /// Title details page: icon-only actions in the header.
  final bool pageStyle;
  final Entry item;
  final HomeProfile profile;
  final Map<LibraryList, bool> saved;
  final ContentMetadata? metadata;

  @override
  ConsumerState<LibraryButtons> createState() => _LibraryButtonsState();
}

class _LibraryButtonsState extends ConsumerState<LibraryButtons> {
  late final saved = {...widget.saved};
  LibraryList? busy;

  @override
  void didUpdateWidget(LibraryButtons old) {
    super.didUpdateWidget(old);
    // Library state that changed on the backend (another device, another page).
    if (busy != null) return;
    for (final MapEntry(:key, :value) in widget.saved.entries) {
      if (old.saved[key] != value) saved[key] = value;
    }
  }

  Future<void> toggle(LibraryList list) async {
    if (busy != null) return;
    final was = saved[list] ?? false;
    setState(() => busy = list);
    try {
      await saveToLibrary(
        ref,
        list: list,
        item: widget.item,
        profile: widget.profile,
        remove: was,
        metadata: widget.metadata,
      );
      if (mounted) setState(() => saved[list] = !was);
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final favorite = saved[LibraryList.favorites] ?? false;
    final wished = saved[LibraryList.wishlist] ?? false;
    if (widget.pageStyle) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularButton(
            key: const Key('details-favorite'),
            onPad: true,
            label: l.favoriteLabel,
            selected: favorite,
            onPressed: busy != null
                ? null
                : () => toggle(LibraryList.favorites),
            child: _icon(
              LibraryList.favorites,
              favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              favorite,
            ),
          ),
          if (!widget.item.isChannel)
            CircularButton(
              key: const Key('details-wishlist'),
              onPad: true,
              label: l.wishlistLabel,
              selected: wished,
              onPressed: busy != null
                  ? null
                  : () => toggle(LibraryList.wishlist),
              child: _icon(
                LibraryList.wishlist,
                wished ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                wished,
              ),
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _icon(LibraryList list, IconData icon, bool active) => busy == list
      ? const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.textPrimary,
          ),
        )
      : Icon(icon, color: active ? AppColors.primary : AppColors.textPrimary);
}

/// Content options (reference: "Modal Sheet – Opções de conteúdo"), from
/// the "⋮" of a card or a long press: Assistir na TV (catalog items),
/// Favoritos, Lista de desejos (titles), Compartilhar and Ver detalhes.
/// Only existing actions; nothing here creates new lists.
Future<void> showLibraryActions(
  BuildContext context, {
  required Entry item,
  required HomeData home,
}) => showAppModalSheet<void>(
  context: context,
  builder: (_) => AppModalSheet(
    content: _ContentOptions(item: item, home: home, host: context),
  ),
);

class _ContentOptions extends ConsumerStatefulWidget {
  const _ContentOptions({
    required this.item,
    required this.home,
    required this.host,
  });
  final Entry item;
  final HomeData home;

  /// Page behind the sheet (navigation after the sheet closes).
  final BuildContext host;

  @override
  ConsumerState<_ContentOptions> createState() => _ContentOptionsState();
}

class _ContentOptionsState extends ConsumerState<_ContentOptions> {
  late final saved = {
    for (final list in LibraryList.values)
      list: widget.home.isSaved(list, widget.item),
  };
  LibraryList? busy;
  bool removingProgress = false;

  Future<void> removeProgress() async {
    final profile = widget.home.profile;
    if (profile == null) return;
    setState(() => removingProgress = true);
    try {
      await ref.read(repositoryProvider).mutate('removeProgress', {
        'profileId': profile.id,
        'contentId': widget.item.id,
      });
      ref
        ..invalidate(homeProvider)
        ..invalidate(homeSectionProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => removingProgress = false);
        showFailure(context, e);
      }
    }
  }

  Future<void> toggle(LibraryList list) async {
    final profile = widget.home.profile;
    if (busy != null || profile == null) return;
    final was = saved[list]!;
    setState(() => busy = list);
    try {
      await saveToLibrary(
        ref,
        list: list,
        item: widget.item,
        profile: profile,
        remove: was,
      );
      if (mounted) setState(() => saved[list] = !was);
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  void closeThen(void Function(BuildContext host) action) {
    Navigator.of(context).pop();
    if (widget.host.mounted) action(widget.host);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final item = widget.item;
    final persistent = widget.home.profile?.persistent ?? false;
    final favorite = saved[LibraryList.favorites]!;
    final wished = saved[LibraryList.wishlist]!;
    final kind = switch (item.kind) {
      'channel' => l.channelKind,
      'series' => l.seriesKind,
      _ => l.movieKind,
    };
    return Column(
      key: const Key('content-options'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: item.name,
          subtitle: [kind, if (item.year case final y?) '$y'].join(' • '),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.xs),
            child: SizedBox(
              width: 48,
              height: 72,
              child: Artwork(
                item: item,
                fit: item.isChannel ? BoxFit.contain : BoxFit.cover,
              ),
            ),
          ),
        ),
        if (!item.isEditorial)
          SheetActionRow(
            key: const Key('option-watch'),
            icon: AppIcons.play,
            label: l.watchOnTv,
            onTap: () => closeThen((host) => showWatchOnTv(host, item)),
          ),
        if (persistent) ...[
          SheetActionRow(
            key: const Key('option-favorite'),
            material: favorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            active: favorite,
            label: favorite ? l.removeFromFavorites : l.addToFavorites,
            onTap: busy == null ? () => toggle(LibraryList.favorites) : null,
          ),
          if (!item.isChannel)
            SheetActionRow(
              key: const Key('option-wishlist'),
              material: wished
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              active: wished,
              label: wished ? l.removeFromWishlist : l.addToWishlist,
              onTap: busy == null ? () => toggle(LibraryList.wishlist) : null,
            ),
        ],
        // Only for titles in "Continuar assistindo": forgets the progress so
        // the title leaves that row.
        if (persistent &&
            (item.progress != null ||
                widget.home.continueWatching.any((c) => c.id == item.id)))
          SheetActionRow(
            key: const Key('option-remove-progress'),
            material: Icons.remove_circle_outline_rounded,
            label: l.removeFromContinueWatching,
            onTap: removingProgress ? null : removeProgress,
          ),
        SheetActionRow(
          key: const Key('option-share'),
          material: Icons.ios_share_rounded,
          label: l.share,
          onTap: () async {
            final title = item.year == null
                ? item.name
                : '${item.name} (${item.year})';
            try {
              await AppSharing.share(AppSharing.message(title, title));
            } catch (e) {
              if (context.mounted) showFailure(context, e);
            }
          },
        ),
        SheetActionRow(
          key: const Key('option-details'),
          material: Icons.info_outline_rounded,
          label: l.seeDetails,
          onTap: () => closeThen((host) => openTitle(host, item)),
        ),
      ],
    );
  }
}
