import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import '../manager/widgets/home_welcome_state.dart';
import '../manager/widgets/account_avatar.dart';
import '../manager/widgets/iptv_source_status.dart';
import 'content_details_page.dart';
import 'home_data.dart';
import 'home_providers.dart';
import 'home_widgets.dart';
import 'library.dart';
import 'now_playing.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  /// Home tab: 0 Meu iPlex, 1 Canais, 2 Filmes, 3 Séries.
  int tab = 0;

  /// Room below the content for the main menu.
  static const _bottomSpace = AppDimensions.bottomNav + AppSpacing.xl;

  /// Opens the full details page of [item]; when the same title has saved
  /// progress (from any row or the search), that entry is used so "continue"
  /// is offered.
  void open(Entry item, HomeData? home) {
    final withProgress = item.progress != null
        ? item
        : home?.continueWatching.where((c) => c.id == item.id).firstOrNull ??
              item;
    openTitle(context, withProgress);
  }

  /// "⋮" / long press on a card: content options (the list actions only
  /// for persistent profiles, inside the sheet).
  ValueChanged<Entry>? libraryActions(HomeData? home) => home == null
      ? null
      : (item) => showLibraryActions(context, item: item, home: home);

  Future<void> pickSource(List<Entry> sources, String? current) async {
    final picked = await showAppModalSheet<String>(
      context: context,
      builder: (c) => _SourcePicker(sources: sources, current: current),
    );
    if (picked == null || picked == current) return;
    await ref.read(selectedSourceProvider.notifier).select(picked);
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    return SafeArea(
      top: false,
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
    final l = context.l;
    final playing = tab == 0 ? ref.watch(nowPlayingProvider) : null;
    final statusBar = MediaQuery.paddingOf(context).top;
    final appBar = Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        statusBar + AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'iPlex',
              key: Key('home-title'),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          _BarButton(
            key: const Key('home-source-picker'),
            label: l.selectIptvSource,
            onTap: sources.isEmpty ? null : () => pickSource(sources, sourceId),
            child: const AppIcon(AppIcons.iptv),
          ),
          _BarButton(
            key: const Key('home-account'),
            label: l.account,
            onTap: () => context.go('/account'),
            child: const AccountAvatarFace(size: 32),
          ),
        ],
      ),
    );

    final tabs = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: AppTabs<int>(
        key: const Key('home-tabs'),
        padding: EdgeToEdge.inset,
        translucent: playing != null,
        options: [
          (0, l.myIplex),
          (1, l.filterChannels),
          (2, l.filterMovies),
          (3, l.filterSeries),
        ],
        selected: tab,
        onSelected: (i) => setState(() => tab = i),
      ),
    );

    final Widget header;
    if (playing != null) {
      header = AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Artwork(
              key: const Key('now-playing-art'),
              item: playing.item,
              backdrop: true,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment(0, -0.2),
                  colors: [Color(0xB3000000), Colors.transparent],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(0, 0.1),
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.backgroundPrimary.withValues(alpha: 0.8),
                    AppColors.backgroundPrimary,
                  ],
                  stops: const [0.0, 0.65, 1.0],
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                appBar,
                tabs,
                const Spacer(),
                Opacity(
                  opacity: 0,
                  child: SizedBox(
                    width: 1,
                    height: 1,
                    child: Text(l.homeNowPlaying),
                  ),
                ),
                NowPlayingBar(playing: playing),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ],
        ),
      );
    } else {
      header = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          appBar,
          tabs,
          const SizedBox(height: AppSpacing.md),
        ],
      );
    }
    if (ready.isEmpty) {
      // Saved titles stay reachable even without a ready source.
      final library = ref.watch(homeProvider(null)).asData?.value;
      return ListView(
        children: [
          header,
          _Padded(child: _noReadySource(context, sources)),
          if (library != null) ..._libraryRows(context, library),
          SizedBox(height: _bottomSpace),
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
          if (tab == 0)
            ..._homeSlivers(context, home, sourceId)
          else if (source != null)
            SliverToBoxAdapter(
              child: CatalogTab(
                key: ValueKey('catalog-${source.id}-$tab'),
                source: source,
                kind: const ['channel', 'movie', 'series'][tab - 1],
                home: home.asData?.value,
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: _bottomSpace)),
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
          child: _Padded(child: PosterRowsSkeleton(rows: 3)),
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
        void tap(Entry item) => open(item, data);
        final rows = [
          (l.homeFavorites, data.libraryFavorites, HomeSection.favorites),
          (
            l.homeContinueWatching,
            data.continueWatching,
            HomeSection.continueWatching,
          ),
          (l.homeWishlist, data.wishlist, HomeSection.wishlist),
          (l.homeRecentMovies, data.recentMovies, HomeSection.recentMovies),
          (l.homeRecentSeries, data.recentSeries, HomeSection.recentSeries),
          (
            l.homeRecentSearches,
            data.recentSearches,
            HomeSection.recentSearches,
          ),
        ].where((row) => row.$2.isNotEmpty);
        if (rows.isEmpty) {
          return [
            SliverToBoxAdapter(
              child: _Padded(
                child: EmptyState(
                  title: l.homeEmptyTitle,
                  body: l.homeEmptyBody,
                  icon: AppIcons.iptv,
                  action: AppButton(
                    label: l.exploreCatalog,
                    onPressed: () => context.go('/search'),
                  ),
                ),
              ),
            ),
          ];
        }
        return [
          for (final row in rows)
            SliverToBoxAdapter(
              child: HomeRow(
                title: row.$1,
                items: row.$2,
                onTap: tap,
                onLongPress: libraryActions(data),
                onSeeAll: () => context.push('/home/section/${row.$3.name}'),
              ),
            ),
        ];
      },
    );
  }

  /// Favoritos and Lista de desejos (also titles no source offers).
  List<Widget> _libraryRows(BuildContext context, HomeData home) => [
    for (final (title, items, section) in [
      (context.l.homeFavorites, home.libraryFavorites, HomeSection.favorites),
      (context.l.homeWishlist, home.wishlist, HomeSection.wishlist),
    ])
      if (items.isNotEmpty)
        HomeRow(
          title: title,
          items: items,
          onTap: (item) => open(item, home),
          onLongPress: libraryActions(home),
          onSeeAll: () => context.push('/home/section/${section.name}'),
        ),
  ];

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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: l.iptvSources, subtitle: l.selectIptvSource),
          for (final source in sources)
            () {
              final isReady = ready.contains(source.id);
              // The app list card: name, last sync date/time and the state
              // on the right; the current source has the white border.
              return NeumorphicListTile(
                key: ValueKey('source-option-${source.id}'),
                icon: AppIcons.iptv,
                title: source.name,
                subtitle: _syncInfo(context, source),
                selected: source.id == current,
                enabled: isReady,
                trailing: IptvSourceIndicator(source: source),
                onTap: isReady ? () => Navigator.pop(context, source.id) : null,
              );
            }(),
        ],
      ),
    );
  }

  String _syncInfo(BuildContext context, Entry source) {
    final timestamp = source.data['lastSuccessfulSyncAt'] != null
        ? source.number('lastSuccessfulSyncAt')
        : source.number('lastSyncAt');
    if (timestamp <= 0) return context.l.neverSynced;
    return formatCardDateTime(
      context,
      DateTime.fromMillisecondsSinceEpoch(timestamp),
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

/// Flat 48 dp action of the Home app bar.
class _BarButton extends StatelessWidget {
  const _BarButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
  });
  final String label;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: InkResponse(
      radius: AppDimensions.touch / 2,
      onTap: onTap,
      child: SizedBox.square(
        dimension: AppDimensions.touch,
        child: Center(child: child),
      ),
    ),
  );
}

