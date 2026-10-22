import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:flutter/material.dart';
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
        'library': {
          'favorites': [item('ch1', 'Canal Notícias', 'channel')],
          'wishlist': [
            for (var i = 0; i < 12; i++) item('l$i', 'Título $i', 'movie'),
          ],
        },
        'recentMovies': [item('r1', 'Filme Novo', 'movie')],
        'recentSeries': [item('r2', 'Série Nova', 'series')],
      });
      await navigation.launch(tester, repo);
      tester.view.physicalSize = const Size(390, 2400);
      await tester.pumpAndSettle();
      final titles = [
        'Favorites',
        'Continue watching',
        'Wishlist',
        'Recently added movies',
        'Recently added series',
      ];
      final ys = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
      expect(ys, [...ys]..sort(), reason: 'fixed section order');
      final myList = tester.widget<ListView>(
        find.byKey(const PageStorageKey('home-row-Wishlist')),
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
      'Wishlist',
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
