import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import '../manager/iptv_source_status.dart';
import '../manager/widgets/home_welcome_state.dart';
import 'content_details_sheet.dart';
import 'home_data.dart';
import 'home_providers.dart';
import 'home_widgets.dart';

/// Home ("Meu iPlex" of the Control): search over the authorized catalog of
/// the selected IPTV source, the profile's own rows (favorites, continue
/// watching, my list — aggregated over all sources) and the recently added
/// titles of the selected source. Rows only appear when they have content.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final search = TextEditingController();
  final searchFocus = FocusNode();
  Timer? debounce;
  String query = '';
  int generation = 0;
  List<Entry> results = [];
  Object? cursor, searchError;
  bool searching = false, more = false;

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  Future<void> runSearch(Entry source, {bool reset = true}) async {
    final fid = ref.read(accountProvider).asData?.value?.iptvScopeId;
    if (fid == null || query.trim().isEmpty) return;
    final request = ++generation;
    setState(() {
      searching = true;
      searchError = null;
      if (reset) {
        results = [];
        cursor = null;
        more = false;
      }
    });
    try {
      final page = await ref
          .read(repositoryProvider)
          .catalog(fid, source, query.trim(), cursor: cursor)
          .timeout(const Duration(seconds: 30));
      if (!mounted || request != generation) return;
      setState(() {
        results = {
          for (final item in [...results, ...page.items]) item.id: item,
        }.values.toList();
        cursor = page.cursor;
        more = page.hasMore;
      });
    } catch (e) {
      if (mounted && request == generation) setState(() => searchError = e);
    } finally {
      if (mounted && request == generation) setState(() => searching = false);
    }
  }

  void onQuery(String value, Entry? source) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => query = value);
      if (source != null) runSearch(source);
    });
  }

  void clearSearch() {
    debounce?.cancel();
    generation++;
    search.clear();
    setState(() {
      query = '';
      results = [];
      searchError = null;
      searching = false;
    });
  }

  /// Opens the details of [item]; when the same title has saved progress (from
  /// any row or the search), that entry is used so "continue" is offered.
  void open(Entry item, HomeData? home, String? sourceId) {
    final withProgress = item.progress != null
        ? item
        : home?.continueWatching.where((c) => c.id == item.id).firstOrNull ??
              item;
    showContentDetails(
      context,
      item: withProgress,
      profile: home?.profile,
      favorite: home?.isFavorite(item) ?? false,
      onLibraryChanged: () => ref.invalidate(homeProvider(sourceId)),
    );
  }

  Future<void> pickSource(List<Entry> sources, String? current) async {
    final picked = await showAppModalSheet<String>(
      context: context,
      builder: (c) => _SourcePicker(sources: sources, current: current),
    );
    if (picked == null || picked == current) return;
    await ref.read(selectedSourceProvider.notifier).select(picked);
    if (query.trim().isNotEmpty) {
      final source = sources.where((s) => s.id == picked).firstOrNull;
      if (source != null) runSearch(source);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(accountProvider.select((a) => a.asData?.value?.iptvScopeId), (
      previous,
      next,
    ) {
      if (previous != next) clearSearch();
    });
    final account = ref.watch(accountProvider);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppDimensions.maxWidth),
          child: account.when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const _Padded(child: AppLoadingSkeleton()),
            error: (e, stack) => _Padded(
              child: ErrorState(onRetry: () => ref.invalidate(accountProvider)),
            ),
            data: (account) {
              if (account?.iptvScopeId == null) {
                return const _Padded(child: HomeWelcomeState());
              }
              final sources = ref.watch(entriesProvider('sources'));
              return sources.when(
                loading: () => const _Padded(child: AppLoadingSkeleton()),
                error: (e, stack) => _Padded(
                  child: ErrorState(
                    onRetry: () => ref.invalidate(entriesProvider('sources')),
                  ),
                ),
                data: (sources) => _content(context, sources),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, List<Entry> sources) {
    final ready = readySources(sources, ref.watch(unlockedSourcesProvider));
    final sourceId = effectiveSourceId(
      ref.watch(selectedSourceProvider),
      ready,
    );
    final source = ready.where((s) => s.id == sourceId).firstOrNull;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              focusNode: searchFocus,
              skipTraversal: true,
              child: NeumorphicSearchField(
                key: const Key('home-search'),
                controller: search,
                hintText: context.l.homeSearchHint,
                onChanged: (value) => onQuery(value, source),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          CircularButton(
            key: const Key('home-source-picker'),
            label: context.l.selectIptvSource,
            icon: AppIcons.iptv,
            size: AppDimensions.touch,
            onPressed: sources.isEmpty
                ? null
                : () => pickSource(sources, sourceId),
          ),
        ],
      ),
    );
    if (ready.isEmpty) {
      return ListView(
        children: [
          header,
          _Padded(child: _noReadySource(context, sources)),
        ],
      );
    }
    final home = ref.watch(homeProvider(sourceId));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(homeProvider(sourceId));
        await ref
            .read(homeProvider(sourceId).future)
            .catchError((_) => const HomeData());
      },
      child: CustomScrollView(
        key: const PageStorageKey('home-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: header),
          if (source != null && source.text('status') == 'error')
            SliverToBoxAdapter(
              child: _Padded(
                child: Text(
                  context.l.sourceError,
                  style: const TextStyle(color: AppColors.warning),
                ),
              ),
            ),
          if (query.trim().isNotEmpty)
            ..._searchSlivers(context, source, home.asData?.value, sourceId)
          else
            ..._homeSlivers(context, home, sourceId),
          const SliverToBoxAdapter(
            child: SizedBox(height: AppDimensions.bottomNav + AppSpacing.xl),
          ),
        ],
      ),
    );
  }

  List<Widget> _homeSlivers(
    BuildContext context,
    AsyncValue<HomeData> home,
    String? sourceId,
  ) {
    final l = context.l;
    return home.when(
      skipLoadingOnRefresh: true,
      loading: () => [
        const SliverToBoxAdapter(
          child: _Padded(child: AppLoadingSkeleton(rows: 4)),
        ),
      ],
      error: (e, stack) => [
        SliverToBoxAdapter(
          child: _Padded(
            child: ErrorState(
              onRetry: () => ref.invalidate(homeProvider(sourceId)),
            ),
          ),
        ),
      ],
      data: (data) {
        void tap(Entry item) => open(item, data, sourceId);
        final rows = [
          (l.homeFavorites, data.favorites),
          (l.homeContinueWatching, data.continueWatching),
          (l.homeMyList, data.myList),
          (l.homeRecentMovies, data.recentMovies),
          (l.homeRecentSeries, data.recentSeries),
        ].where((row) => row.$2.isNotEmpty);
        if (rows.isEmpty) {
          return [
            SliverToBoxAdapter(
              child: _Padded(
                child: EmptyState(
                  title: l.homeEmptyTitle,
                  body: l.homeEmptyBody,
                  icon: AppIcons.search,
                  action: AppButton(
                    label: l.exploreCatalog,
                    onPressed: searchFocus.requestFocus,
                  ),
                ),
              ),
            ),
          ];
        }
        return [
          for (final row in rows)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.lg),
                child: HomeRow(title: row.$1, items: row.$2, onTap: tap),
              ),
            ),
        ];
      },
    );
  }

  List<Widget> _searchSlivers(
    BuildContext context,
    Entry? source,
    HomeData? home,
    String? sourceId,
  ) {
    final l = context.l;
    if (searchError != null) {
      return [
        SliverToBoxAdapter(
          child: _Padded(
            child: ErrorState(
              onRetry: () {
                if (source != null) runSearch(source);
              },
            ),
          ),
        ),
      ];
    }
    if (searching && results.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: _Padded(child: AppLoadingSkeleton(rows: 3)),
        ),
      ];
    }
    if (results.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _Padded(
            child: EmptyState(
              title: l.noResults,
              body: l.noResultsBody,
              icon: AppIcons.search,
              action: AppButton(label: l.clearSearch, onPressed: clearSearch),
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: HomeCardSize.posterWidth + AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio:
                HomeCardSize.posterWidth /
                (HomeCardSize.posterHeight +
                    HomeCardSize.caption +
                    AppSpacing.sm),
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _SearchCard(
              item: results[index],
              onTap: () => open(results[index], home, sourceId),
            ),
            childCount: results.length,
          ),
        ),
      ),
      if (searching)
        const SliverToBoxAdapter(
          child: _Padded(child: AppLoadingSkeleton(rows: 1)),
        )
      else if (more && source != null)
        SliverToBoxAdapter(
          child: _Padded(
            child: AppButton(
              label: l.more,
              onPressed: () => runSearch(source, reset: false),
            ),
          ),
        ),
    ];
  }

  Widget _noReadySource(BuildContext context, List<Entry> sources) {
    final l = context.l;
    if (sources.isEmpty) return const HomeWelcomeState();
    final failed = sources.every((entry) => entry.text('status') == 'error');
    return EmptyState(
      title: failed ? l.catalogSyncFailed : l.sourceQueued,
      body: failed ? l.sourceError : l.catalogPreparing,
      action: Column(
        children: [
          AppButton(label: l.iptv, onPressed: () => context.go('/iptv')),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: l.retry,
            onPressed: () => ref.invalidate(entriesProvider('sources')),
          ),
        ],
      ),
    );
  }
}

