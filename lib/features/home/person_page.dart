import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import 'content_details_page.dart';
import 'browse_widgets.dart';
import 'details_layout.dart';
import 'library.dart';
import 'home_data.dart';
import 'home_widgets.dart';
import 'metadata_service.dart';

final _personProvider = FutureProvider.autoDispose.family<PersonDetails?, int>(
  (ref, id) => ref.watch(metadataServiceProvider).person(id),
  retry: (retryCount, error) => null,
);

/// A person (TMDB): photo, biography, birth, filmography and career timeline.
/// Every work opens its own details page, available on IPTV or not.
class PersonPage extends ConsumerWidget {
  const PersonPage({super.key, required this.tmdbId});
  final int tmdbId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final person = ref.watch(_personProvider(tmdbId));
    final home = ref.watch(currentHomeProvider).asData?.value;
    // Same look as the title page: black page, the photo as the cover.
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, box) => person.when(
          loading: () => DetailsSkeleton(height: box.maxHeight, person: true),
          error: (e, stack) => PageTemplate(
            title: '',
            showBack: true,
            child: e is MetadataUnavailable && e.status == 403
                ? EmptyState(
                    title: l.discoveryNotAllowed,
                    body: '',
                    icon: AppIcons.alert,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.personUnavailable,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ErrorState(
                        onRetry: () => ref.invalidate(_personProvider(tmdbId)),
                      ),
                    ],
                  ),
          ),
          data: (p) => p == null
              ? PageTemplate(
                  title: '',
                  showBack: true,
                  child: EmptyState(
                    title: l.personUnavailable,
                    body: '',
                    icon: AppIcons.person,
                  ),
                )
              : _PersonLoaded(
                  key: ValueKey(p.tmdbId),
                  person: p,
                  home: home,
                  height: box.maxHeight,
                ),
        ),
      ),
    );
  }
}

/// Centered like the title page: name, birthplace, dates and social icons;
/// then the biography (like the synopsis) and the filmography.
/// Actor page body (prototype screens 6 and 7): name and department over the
/// photo, then Sobre (birth, social profiles, whole biography) and
/// Filmografia (newest first; each work opens its details page and can be
/// saved to Favoritos / Lista de desejos without opening it).
List<Widget> _personChildren(
  BuildContext context, {
  required PersonDetails person,
  required HomeData? home,
  required int tab,
  required ValueChanged<int> onTab,
}) {
  final l = context.l;
  final p = person;
  final dates = [
    if (p.birthday case final b?) formatDate(context, b),
    if (p.deathday case final d?) formatDate(context, d),
  ].join(' – ');
  final secondary = AppTypography.bodyMedium.copyWith(
    color: AppColors.textSecondary,
  );
  final department = switch (p.knownFor) {
    'Acting' => l.deptActing,
    'Directing' => l.deptDirecting,
    'Writing' => l.deptWriting,
    'Production' => l.deptProduction,
    _ => '',
  };
  return [
    Text(
      p.name,
      key: const Key('person-name'),
      style: AppTypography.headlineMedium.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    ),
    if (department.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.xs),
      Text(department, style: secondary),
    ],
    const SizedBox(height: AppSpacing.md),
    EdgeToEdge(
      child: AppTabs<int>(
        key: const Key('person-tabs'),
        padding: EdgeToEdge.inset,
        options: [
          (0, l.aboutTab),
          // Number of acting credits (works only as crew are not counted).
          (
            1,
            '${l.filmographyTab} (${p.credits.where((c) => c.character.isNotEmpty || c.job.isEmpty).length})',
          ),
        ],
        selected: tab,
        onSelected: onTab,
      ),
    ),
    const SizedBox(height: AppSpacing.md),
    if (tab == 0) ...[
      Column(
        key: const Key('person-facts'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p.placeOfBirth case final place?) Text(place, style: secondary),
          if (dates.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(dates, style: secondary),
          ],
        ],
      ),
      if (p.social.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        _SocialBar(links: p.social),
      ],
      if (p.biography.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        // Always the whole biography.
        Text(
          p.biography,
          key: const Key('person-biography'),
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
            height: 1.45,
          ),
        ),
      ],
    ] else
      for (final c in p.credits)
        MediaListRow(
          key: ValueKey('timeline-${c.kind}-${c.tmdbId}'),
          image: Artwork(item: c.entry),
          title: c.title,
          subtitle: [
            if (c.year ?? c.date?.year case final y?) '$y',
            if (c.character.isNotEmpty)
              c.character
            else if (c.job.isNotEmpty)
              c.job,
          ].join(' · '),
          onTap: () => openTitle(context, c.entry),
          trailing: home?.profile?.persistent == true
              ? _RowLibrary(item: c.entry, home: home!)
              : null,
        ),
  ];
}

