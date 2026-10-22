import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import 'content_details_page.dart';
import 'home_data.dart';
import 'home_providers.dart';
import 'home_widgets.dart';
import 'library.dart';

/// "Ver tudo": one screen for every Home category. The tabs switch between
/// the categories that have content (opening on the one tapped); each shows
/// all its items (the Home shows the first 10) in a two-column grid —
/// titles as 2:3 posters, channels as square tiles.
class HomeSectionPage extends ConsumerStatefulWidget {
  const HomeSectionPage({super.key, required this.section});
  final HomeSection section;

  @override
  ConsumerState<HomeSectionPage> createState() => _HomeSectionPageState();
}

class _HomeSectionPageState extends ConsumerState<HomeSectionPage> {
  late HomeSection section = widget.section;

  static String title(BuildContext context, HomeSection section) {
    final l = context.l;
    return switch (section) {
      HomeSection.favorites => l.homeFavorites,
      HomeSection.continueWatching => l.homeContinueWatching,
      HomeSection.wishlist => l.homeWishlist,
      HomeSection.recentMovies => l.homeRecentMovies,
      HomeSection.recentSeries => l.homeRecentSeries,
      HomeSection.recentSearches => l.homeRecentSearches,
    };
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(entriesProvider('sources')).asData?.value;
    final sourceId = sources == null
        ? null
        : effectiveSourceId(
            ref.watch(selectedSourceProvider),
            readySources(sources, ref.watch(unlockedSourcesProvider)),
          );
    // Categories with content on the Home, in the Home order.
    final home = ref.watch(currentHomeProvider).asData?.value;
    final sections = [
      for (final s in HomeSection.values)
        if (s == section || (home?.section(s).isNotEmpty ?? false)) s,
    ];
    final key = (section, sourceId);
    final data = ref.watch(homeSectionProvider(key));
    return Scaffold(
      backgroundColor: AppColors.backgroundDeep,
      body: PageTemplate(
        title: context.l.seeAll,
        showBack: true,
        // Tabs run edge to edge; the grid keeps the page margin.
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        child: Column(
          key: const Key('home-section-page'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTabs<HomeSection>(
              key: const Key('home-section-tabs'),
              padding: EdgeToEdge.inset,
              options: [for (final s in sections) (s, title(context, s))],
              selected: section,
              onSelected: (s) => setState(() => section = s),
            ),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: EdgeToEdge.inset,
              child: data.when(
                loading: () => const PosterGridSkeleton(),
                error: (e, stack) => ErrorState(
                  onRetry: () => ref.invalidate(homeSectionProvider(key)),
                ),
                data: (home) {
                  final items = home.section(section);
                  if (items.isEmpty) {
                    return EmptyState(
                      title: context.l.noResults,
                      body: '',
                      icon: AppIcons.search,
                    );
                  }
                  return LayoutBuilder(
                    builder: (context, box) {
                      // Two items per row.
                      final cell = (box.maxWidth - AppSpacing.md) / 2;
                      return Wrap(
                        key: const Key('home-section-grid'),
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.lg,
                        children: [
                          for (final item in items)
                            HomeCard(
                              item: item,
                              width: cell,
                              onTap: () => openTitle(context, item),
                              onLongPress: () => showLibraryActions(
                                context,
                                item: item,
                                home: home,
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
