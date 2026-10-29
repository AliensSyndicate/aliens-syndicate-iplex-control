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
import 'support/catalog_sets_fixture.dart';
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
  catalogFeedTests();
  floatingBarTests();
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
        'releases': [
          item('r1', 'Filme Novo', 'movie'),
          item('r2', 'Série Nova', 'series'),
        ],
        'watched': [item('h1', 'Já Visto', 'movie')],
        'recentSearches': [item('s1', 'Buscado', 'movie')],
      });
      await navigation.launch(tester, repo);
      tester.view.physicalSize = const Size(390, 2600);
      await tester.pumpAndSettle();
      // Same rule as the TV "Meu iPlex".
      final titles = [
        'Continue watching',
        'Favorites',
        'Wishlist',
        'New releases',
        'Watched',
      ];
      final ys = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
      expect(ys, [...ys]..sort(), reason: 'fixed section order');
      expect(find.text('Recently searched'), findsNothing);
      expect(find.text('Recently added movies'), findsNothing);
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
    expect(find.text('New releases'), findsOneWidget);
    for (final t in [
      'Favorites',
      'Continue watching',
      'Wishlist',
      'Watched',
      'Recently added movies',
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
    // The TMDB lookup of a card starts after a short moment on screen.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
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
      expect(
        repo.mutationPayloads
            .lastWhere((m) => m.$1 == 'readHome')
            .$2['sourceId'],
        's1',
      );
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
      expect(repo.mutationPayloads.lastWhere((m) => m.$1 == 'readHome').$2, {
        'sourceId': 's2',
      });
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
    'Meu iPlex layout (same as the TV): 16:9 Continuar and Favoritos, square channels, posters elsewhere, featured release on top',
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
          'library': {
            'favorites': [
              item('ch1', 'Canal Notícias', 'channel'),
              item('f1', 'Favorito', 'movie'),
            ],
            'wishlist': [],
          },
          'recentMovies': [item('r1', 'Filme Novo', 'movie')],
        }),
      );
      tester.view.physicalSize = const Size(390, 3000);
      await tester.pumpAndSettle();
      Size art(String id) => tester.getSize(
        find.descendant(
          of: find.byKey(ValueKey('home-card-$id')).first,
          matching: find.byType(Artwork),
        ),
      );
      expect(art('m1').width / art('m1').height, closeTo(16 / 9, 0.01));
      expect(art('f1'), art('m1'));
      expect(art('ch1').width, art('ch1').height, reason: 'channels: square');
      expect(art('r1').height / art('r1').width, closeTo(1.5, 0.01));
      // Featured release: portrait art up to the status bar, title and the
      // primary "See details"; no greeting or label.
      final hero = find.byKey(const Key('home-hero'));
      expect(hero, findsOneWidget);
      expect(tester.getTopLeft(hero).dy, 0);
      final heroSize = tester.getSize(hero);
      expect(heroSize.height / heroSize.width, closeTo(16 / 9, 0.01));
      expect(find.text('Featured release'), findsNothing);
      expect(find.textContaining('Hi, '), findsNothing);
      expect(find.byKey(const Key('home-hero-title')), findsOneWidget);
      // "Ver detalhes" and "Assistir na TV" in the featured release: icons
      // only.
      for (final key in ['home-hero-open', 'home-hero-tv']) {
        expect(find.byKey(Key(key)), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(Text),
          ),
          findsNothing,
          reason: key,
        );
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.width, size.height, reason: '$key: round, 1:1');
      }
      // "Assistir" (on this phone) is the white main button; then details.
      expect(
        tester
            .widget<AppButton>(find.byKey(const Key('home-hero-play')))
            .primary,
        isTrue,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('home-hero'))).dy,
        lessThan(tester.getTopLeft(find.text('Continue watching')).dy),
      );
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
    for (final title in ['Favorites', 'Wishlist', 'New releases']) {
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
    for (final t in ['Favorites', 'Wishlist', 'New releases']) {
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

class _FeedRepo extends navigation.SessionRepository {
  _FeedRepo(this.kind, {this.failure = false}) : super(uid: 'u', linked: true) {
    sources = [
      Entry('s', {'name': 'Minha IPTV', 'version': 'v', 'status': 'ready'}),
    ];
    home = {'profile': profile};
  }
  final String kind;

  /// The catalog cannot be read.
  final bool failure;
  static const total = 100;
  static const small = 5;

  /// Chunk requests, in order.
  final chunks = <Map<String, dynamic>>[];

  /// Lists of the account's profile (`readProfileLibrary`).
  Map<String, dynamic> library = const {};

  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (action == 'readCatalogChunk') chunks.add(Map.of(payload));
    if (action == 'readProfileLibrary') return library;
    if (failure && action == 'readCatalogManifest') {
      throw const AppFailure('unavailable');
    }
    return catalogSetsAnswer(
          action,
          payload,
          [
            for (var i = 0; i < total; i++)
              {
                'id': 'i$i',
                'title': 'Item $i',
                'kind': kind,
                'category': 'ACAO',
                'sourceId': 's',
              },
            for (var i = 0; i < small; i++)
              {
                'id': 'c$i',
                'title': 'Comédia $i',
                'kind': kind,
                'categoryId': '7',
                'category': 'ignored when the id has a name',
                'sourceId': 's',
              },
          ],
          categories: [
            {'id': '7', 'name': 'FILMES | Comédia', 'kind': kind},
          ],
        ) ??
        await super.mutate(action, payload);
  }
}

/// The feed's loading row pulses forever: pump a few frames instead of settling.
Future<void> settleFeed(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void catalogFeedTests() {
  for (final (tab, kind) in [(1, 'channel'), (2, 'movie'), (3, 'series')]) {
    testWidgets(
      '$kind tab: categories grouped in the app (TV names) with counts; one '
      'opens at a time, three per row, A–Z',
      (tester) async {
        final repo = _FeedRepo(kind);
        await navigation.launch(tester, repo);
        await tester.tap(find.byKey(ValueKey('tab-$tab')));
        await settleFeed(tester);
        // Read as the TV reads it: the kind's items and its categories.
        final set = const {
          'channel': 'live',
          'movie': 'vod',
          'series': 'series',
        }[kind]!;
        // (The three kinds load in the background once Meu iPlex has data.)
        expect(
          repo.chunks.map((c) => c['set']),
          containsAll([set, '${set}_categories']),
        );
        expect(repo.chunks.map((c) => c['set']), isNot(contains('adult')));
        // The top menu keeps the Meu iPlex look on every tab.
        expect(
          tester
              .widget<AppTabs<int>>(find.byKey(const Key('home-tabs')))
              .translucent,
          isTrue,
        );
        // Only the categories (TV de-para) and their counts, A–Z.
        expect(find.text('Ação'), findsOneWidget);
        expect(find.text('Comédia'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Ação')).dy,
          lessThan(tester.getTopLeft(find.text('Comédia')).dy),
        );
        String count(String key) => tester
            .widget<Text>(find.byKey(ValueKey('catalog-category-count-$key')))
            .data!;
        expect(count('acao'), '100');
        expect(count('comedia'), '5');
        expect(find.byType(HomeCard), findsNothing);

        await tester.tap(find.text('Ação'));
        await settleFeed(tester);
        // Three cards share the first row; channels are square, titles 2:3;
        // numbers sort by value (Item 2 before Item 10).
        final first = tester.getRect(
          find.byKey(const ValueKey('home-card-i0')),
        );
        final third = tester.getRect(
          find.byKey(const ValueKey('home-card-i2')),
        );
        final fourth = tester.getRect(
          find.byKey(const ValueKey('home-card-i3')),
        );
        expect(third.top, first.top);
        expect(fourth.top, greaterThan(first.top));
        expect(
          first.height / first.width,
          closeTo(kind == 'channel' ? 1 : 1.5, 0.01),
        );
        expect(
          first.top,
          greaterThan(tester.getBottomLeft(find.text('Ação')).dy),
        );
        // The rest is built while scrolling, without new requests.
        final requests = repo.chunks.length;
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('home-card-i99')),
          600,
          scrollable: find
              .descendant(
                of: find.byKey(const PageStorageKey('home-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(repo.chunks.length, requests);

        // Opening another category closes the first; tapping again closes it.
        await tester.scrollUntilVisible(
          find.text('Comédia'),
          600,
          scrollable: find
              .descendant(
                of: find.byKey(const PageStorageKey('home-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        // Up from under the bottom navigation.
        await tester.drag(
          find.byKey(const PageStorageKey('home-scroll')),
          const Offset(0, -300),
        );
        await settleFeed(tester);
        await tester.tap(find.text('Comédia'));
        await settleFeed(tester);
        expect(find.byKey(const ValueKey('home-card-c0')), findsOneWidget);
        expect(find.byKey(const ValueKey('home-card-i0')), findsNothing);
        await tester.tap(find.text('Comédia'));
        await settleFeed(tester);
        expect(find.byType(HomeCard), findsNothing);
      },
    );
  }

  testWidgets('the profile lists come first, with this tab\'s kind only, '
      'in the TV order; empty ones are left out', (tester) async {
    final repo = _FeedRepo('movie')
      ..library = {
        'continueWatching': [
          item(
            'p1',
            'Em andamento',
            'movie',
            progress: {'position': 30, 'duration': 100},
          ),
          item('p2', 'Série em andamento', 'series'),
        ],
        'favorites': [
          item('f1', 'Favorito', 'movie'),
          item('f2', 'Canal favorito', 'channel'),
        ],
        'wishlist': [item('w1', 'Desejo série', 'series')],
        // History lists every episode: one entry per title.
        'watched': [item('h1', 'Visto', 'movie'), item('h1', 'Visto', 'movie')],
      };
    await navigation.launch(tester, repo);
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await settleFeed(tester);
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(find.text('Wishlist'), findsNothing, reason: 'no movie there');
    expect(top('Continue watching'), lessThan(top('Favorites')));
    expect(top('Favorites'), lessThan(top('Watched')));
    expect(top('Watched'), lessThan(top('Ação')));
    String count(String key) => tester
        .widget<Text>(find.byKey(ValueKey('catalog-category-count-$key')))
        .data!;
    expect(count('personal-continueWatching'), '1');
    expect(count('personal-favorites'), '1');
    expect(count('personal-watched'), '1');
    await tester.tap(find.text('Favorites'));
    await settleFeed(tester);
    expect(find.byKey(const ValueKey('home-card-f1')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-card-f2')), findsNothing);
  });

  testWidgets('catalog that cannot be read: retry, never a "Todos" list', (
    tester,
  ) async {
    await navigation.launch(tester, _FeedRepo('movie', failure: true));
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await settleFeed(tester);
    expect(find.byType(HomeCard), findsNothing);
    expect(find.byType(ErrorState), findsOneWidget);
  });
}

void floatingBarTests() {
  testWidgets(
    'app bar and tabs leave with the content when scrolling down and return at once on any scroll back',
    (tester) async {
      final repo = _FeedRepo('movie');
      await navigation.launch(tester, repo);
      await tester.tap(find.byKey(const ValueKey('tab-2')));
      await settleFeed(tester);
      await tester.tap(find.text('Ação'));
      await settleFeed(tester);
      final title = find.byKey(const Key('home-title'));
      final tabs = find.byKey(const Key('home-tabs'));
      final top0 = tester.getTopLeft(title).dy;
      final scroll = find.byKey(const PageStorageKey('home-scroll'));
      // Scrolling the list: the bar moves up with the content and disappears.
      await tester.drag(scroll, const Offset(0, -600));
      await settleFeed(tester);
      expect(tester.getBottomLeft(tabs).dy, lessThanOrEqualTo(0));
      // Far from the top, a small scroll back brings it down right away.
      await tester.drag(scroll, const Offset(0, 120));
      await settleFeed(tester);
      expect(tester.getTopLeft(title).dy, greaterThan(top0 - 130));
      expect(tester.getBottomLeft(tabs).dy, greaterThan(0));
      // The bar has no background of its own (transparent).
      final filled = find.ancestor(
        of: tabs,
        matching: find.byWidgetPredicate(
          (w) =>
              w is ColoredBox &&
              w.color != Colors.transparent &&
              w.color.a > 0 &&
              w.color == AppColors.backgroundPrimary &&
              tester.getSize(find.byWidget(w)).height < 200,
        ),
      );
      expect(filled, findsNothing);
      // Back at the top: in place again.
      await tester.drag(scroll, const Offset(0, 3000));
      await settleFeed(tester);
      expect(tester.getTopLeft(title).dy, top0);
    },
  );
}
