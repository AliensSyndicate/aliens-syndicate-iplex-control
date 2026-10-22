import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import 'details_button.dart';
import 'home_data.dart';
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
    'generation': profile.favoritesGeneration,
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

  /// Title details page: icon actions of the top bar.
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
      // Details page top bar: icons only, filled when saved.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DetailsBarIcon(
            key: const Key('details-favorite'),
            busy: busy == LibraryList.favorites,
            label: favorite ? l.unfavoriteAction : l.favoriteAction,
            material: favorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            onPressed: () => toggle(LibraryList.favorites),
          ),
          if (!widget.item.isChannel)
            DetailsBarIcon(
              key: const Key('details-wishlist'),
              busy: busy == LibraryList.wishlist,
              label: wished ? l.unsaveAction : l.saveAction,
              material: wished
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              onPressed: () => toggle(LibraryList.wishlist),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          key: const Key('details-favorite'),
          busy: busy == LibraryList.favorites,
          label: favorite ? l.unfavoriteAction : l.favoriteAction,
          onPressed: () => toggle(LibraryList.favorites),
        ),
        if (!widget.item.isChannel) ...[
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const Key('details-wishlist'),
            busy: busy == LibraryList.wishlist,
            label: wished ? l.unsaveAction : l.saveAction,
            onPressed: () => toggle(LibraryList.wishlist),
          ),
        ],
      ],
    );
  }
}

/// Library actions from any card (long press): same toggles as the page.
Future<void> showLibraryActions(
  BuildContext context, {
  required Entry item,
  required HomeData home,
}) async {
  final profile = home.profile;
  if (profile == null || !profile.persistent) return;
  await showAppModalSheet<void>(
    context: context,
    title: item.name,
    content: LibraryButtons(
      item: item,
      profile: profile,
      saved: {
        for (final list in LibraryList.values) list: home.isSaved(list, item),
      },
    ),
  );
}
