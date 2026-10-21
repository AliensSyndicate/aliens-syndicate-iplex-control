import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/home/content_details_sheet.dart';
import 'package:aliens_syndicate_iplex_control/features/home/home_data.dart';
import 'package:aliens_syndicate_iplex_control/features/home/metadata_service.dart';
import 'package:aliens_syndicate_iplex_control/features/watch_on_tv/watch_on_tv_sheet.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'navigation_test.dart' as navigation;
import 'widget_test.dart' as fixtures;

Map<String, dynamic> item(
  String id,
  String title,
  String kind, {
  String source = 's',
  Map<String, dynamic>? progress,
  String? episodeId,
  String? imageRef,
  String? epgId,
  String? year,
}) => {
  'id': id,
  'title': title,
  'kind': kind,
  'sourceId': source,
  'sourceName': 'Minha IPTV',
  'providerRef': id,
  'category': kind == 'channel' ? 'Notícias' : 'Filmes',
  'progress': ?progress,
  'episodeId': ?episodeId,
  'imageRef': ?imageRef,
  'epgId': ?epgId,
  'year': ?year,
};

const profile = {
  'id': 'admin',
  'name': 'Account',
  'type': 'admin',
  'generations': {'favorites': 2},
};

navigation.SessionRepository repoWith(Map<String, dynamic> home) =>
    navigation.SessionRepository(uid: 'u', linked: true)
      ..sources = [
        Entry('s', {'name': 'Minha IPTV', 'version': 'v', 'status': 'ready'}),
      ]
      ..home = home;

/// Sheet host with its own overrides (metadata, repository).
class _SheetRepo extends fixtures.TestRepository {
  _SheetRepo() : super(signedIn: true);
  final payloads = <(String, Map<String, dynamic>)>[];
  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    payloads.add((action, Map.of(payload)));
    if (action == 'readSourceEpg') {
      final now = DateTime.now().millisecondsSinceEpoch;
      return {
        'programmes': [
          {
            'title': 'Jornal da Manhã',
            'startAt': now - 600000,
            'endAt': now + 600000,
          },
          {
            'title': 'Esporte Total',
            'startAt': now + 600000,
            'endAt': now + 4200000,
          },
        ],
      };
    }
    return {};
  }
}

class _Metadata implements MetadataService {
  _Metadata(this.value);
  final ContentMetadata? value;
  @override
  Future<ContentMetadata?> summary(Entry item) async => value;
  @override
  Future<ContentMetadata?> details(Entry item) async => value;
}