/// Heart and bookmark of a filmography row (same rule as the details page:
/// TMDB titles can be saved even when no IPTV source offers them).
class _RowLibrary extends ConsumerStatefulWidget {
  const _RowLibrary({required this.item, required this.home});
  final Entry item;
  final HomeData home;
  @override
  ConsumerState<_RowLibrary> createState() => _RowLibraryState();
}

class _RowLibraryState extends ConsumerState<_RowLibrary> {
  late final saved = {
    for (final list in LibraryList.values)
      list: widget.home.isSaved(list, widget.item),
  };
  LibraryList? busy;

  Future<void> toggle(LibraryList list) async {
    if (busy != null) return;
    final was = saved[list]!;
    setState(() => busy = list);
    try {
      await saveToLibrary(
        ref,
        list: list,
        item: widget.item,
        profile: widget.home.profile!,
        remove: was,
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
    Widget icon(LibraryList list, IconData on, IconData off, String label) =>
        Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: InkResponse(
            key: ValueKey('row-${list.name}-${widget.item.id}'),
            radius: 22,
            onTap: busy == null ? () => toggle(list) : null,
            child: SizedBox.square(
              dimension: 40,
              child: Icon(
                saved[list]! ? on : off,
                size: 22,
                color: saved[list]!
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon(
          LibraryList.favorites,
          Icons.favorite_rounded,
          Icons.favorite_border_rounded,
          l.favoriteLabel,
        ),
        icon(
          LibraryList.wishlist,
          Icons.bookmark_rounded,
          Icons.bookmark_border_rounded,
          l.wishlistLabel,
        ),
      ],
    );
  }
}

class _PersonLoaded extends StatefulWidget {
  const _PersonLoaded({
    super.key,
    required this.person,
    required this.home,
    required this.height,
  });
  final PersonDetails person;
  final HomeData? home;
  final double height;

  @override
  State<_PersonLoaded> createState() => _PersonLoadedState();
}

class _PersonLoadedState extends State<_PersonLoaded> {
  bool ready = false;
  int tab = 0;
  String? get photo => tmdbSized(widget.person.photo);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ready) return;
    final url = photo;
    if (url == null) {
      ready = true;
      return;
    }
    // A missing or slow photo never blocks the page for long.
    precacheImage(
      CachedNetworkImage(url, decodeWidth: 1080),
      context,
      // A failed photo falls back to initials; it is not an app error.
      onError: (error, stack) {},
    ).timeout(const Duration(seconds: 8)).catchError((_) {}).whenComplete(() {
      if (mounted) setState(() => ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return DetailsSkeleton(height: widget.height, person: true);
    final p = widget.person;
    return DetailsLayout(
      height: widget.height,
      coverFraction: 0.6,
      contentStart: 0.42,
      cover: _PersonCover(name: p.name, url: photo),
      children: _personChildren(
        context,
        person: p,
        home: widget.home,
        tab: tab,
        onTab: (i) => setState(() => tab = i),
      ),
    );
  }
}

/// The actor's own photo (TMDB profile) as the cover; initials without one.
class _PersonCover extends StatelessWidget {
  const _PersonCover({required this.name, required this.url});
  final String name;
  final String? url;

  Widget _initials() => ColoredBox(
    color: Colors.black,
    child: Center(
      child: Text(
        name
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w.characters.first.toUpperCase())
            .join(),
        style: AppTypography.headlineLarge.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final photo = url;
    if (photo == null) return _initials();
    return ColoredBox(
      color: Colors.black,
      child: Image(
        image: CachedNetworkImage(photo, decodeWidth: 1080),
        key: const Key('person-cover'),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stack) => _initials(),
      ),
    );
  }
}

/// Social profiles: one white icon each, opened in the browser (in-app
/// browser view, never a deep link into another app).
class _SocialBar extends StatelessWidget {
  const _SocialBar({required this.links});
  final List<SocialLink> links;

  static const _icons = {
    'instagram': AppIcons.instagram,
    'x': AppIcons.x,
    'facebook': AppIcons.facebook,
    'tiktok': AppIcons.tiktok,
    'youtube': AppIcons.youtube,
    'imdb': AppIcons.web,
  };

  @override
  Widget build(BuildContext context) => Transform.translate(
    // 48 dp targets around 24 dp icons: the first glyph lines up with the text.
    offset: const Offset(-(AppDimensions.touch - AppDimensions.icon) / 2, 0),
    child: Wrap(
      key: const Key('person-social'),
      children: [
        for (final link in links)
          Semantics(
            button: true,
            link: true,
            label: link.label,
            excludeSemantics: true,
            child: InkResponse(
              key: ValueKey('social-${link.network}'),
              radius: AppDimensions.touch / 2,
              onTap: () =>
                  launchUrl(link.url, mode: LaunchMode.inAppBrowserView),
              child: SizedBox.square(
                dimension: AppDimensions.touch,
                child: Center(
                  child: AppIcon(_icons[link.network]!, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