/// Canais / Filmes / Séries tab: the selected source's catalog of one kind
/// (readSourceCatalog `kind`), 30 at a time, same cards as the Home rows.
class CatalogTab extends ConsumerStatefulWidget {
  const CatalogTab({
    super.key,
    required this.source,
    required this.kind,
    required this.home,
  });
  final Entry source;
  final String kind;
  final HomeData? home;

  @override
  ConsumerState<CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends ConsumerState<CatalogTab> {
  final items = <Entry>[];
  Object? cursor = 0, error;
  bool loading = false, more = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading || !more) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await ref.read(repositoryProvider).mutate(
        'readSourceCatalog',
        {
          'id': widget.source.id,
          'version': widget.source.text('version'),
          'kind': widget.kind,
          'cursor': cursor,
        },
      );
      if (!mounted) return;
      setState(() {
        items.addAll([
          for (final raw in (result['items'] as List? ?? const []))
            if (raw is Map && raw['id'] is String)
              Entry(raw['id'] as String, Map<String, dynamic>.from(raw)),
        ]);
        cursor = result['cursor'];
        more = result['hasMore'] == true;
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    if (error != null && items.isEmpty) {
      return _Padded(
        child: ErrorState(
          onRetry: () {
            more = true;
            load();
          },
        ),
      );
    }
    if (loading && items.isEmpty) {
      return const _Padded(child: PosterGridSkeleton());
    }
    if (items.isEmpty) {
      return _Padded(
        child: EmptyState(
          title: l.noResults,
          body: l.noResultsBody,
          icon: AppIcons.search,
        ),
      );
    }
    final home = widget.home;
    return _Padded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            key: ValueKey('catalog-grid-${widget.kind}'),
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final item in items)
                HomeCard(
                  item: item,
                  onTap: () => openTitle(context, item),
                  onLongPress: home == null
                      ? null
                      : () =>
                            showLibraryActions(context, item: item, home: home),
                ),
            ],
          ),
          if (more) ...[
            const SizedBox(height: AppSpacing.lg),
            loading
                ? const AppLoadingSkeleton(rows: 1)
                : AppButton(label: l.more, onPressed: load),
          ],
        ],
      ),
    );
  }
}