Future<_SheetRepo> _openSheet(
  WidgetTester tester,
  Map<String, dynamic> data, {
  HomeProfile? profile = const HomeProfile('admin', 'Account', 'admin', 2),
  bool favorite = false,
  ContentMetadata? metadata,
}) async {
  tester.view.physicalSize = const Size(390, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _SheetRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        metadataServiceProvider.overrideWithValue(_Metadata(metadata)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showContentDetails(
                context,
                item: Entry(data['id'] as String, data),
                profile: profile,
                favorite: favorite,
                onLibraryChanged: () {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  setUpAll(fixtures.loadTestFont);
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  testWidgets(
    'all rows, in order, only with real content; at most 10 cards per row',
    (tester) async {
      final repo = repoWith({
        'profile': profile,
        'favorites': [item('ch1', 'Canal Notícias', 'channel')],
        'continueWatching': [
          item(
            'm1',
            'Missão Fictícia',
            'movie',
            progress: {'position': 30, 'duration': 100},
          ),
        ],
        'myList': [
          for (var i = 0; i < 12; i++) item('l$i', 'Título $i', 'movie'),
        ],
        'recentMovies': [item('r1', 'Filme Novo', 'movie')],
        'recentSeries': [item('r2', 'Série Nova', 'series')],
      });
      await navigation.launch(tester, repo);
      tester.view.physicalSize = const Size(390, 2400);
      await tester.pumpAndSettle();
      final titles = [
        'Favorites',
        'Continue watching',
        'My list',
        'Recently added movies',
        'Recently added series',
      ];
      final ys = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
      expect(ys, [...ys]..sort(), reason: 'fixed section order');
      final myList = tester.widget<ListView>(
        find.byKey(const PageStorageKey('home-row-My list')),
      );
      expect(
        (myList.childrenDelegate as SliverChildBuilderDelegate).childCount,
        19,
        reason: '10 cards + 9 separators',
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Your Home is still empty'), findsNothing);
      expect(
        repo.mutationPayloads
            .firstWhere((m) => m.$1 == 'readHome')
            .$2['sourceId'],
        's',
      );
    },
  );

  testWidgets('rows without content are not shown (no empty cards)', (
    tester,
  ) async {
    await navigation.launch(
      tester,
      repoWith({
        'profile': profile,
        'recentMovies': [item('r1', 'Filme Novo', 'movie')],
      }),
    );
    expect(find.text('Recently added movies'), findsOneWidget);
    for (final t in [
      'Favorites',
      'Continue watching',
      'My list',
      'Recently added series',
    ]) {
      expect(find.text(t), findsNothing);
    }
  });

  testWidgets('cards: source artwork when published, initials otherwise', (
    tester,
  ) async {
    await navigation.launch(
      tester,
      repoWith({
        'recentMovies': [
          item(
            'a',
            'Com Capa',
            'movie',
            imageRef: 'https://img.example.com/a.jpg',
          ),
          item('b', 'Sem Capa', 'movie'),
        ],
      }),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-card-a')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-card-b')),
        matching: find.text('SC'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'IPTV selector: all sources with state; choosing one reloads rows and is remembered',
    (tester) async {
      final repo = repoWith({})
        ..sources = [
          Entry('s1', {'name': 'Fonte A', 'version': 'v1', 'status': 'ready'}),
          Entry('s2', {'name': 'Fonte B', 'version': 'v2', 'status': 'ready'}),
          Entry('s3', {'name': 'Fonte C', 'status': 'error'}),
        ];
      await navigation.launch(tester, repo);
      expect(repo.mutationPayloads.last.$2['sourceId'], 's1');
      await tester.tap(find.byKey(const Key('home-source-picker')));
      await tester.pumpAndSettle();
      for (final name in ['Fonte A', 'Fonte B', 'Fonte C']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.textContaining('Selected'), findsOneWidget);
      await tester.tap(find.text('Fonte C'));
      await tester.pumpAndSettle();
      expect(
        find.text('Fonte C'),
        findsOneWidget,
        reason: 'a source without catalog cannot be selected',
      );
      await tester.tap(find.text('Fonte B'));
      await tester.pumpAndSettle();
      expect(repo.mutationPayloads.last.$1, 'readHome');
      expect(repo.mutationPayloads.last.$2, {'sourceId': 's2'});
      expect(
        await SharedPreferencesAsync().getString('iplex.home.source.u.family'),
        's2',
      );
    },
  );

  testWidgets('remembered source is used when the app opens again', (
    tester,
  ) async {
    await SharedPreferencesAsync().setString(
      'iplex.home.source.u.family',
      's2',
    );
    final repo = repoWith({})
      ..sources = [
        Entry('s1', {'name': 'Fonte A', 'version': 'v1'}),
        Entry('s2', {'name': 'Fonte B', 'version': 'v2'}),
      ];
    await navigation.launch(tester, repo);
    expect(
      repo.mutationPayloads.lastWhere((m) => m.$1 == 'readHome').$2['sourceId'],
      's2',
    );
  });

  testWidgets('search failure is explicit and can be retried', (tester) async {
    final repo = repoWith({})..catalogFailure = true;
    await navigation.launch(tester, repo);
    await tester.enterText(find.byType(TextFormField), 'avail');
    await tester.pump(const Duration(milliseconds: 351));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    repo.catalogFailure = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Available title'), findsOneWidget);
  });

  testWidgets('QR code lives on Account, not on Home', (tester) async {
    final container = await navigation.launch(tester, repoWith({}));
    expect(find.byKey(const Key('account-public-code')), findsNothing);
    container.read(routerProvider).go('/account');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-public-code')), findsOneWidget);
  });

  testWidgets('movie sheet: TMDB details, synopsis, cast and list actions', (
    tester,
  ) async {
    final repo = await _openSheet(
      tester,
      item('m1', 'Missão Fictícia', 'movie', year: '2021'),
      metadata: const ContentMetadata(
        overview: 'Uma missão.',
        genres: ['Ação', 'Drama'],
        year: 2021,
        runtimeMinutes: 118,
        certification: '14',
        cast: ['Ana', 'Rui'],
      ),
    );
    expect(find.text('Missão Fictícia'), findsOneWidget);
    expect(find.text('2021 | Ação | 1h 58min'), findsOneWidget);
    expect(find.byKey(const Key('details-stars')), findsNothing);
    expect(find.byKey(const Key('details-watch-on-tv')), findsOneWidget);
    expect(find.text('Rated 14'), findsOneWidget);
    expect(find.text('Ação, Drama'), findsOneWidget);
    expect(find.text('Filmes'), findsOneWidget);
    expect(find.text('Minha IPTV'), findsNothing);
    expect(find.text('Uma missão.'), findsOneWidget);
    expect(find.text('Cast: Ana, Rui'), findsOneWidget);
    expect(find.byKey(const Key('details-continue')), findsNothing);
    await tester.tap(find.text('Add to My list'));
    await tester.pumpAndSettle();
    expect(repo.payloads.last.$1, 'favorite');
    expect(repo.payloads.last.$2, {
      'profileId': 'admin',
      'contentId': 'm1',
      'title': 'Missão Fictícia',
      'generation': 2,
    });
    expect(find.text('Remove from My list'), findsOneWidget);
  });

  testWidgets('dragging the full-screen sheet down closes it', (tester) async {
    await _openSheet(tester, item('m1', 'Missão Fictícia', 'movie'));
    expect(find.byKey(const Key('details-watch-on-tv')), findsOneWidget);
    await tester.drag(find.text('Missão Fictícia'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('details-watch-on-tv')), findsNothing);
  });

  testWidgets('movie without a TMDB match keeps source data only', (
    tester,
  ) async {
    await _openSheet(tester, {
      ...item('m2', 'Filme Raro', 'movie', year: '1999'),
      'plot': 'Sinopse da fonte.',
    });
    expect(find.text('1999 | Filmes'), findsOneWidget);
    expect(find.text('Sinopse da fonte.'), findsOneWidget);
    expect(find.textContaining('Cast'), findsNothing);
    expect(find.textContaining('min'), findsNothing);
  });

  testWidgets(
    'series sheet: seasons; "continue" opens Watch on TV with resume and episode',
    (tester) async {
      await _openSheet(
        tester,
        item(
          'se1',
          'Série Exemplo',
          'series',
          progress: {'position': 10, 'duration': 100},
          episodeId: '3011',
        ),
        metadata: const ContentMetadata(seasonCount: 2, genres: ['Drama']),
      );
      expect(find.textContaining('2 seasons'), findsOneWidget);
      await tester.tap(find.byKey(const Key('details-continue')));
      await tester.pumpAndSettle();
      final sheet = tester.widget<WatchOnTvSheet>(find.byType(WatchOnTvSheet));
      expect(
        [sheet.resume, sheet.episodeId, sheet.item.id],
        [true, '3011', 'se1'],
      );
    },
  );

  testWidgets(
    'channel sheet: live info and guide, no invented runtime or cast',
    (tester) async {
      final repo = await _openSheet(
        tester,
        item('ch1', 'Canal Notícias', 'channel', epgId: 'news.br'),
      );
      expect(find.textContaining('Live channel'), findsOneWidget);
      expect(find.textContaining('Now · '), findsOneWidget);
      expect(find.textContaining('Jornal da Manhã'), findsOneWidget);
      expect(find.textContaining('Up next · '), findsOneWidget);
      expect(find.textContaining('min'), findsNothing);
      expect(find.textContaining('Cast'), findsNothing);
      expect(repo.payloads.first.$1, 'readSourceEpg');
      expect(repo.payloads.first.$2, {'id': 's', 'channelId': 'news.br'});
      expect(find.text('Add to favorites'), findsOneWidget);
    },
  );

  testWidgets('guest or missing profile: no list actions, Watch on TV only', (
    tester,
  ) async {
    await _openSheet(
      tester,
      item('m1', 'Missão', 'movie'),
      profile: const HomeProfile('guest', 'Visitante', 'guest', 0),
    );
    expect(find.byKey(const Key('details-watch-on-tv')), findsOneWidget);
    expect(find.text('Add to My list'), findsNothing);
  });

  testWidgets(
    'a title opened from another row still offers "continue" when it has progress',
    (tester) async {
      final series = item('se1', 'Série Exemplo', 'series');
      await navigation.launch(
        tester,
        repoWith({
          'profile': profile,
          'continueWatching': [
            {
              ...series,
              'progress': {'position': 10, 'duration': 100},
              'episodeId': '3011',
            },
          ],
          'recentSeries': [series],
        }),
      );
      tester.view.physicalSize = const Size(390, 2400);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-card-se1')).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('details-continue')), findsOneWidget);
    },
  );
}
