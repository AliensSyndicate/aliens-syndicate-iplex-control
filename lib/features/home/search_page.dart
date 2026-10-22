import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import 'browse_widgets.dart';
import 'content_details_page.dart';
import 'home_data.dart';
import 'home_providers.dart';
import 'home_widgets.dart';
import 'library.dart';
import 'metadata_service.dart';

enum SearchFilter { all, channel, movie, series, actor }

/// Busca (menu): the existing catalog search of the selected IPTV source
/// (titles and channels) plus actors from TMDB; recent searches when empty.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final controller = TextEditingController();
  Timer? debounce;
  String query = '';
  SearchFilter filter = SearchFilter.all;
  int generation = 0;
  bool loading = false;
  Object? error;
  List<Entry> titles = const [];
  List<PersonResult> people = const [];
  bool peopleUnavailable = false;

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  Entry? _source() {
    final sources = ref.read(entriesProvider('sources')).asData?.value;
    if (sources == null) return null;
    final ready = readySources(sources, ref.read(unlockedSourcesProvider));
    final id = effectiveSourceId(ref.read(selectedSourceProvider), ready);
    return ready.where((s) => s.id == id).firstOrNull;
  }

  void onChanged(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => query = value.trim());
      run();
    });
  }

  Future<void> run() async {
    final request = ++generation;
    if (query.isEmpty) {
      setState(() {
        titles = const [];
        people = const [];
        error = null;
        loading = false;
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    final fid = ref.read(accountProvider).asData?.value?.iptvScopeId;
    final source = _source();
    final wantTitles = filter != SearchFilter.actor;
    final wantPeople =
        (filter == SearchFilter.all || filter == SearchFilter.actor) &&
        query.length >= 2;
    try {
      final results = await Future.wait([
        wantTitles && fid != null && source != null
            ? ref
                  .read(repositoryProvider)
                  .catalog(fid, source, query)
                  .timeout(const Duration(seconds: 30))
                  .then((p) => p.items)
            : Future.value(const <Entry>[]),
        wantPeople
            ? ref
                  .read(metadataServiceProvider)
                  .searchPeople(query)
                  .then<List<PersonResult>?>((r) => r)
                  .catchError((Object _) => null)
            : Future.value(const <PersonResult>[]),
      ]);
      if (!mounted || request != generation) return;
      setState(() {
        titles = results[0] as List<Entry>;
        final found = results[1] as List<PersonResult>?;
        people = found ?? const [];
        peopleUnavailable = found == null;
      });
    } catch (e) {
      if (mounted && request == generation) setState(() => error = e);
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  List<Entry> get _shownTitles => switch (filter) {
    SearchFilter.all => titles,
    SearchFilter.actor => const [],
    SearchFilter.channel => [
      for (final t in titles)
        if (t.kind == 'channel') t,
    ],
    SearchFilter.movie => [
      for (final t in titles)
        if (t.kind == 'movie') t,
    ],
    SearchFilter.series => [
      for (final t in titles)
        if (t.kind == 'series') t,
    ],
  };

  void openItem(Entry item, HomeData? home) {
    if (home?.profile?.type != 'guest') {
      unawaited(ref.read(recentSearchProvider.notifier).record(item.id));
    }
    openTitle(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final home = ref.watch(currentHomeProvider).asData?.value;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppDimensions.maxWidth),
          child: ListView(
            key: const Key('search-page'),
            padding: const EdgeInsets.fromLTRB(
              0,
              AppSpacing.md,
              0,
              AppDimensions.bottomNav + AppSpacing.xl,
            ),
            children: EdgeToEdge.padded([
              Text(l.searchTitle, style: AppTypography.headlineMedium),
              const SizedBox(height: AppSpacing.md),
              NeumorphicSearchField(
                key: const Key('search-field'),
                controller: controller,
                hintText: l.searchPageHint,
                onChanged: onChanged,
              ),
              const SizedBox(height: AppSpacing.md),
              EdgeToEdge(
                child: AppTabs<SearchFilter>(
                  padding: EdgeToEdge.inset,
                  options: [
                    (SearchFilter.all, l.filterAll),
                    (SearchFilter.channel, l.filterChannels),
                    (SearchFilter.movie, l.filterMovies),
                    (SearchFilter.series, l.filterSeries),
                    (SearchFilter.actor, l.filterActors),
                  ],
                  selected: filter,
                  onSelected: (f) {
                    final needsPeople =
                        (f == SearchFilter.actor || f == SearchFilter.all) &&
                        people.isEmpty;
                    final needsTitles =
                        f != SearchFilter.actor && titles.isEmpty;
                    setState(() => filter = f);
                    if (query.isNotEmpty && (needsPeople || needsTitles)) run();
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ..._body(context, home),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, HomeData? home) {
    final l = context.l;
    if (query.isEmpty) {
      final recent = home?.recentSearches ?? const <Entry>[];
      if (recent.isEmpty) return const [];
      return [
        Text(l.recentSearchesTitle, style: AppTypography.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        for (final item in recent) _titleRow(context, item, home),
      ];
    }
    if (error != null) return [ErrorState(onRetry: run)];
    if (loading && titles.isEmpty && people.isEmpty) {
      return const [AppLoadingSkeleton(rows: 3)];
    }
    final shownTitles = _shownTitles;
    final showPeople =
        filter == SearchFilter.all || filter == SearchFilter.actor;
    if (shownTitles.isEmpty && (!showPeople || people.isEmpty)) {
      return [
        EmptyState(
          title: l.noResults,
          body: filter == SearchFilter.actor && peopleUnavailable
              ? l.discoveryNotAllowed
              : l.noResultsBody,
          icon: AppIcons.search,
        ),
      ];
    }
    return [
      if (showPeople)
        for (final p in people)
          // Reference: "Card de ator".
          MediaListRow(
            key: ValueKey('search-person-${p.tmdbId}'),
            image: PhotoOrInitials(name: p.name, url: p.photo),
            title: p.name,
            subtitle: switch (p.knownFor) {
              'Directing' => l.deptDirecting,
              'Writing' => l.deptWriting,
              'Production' => l.deptProduction,
              _ => l.actorKind,
            },
            onTap: () => openPerson(context, p.tmdbId),
            trailing: const AppIcon(
              AppIcons.right,
              size: AppDimensions.iconSmall,
              color: AppColors.textSecondary,
            ),
          ),
      for (final item in shownTitles) _titleRow(context, item, home),
    ];
  }

  Widget _titleRow(BuildContext context, Entry item, HomeData? home) {
    final l = context.l;
    final kind = switch (item.kind) {
      'channel' => l.channelKind,
      'series' => l.seriesKind,
      _ => l.movieKind,
    };
    return MediaListRow(
      key: ValueKey('search-card-${item.id}'),
      image: Artwork(
        item: item,
        fit: item.isChannel ? BoxFit.contain : BoxFit.cover,
      ),
      title: item.name,
      subtitle: [kind, if (item.year case final y?) '$y'].join(' · '),
      onTap: () => openItem(item, home),
    );
  }
}
