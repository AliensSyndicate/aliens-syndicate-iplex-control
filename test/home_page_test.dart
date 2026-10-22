import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/app/bottom_navigation.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/home/home_widgets.dart';
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
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-card-m1')),
          matching: find.byType(LinearProgressIndicator),
        ),
        findsOneWidget,
      );
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

  testWidgets(
    'Continue watching uses the same poster cards as the other rows',
    (tester) async {
      await navigation.launch(
        tester,
        repoWith({
          'profile': profile,
          'continueWatching': [
            item(
              'm1',
              'Missão Fictícia',
              'movie',
              progress: {'position': 30, 'duration': 100},
            ),
          ],
          'recentMovies': [item('r1', 'Filme Novo', 'movie')],
        }),
      );
      tester.view.physicalSize = const Size(390, 2400);
      await tester.pumpAndSettle();
      Size art(String id) => tester.getSize(
        find.descendant(
          of: find.byKey(ValueKey('home-card-$id')).first,
          matching: find.byType(Artwork),
        ),
      );
      expect(art('m1'), art('r1'));
      expect(art('m1').height / art('m1').width, closeTo(1.5, 0.01));
    },
  );

  testWidgets('"See all" on every section opens the whole list', (
    tester,
  ) async {
    final repo = repoWith({
      'profile': profile,
      'library': {
        'favorites': [
          for (var i = 0; i < 12; i++) item('f$i', 'Favorito $i', 'movie'),
        ],
        'wishlist': [item('w1', 'Desejo', 'movie')],
      },
      'recentMovies': [item('r1', 'Filme Novo', 'movie')],
    });
    final c = await navigation.launch(tester, repo);
    tester.view.physicalSize = const Size(390, 2400);
    await tester.pumpAndSettle();
    for (final title in ['Favorites', 'Wishlist', 'Recently added movies']) {
      final link = find.byKey(ValueKey('home-see-all-$title'));
      expect(link, findsOneWidget);
      expect(
        tester.getTopRight(link).dx,
        greaterThan(tester.getTopRight(find.text(title)).dx),
        reason: 'at the end of the section title row',
      );
    }
    final row = tester.widget<ListView>(
      find.byKey(const PageStorageKey('home-row-Favorites')),
    );
    expect(
      (row.childrenDelegate as SliverChildBuilderDelegate).childCount,
      19,
      reason: 'the Home shows the first 10',
    );
    await tester.tap(find.byKey(const ValueKey('home-see-all-Favorites')));
    await tester.pumpAndSettle();
    expect(c.read(routerProvider).state.uri.path, '/home/section/favorites');
    expect(
      repo.mutationPayloads.lastWhere((m) => m.$1 == 'readHome').$2['section'],
      'favorites',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('home-section-grid')),
        matching: find.byType(HomeCard),
      ),
      findsNWidgets(12),
    );
    await tester.tap(find.byKey(const ValueKey('home-card-f11')));
    await tester.pumpAndSettle();
    expect(c.read(routerProvider).state.uri.path, '/home/title');
  });

  testWidgets(
    'now playing bar: floating above the menu, Home only, opens the title',
    (tester) async {
      final repo = repoWith({
        'profile': profile,
        'continueWatching': [
          item(
            'm1',
            'Missão Fictícia',
            'movie',
            progress: {'position': 30, 'duration': 100},
          ),
        ],
      });
      final c = await navigation.launch(tester, repo);
      final bar = find.byKey(const Key('now-playing-bar'));
      expect(bar, findsOneWidget);
      expect(
        find.descendant(of: bar, matching: find.text('Missão Fictícia')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('now-playing-progress')), findsOneWidget);
      expect(find.byKey(const Key('now-playing-subtitle')), findsNothing);
      // Floating: side margins and above the main menu.
      final rect = tester.getRect(bar);
      expect(rect.left, 16);
      expect(rect.right, 390 - 16);
      expect(
        rect.bottom,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(BottomNavigation)).dy),
      );
      // Only on the Home.
      c.read(routerProvider).go('/devices');
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
      c.read(routerProvider).go('/home');
      await tester.pumpAndSettle();
      // No icon on the right; tapping the bar opens the title.
      expect(find.byKey(const Key('now-playing-tv')), findsNothing);
      expect(
        find.descendant(of: bar, matching: find.byType(AppIcon)),
        findsNothing,
      );
      await tester.tap(bar);
      await tester.pumpAndSettle();
      expect(c.read(routerProvider).state.uri.path, '/home/title');
    },
  );

  testWidgets('now playing bar: channel shows the name only, no progress', (
    tester,
  ) async {
    await navigation.launch(
      tester,
      repoWith({
        'profile': profile,
        'library': {
          'favorites': [item('ch1', 'Canal Notícias', 'channel')],
        },
      }),
    );
    final bar = find.byKey(const Key('now-playing-bar'));
    expect(
      find.descendant(of: bar, matching: find.text('Canal Notícias')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('now-playing-progress')), findsNothing);
    expect(find.byKey(const Key('now-playing-subtitle')), findsNothing);
  });

  testWidgets(
    'now playing bar: progress under the name, 2:3 poster, track without progress',
    (tester) async {
      await navigation.launch(
        tester,
        repoWith({
          'profile': profile,
          'recentMovies': [item('r1', 'Filme Novo', 'movie')],
        }),
      );
      final track = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('now-playing-progress')),
      );
      expect(track.value, 0);
      // Under the name on the card base, aligned with the poster bottom
      // (never under the poster); 2:3 poster.
      final art = tester.getRect(find.byKey(const Key('now-playing-art')));
      final line = tester.getRect(
        find.byKey(const Key('now-playing-progress')),
      );
      final name = tester.getRect(find.byKey(const Key('now-playing-title')));
      expect(line.left, greaterThan(art.right));
      expect(line.top, greaterThan(name.bottom));
      expect(
        line.bottom,
        art.bottom,
        reason: 'on the base, aligned with the poster',
      );
      expect(line.height, 3);
      expect(art.height / art.width, closeTo(1.5, 0.01));
    },
  );
}
