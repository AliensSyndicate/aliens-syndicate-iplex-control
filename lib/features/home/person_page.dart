import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design_system/components.dart';
import 'content_details_page.dart';
import 'details_layout.dart';
import 'home_data.dart';
import 'home_widgets.dart';
import 'library.dart';
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
class _PersonBody {
  const _PersonBody({required this.person, required this.home});
  final PersonDetails person;
  final HomeData? home;

  List<Widget> children(BuildContext context) {
    final p = person;
    String date(DateTime d) => formatDate(context, d);
    final dates = [
      if (p.birthday case final b?) date(b),
      if (p.deathday case final d?) date(d),
    ].join(' – ');
    final secondary = AppTypography.bodyMedium.copyWith(
      color: AppColors.textSecondary,
    );
    return [
      Text(
        p.name,
        key: const Key('person-name'),
        textAlign: TextAlign.center,
        style: AppTypography.headlineMedium.copyWith(
          color: AppColors.textPrimary,
        ),
      ),
      // No labels: birthplace, then the dates.
      Column(
        key: const Key('person-facts'),
        children: [
          if (p.placeOfBirth case final place?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(place, textAlign: TextAlign.center, style: secondary),
          ],
          if (dates.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(dates, textAlign: TextAlign.center, style: secondary),
          ],
        ],
      ),
      // Only the icons, centered.
      if (p.social.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        _SocialBar(links: p.social),
      ],
      if (p.biography.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
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
      if (p.credits.isNotEmpty) ..._timeline(context, p.credits),
    ];
  }

  /// Filmography: vertical, newest first, grouped by year (undated works
  /// last). Each work is the cast card of the title page laid out
  /// horizontally: the 3:4 cover on the left, the text on the right.
  List<Widget> _timeline(BuildContext context, List<PersonCredit> credits) {
    final l = context.l;
    final byYear = <int?, List<PersonCredit>>{};
    for (final c in credits) {
      (byYear[c.year ?? c.date?.year] ??= []).add(c);
    }
    final years = byYear.keys.toList()
      ..sort((a, b) => (b ?? -1).compareTo(a ?? -1));
    return [
      const SizedBox(height: AppSpacing.md),
      // Number of acting credits (works only as crew are not counted).
      Semantics(
        header: true,
        child: SectionHeader(
          '${l.filmography} (${credits.where((c) => c.character.isNotEmpty || c.job.isEmpty).length})',
        ),
      ),
      for (final (i, year) in years.indexed) ...[
        // Years are labels inside the section, not section titles.
        Padding(
          padding: EdgeInsets.only(
            top: i == 0 ? 0 : AppSpacing.sm,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            year == null ? l.undatedLabel : '$year',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        for (final c in byYear[year]!)
          _CreditCard(
            key: ValueKey('timeline-${c.kind}-${c.tmdbId}'),
            credit: c,
            subtitle: [
              c.kind == 'movie' ? l.movieKind : l.seriesKind,
              if (c.character.isNotEmpty) l.asCharacter(c.character),
              if (c.character.isEmpty && c.job.isNotEmpty) c.job,
              if (c.episodeCount case final n? when n > 0) l.episodesCount(n),
            ].join(' · '),
            onTap: () => openTitle(context, c.entry),
          ),
      ],
    ];
  }
}

/// Social profiles below the birth information: one icon each, opened in the
/// browser (in-app browser view, never a deep link into another app).
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
  Widget build(BuildContext context) => Center(
    child: Wrap(
      key: const Key('person-social'),
      alignment: WrapAlignment.center,
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

/// Keeps the skeleton until the actor's photo is decoded too, then shows the
/// page at once (no cover popping in afterwards).
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
      NetworkImage(url),
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
      cover: _PersonCover(name: p.name, url: photo),
      children: _PersonBody(person: p, home: widget.home).children(context),
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
      child: Image.network(
        photo,
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

/// One work of the filmography: the cast card of the title page laid out
/// horizontally (same 3:4 rounded cover and text styles, no surface), the
/// text vertically centered next to the cover.
class _CreditCard extends StatelessWidget {
  const _CreditCard({
    super.key,
    required this.credit,
    required this.subtitle,
    required this.onTap,
  });
  final PersonCredit credit;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Semantics(
      button: true,
      label: '${credit.title}, $subtitle',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: SizedBox(
                width: PortraitCard.width,
                height: PortraitCard.height,
                child: Artwork(item: credit.entry),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    credit.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      fontSize: 15,
                      height: 1.25,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
