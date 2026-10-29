import 'package:flutter/rendering.dart' show ScrollCacheExtent;

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
import 'catalog_groups.dart';
import 'content_details_page.dart';
import 'home_data.dart';
import 'home_providers.dart';
import 'home_section_page.dart';
import 'home_widgets.dart';
import 'library.dart';
import 'now_playing.dart';
import 'release_hero.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  /// Home tab: 0 Meu iPlex, 1 Canais, 2 Filmes, 3 Séries.
  int tab = 0;

  /// Kind shown in the "Adulto" tab (null: the first one it has).
  String? adultKind;

  /// Room below the content for the main menu.
  static const _bottomSpace = AppDimensions.bottomNav + AppSpacing.xl;

  // Floating app bar (name, IPTV, avatar and tabs): it leaves with the content
  // when scrolling down the list and comes back at once on any scroll back.
  final scroll = ScrollController();
  final barKey = GlobalKey();
  final bar = ValueNotifier<double>(0);
  double barHeight = 0;

  @override
  void dispose() {
    scroll.dispose();
    bar.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || n.depth != 0) return false;
    if (n is ScrollUpdateNotification) {
      final measured = barKey.currentContext?.size?.height ?? barHeight;
      final height = measured > 0 ? measured : barHeight;
      final pixels = n.metrics.pixels;
      var offset = bar.value - (n.scrollDelta ?? 0);
      if (pixels <= 0) offset = 0;
      offset = offset.clamp(-height, 0.0);
      if (offset != bar.value) bar.value = offset;
    }
    return false;
  }

  void _measureBar() {
    final height = barKey.currentContext?.size?.height ?? 0;
    if (height > 0 && (height - barHeight).abs() > 0.5 && mounted) {
      setState(() => barHeight = height);
    }
  }

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
    // "Adulto" (as on the TV menu): only for a profile that sees adult
    // content in this source (never kids); the tab closes when it no longer
    // does.
    final adultKinds = ready.isEmpty
        ? const <String>[]
        : ref.watch(homeProvider(sourceId)).asData?.value.adultKinds ??
              const <String>[];
    if (tab == 4 && adultKinds.isEmpty) tab = 0;
    final playing = tab == 0 ? ref.watch(nowPlayingProvider) : null;
    final hero = playing == null ? _hero(sourceId, ready) : null;
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
        // Over artwork (playing or featured release).
        translucent: playing != null || hero != null,
        options: [
          (0, l.myIplex),
          (1, l.filterChannels),
          (2, l.filterMovies),
          (3, l.filterSeries),
          if (adultKinds.isNotEmpty) (4, l.adultTab),
        ],
        selected: tab,
        onSelected: (i) => setState(() => tab = i),
      ),
    );

    final floating = ready.isNotEmpty;
    // Reserved where the floating bar sits at the top of the page.
    final barSpace = SizedBox(
      height: barHeight > 0
          ? barHeight
          : statusBar + AppSpacing.sm * 2 + AppDimensions.touch * 2,
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
                if (floating) barSpace else ...[appBar, tabs],
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
    } else if (hero case (final home, final releases)) {
      // Meu iPlex: the day's featured release, as on the TV.
      final account = ref.watch(accountProvider).asData?.value;
      final profile = home.profile;
      header = Column(
        children: [
          ReleaseHero(
            candidates: releases,
            storageKey:
                'iplex.hero.v1.${account?.uid}.${account?.iptvScopeId}.${profile?.id}',
            top: floating
                ? barSpace
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [appBar, tabs],
                  ),
            onOpen: (item) => open(item, home),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      );
    } else {
      header = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (floating) barSpace else ...[appBar, tabs],
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureBar());
    final barContent = KeyedSubtree(
      key: barKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [appBar, tabs],
      ),
    );
    final feed = RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(homeProvider(sourceId));
        await ref
            .read(homeProvider(sourceId).future)
            .catchError((_) => const HomeData());
      },
      child: CustomScrollView(
        key: const PageStorageKey('home-scroll'),
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        scrollCacheExtent: const ScrollCacheExtent.pixels(800),
        slivers: [
          SliverToBoxAdapter(child: header),
          if (tab == 0)
            ..._homeSlivers(context, home, sourceId)
          else if (source != null && tab == 4)
            ..._adultSlivers(context, source, adultKinds, home.asData?.value)
          else if (source != null)
            CatalogTab(
              key: ValueKey('catalog-${source.id}-$tab'),
              source: source,
              kind: const ['channel', 'movie', 'series'][tab - 1],
              home: home.asData?.value,
            ),
          SliverToBoxAdapter(child: SizedBox(height: _bottomSpace)),
        ],
      ),
    );
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: feed,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder(
            valueListenable: bar,
            // Transparent background: only the content of the bar moves.
            builder: (context, offset, child) =>
                Transform.translate(offset: Offset(0, offset), child: child),
            child: barContent,
          ),
        ),
      ],
    );
  }

  /// "Adulto": the same feed as Canais / Filmes / Séries, with only the
  /// kinds that have adult content (Ao vivo, Filmes, Séries, as on the TV).
  List<Widget> _adultSlivers(
    BuildContext context,
    Entry source,
    List<String> kinds,
    HomeData? home,
  ) {
    final l = context.l;
    final kind = kinds.contains(adultKind) ? adultKind! : kinds.first;
    final labels = {
      'channel': l.filterChannels,
      'movie': l.filterMovies,
      'series': l.filterSeries,
    };
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AppTabs<String>(
            key: const Key('adult-kinds'),
            padding: EdgeToEdge.inset,
            options: [for (final k in kinds) (k, labels[k]!)],
            selected: kind,
            onSelected: (k) => setState(() => adultKind = k),
          ),
        ),
      ),
      CatalogTab(
        key: ValueKey('catalog-${source.id}-adult-$kind'),
        source: source,
        kind: kind,
        home: home,
        adult: true,
      ),
    ];
  }

  /// Home data and Lançamentos for the featured release (Meu iPlex tab with
  /// a ready source only), or null.
  (HomeData, List<Entry>)? _hero(String? sourceId, List<Entry> ready) {
    if (tab != 0 || ready.isEmpty) return null;
    final home = ref.watch(homeProvider(sourceId)).asData?.value;
    final releases = home?.section(HomeSection.releases) ?? const <Entry>[];
    return home == null || releases.isEmpty ? null : (home, releases);
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
          for (final section in homeSections)
            if (data.section(section).isNotEmpty) section,
        ];
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
          for (final section in rows)
            SliverToBoxAdapter(
              child: HomeRow(
                title: homeSectionTitle(context, section),
                items: data.section(section),
                landscape: landscapeSections.contains(section),
                onTap: tap,
                onLongPress: libraryActions(data),
                onSeeAll: () => context.push('/home/section/${section.name}'),
              ),
            ),
        ];
      },
    );
  }

  /// Personal rows without a ready source (Favoritos and Lista de desejos
  /// also hold titles no source offers).
  List<Widget> _libraryRows(BuildContext context, HomeData home) => [
    for (final section in homeSections)
      if (section != HomeSection.releases && home.section(section).isNotEmpty)
        HomeRow(
          title: homeSectionTitle(context, section),
          items: home.section(section),
          landscape: landscapeSections.contains(section),
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
/// (readSourceCatalog `kind`) as a feed: [catalogColumns] cards per row (square for
/// channels, 2:3 posters for titles), [catalogPageSize] at a time, the next
/// page loads by itself while the user scrolls. It is a sliver of the Home
/// scroll view.
class CatalogTab extends ConsumerStatefulWidget {
  const CatalogTab({
    super.key,
    required this.source,
    required this.kind,
    required this.home,
    this.adult = false,
  });
  final Entry source;
  final String kind;
  final HomeData? home;

  /// The "Adulto" tab: adult content only; every other tab never has it.
  final bool adult;

  @override
  ConsumerState<CatalogTab> createState() => _CatalogTabState();
}

/// Cards per row of a category.
const catalogColumns = 3;

class _CatalogTabState extends ConsumerState<CatalogTab> {
  /// The open category (one at a time, so the screen stays clean). There is
  /// no "Todos": titles only show inside an open category.
  String? open;
  final headers = <String, GlobalKey>{};

  ({String sourceId, String version, String kind, bool adult}) get _key => (
    sourceId: widget.source.id,
    version: widget.source.text('version'),
    kind: widget.kind,
    adult: widget.adult,
  );

  /// Opens [key] (closing the open one) or closes it; the header stays in
  /// view.
  void toggle(String key) {
    setState(() => open = open == key ? null : key);
    if (open == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final header = headers[key]?.currentContext;
      if (header != null && header.mounted) {
        Scrollable.ensureVisible(
          header,
          duration: AppMotion.duration(context, AppMotion.pageEnter),
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      }
    });
  }

  Widget _box(Widget child) => SliverToBoxAdapter(child: _Padded(child: child));

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final groups = ref.watch(catalogGroupsProvider(_key));
    if (groups.hasError && !groups.hasValue) {
      return _box(
        ErrorState(
          onRetry: () => ref.invalidate(
            catalogSetProvider((
              _key.sourceId,
              _key.version,
              widget.adult ? 'adult' : widget.kind,
            )),
          ),
        ),
      );
    }
    final categories = groups.asData?.value;
    if (categories == null) return _box(const _CategorySkeleton());
    if (categories.isEmpty) {
      return _box(
        EmptyState(
          title: l.noResults,
          body: l.noResultsBody,
          icon: AppIcons.search,
        ),
      );
    }
    final index = categories.indexWhere((c) => c.key == open);
    Widget headerList(Iterable<CatalogGroup> list) => SliverList.list(
      children: [
        for (final c in list)
          _CategoryHeader(
            key: headers.putIfAbsent(c.key, GlobalKey.new),
            category: c,
            open: c.key == open,
            onTap: () => toggle(c.key),
          ),
      ],
    );
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      sliver: SliverMainAxisGroup(
        key: ValueKey('catalog-categories-${widget.kind}'),
        slivers: [
          headerList(index < 0 ? categories : categories.take(index + 1)),
          if (index >= 0) ...[
            _grid(context, categories[index]),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
            headerList(categories.skip(index + 1)),
          ],
        ],
      ),
    );
  }

  /// Titles of one category, [catalogColumns] per row (built as they scroll
  /// into view).
  Widget _grid(BuildContext context, CatalogGroup group) {
    final home = widget.home;
    final square = widget.kind == 'channel';
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.sm;
        final cell =
            (constraints.crossAxisExtent - gap * (catalogColumns - 1)) /
            catalogColumns;
        return SliverGrid(
          key: ValueKey('catalog-grid-${widget.kind}-${group.key}'),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: catalogColumns,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: square ? 1 : 2 / 3,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final item = group.items[index];
            return HomeCard(
              item: item,
              width: cell,
              onTap: () => openTitle(context, item),
              onLongPress: home == null
                  ? null
                  : () => showLibraryActions(context, item: item, home: home),
            );
          }, childCount: group.items.length),
        );
      },
    );
  }
}

/// Accordion header of a category (same surface as the Help questions): the
/// name, how many titles it has and the open/closed arrow.
class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    super.key,
    required this.category,
    required this.open,
    required this.onTap,
  });
  final CatalogGroup category;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Semantics(
      button: true,
      expanded: open,
      child: Material(
        key: ValueKey('catalog-category-${category.key}'),
        color: AppColors.surfaceDefault,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.card),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  '${category.items.length}',
                  key: ValueKey('catalog-category-count-${category.key}'),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(width: AppSpacing.sm),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: AppMotion.duration(context, AppMotion.pageEnter),
                  curve: AppMotion.pageCurve,
                  child: const AppIcon(
                    AppIcons.down,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Category headers while the list of categories loads.
class _CategorySkeleton extends StatelessWidget {
  const _CategorySkeleton();
  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l.loading,
    liveRegion: true,
    child: ExcludeSemantics(
      child: AppSkeletonPulse(
        child: Column(
          children: [
            for (var i = 0; i < 8; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              const AppSkeletonBlock(height: 56, radius: AppRadii.card),
            ],
          ],
        ),
      ),
    ),
  );
}
