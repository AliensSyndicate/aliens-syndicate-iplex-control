import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import '../player/mobile_player_page.dart';
import '../watch_on_tv/watch_on_tv_sheet.dart';
import 'details_layout.dart';
import 'home_data.dart';
import 'home_providers.dart';
import 'home_widgets.dart';
import 'library.dart';
import 'metadata_service.dart';
import 'browse_widgets.dart';
import 'season_episodes.dart';
import '../../core/data/app_sharing.dart';

/// Opens the full details page of [item] on top of the current page (Home →
/// title → person → title …); Back returns through the same stack. Adult
/// content never has a details page (as on the TV): a movie or channel goes
/// straight to "Assistir na TV" and a series to its episodes.
void openTitle(BuildContext context, Entry item) {
  if (!item.isEditorial && isAdultEntry(item)) {
    if (item.kind == 'series') {
      context.push('/home/adult-series', extra: item);
    } else {
      showWatchOnTv(context, item);
    }
    return;
  }
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

  /// Series tab (Temporadas / Sobre / Elenco).
  int seriesTab = 0;

  /// Season shown in the Temporadas tab.
  int? season;

  Widget _layout(
    BuildContext context,
    BoxConstraints box,
    Entry shown,
    ContentMetadata? meta,
    bool loading,
    HomeData? home,
  ) {
    final channel = shown.isChannel;
    final series = shown.kind == 'series';
    return DetailsLayout(
      height: box.maxHeight,
      actions: _headerActions(context, shown, meta, home),
      coverFraction: channel ? 0.45 : 0.6,
      contentStart: channel ? 0.32 : 0.42,
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
      children: [
        ..._summary(context, shown, meta),
        const SizedBox(height: AppSpacing.lg),
        _actions(context, shown, home),
        ..._availability(context, shown),
        if (series) ...[
          const SizedBox(height: AppSpacing.lg),
          EdgeToEdge(
            child: AppTabs<int>(
              key: const Key('series-tabs'),
              padding: EdgeToEdge.inset,
              options: [
                (0, context.l.seasonsTab),
                (1, context.l.aboutTab),
                (2, context.l.castTab),
              ],
              selected: seriesTab,
              onSelected: (i) => setState(() => seriesTab = i),
            ),
          ),
          if (seriesTab == 0) ..._seasons(context, shown, meta),
          if (seriesTab == 1) ...[
            ..._synopsis(shown, meta),
            ..._information(context, shown, meta),
          ],
          if (seriesTab == 2) ..._people(context, meta, home),
        ] else ...[
          ..._synopsis(shown, meta),
          ..._people(context, meta, home),
          ..._information(context, shown, meta),
        ],
        ..._guide(context),
        ..._recommendations(context, meta),
      ],
    );
  }

  /// Title, original title and "2024  2h 46min  [14]  Gênero · Gênero".
  List<Widget> _summary(
    BuildContext context,
    Entry shown,
    ContentMetadata? meta,
  ) {
    final l = context.l;
    final channel = shown.isChannel;
    final year = meta?.year ?? shown.year;
    final genres = meta?.genres ?? const <String>[];
    final category = editorial ? '' : shown.text('category');
    final minutes = meta?.runtimeMinutes;
    final seasons = _seasonCount(meta);
    final seal = AgeRatingBadge.normalize(_rawAgeRating(shown, meta));
    final original = meta?.originalTitle;
    final secondary = AppTypography.bodyMedium.copyWith(
      color: AppColors.textSecondary,
    );
    final facts = <InlineSpan>[
      if (channel) TextSpan(text: l.liveChannel),
      if (!channel && year != null) TextSpan(text: '$year'),
      if (minutes != null && shown.kind == 'movie')
        TextSpan(text: formatRuntime(context, minutes)),
      if (shown.kind == 'series' && seasons > 0)
        TextSpan(text: l.seasonsCount(seasons)),
      if (seal != null)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Semantics(
            label: l.ageRatingLabel(seal),
            child: AgeRatingBadge(seal, size: 20),
          ),
        ),
      if (genres.isNotEmpty)
        TextSpan(text: genres.take(2).join(' · '))
      else if (category.isNotEmpty)
        TextSpan(text: category),
    ];
    return [
      Text(
        shown.name,
        key: const Key('details-title'),
        style: AppTypography.headlineMedium.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      if (original != null &&
          original.toLowerCase() != shown.name.toLowerCase()) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(original, style: secondary),
      ],
      if (facts.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        Text.rich(
          key: const Key('details-facts'),
          TextSpan(
            children: [
              for (final (i, span) in facts.indexed) ...[
                if (i > 0) const TextSpan(text: '   '),
                span,
              ],
            ],
          ),
          style: secondary,
        ),
      ],
      ..._ageRating(context, shown, meta),
    ];
  }

  /// Playback fills the content width; resume and restart share it equally.
  Widget _actions(BuildContext context, Entry shown, HomeData? home) {
    final l = context.l;
    final target = _withProgress(home);
    final resume = target?.progress != null && !shown.isChannel;
    final episode = _episode(target);
    const actionHeight = 44.0;
    return Column(
      key: const Key('details-actions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // On this phone (landscape player), and the restart beside it.
        Row(
          children: [
            Expanded(
              child: AppButton.primary(
                key: Key(resume ? 'details-continue' : 'details-play'),
                height: actionHeight,
                icon: AppIcons.play,
                label: resume ? l.continueLabel : l.playHere,
                onPressed: target == null
                    ? null
                    : () => openMobilePlayer(
                        context,
                        target,
                        episodeId: resume ? target.episodeId : episode?.id,
                        resume: resume,
                      ),
              ),
            ),
            if (resume && target != null) ...[
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                key: const Key('details-restart'),
                height: actionHeight,
                width: actionHeight,
                semanticsLabel: l.restartLabel,
                icon: AppIcons.refresh,
                onPressed: () => openMobilePlayer(
                  context,
                  target,
                  episodeId: target.episodeId ?? episode?.id,
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.sm),
            // On a linked TV (continues from the same point when resuming).
            AppButton(
              key: const Key('details-watch-on-tv'),
              height: actionHeight,
              width: actionHeight,
              semanticsLabel: l.watchOnTv,
              icon: AppIcons.devices,
              onPressed: target == null
                  ? null
                  : () => watchOnTv(target, resume: resume),
            ),
          ],
        ),
      ],
    );
  }

  Widget _headerActions(
    BuildContext context,
    Entry shown,
    ContentMetadata? meta,
    HomeData? home,
  ) {
    final target = _withProgress(home);
    final profile = home?.profile;
    return Row(
      key: const Key('details-header-actions'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (profile != null && profile.persistent)
          LibraryButtons(
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
          ),
        CircularButton(
          key: const Key('details-share'),
          onPad: true,
          label: context.l.share,
          child: const Icon(
            Icons.ios_share_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () => _share(context, shown, meta),
        ),
      ],
    );
  }

  /// Native share sheet with the title (never a fabricated store link).
  Future<void> _share(
    BuildContext context,
    Entry shown,
    ContentMetadata? meta,
  ) async {
    final year = meta?.year ?? shown.year;
    final title = year == null ? shown.name : '${shown.name} ($year)';
    try {
      await AppSharing.share(AppSharing.message(title, title));
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  /// Discreet note when the title cannot be sent to a TV.
  List<Widget> _availability(BuildContext context, Entry shown) => [
    if (playable == null && !resolving) ...[
      const SizedBox(height: AppSpacing.md),
      Text(
        context.l.notAvailableToWatch,
        key: const Key('details-unavailable'),
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    ],
  ];

  String? _rawAgeRating(Entry shown, ContentMetadata? meta) =>
      meta?.certification ??
      (shown.text('ageRating').isEmpty ? null : shown.text('ageRating'));

  /// Reasons of the age rating, under the facts line that carries the seal.
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

  /// Whole synopsis (TMDB first, then the source's plot).
  List<Widget> _synopsis(Entry shown, ContentMetadata? meta) {
    final synopsis = (meta?.overview.isNotEmpty ?? false)
        ? meta!.overview
        : shown.text('plot');
    if (synopsis.isEmpty) return const [];
    return [
      const SizedBox(height: AppSpacing.lg),
      Text(
        synopsis,
        key: const Key('details-synopsis'),
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.textPrimary,
          height: 1.45,
        ),
      ),
    ];
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    ),
  );

  /// Informações: label / value rows (only what is known).
  List<Widget> _information(
    BuildContext context,
    Entry shown,
    ContentMetadata? meta,
  ) {
    final l = context.l;
    final seal = AgeRatingBadge.normalize(_rawAgeRating(shown, meta));
    final rawAge = _rawAgeRating(shown, meta);
    final directors = [for (final p in meta?.crew ?? const <Credit>[]) p.name];
    final genres = meta?.genres ?? const <String>[];
    final year = meta?.year ?? shown.year;
    final rows = <(String, Widget)>[
      if (meta?.originalTitle case final original?)
        (l.originalTitleRow, _value(original)),
      if (directors.isNotEmpty)
        (
          shown.kind == 'series'
              ? l.createdByLabel('').replaceAll(':', '').trim()
              : l.directionLabel,
          _value(directors.join(', ')),
        ),
      if (genres.isNotEmpty) (l.genresLabel, _value(genres.join(', '))),
      if (seal != null)
        (
          l.ageRatingRowLabel,
          Row(
            children: [
              AgeRatingBadge(seal, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: _value(seal == 'L' ? 'Livre' : '$seal+')),
            ],
          ),
        )
      else if (rawAge != null)
        (l.ageRatingRowLabel, _value(rawAge)),
      if (meta?.runtimeMinutes case final minutes?)
        (l.runtimeLabel, _value(formatRuntime(context, minutes))),
      if (meta?.releaseDate case final date?)
        (l.releaseYearLabel, _value(formatDate(context, date)))
      else if (year != null)
        (l.releaseYearLabel, _value('$year')),
      if (meta?.rating case final rating?)
        (
          l.ratingRowLabel,
          Row(
            children: [
              const Icon(
                Icons.star_rounded,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.xs),
              _value('${rating.toStringAsFixed(1)} (TMDB)'),
            ],
          ),
        ),
    ];
    if (rows.isEmpty) return const [];
    return [
      _sectionTitle(l.infoTitle),
      for (final (label, value) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 132,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Expanded(child: value),
            ],
          ),
        ),
    ];
  }

  Widget _value(String text) => Text(
    text,
    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
  );

  /// Elenco: round photos with name and character. A person opens their page,
  /// except for kids profiles (no editorial discovery).
  List<Widget> _people(
    BuildContext context,
    ContentMetadata? meta,
    HomeData? home,
  ) {
    if (meta == null || meta.cast.isEmpty) return const [];
    final discover = home?.profile?.canDiscover ?? true;
    return [
      _sectionTitle(context.l.castLabel),
      EdgeToEdge(
        child: PeopleRow(
          people: meta.cast,
          onTap: discover ? (id) => openPerson(context, id) : null,
        ),
      ),
    ];
  }

  /// Temporadas: season selector and its episodes (TMDB names, synopsis and
  /// runtime). Only the episodes the IPTV source offers can be sent to a TV.
  List<Widget> _seasons(
    BuildContext context,
    Entry shown,
    ContentMetadata? meta,
  ) {
    final target = playable;
    final numbers = target != null && episodes.isNotEmpty
        ? ({for (final e in episodes) e.season}.toList()..sort())
        : [
            for (final s in meta?.seasons ?? const <SeasonInfo>[])
              if (s.number > 0) s.number,
          ];
    if (numbers.isEmpty) return const [];
    final current = numbers.contains(season) ? season! : numbers.first;
    return [
      const SizedBox(height: AppSpacing.md),
      _SeasonPicker(
        seasons: numbers,
        selected: current,
        onSelected: (n) => setState(() => season = n),
      ),
      const SizedBox(height: AppSpacing.sm),
      SeasonEpisodes(
        key: ValueKey('season-$current'),
        series: target ?? shown,
        season: current,
        available: target == null ? const [] : episodes,
        tmdbId: meta?.tmdbId ?? shown.tmdbId,
        onPlay: target == null
            ? null
            : (e) => watchOnTv(target, episodeId: e.id),
      ),
    ];
  }

  /// "Você também pode gostar": TMDB recommendations, each opens its page.
  List<Widget> _recommendations(BuildContext context, ContentMetadata? meta) {
    final items = meta?.recommendations ?? const <Entry>[];
    if (items.isEmpty) return const [];
    return [
      _sectionTitle(context.l.youMayLike),
      EdgeToEdge(
        child: SizedBox(
          height:
              HomeCardSize.posterHeight + HomeCardSize.caption + AppSpacing.sm,
          child: ListView.separated(
            key: const Key('details-recommendations'),
            padding: EdgeToEdge.inset,
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) => HomeCard(
              item: items[index],
              onTap: () => openTitle(context, items[index]),
            ),
          ),
        ),
      ),
    ];
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

  static const _size = 80.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _size + AppSpacing.sm + MediaQuery.textScalerOf(context).scale(52),
    child: ListView.separated(
      padding: EdgeToEdge.inset,
      scrollDirection: Axis.horizontal,
      itemCount: people.length,
      separatorBuilder: (context, index) =>
          const SizedBox(width: AppSpacing.md),
      itemBuilder: (context, index) {
        final person = people[index];
        final tap = person.id != null && onTap != null
            ? () => onTap!(person.id!)
            : null;
        return Semantics(
          button: tap != null,
          label: [
            person.name,
            person.role,
          ].where((s) => s.isNotEmpty).join(', '),
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('person-${person.id ?? person.name}'),
            behavior: HitTestBehavior.opaque,
            onTap: tap,
            child: SizedBox(
              width: _size + AppSpacing.sm,
              child: Column(
                children: [
                  ClipOval(
                    child: SizedBox.square(
                      dimension: _size,
                      child: PhotoOrInitials(
                        name: person.name,
                        url: tmdbSized(person.photo, 'w185'),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    person.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.25,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (person.role.isNotEmpty)
                    Text(
                      person.role,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Season selector (pill): opens the list of seasons.
class _SeasonPicker extends StatelessWidget {
  const _SeasonPicker({
    required this.seasons,
    required this.selected,
    required this.onSelected,
  });
  final List<int> seasons;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return InkWell(
      key: const Key('season-picker'),
      borderRadius: BorderRadius.circular(AppRadii.sm),
      onTap: seasons.length < 2
          ? null
          : () async {
              final picked = await showAppModalSheet<int>(
                context: context,
                builder: (sheet) => AppModalSheet(
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SheetHeader(icon: AppIcons.series, title: l.seasonsTab),
                      for (final n in seasons)
                        SelectionRow(
                          key: ValueKey('season-option-$n'),
                          title: l.seasonNumber(n),
                          selected: n == selected,
                          onTap: () => Navigator.of(sheet).pop(n),
                        ),
                    ],
                  ),
                ),
              );
              if (picked != null) onSelected(picked);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l.seasonNumber(selected),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (seasons.length > 1) const AppIcon(AppIcons.down, size: 18),
          ],
        ),
      ),
    );
  }
}

class _Programme {
  const _Programme(this.title, this.start, this.end);
  final String title;
  final DateTime start, end;
}

/// Episodes of an adult series (as on the TV): the source's own seasons and
/// names, no TMDB, nothing saved; an episode opens "Assistir na TV".
class AdultSeriesPage extends ConsumerStatefulWidget {
  const AdultSeriesPage({super.key, required this.series});
  final Entry series;

  @override
  ConsumerState<AdultSeriesPage> createState() => _AdultSeriesPageState();
}

class _AdultSeriesPageState extends ConsumerState<AdultSeriesPage> {
  late Future<List<TvEpisode>> episodes = _load();
  int? season;

  Future<List<TvEpisode>> _load() async {
    final result = await ref.read(repositoryProvider).mutate(
      'readSourceSeries',
      {
        'id': widget.series.sourceId,
        'seriesId': widget.series.text('providerRef'),
      },
    );
    return parseEpisodes(result['details']);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      body: PageTemplate(
        title: widget.series.name,
        showBack: true,
        child: FutureBuilder<List<TvEpisode>>(
          future: episodes,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorState(
                onRetry: () => setState(() => episodes = _load()),
              );
            }
            final list = snapshot.data;
            if (list == null) return const AppLoadingSkeleton();
            if (list.isEmpty) {
              return EmptyState(
                title: l.noResults,
                body: l.noResultsBody,
                icon: AppIcons.search,
              );
            }
            final numbers = {for (final e in list) e.season}.toList()..sort();
            final current = numbers.contains(season) ? season! : numbers.first;
            return Column(
              key: const Key('adult-series'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SeasonPicker(
                  seasons: numbers,
                  selected: current,
                  onSelected: (n) => setState(() => season = n),
                ),
                const SizedBox(height: AppSpacing.sm),
                SeasonEpisodes(
                  key: ValueKey('adult-season-$current'),
                  series: widget.series,
                  season: current,
                  available: list,
                  onPlay: (e) =>
                      showWatchOnTv(context, widget.series, episodeId: e.id),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