/// Search results mix channels and titles: same poster footprint for a tidy grid.
class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.item, required this.onTap});
  final Entry item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: item.name,
    excludeSemantics: true,
    child: GestureDetector(
      key: ValueKey('search-card-${item.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: HomeCardSize.posterWidth / HomeCardSize.posterHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Artwork(
                item: item,
                fit: item.isChannel ? BoxFit.contain : BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              fontSize: 13,
              height: 1.25,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Bottom sheet: every registered source with its sync state; only sources
/// with a published catalog can be selected. Names and states only — never
/// URLs, hosts or credentials.
class _SourcePicker extends ConsumerWidget {
  const _SourcePicker({required this.sources, required this.current});
  final List<Entry> sources;
  final String? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final ready = readySources(
      sources,
      ref.watch(unlockedSourcesProvider),
    ).map((s) => s.id).toSet();
    return AppModalSheet(
      title: l.iptvSources,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final source in sources)
            EntryTile(
              key: ValueKey('source-option-${source.id}'),
              title: source.name,
              subtitle: source.id == current
                  ? '${l.selectedSource} · ${iptvSourceStatus(context, source)}'
                  : iptvSourceStatus(context, source),
              icon: source.id == current ? AppIcons.check : AppIcons.iptv,
              onTap: ready.contains(source.id)
                  ? () => Navigator.pop(context, source.id)
                  : null,
            ),
        ],
      ),
    );
  }
}

class _Padded extends StatelessWidget {
  const _Padded({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    child: child,
  );
}
