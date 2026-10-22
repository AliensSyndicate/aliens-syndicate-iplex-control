import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import 'content_details_page.dart';
import 'home_data.dart';
import 'home_providers.dart';
import 'home_widgets.dart';
import 'library.dart';

/// "Ver tudo": every item of one Home section (the Home shows the first 10),
/// with the same cards, tap (details page) and long press (lists).
class HomeSectionPage extends ConsumerWidget {
  const HomeSectionPage({super.key, required this.section});
  final HomeSection section;

  String _title(BuildContext context) {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(entriesProvider('sources')).asData?.value;
    final sourceId = sources == null
        ? null
        : effectiveSourceId(
            ref.watch(selectedSourceProvider),
            readySources(sources, ref.watch(unlockedSourcesProvider)),
          );
    final key = (section, sourceId);
    final data = ref.watch(homeSectionProvider(key));
    return Scaffold(
      backgroundColor: AppColors.backgroundDeep,
      body: PageTemplate(
        title: _title(context),
        showBack: true,
        child: data.when(
          loading: () => const AppLoadingSkeleton(rows: 3),
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
            return Wrap(
              key: const Key('home-section-grid'),
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final item in items)
                  HomeCard(
                    item: item,
                    onTap: () => openTitle(context, item),
                    onLongPress: () =>
                        showLibraryActions(context, item: item, home: home),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
