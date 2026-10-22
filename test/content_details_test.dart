import 'dart:async';

import 'package:aliens_syndicate_iplex_control/app/app.dart';
import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/features/home/details_button.dart';
import 'package:aliens_syndicate_iplex_control/features/home/home_data.dart';
import 'package:aliens_syndicate_iplex_control/features/home/home_providers.dart';
import 'package:aliens_syndicate_iplex_control/features/home/metadata_service.dart';
import 'package:aliens_syndicate_iplex_control/features/watch_on_tv/watch_on_tv_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'home_page_test.dart' show item, profile;
import 'navigation_test.dart' as navigation;
import 'widget_test.dart' as fixtures;

/// Backend double with a real in-memory library (same contract as readHome /
/// saveLibraryItem / resolveTitle): saved titles survive "restarts" (a new app
/// on the same repository) and availability is decided by the backend.
class LibraryRepo extends navigation.SessionRepository {
  LibraryRepo() : super(uid: 'u', linked: true) {
    sources = [
      Entry('s', {'name': 'Minha IPTV', 'version': 'v', 'status': 'ready'}),
    ];
  }
  Map<String, dynamic> profileJson = profile;
  List<Map<String, dynamic>> recentMovies = [], recentSeries = [];

  /// tmdb key → catalog item the backend would resolve (confident match).
  final catalogByTmdb = <String, Map<String, dynamic>>{};
  final library = {
    'favorites': <Map<String, dynamic>>[],
    'wishlist': <Map<String, dynamic>>[],
  };
  bool resolveFailure = false;

  String _key(Map<String, dynamic> p) => p['tmdbId'] != null
      ? 'tmdb:${p['kind'] == 'movie' ? 'movie' : 'tv'}:${p['tmdbId']}'
      : '${p['contentId']}';

  @override
  Map<String, dynamic> get home => {
    'profile': profileJson,
    'recentMovies': recentMovies,
    'recentSeries': recentSeries,
    'library': {
      for (final list in library.keys)
        list: [
          for (final row in library[list]!)
            catalogByTmdb[row['key']] != null
                ? {
                    ...catalogByTmdb[row['key']]!,
                    'library': {'id': row['key']},
                    'available': true,
                  }
                : row['contentId'] != null
                ? {
                    ...item(
                      row['contentId'] as String,
                      row['title'] as String,
                      row['kind'] as String,
                    ),
                    'available': true,
                  }
                : {
                    'id':
                        'tmdb-${row['kind'] == 'movie' ? 'movie' : 'tv'}-${row['tmdbId']}',
                    'kind': row['kind'],
                    'title': row['title'],
                    'tmdbId': row['tmdbId'],
                    'available': false,
                  },
        ],
    },
    'saved': {
      for (final list in library.keys)
        list: [
          for (final row in library[list]!) ...[
            row['key'],
            ?row['contentId'],
            if (catalogByTmdb[row['key']] case final c?) c['id'],
          ],
        ],
    },
  };
  @override
  set home(Map<String, dynamic> value) {}

  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (action == 'saveLibraryItem') {
      mutationPayloads.add((action, Map.of(payload)));
      final rows = library[payload['list']]!;
      final key = _key(payload);
      rows.removeWhere(
        (r) =>
            r['key'] == key ||
            (payload['contentId'] != null &&
                r['contentId'] == payload['contentId']),
      );
      if (payload['remove'] != true) rows.insert(0, {...payload, 'key': key});
      return {'ok': true};
    }
    if (action == 'resolveTitle') {
      mutationPayloads.add((action, Map.of(payload)));
      if (resolveFailure) throw const AppFailure('unavailable');
      return {
        'item':
            catalogByTmdb['tmdb:${payload['kind'] == 'movie' ? 'movie' : 'tv'}:${payload['tmdbId']}'],
      };
    }
    if (action == 'readSourceSeries') {
      mutationPayloads.add((action, Map.of(payload)));
      return {
        'details': {
          'episodes': {
            '1': [
              {'id': '3011', 'title': 'Começo', 'season': 1, 'episodeNum': 1},
              {'id': '3012', 'title': 'Meio', 'season': 1, 'episodeNum': 2},
            ],
          },
        },
      };
    }
    return super.mutate(action, payload);
  }
}

