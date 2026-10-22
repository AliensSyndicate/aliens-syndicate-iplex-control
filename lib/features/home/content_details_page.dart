import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import '../watch_on_tv/watch_on_tv_sheet.dart';
import 'details_button.dart';
import 'details_layout.dart';
import 'home_data.dart';
import 'home_providers.dart';
import 'home_widgets.dart';
import 'library.dart';
import 'metadata_service.dart';
import 'season_sheet.dart';

/// Opens the full details page of [item] on top of the current page (Home →
/// title → person → title …); Back returns through the same stack.
void openTitle(BuildContext context, Entry item) {
  if (item.isEditorial) {
    context.push('/home/title/${item.kind}/${item.tmdbId}', extra: item);
  } else {
    context.push('/home/title', extra: item);
  }
}

void openPerson(BuildContext context, int tmdbId) =>
    context.push('/home/person/$tmdbId');

/// "1h 58min" / "45 min" — locale-neutral.
String formatRuntime(BuildContext context, int minutes) => minutes >= 60
    ? '${minutes ~/ 60}h${minutes % 60 == 0 ? '' : ' ${minutes % 60}min'}'
    : context.l.runtimeMinutes(minutes);

String formatDate(BuildContext context, DateTime date) {
  final locale = Localizations.localeOf(context).toString();
  return locale.startsWith('pt')
      ? DateFormat('dd/MM/yyyy', locale).format(date)
      : DateFormat.yMd(locale).format(date);
}

/// Details of a catalog item or of an editorial (TMDB) title that may not exist
/// in any IPTV source. Actions start a title on a paired TV (the existing
/// "Assistir na TV" flow, only for a playable catalog item) or change the
/// profile's lists — the Control never becomes a remote control.
class ContentDetailsPage extends ConsumerStatefulWidget {
  const ContentDetailsPage({super.key, this.item, this.kind, this.tmdbId});

  /// Catalog item, or an editorial entry used as a placeholder while loading.
  final Entry? item;
  final String? kind;
  final int? tmdbId;

  @override
  ConsumerState<ContentDetailsPage> createState() => _ContentDetailsPageState();
}

class _ContentDetailsPageState extends ConsumerState<ContentDetailsPage> {
  Future<ContentMetadata?>? metadata;
  Future<List<_Programme>>? guide;

  List<TvEpisode> episodes = const [];

  /// Catalog item that can be sent to the TV (null: not available to watch).
  Entry? playable;
  bool resolving = false;

  /// Series episodes still being read from the source.
  bool loadingEpisodes = false;

  late final Entry? entry = _initialEntry();
  Entry? _initialEntry() {
    final item = widget.item;
    if (item != null && !item.isEditorial) return item;
    final kind = widget.kind ?? item?.kind,
        tmdbId = widget.tmdbId ?? item?.tmdbId;
    if ((kind != 'movie' && kind != 'series') || tmdbId == null) return null;
    return item ?? editorialEntry(kind: kind!, tmdbId: tmdbId, title: '');
  }

  bool get editorial => entry?.isEditorial ?? false;

  @override
  void initState() {
    super.initState();
    final item = entry;
    if (item == null) return;
    _load(item);
  }

  void _load(Entry item) {
    final service = ref.read(metadataServiceProvider);
    if (editorial) {
      // Availability is looked up right after the metadata: the page stays on
      // its skeleton until both are known.
      resolving = true;
      metadata = service.title(item.kind, item.tmdbId!);
      metadata!.then(_resolveAvailability, onError: (_) {}).ignore();
      return;
    }
    playable = item;
    if (item.isPlayableTitle) metadata = service.details(item);
    final epgId = item.text('epgId');
    if (item.isChannel && epgId.isNotEmpty) guide = _loadGuide(item, epgId);
    if (item.kind == 'series') _loadEpisodes(item);
  }

