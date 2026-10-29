import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/home/content_details_page.dart';
import 'package:aliens_syndicate_iplex_control/features/home/home_data.dart';
import 'package:aliens_syndicate_iplex_control/features/watch_on_tv/watch_on_tv_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'home_page_test.dart' show profile, settleFeed;
import 'navigation_test.dart' as navigation;
import 'support/catalog_sets_fixture.dart';
import 'widget_test.dart' as fixtures;

/// Adult content in the Control follows the TV (iplex-web): its own "Adulto"
/// tab, never in the other tabs, no details page, no TMDB, nothing saved.
class _AdultRepo extends navigation.SessionRepository {
  _AdultRepo({List<String> adultKinds = const ['channel', 'series']})
    : super(uid: 'u', linked: true) {
    sources = [
      Entry('s', {'name': 'Minha IPTV', 'version': 'v', 'status': 'ready'}),
    ];
    home = {'profile': profile, 'adultKinds': adultKinds};
  }

  /// Sets read, in order.
  final chunks = <String>[];

  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (action == 'readSourceSeries') {
      return {
        'details': {
          'episodes': {
            '1': [
              {'id': 'e1', 'title': 'Primeiro', 'season': 1, 'episodeNum': 1},
            ],
          },
        },
      };
    }
    if (action == 'readCatalogChunk') chunks.add(payload['set'] as String);
    return catalogSetsAnswer(action, payload, [
          for (final kind in const ['channel', 'movie', 'series']) ...[
            {
              'id': '$kind-regular',
              'title': 'Regular $kind',
              'kind': kind,
              'category': 'Geral',
              'sourceId': 's',
              'providerRef': '1',
            },
            {
              'id': '$kind-adult',
              'title': 'XXX $kind',
              'kind': kind,
              'category': 'Adultos',
              'sourceId': 's',
              'providerRef': '1',
            },
            // An older backend may still send adult items with the others.
            {
              'id': '$kind-leak',
              'title': 'Hot $kind',
              'kind': kind,
              'category': 'Geral',
              'isAdult': true,
              'sourceId': 's',
              'set': const {
                'channel': 'live',
                'movie': 'vod',
                'series': 'series',
              }[kind],
            },
          ],
        ]) ??
        await super.mutate(action, payload);
  }
}

/// Opens a category of the tab (titles only show inside it): "Geral" in the
/// regular tabs, "Adulto" in the adult one.
Future<void> _openCategory(WidgetTester tester, [String key = 'adulto']) async {
  await tester.tap(find.byKey(ValueKey('catalog-category-$key')));
  await settleFeed(tester);
}

void main() {
  setUpAll(fixtures.loadTestFont);
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test('adult signals: provider flag, words, 18 rating, "Sexo" category', () {
    Entry e(Map<String, dynamic> data) => Entry('x', data);
    expect(isAdultEntry(e({'title': 'Drama', 'isAdult': true})), isTrue);
    expect(isAdultEntry(e({'title': 'XXX Night'})), isTrue);
    expect(isAdultEntry(e({'title': 'Filme', 'category': 'Eróticos'})), isTrue);
    expect(isAdultEntry(e({'title': 'Canal', 'category': 'SEXO'})), isTrue);
    expect(isAdultEntry(e({'title': 'Filme', 'ageRating': '18 anos'})), isTrue);
    // "Sexo" in a title is not a signal (a category name only).
    expect(isAdultEntry(e({'title': 'Sexo e a Cidade'})), isFalse);
    expect(isAdultEntry(e({'title': 'Drama', 'category': 'Filmes'})), isFalse);
  });

  testWidgets('"Adult" tab only with adult kinds; other tabs never have it', (
    tester,
  ) async {
    final repo = _AdultRepo();
    await navigation.launch(tester, repo);
    expect(find.byKey(const ValueKey('tab-4')), findsOneWidget);
    expect(find.text('Adult'), findsOneWidget);

    // Regular tab: asks without adult content and drops what still leaks.
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await settleFeed(tester);
    await _openCategory(tester, 'geral');
    expect(repo.chunks, isNot(contains('adult')));
    expect(find.byKey(const ValueKey('home-card-movie-regular')), findsOne);
    expect(find.byKey(const ValueKey('home-card-movie-leak')), findsNothing);

    // Adult tab: only its kinds (TV order), adult content only.
    await tester.tap(find.byKey(const ValueKey('tab-4')));
    await settleFeed(tester);
    expect(find.byKey(const ValueKey('tab-channel')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-series')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-movie')), findsNothing);
    expect(repo.chunks, contains('adult'));
    await tester.tap(find.byKey(const ValueKey('tab-series')));
    await settleFeed(tester);
    await _openCategory(tester);
    expect(find.byKey(const ValueKey('home-card-series-adult')), findsOne);
  });

  testWidgets('no adult kinds (adult off, kids): no "Adult" tab', (
    tester,
  ) async {
    await navigation.launch(tester, _AdultRepo(adultKinds: const []));
    expect(find.byKey(const ValueKey('tab-4')), findsNothing);
  });

  testWidgets('adult channel goes straight to "Watch on TV"; series to its '
      'episodes; options only offer watching', (tester) async {
    final repo = _AdultRepo();
    await navigation.launch(tester, repo);
    await tester.tap(find.byKey(const ValueKey('tab-4')));
    await settleFeed(tester);
    await _openCategory(tester);

    await tester.longPress(
      find.byKey(const ValueKey('home-card-channel-adult')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('option-watch')), findsOneWidget);
    for (final key in ['favorite', 'wishlist', 'share', 'details']) {
      expect(find.byKey(Key('option-$key')), findsNothing, reason: key);
    }
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-card-channel-adult')));
    await tester.pumpAndSettle();
    expect(find.byType(WatchOnTvSheet), findsOneWidget);
    expect(find.byType(ContentDetailsPage), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tab-series')));
    await settleFeed(tester);
    await _openCategory(tester);
    await tester.tap(find.byKey(const ValueKey('home-card-series-adult')));
    await tester.pumpAndSettle();
    expect(find.byType(AdultSeriesPage), findsOneWidget);
    expect(find.byType(ContentDetailsPage), findsNothing);
    await tester.tap(find.text('1. Primeiro'));
    await tester.pumpAndSettle();
    expect(find.byType(WatchOnTvSheet), findsOneWidget);
    expect(
      tester.widget<WatchOnTvSheet>(find.byType(WatchOnTvSheet)).episodeId,
      'e1',
    );
  });
}
