import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import 'content_details_page.dart';
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
    return Scaffold(
      backgroundColor: AppColors.backgroundDeep,
      body: person.when(
        loading: () => PageTemplate(
          title: '',
          showBack: true,
          child: const AppLoadingSkeleton(rows: 4),
        ),
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
            : PageTemplate(
                title: p.name,
                showBack: true,
                child: _PersonBody(person: p, home: home),
              ),
      ),
    );
  }
}

class _PersonBody extends StatefulWidget {
  const _PersonBody({required this.person, required this.home});
  final PersonDetails person;
  final HomeData? home;

  @override
  State<_PersonBody> createState() => _PersonBodyState();
}

class _PersonBodyState extends State<_PersonBody> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final p = widget.person;
    final facts = [
      if (p.birthday case final b?)
        l.bornLabel([formatDate(context, b), ?p.placeOfBirth].join(' · '))
      else
        ?p.placeOfBirth,
      if (p.deathday case final d?) l.diedLabel(formatDate(context, d)),
    ];
    final movies = [
      for (final c in p.credits)
        if (c.kind == 'movie') c,
    ];
    final series = [
      for (final c in p.credits)
        if (c.kind == 'series') c,
    ];
    final long = p.biography.length > 400;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: SizedBox(
                width: HomeCardSize.posterWidth,
                height: HomeCardSize.posterHeight,
                child: Artwork(
                  item: editorialEntry(
                    kind: 'movie',
                    tmdbId: p.tmdbId,
                    title: p.name,
                    poster: p.photo,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final fact in facts) ...[
                    Text(
                      fact,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (p.biography.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Semantics(header: true, child: SectionHeader(l.biography)),
          Text(
            p.biography,
            key: const Key('person-biography'),
            maxLines: expanded || !long ? null : 6,
            overflow: expanded || !long ? null : TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary,
              height: 1.45,
            ),
          ),
          if (long)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => expanded = !expanded),
                child: Text(expanded ? l.showLess : l.showMore),
              ),
            ),
        ],
        if (p.credits.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(l.filmography, style: AppTypography.titleLarge),
          for (final (title, credits) in [
            (l.moviesLabel, movies),
            (l.seriesLabel, series),
          ])
            if (credits.isNotEmpty)
              HomeRow(
                title: title,
                items: [for (final c in credits) c.entry],
                limit: 20,
                onTap: (item) => openTitle(context, item),
                onLongPress: _library(context),
              ),
          ..._timeline(context, p.credits),
        ],
      ],
    );
  }

  ValueChanged<Entry>? _library(BuildContext context) {
    final home = widget.home;
    if (home?.profile?.persistent != true) return null;
    return (item) => showLibraryActions(context, item: item, home: home!);
  }

  /// Career timeline: newest first, grouped by year; undated works last.
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
      Text(l.careerTimeline, style: AppTypography.titleLarge),
      for (final year in years) ...[
        SectionHeader(year == null ? l.undatedLabel : '$year'),
        for (final c in byYear[year]!)
          EntryTile(
            key: ValueKey('timeline-${c.kind}-${c.tmdbId}'),
            title: c.title,
            subtitle: [
              c.kind == 'movie' ? l.movieKind : l.seriesKind,
              if (c.character.isNotEmpty) l.asCharacter(c.character),
              if (c.character.isEmpty && c.job.isNotEmpty) c.job,
              if (c.episodeCount case final n? when n > 0) l.episodesCount(n),
            ].join(' · '),
            icon: c.kind == 'movie' ? AppIcons.movie : AppIcons.series,
            onTap: () => openTitle(context, c.entry),
          ),
      ],
    ];
  }
}