  /// Editorial title: is there a confident, authorized catalog correspondence?
  Future<void> _resolveAvailability(ContentMetadata? meta) async {
    final item = entry!;
    setState(() => resolving = true);
    try {
      final result = await ref.read(repositoryProvider).mutate('resolveTitle', {
        'kind': item.kind,
        'tmdbId': item.tmdbId,
        if ((meta?.title ?? item.name).isNotEmpty)
          'title': meta?.title ?? item.name,
        'originalTitle': ?meta?.originalTitle,
        'year': ?(meta?.year ?? item.year),
        'sourceId': ?ref.read(selectedSourceProvider),
      });
      final raw = result['item'];
      if (!mounted || raw is! Map || raw['id'] is! String) return;
      final found = Entry(raw['id'] as String, Map<String, dynamic>.from(raw));
      setState(() => playable = found);
      if (found.kind == 'series') _loadEpisodes(found);
    } catch (_) {
      // Unknown availability is shown as unavailable; saving still works.
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }

  /// Seasons and episodes come from the source itself (never from TMDB), so
  /// only what the IPTV source really offers is presented as playable.
  Future<void> _loadEpisodes(Entry item) async {
    if (mounted) setState(() => loadingEpisodes = true);
    try {
      final result = await ref.read(repositoryProvider).mutate(
        'readSourceSeries',
        {'id': item.sourceId, 'seriesId': item.text('providerRef')},
      );
      final list = parseEpisodes(result['details']);
      if (mounted) setState(() => episodes = list);
    } catch (_) {
      // Optional section: the page stays complete without it.
    } finally {
      if (mounted) setState(() => loadingEpisodes = false);
    }
  }

  Future<List<_Programme>> _loadGuide(Entry item, String epgId) async {
    final result = await ref.read(repositoryProvider).mutate('readSourceEpg', {
      'id': item.sourceId,
      'channelId': epgId,
    });
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      for (final raw in (result['programmes'] as List? ?? const []))
        if (raw is Map &&
            raw['title'] is String &&
            (raw['endAt'] as num? ?? 0) > now)
          _Programme(
            '${raw['title']}',
            DateTime.fromMillisecondsSinceEpoch(
              (raw['startAt'] as num).toInt(),
            ),
            DateTime.fromMillisecondsSinceEpoch((raw['endAt'] as num).toInt()),
          ),
    ].take(3).toList();
  }

  /// Saved progress of the playable item (from any Home row).
  Entry? _withProgress(HomeData? home) {
    final item = playable;
    if (item == null || item.progress != null) return item;
    return home?.continueWatching.where((c) => c.id == item.id).firstOrNull ??
        item;
  }

  /// The one episode suggested for a series: the one in progress, else the
  /// first available.
  TvEpisode? _episode(Entry? item) {
    if (item?.kind != 'series' || episodes.isEmpty) return null;
    return episodes.where((e) => e.id == item!.episodeId).firstOrNull ??
        episodes.first;
  }

  void watchOnTv(Entry item, {bool resume = false, String? episodeId}) =>
      showWatchOnTv(
        context,
        item,
        resume: resume,
        episodeId: episodeId ?? (resume ? item.episodeId : _episode(item)?.id),
      );

