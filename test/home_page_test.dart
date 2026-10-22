import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/home/home_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'navigation_test.dart' as navigation;
import 'support/now_playing_fixture.dart';
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
      // Continue watching: the app progress bar, 8 px with an 8 px margin
      // inside the poster.
      final cardBar = find.descendant(
        of: find.byKey(const ValueKey('home-card-m1')),
        matching: find.byType(AppProgressBar),
      );
      expect(cardBar, findsOneWidget);
      final bar = tester.widget<AppProgressBar>(cardBar);
      expect([bar.height, bar.margin], [8, const EdgeInsets.all(8)]);
      final poster = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('home-card-m1')),
          matching: find.byType(Artwork),
        ),
      );
      final line = tester.getRect(
        find.descendant(
          of: cardBar,
          matching: find.byType(LinearProgressIndicator),
        ),
      );
      expect(line.height, 8);
      expect(line.left - poster.left, 8);
      expect(poster.right - line.right, 8);
      expect(poster.bottom - line.bottom, 8);
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
      // The current source is the selected card (white border).
      expect(
        tester
            .widget<NeumorphicListTile>(
              find.byKey(const ValueKey('source-option-s1')),
            )
            .selected,
        isTrue,
      );
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

  testWidgets(
    'IPTV selector: no icons, 4px circular status dot, 20px padding, inverted colors on selected',
    (tester) async {
      final repo = repoWith({})
        ..sources = [
          Entry('s1', {
            'name': 'Fonte Online',
            'version': 'v1',
            'status': 'ready',
          }),
          Entry('s2', {'name': 'Fonte Offline', 'status': 'error'}),
          Entry('s3', {
            'name': 'Fonte Desligada',
            'status': 'ready',
            'enabled': false,
          }),
        ];
      await navigation.launch(tester, repo);
      await tester.tap(find.byKey(const Key('home-source-picker')));
      await tester.pumpAndSettle();

      final sheet = find.byType(AppModalSheet);
      // The app list card: one per source, 20 padding, state indicator.
      final cards = find.descendant(
        of: sheet,
        matching: find.byType(NeumorphicListTile),
      );
      expect(cards, findsNWidgets(3));
      expect(
        find.descendant(
          of: sheet,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Padding &&
                w.padding == const EdgeInsets.all(AppSpacing.card),
          ),
        ),
        findsNWidgets(3),
      );
      final states = tester
          .widgetList<NeumorphicStatusIndicator>(
            find.descendant(
              of: sheet,
              matching: find.byType(NeumorphicStatusIndicator),
            ),
          )
          .map((d) => d.status)
          .toList();
      expect(states, [
        IndicatorStatus.online,
        IndicatorStatus.error,
        IndicatorStatus.offline,
      ]);

      // Selected (s1): white border; the others: no border.
      ShapeBorder? shape(String id) => tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byKey(ValueKey(id)),
                  matching: find.byType(Material),
                )
                .first,
          )
          .shape;
      expect(
        (shape('source-option-s1')! as RoundedRectangleBorder).side.color,
        AppColors.textPrimary,
      );
      expect(
        (shape('source-option-s2')! as RoundedRectangleBorder).side,
        BorderSide.none,
      );
      expect(
        tester.widget<Text>(find.text('Fonte Online')).style?.color,
        AppColors.textPrimary,
      );
      await fixtures.screenshot(tester, 'source-sheet');
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
    final c = await navigation.launch(tester, repo);
    c.read(routerProvider).go('/search');
    await tester.pumpAndSettle();
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
      final seeAllText = tester.widget<Text>(
        find.descendant(of: link, matching: find.byType(Text)),
      );
      expect(seeAllText.style?.color, Colors.white);
      expect(
        find.descendant(of: link, matching: find.byType(Icon)),
        findsNothing,
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
    // One screen for every category: tabs, opening on the tapped one.
    expect(find.byKey(const Key('home-section-tabs')), findsOneWidget);
    for (final t in ['Favorites', 'Wishlist', 'Recently added movies']) {
      expect(
        find.descendant(
          of: find.byKey(const Key('home-section-tabs')),
          matching: find.text(t),
        ),
        findsOneWidget,
      );
    }
    // Two per row; titles in the 2:3 poster aspect.
    final a = tester.getRect(find.byKey(const ValueKey('home-card-f0')));
    final b = tester.getRect(find.byKey(const ValueKey('home-card-f1')));
    final c2 = tester.getRect(find.byKey(const ValueKey('home-card-f2')));
    expect(a.top, b.top);
    expect(c2.top, greaterThan(a.bottom));
    expect(a.left, 24);
    expect(b.right, closeTo(390 - 24, 0.5));
    final poster = tester.getSize(
      find.descendant(
        of: find.byKey(const ValueKey('home-card-f0')),
        matching: find.byType(Artwork),
      ),
    );
    expect(poster.height / poster.width, closeTo(1.5, 0.01));
    await tester.tap(find.byKey(const ValueKey('home-card-f11')));
    await tester.pumpAndSettle();
    expect(c.read(routerProvider).state.uri.path, '/home/title');
  });

  testWidgets(
    'now playing item: top of the Home, standard background, opens the title',
    (tester) async {
      final repo =
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
            })
            ..devices = [
              tvPlaying(
                itemId: 'm1',
                title: 'Missão Fictícia',
                position: 30,
                duration: 100,
              ),
            ];
      final c = await navigation.launch(tester, repo);
      final bar = find.byKey(const Key('now-playing-bar'));
      expect(bar, findsOneWidget);
      expect(
        find.descendant(of: bar, matching: find.text('Missão Fictícia')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('now-playing-progress')), findsOneWidget);
      // Kind and runtime of what is playing (100 s ≈ 2 min).
      expect(find.text('Movie · 2 min'), findsOneWidget);
      // Top of the Home: between the tabs and "Continue watching", on the
      // screen background.
      final rect = tester.getRect(bar);
      expect(
        rect.top,
        greaterThan(tester.getRect(find.byKey(const Key('home-tabs'))).bottom),
      );
      expect(
        rect.bottom,
        lessThan(tester.getTopLeft(find.text('Continue watching')).dy),
      );
      expect(find.text('Now playing'), findsOneWidget);
      expect(
        (tester.widget<Container>(bar).decoration as BoxDecoration?)?.color,
        isNull,
      );
      // Progress in solid white with translucent track.
      // The app progress bar: 8 px, no margin, white on translucent track.
      final track = tester.widget<AppProgressBar>(
        find.byKey(const Key('now-playing-progress')),
      );
      expect(
        [track.color, track.trackColor, track.height, track.margin],
        [Colors.white, const Color(0x33FFFFFF), 8, EdgeInsets.zero],
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

  testWidgets(
    'now playing item: channel shows its name and "Live", no progress',
    (tester) async {
      await navigation.launch(
        tester,
        repoWith({
            'profile': profile,
            'library': {
              'favorites': [item('ch1', 'Canal Notícias', 'channel')],
            },
          })
          ..devices = [
            tvPlaying(itemId: 'ch1', title: 'Canal Notícias', kind: 'channel'),
          ],
      );
      final bar = find.byKey(const Key('now-playing-bar'));
      expect(
        find.descendant(of: bar, matching: find.text('Canal Notícias')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('now-playing-progress')), findsNothing);
      // Channels: kind only (no runtime, no progress).
      expect(find.text('Live'), findsWidgets);
      expect(
        tester.widget<Text>(find.byKey(const Key('now-playing-subtitle'))).data,
        'Live',
      );
    },
  );

  testWidgets(
    'now playing header: progress under the name, backdrop background, track without progress',
    (tester) async {
      await navigation.launch(
        tester,
        repoWith({
          'profile': profile,
          'recentMovies': [item('r1', 'Filme Novo', 'movie')],
        })..devices = [tvPlaying(itemId: 'r1', title: 'Filme Novo')],
      );
      final track = tester.widget<AppProgressBar>(
        find.byKey(const Key('now-playing-progress')),
      );
      expect(track.value, 0);
      // Under the name, track height 8, backdrop covers the header.
      final art = tester.getRect(find.byKey(const Key('now-playing-art')));
      final line = tester.getRect(
        find.byKey(const Key('now-playing-progress')),
      );
      final name = tester.getRect(find.byKey(const Key('now-playing-title')));
      expect(line.top, greaterThan(name.bottom));
      expect(line.height, 8);
      expect(art.top, lessThanOrEqualTo(name.top));
      expect(art.bottom, greaterThanOrEqualTo(line.bottom));
    },
  );

  testWidgets('"See all": channels square, switching categories in place', (
    tester,
  ) async {
    final repo = repoWith({
      'profile': profile,
      'library': {
        'favorites': [item('ch1', 'Canal Notícias', 'channel')],
        'wishlist': [item('w1', 'Desejo', 'movie')],
      },
    });
    final c = await navigation.launch(tester, repo);
    tester.view.physicalSize = const Size(390, 2400);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-see-all-Favorites')));
    await tester.pumpAndSettle();
    final tile = tester.getSize(
      find.descendant(
        of: find.byKey(const ValueKey('home-card-ch1')),
        matching: find.byType(Artwork),
      ),
    );
    expect(tile.width, tile.height, reason: 'channels: square');
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('home-section-tabs')),
        matching: find.text('Wishlist'),
      ),
    );
    await tester.pumpAndSettle();
    expect(c.read(routerProvider).state.uri.path, '/home/section/favorites');
    expect(
      repo.mutationPayloads.lastWhere((m) => m.$1 == 'readHome').$2['section'],
      'wishlist',
    );
    expect(find.byKey(const ValueKey('home-card-w1')), findsWidgets);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await fixtures.screenshot(tester, 'see-all');
  });
}