class FakeMetadata implements MetadataService {
  final titles = <String, ContentMetadata>{};
  final catalog = <String, ContentMetadata>{};
  final people = <int, PersonDetails>{};
  bool offline = false;
  @override
  Future<ContentMetadata?> summary(Entry item) async => catalog[item.id];
  @override
  Future<ContentMetadata?> details(Entry item) async => catalog[item.id];
  Completer<void>? pendingTitle;
  @override
  Future<ContentMetadata?> title(String kind, int tmdbId) async {
    await pendingTitle?.future;
    if (offline) throw const MetadataUnavailable(503);
    return titles['$kind:$tmdbId'];
  }

  @override
  Future<PersonDetails?> person(int tmdbId) async {
    if (offline) throw Exception('network');
    return people[tmdbId];
  }

  final seasons = <String, List<EpisodeInfo>>{};
  @override
  Future<List<EpisodeInfo>> season(
    Entry series,
    int tmdbId,
    int number,
  ) async => seasons['$tmdbId/$number'] ?? const [];
}

const keanu = PersonDetails(
  tmdbId: 6384,
  name: 'Keanu Reeves',
  biography: 'Ator canadense.',
  placeOfBirth: 'Beirute',
  credits: [
    PersonCredit(
      tmdbId: 777,
      kind: 'movie',
      title: 'Filme Externo',
      character: 'Herói',
      year: 2024,
    ),
    PersonCredit(
      tmdbId: 1001,
      kind: 'movie',
      title: 'Missão Fictícia',
      character: 'Neo',
      year: 2021,
    ),
    PersonCredit(
      tmdbId: 55,
      kind: 'series',
      title: 'Série Externa',
      character: 'Ele mesmo',
      episodeCount: 3,
      year: 2019,
    ),
  ],
);

FakeMetadata metadataFixture() => FakeMetadata()
  ..catalog['m1'] = ContentMetadata(
    tmdbId: 1001,
    title: 'Missão Fictícia',
    originalTitle: 'Fictional Mission',
    overview: 'Uma missão.',
    genres: const ['Ação', 'Drama'],
    year: 2021,
    releaseDate: DateTime(2021, 5, 20),
    runtimeMinutes: 118,
    certification: '14',
    certificationDescriptors: const ['Violência', 'Conteúdo sexual'],
    posterOriginal: 'https://image.tmdb.org/t/p/original/m1.jpg',
    rating: 7.4,
    cast: const [
      Credit(id: 6384, name: 'Keanu Reeves', role: 'Neo'),
      Credit(name: 'Sem Id', role: 'Extra'),
    ],
    crew: const [Credit(id: 9, name: 'Diretora', role: 'Direção')],
  )
  ..titles['movie:777'] = const ContentMetadata(
    tmdbId: 777,
    title: 'Filme Externo',
    overview: 'Fora do IPTV.',
    year: 2024,
  )
  ..titles['series:55'] = const ContentMetadata(
    tmdbId: 55,
    title: 'Série Externa',
    seasonCount: 2,
    seasons: [SeasonInfo(1, 'Temporada 1', 8), SeasonInfo(2, 'Temporada 2', 6)],
  )
  ..people[6384] = keanu;

Future<ProviderContainer> launchWith(
  WidgetTester tester,
  LibraryRepo repo,
  MetadataService metadata,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 2400);
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      metadataServiceProvider.overrideWithValue(metadata),
      initialRouteProvider.overrideWithValue('/home'),
    ],
  );
  addTearDown(() {
    container.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('screen'),
      child: UncontrolledProviderScope(
        container: container,
        child: const IplexApp(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key).last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key).last);
  await tester.pumpAndSettle();
}

String location(ProviderContainer c) => c.read(routerProvider).state.uri.path;