  @override
  Widget build(BuildContext context) {
    final item = entry;
    if (item == null) {
      return Scaffold(
        backgroundColor: AppColors.backgroundDeep,
        body: PageTemplate(
          title: context.l.notFound,
          showBack: true,
          child: ErrorState(onRetry: () => Navigator.of(context).maybePop()),
        ),
      );
    }
    final home = ref.watch(currentHomeProvider).asData?.value;
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, box) => FutureBuilder<ContentMetadata?>(
          future: metadata,
          builder: (context, snapshot) {
            if (editorial && snapshot.hasError) {
              return _unavailable(
                context,
                snapshot.error is MetadataUnavailable &&
                        (snapshot.error as MetadataUnavailable).status == 403
                    ? context.l.discoveryNotAllowed
                    : context.l.metadataUnavailable,
                retry:
                    snapshot.error is MetadataUnavailable &&
                        (snapshot.error as MetadataUnavailable).status == 403
                    ? null
                    : () => setState(() => _load(item)),
              );
            }
            final loading =
                metadata != null &&
                snapshot.connectionState != ConnectionState.done;
            final meta = snapshot.data;
            final homeLoading =
                ref.watch(currentHomeProvider).isLoading &&
                !ref.watch(currentHomeProvider).hasValue;
            if (loading || resolving || loadingEpisodes || homeLoading) {
              return DetailsSkeleton(height: box.maxHeight);
            }
            if (editorial && meta == null) {
              return _unavailable(context, context.l.metadataUnavailable);
            }
            final shown = editorial
                ? editorialEntry(
                    kind: item.kind,
                    tmdbId: item.tmdbId!,
                    title: meta?.title ?? item.name,
                    originalTitle: meta?.originalTitle,
                    year: meta?.year ?? item.year,
                    poster: meta?.poster ?? item.editorialPoster,
                  )
                : item;
            return _layout(context, box, shown, meta, loading, home);
          },
        ),
      ),
    );
  }

  Widget _unavailable(
    BuildContext context,
    String message, {
    VoidCallback? retry,
  }) => Container(
    color: AppColors.backgroundDeep,
    child: PageTemplate(
      title: entry!.name.isEmpty ? '' : entry!.name,
      showBack: true,
      child: retry == null
          ? EmptyState(title: message, body: '', icon: AppIcons.alert)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  message,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ErrorState(onRetry: retry),
              ],
            ),
    ),
  );

  Widget _layout(
    BuildContext context,
    BoxConstraints box,
    Entry shown,
    ContentMetadata? meta,
    bool loading,
    HomeData? home,
  ) {
    final channel = shown.isChannel;
    return DetailsLayout(
      height: box.maxHeight,
      coverFraction: channel ? 0.6 : 0.75,
      // Titles use the original TMDB poster as a full-bleed cover; channels
      // keep their logo.
      cover: channel
          ? Artwork(
              item: shown,
              fit: BoxFit.contain,
              alignment: Alignment.topCenter,
              background: Colors.black,
            )
          : DetailsCover(
              item: shown,
              url: tmdbSized(meta?.posterOriginal ?? meta?.poster),
              loading: loading,
            ),
      actions: _libraryBar(shown, meta, home),
      children: [
        ..._summary(context, shown, meta, home),
        ..._details(context, shown, meta),
        ..._people(context, meta, home),
        ..._seasons(context, shown, meta),
        ..._guide(context),
      ],
    );
  }

  /// Title, original title, "2021 | Gênero | 1h 25min", stars, play and lists.
  List<Widget> _summary(
    BuildContext context,
    Entry shown,
    ContentMetadata? meta,
    HomeData? home,
  ) {
    final l = context.l;
    final channel = shown.isChannel;
    final target = _withProgress(home);
    final resume = target?.progress != null && !channel;
    final episode = _episode(target);
    final year = meta?.year ?? shown.year;
    final genres = meta?.genres ?? const <String>[];
    final category = editorial ? '' : shown.text('category');
    final minutes = meta?.runtimeMinutes;
    final seasons = _seasonCount(meta);
    final facts = <String>[
      if (channel) l.liveChannel,
      if (!channel && year != null) '$year',
      if (genres.isNotEmpty)
        genres.first
      else if (category.isNotEmpty)
        category,
      if (minutes != null && shown.kind == 'movie')
        formatRuntime(context, minutes),
      if (episode case final e?)
        e.number.isEmpty
            ? l.seasonNumber(e.season)
            : l.seasonEpisodeShort(e.season, e.number)
      else if (shown.kind == 'series' && seasons > 0)
        l.seasonsCount(seasons),
    ];
    final score = meta?.rating ?? double.tryParse(shown.text('rating'));
    final stars = score == null || channel
        ? null
        : (score.clamp(0, 10) / 2).toDouble();
    final original = meta?.originalTitle;
    final seal = AgeRatingBadge.normalize(_rawAgeRating(shown, meta));
    return [
      Text(
        shown.name,
        key: const Key('details-title'),
        textAlign: TextAlign.center,
        style: AppTypography.headlineMedium.copyWith(
          color: AppColors.textPrimary,
        ),
      ),
      if (original != null &&
          original.toLowerCase() != shown.name.toLowerCase()) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          l.originalTitleLabel(original),
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
      if (facts.isNotEmpty || seal != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Text.rich(
          key: const Key('details-facts'),
          TextSpan(
            children: [
              // ClassInd seal: first position of the year line.
              if (seal != null) ...[
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Semantics(
                    label: l.ageRatingLabel(seal),
                    child: AgeRatingBadge(seal, size: 24),
                  ),
                ),
                if (facts.isNotEmpty) const TextSpan(text: '  '),
              ],
              TextSpan(text: facts.join(' | ')),
            ],
          ),
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
      ..._ageRating(context, shown, meta),
      if (stars != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Row(
          key: const Key('details-stars'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 5; i++)
              Icon(
                stars >= i + 1
                    ? Icons.star_rounded
                    : stars >= i + 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
                size: 22,
                color: AppColors.warning,
              ),
          ],
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      if (target != null && resume) ...[
        // In progress: continue where it stopped, or start over (same
        // episode for a series).
        Row(
          children: [
            Expanded(
              child: DetailsButton.primary(
                key: const Key('details-continue'),
                label: l.continueLabel,
                onPressed: () => watchOnTv(target, resume: true),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Text only, fit width (label + padding); Continue takes the rest.
            DetailsButton(
              key: const Key('details-restart'),
              label: l.restartLabel,
              onPressed: () =>
                  watchOnTv(target, episodeId: target.episodeId ?? episode?.id),
            ),
          ],
        ),
      ] else if (target != null)
        DetailsButton.primary(
          key: const Key('details-watch-on-tv'),
          label: l.watchOnTv,
          onPressed: () => watchOnTv(target),
        )
      else if (!resolving)
        Text(
          l.notAvailableToWatch,
          key: const Key('details-unavailable'),
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      const SizedBox(height: AppSpacing.lg),
    ];
  }

  /// Favoritar / Salvar as icons on the right of the top bar.
  Widget? _libraryBar(Entry shown, ContentMetadata? meta, HomeData? home) {
    final profile = home?.profile;
    if (profile == null || !profile.persistent) return null;
    final target = playable;
    return LibraryButtons(
      key: ValueKey('library-${shown.id}'),
      pageStyle: true,
      item: shown,
      profile: profile,
      metadata: meta,
      saved: {
        for (final list in LibraryList.values)
          list:
              home!.isSaved(list, shown) ||
              (target != null && home.isSaved(list, target)) ||
              (meta?.tmdbId != null &&
                  home.isSaved(
                    list,
                    editorialEntry(
                      kind: shown.kind,
                      tmdbId: meta!.tmdbId!,
                      title: '',
                    ),
                  )),
      },
    );
  }

  String? _rawAgeRating(Entry shown, ContentMetadata? meta) =>
      meta?.certification ??
      (shown.text('ageRating').isEmpty ? null : shown.text('ageRating'));

  /// Reasons of the age rating, under the year line that carries the seal.
  List<Widget> _ageRating(
    BuildContext context,
    Entry shown,
    ContentMetadata? meta,
  ) {
    final seal = AgeRatingBadge.normalize(_rawAgeRating(shown, meta));
    final reasons = meta?.certificationDescriptors ?? const <String>[];
    if (seal == null || reasons.isEmpty) return const [];
    return [
      const SizedBox(height: AppSpacing.xs),
      Text(
        _sentence(reasons, context),
        key: const Key('details-age-rating'),
        textAlign: TextAlign.center,
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    ];
  }

  /// "Violência, drogas e conteúdo sexual".
  String _sentence(List<String> items, BuildContext context) {
    final lower = [
      for (final (i, t) in items.indexed)
        i == 0 ? t : t[0].toLowerCase() + t.substring(1),
    ];
    if (lower.length == 1) return lower.first;
    return '${lower.sublist(0, lower.length - 1).join(', ')} ${context.l.andConjunction} ${lower.last}';
  }

  int _seasonCount(ContentMetadata? meta) =>
      meta?.seasonCount ?? {for (final e in episodes) e.season}.length;

  /// One item per line, in a single column; then the synopsis.
  List<Widget> _details(
    BuildContext context,
    Entry shown,
    ContentMetadata? meta,
  ) {
    final l = context.l;
    final raw = _rawAgeRating(shown, meta);
    // Shown as the ClassInd seal; only an unknown scheme stays as text.
    final age = AgeRatingBadge.normalize(raw) == null ? raw : null;
    final directors = [for (final p in meta?.crew ?? const <Credit>[]) p.name];
    final genres = meta?.genres ?? const <String>[];
    final category = editorial ? '' : shown.text('category');
    final rows = <(String, bool)>[
      if (age != null) (l.ageRatingLabel(age), true),
      if (meta?.releaseDate case final date?)
        (l.releaseDateLabel(formatDate(context, date)), true),
      if (meta?.runtimeMinutes != null && shown.kind != 'movie')
        (formatRuntime(context, meta!.runtimeMinutes!), true),
      if (shown.kind == 'series' && episodes.isNotEmpty)
        (l.episodesCount(episodes.length), true),
      if (meta?.rating case final rating?)
        (l.ratingLabel(rating.toStringAsFixed(1)), false),
      if (genres.isNotEmpty) (genres.take(6).join(', '), false),
      if (category.isNotEmpty &&
          !genres.any((g) => g.toLowerCase() == category.toLowerCase()))
        (category, false),
    ];
    final synopsis = (meta?.overview.isNotEmpty ?? false)
        ? meta!.overview
        : shown.text('plot');
    return [
      for (final (text, primary) in rows) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          text,
          style: AppTypography.bodyMedium.copyWith(
            color: primary ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ],
      if (directors.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        Text(
          shown.kind == 'series'
              ? l.createdByLabel(directors.join(', '))
              : l.directedByLabel(directors.join(', ')),
          key: const Key('details-director'),
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ],
      if (synopsis.isNotEmpty) ...[
        SizedBox(height: directors.isEmpty ? AppSpacing.lg : AppSpacing.md),
        Text(
          synopsis,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
            height: 1.45,
          ),
        ),
      ],
    ];
  }

  /// Cast and crew with photo, name and role. A person opens their page,
  /// except for kids profiles (no editorial discovery).
  List<Widget> _people(
    BuildContext context,
    ContentMetadata? meta,
    HomeData? home,
  ) {
    if (meta == null) return const [];
    final discover = home?.profile?.canDiscover ?? true;
    // Actors only; direction is shown before the synopsis.
    if (meta.cast.isEmpty) return const [];
    return [
      const SizedBox(height: AppSpacing.md),
      Semantics(header: true, child: SectionHeader(context.l.castLabel)),
      PeopleRow(
        people: meta.cast,
        onTap: discover ? (id) => openPerson(context, id) : null,
      ),
    ];
  }

  /// Series: TMDB seasons (editorial) apart from the episodes the IPTV source
  /// really offers (the only ones sent to the TV).
  /// Series: one Web-style button per season. Seasons come from the IPTV
  /// source when it offers the series (only those episodes are playable);
  /// otherwise from TMDB, for information.
  List<Widget> _seasons(
    BuildContext context,
    Entry shown,
    ContentMetadata? meta,
  ) {
    if (shown.kind != 'series') return const [];
    final target = playable;
    final numbers = target != null && episodes.isNotEmpty
        ? ({for (final e in episodes) e.season}.toList()..sort())
        : [
            for (final s in meta?.seasons ?? const <SeasonInfo>[])
              if (s.number > 0) s.number,
          ];
    if (numbers.isEmpty) return const [];
    return [
      const SizedBox(height: AppSpacing.md),
      Semantics(header: true, child: SectionHeader(context.l.seasonsTitle)),
      Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final n in numbers)
            DetailsButton(
              key: ValueKey('details-season-$n'),
              label: context.l.seasonNumber(n),
              onPressed: () => _openSeason(n, target, shown, meta),
            ),
        ],
      ),
    ];
  }

  /// Season sheet; choosing an available episode opens "Assistir na TV".
  Future<void> _openSeason(
    int number,
    Entry? target,
    Entry shown,
    ContentMetadata? meta,
  ) async {
    final picked = await showSeasonSheet(
      context,
      series: target ?? shown,
      season: number,
      available: target == null ? const [] : episodes,
      tmdbId: meta?.tmdbId ?? shown.tmdbId,
    );
    if (picked != null && target != null && mounted) {
      watchOnTv(target, episodeId: picked.id);
    }
  }

  List<Widget> _guide(BuildContext context) => [
    if (guide != null)
      FutureBuilder<List<_Programme>>(
        future: guide,
        builder: (context, snapshot) {
          final l = context.l;
          final rows = snapshot.data ?? const <_Programme>[];
          if (rows.isEmpty) return const SizedBox.shrink();
          final local = MaterialLocalizations.of(context);
          String time(DateTime t) =>
              local.formatTimeOfDay(TimeOfDay.fromDateTime(t));
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (index, p) in rows.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      '${index == 0 && !p.start.isAfter(DateTime.now()) ? l.onAirNow : l.upNext} · ${time(p.start)}–${time(p.end)} · ${p.title}',
                      style: AppTypography.bodyMedium.copyWith(
                        color: index == 0
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
  ];
}

/// Horizontal list of people (avatar, name, role). Tappable when [onTap].
class PeopleRow extends StatelessWidget {
  const PeopleRow({super.key, required this.people, this.onTap});
  final List<Credit> people;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) => PortraitRow(
    children: [
      for (final person in people)
        PortraitCard(
          key: ValueKey('person-${person.id ?? person.name}'),
          image: _PersonPhoto(person: person),
          title: person.name,
          subtitle: person.role,
          onTap: person.id != null && onTap != null
              ? () => onTap!(person.id!)
              : null,
        ),
    ],
  );
}

/// Horizontal list of [PortraitCard]s (cast on the title page, filmography on
/// the person page).
class PortraitRow extends StatelessWidget {
  const PortraitRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
    // Image + gap + two title lines and one subtitle line, following the
    // system text size (no overflow with larger fonts).
    height:
        PortraitCard.height +
        AppSpacing.sm +
        MediaQuery.textScalerOf(context).scale(52),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      clipBehavior: Clip.none,
      itemCount: children.length,
      separatorBuilder: (context, index) =>
          const SizedBox(width: AppSpacing.md),
      itemBuilder: (context, index) => children[index],
    ),
  );
}

/// Portrait card: 3:4 image with rounded corners, name below and a secondary
/// line (role, character).
class PortraitCard extends StatelessWidget {
  const PortraitCard({
    super.key,
    required this.image,
    required this.title,
    this.subtitle = '',
    this.onTap,
  });
  final Widget image;
  final String title, subtitle;
  final VoidCallback? onTap;

  static const width = 96.0, height = width * 4 / 3;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: [title, subtitle].where((s) => s.isNotEmpty).join(', '),
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: SizedBox(width: width, height: height, child: image),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                fontSize: 13,
                height: 1.25,
                color: AppColors.textPrimary,
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Actor photo (TMDB) or the person's initials on the recessed surface.
class _PersonPhoto extends StatelessWidget {
  const _PersonPhoto({required this.person});
  final Credit person;

  Widget _initials() => ColoredBox(
    color: AppColors.surfaceRecessed,
    child: Center(
      child: Text(
        person.name
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w.characters.first.toUpperCase())
            .join(),
        style: AppTypography.titleLarge.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final url = tmdbSized(person.photo, 'h632');
    if (url == null) return _initials();
    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stack) => _initials(),
    );
  }
}

class _Programme {
  const _Programme(this.title, this.start, this.end);
  final String title;
  final DateTime start, end;
}