void main() {
  setUpAll(fixtures.loadTestFont);
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  testWidgets(
    'movie opens a full page (not a sheet): TMDB details, cast, crew; Back returns Home',
    (tester) async {
      final repo = LibraryRepo()
        ..recentMovies = [item('m1', 'Missão Fictícia', 'movie', year: '2021')];
      final c = await launchWith(tester, repo, metadataFixture());
      await tapKey(tester, const ValueKey('home-card-m1'));
      expect(location(c), '/home/title');
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byKey(const Key('details-title')), findsOneWidget);
      expect(find.text('Original title: Fictional Mission'), findsOneWidget);
      expect(
        find.textContaining('2021 | Ação | 1h 58min', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Released'), findsOneWidget);
      expect(find.text('Rating 7.4/10 (TMDB)'), findsOneWidget);
      // ClassInd seal + reasons, right before the stars; no "Rated" text row.
      expect(find.byType(AgeRatingBadge), findsOneWidget);
      expect(find.text('Violência and conteúdo sexual'), findsOneWidget);
      expect(find.text('Rated 14'), findsNothing);
      // Seal first in the year line; reasons right below it, before the stars.
      final spans =
          (tester
                      .widget<RichText>(
                        find
                            .descendant(
                              of: find.byKey(const Key('details-facts')),
                              matching: find.byType(RichText),
                            )
                            .first,
                      )
                      .text
                  as TextSpan)
              .children!;
      // Text.rich wraps the span given to it in the default style span.
      expect((spans.first as TextSpan).children!.first, isA<WidgetSpan>());
      expect(
        find.descendant(
          of: find.byKey(const Key('details-facts')),
          matching: find.byType(AgeRatingBadge),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('details-age-rating'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('details-stars'))).dy),
      );
      // Scrolling up darkens the cover until black.
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      ColoredBox dim() =>
          tester.widget<ColoredBox>(find.byKey(const Key('details-cover-dim')));
      expect(dim().color.a, 0);
      await tester.drag(
        find.byKey(const Key('details-scroll')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(dim().color.a, greaterThan(0.4));
      await tester.drag(
        find.byKey(const Key('details-scroll')),
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();
      expect(dim().color.a, closeTo(1, 0.001));
      await tester.drag(
        find.byKey(const Key('details-scroll')),
        const Offset(0, 4000),
      );
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(390, 2400);
      await tester.pumpAndSettle();
      // Original TMDB poster as the cover, faded into the page.
      expect(
        (tester.widget<Image>(find.byKey(const Key('details-cover'))).image
                as NetworkImage)
            .url,
        'https://image.tmdb.org/t/p/original/m1.jpg',
      );
      expect(find.byKey(const Key('details-cover-fade')), findsOneWidget);
      // Director before the synopsis.
      expect(
        tester.getTopLeft(find.text('Directed by Diretora')).dy,
        lessThan(tester.getTopLeft(find.text('Uma missão.')).dy),
      );
      // Favoritar | Salvar: icons only, right side of the top bar.
      final fav = tester.getRect(find.byKey(const Key('details-favorite')));
      final save = tester.getRect(find.byKey(const Key('details-wishlist')));
      final back = tester.getRect(find.byKey(const Key('details-back')));
      expect([fav.top, save.top], [back.top, back.top]);
      expect(fav.right, lessThanOrEqualTo(save.left));
      expect(save.right, greaterThan(300));
      expect(find.bySemanticsLabel('Favorite'), findsOneWidget);
      expect(find.bySemanticsLabel('Save'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(
        tester
            .widget<DetailsButton>(find.byKey(const Key('details-watch-on-tv')))
            .primary,
        isTrue,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is DetailsBarIcon && w.key == const Key('details-favorite'),
        ),
        findsOneWidget,
      );
      // Back: icon only, white, no box.
      expect(
        find.descendant(
          of: find.byKey(const Key('details-back')),
          matching: find.byType(CircularButton),
        ),
        findsNothing,
      );
      expect(
        tester
            .widget<AppIcon>(
              find.descendant(
                of: find.byKey(const Key('details-back')),
                matching: find.byType(AppIcon),
              ),
            )
            .color,
        Colors.white,
      );
      for (final key in [
        'details-watch-on-tv',
        'details-favorite',
        'details-wishlist',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(AppIcon),
          ),
          findsNothing,
        );
      }
      expect(find.text('Uma missão.'), findsOneWidget);
      expect(find.text('Cast'), findsOneWidget);
      // Cast: actors only, 3:4 portraits; the crew is not a cast section.
      expect(find.text('Crew'), findsNothing);
      expect(find.text('Diretora'), findsNothing);
      final photo = tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey('person-6384')),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(photo.height / photo.width, closeTo(4 / 3, 0.01));
      expect(find.byKey(const Key('details-watch-on-tv')), findsOneWidget);
      expect(find.byKey(const Key('details-unavailable')), findsNothing);
      await fixtures.screenshot(tester, 'details/movie-iptv');
      await tapKey(tester, const Key('details-back'));
      expect(location(c), '/home');
    },
  );

  testWidgets(
    'Home → movie → actor → filmography → external movie → back through the stack',
    (tester) async {
      final repo = LibraryRepo()
        ..recentMovies = [item('m1', 'Missão Fictícia', 'movie', year: '2021')];
      final c = await launchWith(tester, repo, metadataFixture());
      await tapKey(tester, const ValueKey('home-card-m1'));
      await tapKey(tester, const ValueKey('person-6384'));
      expect(location(c), '/home/person/6384');
      expect(find.text('Keanu Reeves'), findsWidgets);
      expect(find.text('Ator canadense.'), findsOneWidget);
      expect(find.text('Filmography'), findsOneWidget);
      expect(find.text('Career timeline'), findsOneWidget);
      // Timeline: newest first, grouped by year, with the character.
      final ys = [
        for (final y in ['2024', '2021', '2019'])
          tester.getTopLeft(find.text(y)).dy,
      ];
      expect(ys, [...ys]..sort());
      expect(find.text('Movie · as Herói'), findsOneWidget);
      expect(find.text('Series · as Ele mesmo · 3 episodes'), findsOneWidget);
      await fixtures.screenshot(tester, 'details/person');

      await tapKey(tester, const ValueKey('timeline-movie-777'));
      expect(location(c), '/home/title/movie/777');
      expect(find.text('Fora do IPTV.'), findsOneWidget);
      expect(
        find.byKey(const Key('details-unavailable')),
        findsOneWidget,
        reason: 'not offered as playable',
      );
      await fixtures.screenshot(tester, 'details/movie-external-unavailable');
      expect(find.byKey(const Key('details-watch-on-tv')), findsNothing);
      expect(
        repo.mutationPayloads.lastWhere((m) => m.$1 == 'resolveTitle').$2,
        containsPair('tmdbId', 777),
      );

      await tapKey(tester, const Key('details-back'));
      expect(location(c), '/home/person/6384');
      await tester.tap(find.byType(CircularButton).first);
      await tester.pumpAndSettle();
      expect(location(c), '/home/title');
      await tapKey(tester, const Key('details-back'));
      expect(location(c), '/home');
    },
  );

  testWidgets(
    'favorite an IPTV movie and an external movie; wishlist an external series; remove and add again; persists across restarts',
    (tester) async {
      final repo = LibraryRepo()
        ..recentMovies = [item('m1', 'Missão Fictícia', 'movie', year: '2021')];
      var c = await launchWith(tester, repo, metadataFixture());
      await tapKey(tester, const ValueKey('home-card-m1'));
      await tapKey(tester, const Key('details-favorite'));
      expect(
        repo.mutationPayloads.lastWhere((m) => m.$1 == 'saveLibraryItem').$2,
        {
          'profileId': 'admin',
          'generation': 2,
          'list': 'favorites',
          'kind': 'movie',
          'contentId': 'm1',
          'sourceId': 's',
          'tmdbId': 1001,
          'title': 'Missão Fictícia',
          'originalTitle': 'Fictional Mission',
          'year': 2021,
        },
      );
      expect(find.bySemanticsLabel('Unfavorite'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Save'),
        findsOneWidget,
        reason: 'independent lists',
      );

      // External movie (filmography): saved although no IPTV source offers it.
      c.read(routerProvider).push('/home/title/movie/777');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('details-unavailable')), findsOneWidget);
      await tapKey(tester, const Key('details-favorite'));
      final external = repo.mutationPayloads
          .lastWhere((m) => m.$1 == 'saveLibraryItem')
          .$2;
      expect(external['tmdbId'], 777);
      expect(external.containsKey('contentId'), isFalse);
      expect(find.bySemanticsLabel('Unfavorite'), findsOneWidget);

      // External series → wishlist, then remove and add again.
      c.read(routerProvider).push('/home/title/series/55');
      await tester.pumpAndSettle();
      expect(find.text('Seasons'), findsOneWidget);
      // Not playable: TMDB seasons as buttons, episodes for information only.
      expect(find.byKey(const ValueKey('details-season-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('details-season-2')), findsOneWidget);
      expect(find.text('Available on your IPTV'), findsNothing);
      await fixtures.screenshot(tester, 'details/series-external-seasons');
      await tapKey(tester, const Key('details-wishlist'));
      expect(find.bySemanticsLabel('Remove'), findsOneWidget);
      await tapKey(tester, const Key('details-wishlist'));
      expect(
        repo.mutationPayloads
            .lastWhere((m) => m.$1 == 'saveLibraryItem')
            .$2['remove'],
        true,
      );
      expect(find.bySemanticsLabel('Save'), findsOneWidget);
      await tapKey(tester, const Key('details-wishlist'));
      expect(repo.library['wishlist']!.map((r) => r['tmdbId']), [55]);

      // "Restart": a new app on the same backend shows the saved rows and states.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      c = await launchWith(tester, repo, metadataFixture());
      expect(find.text('Favorites'), findsOneWidget);
      expect(find.text('Wishlist'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-card-tmdb-movie-777')),
        findsOneWidget,
        reason: 'unavailable titles stay in the list',
      );
      expect(
        find.byKey(const ValueKey('home-card-tmdb-tv-55')),
        findsOneWidget,
      );
      await tapKey(tester, const ValueKey('home-card-tmdb-movie-777'));
      expect(location(c), '/home/title/movie/777');
      expect(find.bySemanticsLabel('Unfavorite'), findsOneWidget);
    },
  );

  testWidgets(
    'a saved title that a source starts offering becomes playable without saving again',
    (tester) async {
      final repo = LibraryRepo();
      repo.library['favorites']!.add({
        'list': 'favorites',
        'kind': 'movie',
        'tmdbId': 777,
        'title': 'Filme Externo',
        'key': 'tmdb:movie:777',
      });
      await launchWith(tester, repo, metadataFixture());
      await tapKey(tester, const ValueKey('home-card-tmdb-movie-777'));
      expect(find.byKey(const Key('details-unavailable')), findsOneWidget);
      // Synced later: the backend now resolves it (same library row).
      repo.catalogByTmdb['tmdb:movie:777'] = {
        ...item('x7', 'Filme Externo', 'movie'),
        'tmdbId': 777,
      };
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await launchWith(tester, repo, metadataFixture());
      await tapKey(tester, const ValueKey('home-card-x7'));
      expect(find.byKey(const Key('details-watch-on-tv')), findsOneWidget);
      expect(
        find.bySemanticsLabel('Unfavorite'),
        findsOneWidget,
        reason: 'recognized as the same saved title',
      );
      await tapKey(tester, const Key('details-watch-on-tv'));
      expect(
        tester.widget<WatchOnTvSheet>(find.byType(WatchOnTvSheet)).item.id,
        'x7',
      );
      expect(repo.library['favorites']!.length, 1);
    },
  );

  testWidgets(
    'series from IPTV: TMDB seasons apart from the episodes the source offers',
    (tester) async {
      final repo = LibraryRepo()
        ..recentSeries = [item('se1', 'Série Exemplo', 'series')];
      final metadata = metadataFixture()
        ..catalog['se1'] = const ContentMetadata(
          tmdbId: 55,
          seasonCount: 3,
          seasons: [
            SeasonInfo(1, 'Temporada 1', 8),
            SeasonInfo(2, 'Temporada 2', 6),
            SeasonInfo(3, 'Temporada 3', 6),
          ],
        );
      await launchWith(tester, repo, metadata);
      await tapKey(tester, const ValueKey('home-card-se1'));
      metadata.seasons['55/1'] = const [
        EpisodeInfo(
          number: 1,
          name: 'O começo',
          overview: 'Tudo começa.',
          runtimeMinutes: 52,
          still: 'https://image.tmdb.org/t/p/w300/e1.jpg',
        ),
        EpisodeInfo(number: 2, name: 'No meio'),
        EpisodeInfo(number: 3, name: 'Só no TMDB'),
      ];
      expect(find.text('Seasons'), findsOneWidget);
      // Playable series: only the seasons the source offers, Web buttons.
      expect(find.byKey(const ValueKey('details-season-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('details-season-3')), findsNothing);
      expect(
        tester
            .widget<DetailsButton>(
              find.byKey(const ValueKey('details-season-1')),
            )
            .icon,
        isNull,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('details-season-1'))).width,
        lessThan(200),
        reason: 'season buttons fit their label',
      );
      await fixtures.screenshot(tester, 'details/series-iptv-episodes');
      // While TMDB loads: card-shaped flat skeleton (no neumorphic surface).
      await tester.tap(find.byKey(const ValueKey('details-season-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(AppLoadingSkeleton), findsNothing);
      await tester.pumpAndSettle();
      // Full-height season sheet: frame, number, name, synopsis, runtime;
      // no TV choice, no "watch" nor "cancel" buttons.
      expect(find.text('Season 1 - Episode 1'), findsOneWidget);
      expect(find.text('O começo'), findsOneWidget);
      expect(find.text('Tudo começa.'), findsOneWidget);
      expect(find.text('52 min'), findsOneWidget);
      expect(find.text('Season 1 - Episode 2'), findsOneWidget);
      expect(
        find.text('Só no TMDB'),
        findsNothing,
        reason: 'not in the source',
      );
      expect(find.text('Choose a TV'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      expect(find.byKey(const Key('send-to-tv')), findsNothing);
      final frame = tester
          .widgetList<Image>(find.byType(Image))
          .map((i) => i.image)
          .whereType<NetworkImage>()
          .map((i) => i.url);
      expect(frame, contains('https://image.tmdb.org/t/p/w780/e1.jpg'));
      await fixtures.screenshot(tester, 'details/season-sheet');
      await tester.tap(find.text('No meio'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<WatchOnTvSheet>(find.byType(WatchOnTvSheet));
      expect([sheet.item.id, sheet.episodeId], ['se1', '3012']);
      expect(find.text('Choose the episode'), findsNothing);
    },
  );

  testWidgets(
    'long press on a card offers both lists without opening the page',
    (tester) async {
      final repo = LibraryRepo()
        ..recentMovies = [item('m1', 'Missão Fictícia', 'movie')];
      await launchWith(tester, repo, metadataFixture());
      await tester.longPress(find.byKey(const ValueKey('home-card-m1')));
      await tester.pumpAndSettle();
      await fixtures.screenshot(tester, 'details/library-actions');
      expect(find.text('Favorite'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        repo.mutationPayloads
            .lastWhere((m) => m.$1 == 'saveLibraryItem')
            .$2['list'],
        'wishlist',
      );
      expect(find.text('Remove'), findsOneWidget);
    },
  );

  testWidgets(
    'incomplete metadata: only what exists is shown; channel has no wishlist',
    (tester) async {
      final repo = LibraryRepo()
        ..recentMovies = [
          {
            ...item('m2', 'Filme Raro', 'movie', year: '1999'),
            'plot': 'Sinopse da fonte.',
          },
        ];
      await launchWith(tester, repo, FakeMetadata());
      await tapKey(tester, const ValueKey('home-card-m2'));
      expect(find.text('1999 | Filmes'), findsOneWidget);
      expect(find.text('Sinopse da fonte.'), findsOneWidget);
      for (final absent in ['Cast', 'Crew', 'Seasons']) {
        expect(find.text(absent), findsNothing);
      }
      expect(find.textContaining('Original title'), findsNothing);
      expect(find.textContaining('min'), findsNothing);
    },
  );

  testWidgets(
    'TMDB failure: retry offered; guest has no lists; kids cannot open people',
    (tester) async {
      final metadata = metadataFixture()..offline = true;
      final repo = LibraryRepo()
        ..recentMovies = [item('m1', 'Missão Fictícia', 'movie')];
      final c = await launchWith(tester, repo, metadata);
      c.read(routerProvider).push('/home/title/movie/777');
      await tester.pumpAndSettle();
      expect(
        find.text('Information about this title is unavailable right now.'),
        findsOneWidget,
      );
      metadata.offline = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Fora do IPTV.'), findsOneWidget);

      // availability lookup failure: shown as unavailable, saving still works.
      repo.resolveFailure = true;
      c.read(routerProvider).push('/home/title/series/55');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('details-unavailable')), findsOneWidget);
      expect(find.byKey(const Key('details-wishlist')), findsOneWidget);

      repo.profileJson = {
        'id': 'guest',
        'name': 'Visitante',
        'type': 'guest',
        'generations': {'favorites': 0},
      };
      c.read(routerProvider).go('/home');
      await tester.pumpAndSettle();
      c.invalidate(homeProvider);
      c.read(routerProvider).push('/home/title/movie/777');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('details-favorite')), findsNothing);

      repo.profileJson = {
        'id': 'k',
        'name': 'Lia',
        'type': 'kids',
        'generations': {'favorites': 0},
      };
      c.read(routerProvider).go('/home');
      await tester.pumpAndSettle();
      c.invalidate(homeProvider);
      await tester.pumpAndSettle();
      await tapKey(tester, const ValueKey('home-card-m1'));
      await tester.tap(find.byKey(const ValueKey('person-6384')));
      await tester.pumpAndSettle();
      expect(
        location(c),
        '/home/title',
        reason: 'kids profile: no editorial discovery',
      );
    },
  );

  test('home data: library keys recognize the same title by catalog id or TMDB identity', () {
    final data = HomeData.fromJson({
      'saved': {
        'favorites': ['m1', 'tmdb:movie:777'],
        'wishlist': ['tmdb:tv:777'],
      },
    });
    final editorialMovie = Entry('tmdb-movie-777', {
      'kind': 'movie',
      'tmdbId': 777,
    });
    final editorialSeries = Entry('tmdb-tv-777', {
      'kind': 'series',
      'tmdbId': 777,
    });
    final otherSource = Entry('zz', {
      'kind': 'movie',
      'sourceId': 's2',
      'tmdbId': 777,
    });
    expect(data.isSaved(LibraryList.favorites, editorialMovie), isTrue);
    expect(
      data.isSaved(LibraryList.favorites, otherSource),
      isTrue,
      reason: 'no duplicate across sources',
    );
    expect(
      data.isSaved(LibraryList.favorites, editorialSeries),
      isFalse,
      reason: 'movie 777 ≠ tv 777',
    );
    expect(data.isSaved(LibraryList.wishlist, editorialSeries), isTrue);
    expect(data.isSaved(LibraryList.wishlist, editorialMovie), isFalse);
    // Older backend (no library): favorites + my list, all catalog items.
    final legacy = HomeData.fromJson({
      'favorites': [
        {'id': 'c', 'kind': 'channel', 'title': 'C'},
      ],
      'myList': [
        {'id': 'm', 'kind': 'movie', 'title': 'M'},
      ],
      'favoriteIds': ['c', 'm'],
    });
    expect(legacy.libraryFavorites.map((e) => e.id), ['c', 'm']);
    expect(
      legacy.isSaved(LibraryList.favorites, Entry('m', {'kind': 'movie'})),
      isTrue,
    );
  });

  testWidgets(
    'title in progress offers Continue and Start over (same episode)',
    (tester) async {
      final series = item('se1', 'Série Exemplo', 'series');
      final repo = LibraryRepo()
        ..recentSeries = [
          {
            ...series,
            'progress': {'position': 10, 'duration': 100},
            'episodeId': '3012',
          },
        ];
      await launchWith(tester, repo, metadataFixture());
      await tapKey(tester, const ValueKey('home-card-se1'));
      expect(find.text('Continue'), findsOneWidget);
      expect(find.bySemanticsLabel('Start over'), findsOneWidget);
      expect(find.byKey(const Key('details-watch-on-tv')), findsNothing);
      await tapKey(tester, const Key('details-restart'));
      var sheet = tester.widget<WatchOnTvSheet>(find.byType(WatchOnTvSheet));
      expect([sheet.resume, sheet.episodeId], [false, '3012']);
      Navigator.of(tester.element(find.byType(WatchOnTvSheet))).pop();
      await tester.pumpAndSettle();
      await tapKey(tester, const Key('details-continue'));
      sheet = tester.widget<WatchOnTvSheet>(find.byType(WatchOnTvSheet));
      expect([sheet.resume, sheet.episodeId], [true, '3012']);
      Navigator.of(tester.element(find.byType(WatchOnTvSheet))).pop();
      await tester.pumpAndSettle();
      final cont = tester.getRect(find.byKey(const Key('details-continue')));
      final restart = tester.getRect(find.byKey(const Key('details-restart')));
      expect(cont.top, restart.top, reason: 'same row');
      expect(restart.width, 48, reason: 'icon only, fit width');
      expect(cont.width, greaterThan(200));
      expect(
        tester
            .widget<DetailsButton>(find.byKey(const Key('details-restart')))
            .icon,
        isNotNull,
      );
      expect(
        tester
            .widget<DetailsButton>(find.byKey(const Key('details-continue')))
            .primary,
        isTrue,
      );
      expect(
        tester
            .widget<DetailsButton>(find.byKey(const Key('details-restart')))
            .primary,
        isFalse,
      );
    },
  );

  testWidgets(
    'background: TMDB poster when there is one, otherwise the source art',
    (tester) async {
      final repo = LibraryRepo()
        ..recentMovies = [
          item(
            'm1',
            'Missão Fictícia',
            'movie',
            imageRef: 'https://img.example.com/m1.jpg',
          ),
          item(
            'm3',
            'Sem TMDB',
            'movie',
            imageRef: 'https://img.example.com/m3.jpg',
          ),
        ];
      await launchWith(tester, repo, metadataFixture());
      await tapKey(tester, const ValueKey('home-card-m1'));
      expect(find.byKey(const Key('details-cover')), findsOneWidget);
      await tapKey(tester, const Key('details-back'));
      await tapKey(tester, const ValueKey('home-card-m3'));
      expect(find.byKey(const Key('details-cover')), findsNothing);
      final urls = [
        for (final image in tester.widgetList<Image>(find.byType(Image)))
          if (image.image is NetworkImage) (image.image as NetworkImage).url,
      ];
      expect(urls, contains('https://img.example.com/m3.jpg'));
    },
  );

  testWidgets('page skeleton until metadata and availability are loaded', (
    tester,
  ) async {
    final metadata = metadataFixture()..pendingTitle = Completer<void>();
    final repo = LibraryRepo();
    final c = await launchWith(tester, repo, metadata);
    c.read(routerProvider).push('/home/title/movie/777');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('details-skeleton')), findsOneWidget);
    expect(find.byKey(const Key('details-title')), findsNothing);
    expect(find.byKey(const Key('details-back')), findsOneWidget);
    expect(
      find.byType(AppLoadingSkeleton),
      findsNothing,
      reason: 'flat, not neumorphic',
    );
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    await fixtures.screenshot(tester, 'details/skeleton');
    tester.view.physicalSize = const Size(390, 2400);
    metadata.pendingTitle!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('details-skeleton')), findsNothing);
    expect(find.text('Fora do IPTV.'), findsOneWidget);
    expect(find.byKey(const Key('details-unavailable')), findsOneWidget);
  });
}
